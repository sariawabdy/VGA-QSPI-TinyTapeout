"""
flash_sim.py - behavioral model of the Winbond W25Q128JV.

Supported commands (datasheet section in brackets):
  Reading
    03h  Read Data                    [8.2.6]  single SPI
    6Bh  Fast Read Quad Output        [8.2.9]  quad data out, needs QE = 1
  Identification / status
    9Fh  JEDEC ID                     [8.2.29] EF 70 18 for our 25Q128JVSM
    05h  Read Status Register-1       [8.2.4]  bit 0 = BUSY, bit 1 = WEL
    35h  Read Status Register-2       [8.2.4]  bit 1 = QE
  Writing
    06h  Write Enable                 [8.2.1]  sets WEL; needed before every write/erase
    04h  Write Disable                [8.2.3]
    31h  Write Status Register-2      [8.2.5]  used to set QE
    20h  Sector Erase (4 KB)          [8.2.15]
    02h  Page Program (up to 256 B)   [8.2.13]

Design idea: this class knows NOTHING about cocotb or Verilog.
It just reacts to pin events. A thin cocotb wrapper watches the DUT's pins
and calls these methods. That way you can test this file with plain Python first.

Pins (SPI Mode 0):
  /CS   - chip select, driven by the master
  CLK   - clock, driven by the master
  IO0   - DI in single SPI; also a data OUTPUT during quad reads
  IO1   - DO in single SPI; data output during quad reads
  IO2   - /WP  when QE = 0, data output during quad reads when QE = 1
  IO3   - /HOLD when QE = 0, data output during quad reads when QE = 1

Timing rules modeled:
  - /CS low starts a transaction; command, address and data IN are latched on
    CLK RISING edges, MSB first; data OUT changes on CLK FALLING edges.
  - Write Enable, Write Status Register, Erase and Program only take effect when
    /CS goes HIGH, and only if /CS rises exactly on a byte boundary (datasheet).
  - Erase/program/write-status set BUSY. The real chip is busy for milliseconds;
    here BUSY clears after a set number of Read Status Register-1 transactions,
    so simulations stay fast. While BUSY, only status reads are accepted.
  - Programming can only change bits from 1 to 0 (real flash behavior), so a
    sector must be erased (all 0xFF) before writing new data.
  - With QE = 0, /HOLD (IO3) low pauses the chip. Set `flash.hold_n` from the pin;
    None (nobody drives it) is treated as low, because the Pmod has no pull-up.
"""

READ_DATA = 0x03
FAST_READ_QUAD_OUTPUT = 0x6B
JEDEC_ID = 0x9F
READ_STATUS_1 = 0x05
READ_STATUS_2 = 0x35
WRITE_ENABLE = 0x06
WRITE_DISABLE = 0x04
WRITE_STATUS_2 = 0x31
SECTOR_ERASE = 0x20
PAGE_PROGRAM = 0x02

DUMMY_CLOCKS = 8
MEM_SIZE = 16 * 1024 * 1024  # 128 Mbit = 16 MB
ADDR_MASK = MEM_SIZE - 1     # 0xFFFFFF
SECTOR_SIZE = 4096
PAGE_SIZE = 256

STATUS_READS = (READ_STATUS_1, READ_STATUS_2)
WITH_ADDRESS = (READ_DATA, FAST_READ_QUAD_OUTPUT, SECTOR_ERASE, PAGE_PROGRAM)


class W25Q128JV:
    # States of one transaction (between /CS low and /CS high)
    IDLE = "IDLE"
    CMD = "CMD"              # shifting in the 8-bit instruction
    ADDR = "ADDR"            # shifting in the 24-bit address
    DUMMY = "DUMMY"          # 6Bh only: 8 dummy clocks, flash drives nothing
    DATA_OUT = "DATA_OUT"    # 1 bit per falling edge on IO1 (03h, status, ID)
    QUAD_OUT = "QUAD_OUT"    # 6Bh: 4 bits per falling edge on IO3..IO0
    DATA_IN = "DATA_IN"      # 31h / 02h: collecting bytes from IO0
    ARMED = "ARMED"          # 06h / 04h / 20h: complete, waiting for /CS high
    IGNORE = "IGNORE"        # unsupported or refused: ignore until /CS goes high

    def __init__(self, init_data: bytes = b"", qe: bool = True,
                 jedec_id=(0xEF, 0x70, 0x18),
                 busy_polls_erase=4, busy_polls_program=2, busy_polls_status=1):
        # Erased flash reads as 0xFF everywhere
        self.mem = bytearray([0xFF]) * MEM_SIZE
        self.mem[: len(init_data)] = init_data
        self.jedec_id = tuple(jedec_id)
        self.sr2 = 0x02 if qe else 0x00   # Status Register-2, bit 1 = QE
        self.wel = False                  # Write Enable Latch
        self.busy_polls = 0               # status reads left until BUSY clears
        self.busy_polls_erase = busy_polls_erase
        self.busy_polls_program = busy_polls_program
        self.busy_polls_status = busy_polls_status
        self.hold_n = 1                   # /HOLD pin as seen by the flash (QE = 0 only)
        self.log = []                     # executed write operations, for tests
        self._reset_transaction()

    # ---------------- registers ----------------

    @property
    def qe(self) -> bool:
        return bool(self.sr2 & 0x02)

    @qe.setter
    def qe(self, value: bool):
        self.sr2 = (self.sr2 | 0x02) if value else (self.sr2 & ~0x02)

    @property
    def busy(self) -> bool:
        return self.busy_polls > 0

    @property
    def sr1(self) -> int:
        return (0x01 if self.busy else 0) | (0x02 if self.wel else 0)

    # ---------------- internal helpers ----------------

    def _reset_transaction(self):
        self.state = self.IDLE
        self.shift_in = 0      # bits collected so far (command, address or data byte)
        self.bit_count = 0     # bits/clocks counted in the current phase
        self.total_bits = 0    # all bits clocked in since /CS fell
        self.command = None
        self.addr = 0
        self.data_in = []      # bytes received for 31h / 02h
        self.out_source = None # "mem", "sr1", "sr2", "id"
        self.id_index = 0
        self.out_byte = 0      # byte currently being shifted out
        self.out_bit = 0       # single SPI: bits sent of out_byte / quad: nibbles sent
        # What the flash drives on IO0..IO3. None = high impedance (not driving).
        self.io = [None, None, None, None]

    @property
    def do(self):
        """DO = IO1. Kept so single-SPI code can still read `flash.do`."""
        return self.io[1]

    def _held(self) -> bool:
        """With QE = 0, IO3 is /HOLD: low (or floating) pauses the chip."""
        return (not self.qe) and self.hold_n != 1

    def _load_byte(self):
        """Prepare the next byte to shift out, starting from its MSB."""
        if self.out_source == "mem":
            self.out_byte = self.mem[self.addr]
        elif self.out_source == "sr1":
            self.out_byte = self.sr1
        elif self.out_source == "sr2":
            self.out_byte = self.sr2
        elif self.out_source == "id":
            self.out_byte = self.jedec_id[self.id_index % 3]
        self.out_bit = 0

    def _next_byte(self):
        """Byte finished. Memory reads auto-increment; past 0xFFFFFF this MODEL
        wraps to 0 (the datasheet doesn't specify what the real chip does there)."""
        if self.out_source == "mem":
            self.addr = (self.addr + 1) & ADDR_MASK
        elif self.out_source == "id":
            self.id_index += 1
        self._load_byte()

    def _start_output(self, source):
        self.out_source = source
        self._load_byte()
        self.state = self.DATA_OUT

    # ---------------- pin events ----------------

    def cs_fall(self):
        """/CS went low: a new transaction starts with the command byte."""
        self._reset_transaction()
        self.state = self.CMD

    def cs_rise(self):
        """/CS went high: write-type commands execute now, then everything resets."""
        self._execute_on_cs_high()
        self._reset_transaction()

    def _execute_on_cs_high(self):
        cmd, bits = self.command, self.total_bits
        on_boundary = bits > 0 and bits % 8 == 0

        if cmd == READ_STATUS_1 and bits >= 16 and self.busy_polls > 0:
            self.busy_polls -= 1     # model "time passing" while the master polls

        if self.busy or not on_boundary:
            return
        if cmd == WRITE_ENABLE and bits == 8:
            self.wel = True
        elif cmd == WRITE_DISABLE and bits == 8:
            self.wel = False
        elif cmd == WRITE_STATUS_2 and self.wel and len(self.data_in) >= 1:
            # Only QE (bit 1) is modeled as writable here.
            self.sr2 = (self.sr2 & ~0x02) | (self.data_in[0] & 0x02)
            self.wel = False
            self.busy_polls = self.busy_polls_status
            self.log.append(("write_sr2", self.data_in[0]))
        elif cmd == SECTOR_ERASE and self.wel and bits == 32:
            start = self.addr & ~(SECTOR_SIZE - 1)
            self.mem[start:start + SECTOR_SIZE] = bytes([0xFF]) * SECTOR_SIZE
            self.wel = False
            self.busy_polls = self.busy_polls_erase
            self.log.append(("erase", start))
        elif cmd == PAGE_PROGRAM and self.wel and len(self.data_in) >= 1:
            page = self.addr & ~(PAGE_SIZE - 1)
            offset = self.addr & (PAGE_SIZE - 1)
            buffer = {}
            for i, value in enumerate(self.data_in):          # > 256 bytes wraps in the page
                buffer[(offset + i) % PAGE_SIZE] = value
            for col, value in buffer.items():
                self.mem[page + col] &= value                 # program can only clear bits
            self.wel = False
            self.busy_polls = self.busy_polls_program
            self.log.append(("program", self.addr, len(self.data_in)))

    def clk_rise(self, di: int):
        """Rising edge of CLK: the flash LATCHES the bit on IO0 (DI)."""
        if self.state == self.IDLE or self._held():
            return
        self.total_bits += 1

        if self.state == self.CMD:
            self.shift_in = (self.shift_in << 1) | (di & 1)   # MSB first
            self.bit_count += 1
            if self.bit_count == 8:
                self.command = self.shift_in
                self.shift_in = 0
                self.bit_count = 0
                self._decode_command()

        elif self.state == self.ADDR:
            self.shift_in = (self.shift_in << 1) | (di & 1)
            self.bit_count += 1
            if self.bit_count == 24:
                self.addr = self.shift_in & ADDR_MASK
                self.shift_in = 0
                self.bit_count = 0
                if self.command == READ_DATA:
                    # The very next FALLING edge must already output bit 7,
                    # so the first byte has to be loaded right now.
                    self._start_output("mem")
                elif self.command == FAST_READ_QUAD_OUTPUT:
                    self.state = self.DUMMY
                elif self.command == SECTOR_ERASE:
                    self.state = self.ARMED
                elif self.command == PAGE_PROGRAM:
                    self.state = self.DATA_IN

        elif self.state == self.DATA_IN:
            self.shift_in = (self.shift_in << 1) | (di & 1)
            self.bit_count += 1
            if self.bit_count == 8:
                self.data_in.append(self.shift_in)
                self.shift_in = 0
                self.bit_count = 0

        elif self.state == self.DUMMY:
            # IO0 is "don't care" here. The master must stop driving IO0
            # before the first data falling edge, because the flash drives it next.
            self.bit_count += 1
            if self.bit_count == DUMMY_CLOCKS:
                self.bit_count = 0
                # Same trick as 03h: the falling edge after the last dummy
                # clock already outputs the high nibble of byte 1.
                self.out_source = "mem"
                self._load_byte()
                self.state = self.QUAD_OUT
        # In DATA_OUT / QUAD_OUT / ARMED / IGNORE, IO0 input is ignored.

    def _decode_command(self):
        cmd = self.command
        if self.busy and cmd not in STATUS_READS:
            self.state = self.IGNORE          # busy: only status reads are accepted
        elif cmd == READ_DATA:
            self.state = self.ADDR
        elif cmd == FAST_READ_QUAD_OUTPUT:
            self.state = self.ADDR if self.qe else self.IGNORE
        elif cmd == READ_STATUS_1:
            self._start_output("sr1")
        elif cmd == READ_STATUS_2:
            self._start_output("sr2")
        elif cmd == JEDEC_ID:
            self._start_output("id")
        elif cmd in (WRITE_ENABLE, WRITE_DISABLE):
            self.state = self.ARMED
        elif cmd == WRITE_STATUS_2:
            self.state = self.DATA_IN
        elif cmd in (SECTOR_ERASE, PAGE_PROGRAM):
            self.state = self.ADDR
        else:
            self.state = self.IGNORE          # unknown command

    def clk_fall(self):
        """Falling edge of CLK: the flash SHIFTS OUT its next bit(s)."""
        if self._held():
            return
        if self.state == self.DATA_OUT:
            # Single SPI: one bit on IO1 (DO), MSB first
            self.io[1] = (self.out_byte >> (7 - self.out_bit)) & 1
            self.out_bit += 1
            if self.out_bit == 8:
                self._next_byte()

        elif self.state == self.QUAD_OUT:
            # Quad: high nibble first, then low nibble. IO3 carries the top bit.
            shift = 4 if self.out_bit == 0 else 0
            nibble = (self.out_byte >> shift) & 0xF
            for k in range(4):
                self.io[k] = (nibble >> k) & 1
            self.out_bit += 1
            if self.out_bit == 2:
                self._next_byte()


# ---------------- quick self-test (plain Python, no cocotb) ----------------

def _clock_byte_in(flash: W25Q128JV, byte: int):
    for i in range(7, -1, -1):
        flash.clk_rise((byte >> i) & 1)
        flash.clk_fall()


def _send_header(flash: W25Q128JV, command: int, addr: int):
    """Master side: /CS low, then command + 24-bit address on IO0, MSB first."""
    flash.cs_fall()
    for byte in (command, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF):
        for i in range(7, -1, -1):
            assert flash.io == [None] * 4, "flash must not drive IO while the master sends"
            flash.clk_rise((byte >> i) & 1)
            flash.clk_fall()


def _read_bytes_single(flash: W25Q128JV, n_bytes: int) -> bytes:
    result = bytearray()
    for _ in range(n_bytes):
        value = 0
        for _ in range(8):
            value = (value << 1) | (flash.do or 0)   # master samples on rising edge (high-Z reads 0)
            flash.clk_rise(0)
            flash.clk_fall()
        result.append(value)
    return bytes(result)


def spi_read(flash: W25Q128JV, addr: int, n_bytes: int) -> bytes:
    """Act like an SPI master in Mode 0 and read n_bytes with Read Data (03h)."""
    _send_header(flash, READ_DATA, addr)
    # The falling edge after the last address bit already put data bit 7 on DO.
    result = _read_bytes_single(flash, n_bytes)
    flash.cs_rise()
    return result


def spi_read_quad(flash: W25Q128JV, addr: int, n_bytes: int) -> bytes:
    """Act like a quad SPI master and read n_bytes with Fast Read Quad Output (6Bh)."""
    _send_header(flash, FAST_READ_QUAD_OUTPUT, addr)
    for _ in range(DUMMY_CLOCKS):
        assert flash.io == [None] * 4, "flash must stay high-Z during dummy clocks"
        flash.clk_rise(0)
        flash.clk_fall()
    result = bytearray()
    for _ in range(n_bytes):
        value = 0
        for _ in range(2):
            nibble = (flash.io[3] << 3) | (flash.io[2] << 2) | (flash.io[1] << 1) | flash.io[0]
            value = (value << 4) | nibble
            flash.clk_rise(0)
            flash.clk_fall()
        result.append(value)
    flash.cs_rise()
    return bytes(result)


def spi_command(flash: W25Q128JV, out_bytes, n_in=0) -> bytes:
    """Generic single-SPI transaction: send out_bytes, then read n_in bytes."""
    flash.cs_fall()
    for b in out_bytes:
        _clock_byte_in(flash, b)
    result = _read_bytes_single(flash, n_in)
    flash.cs_rise()
    return result


def wait_not_busy(flash: W25Q128JV, limit=100):
    for _ in range(limit):
        if spi_command(flash, [READ_STATUS_1], 1)[0] & 0x01 == 0:
            return
    raise AssertionError("flash stayed busy")


if __name__ == "__main__":
    flash = W25Q128JV(bytes(range(256)))

    # --- Read Data (03h) ---
    assert spi_read(flash, 0x000010, 2) == bytes([0x10, 0x11])
    assert spi_read(flash, 0x000000, 256) == bytes(range(256))
    assert flash.do is None, "DO should be high-Z after /CS goes high"

    # --- Fast Read Quad Output (6Bh) ---
    assert spi_read_quad(flash, 0x000010, 2) == bytes([0x10, 0x11])
    assert spi_read_quad(flash, 0x000000, 256) == bytes(range(256))
    assert flash.io == [None] * 4, "all IO pins should be high-Z after /CS goes high"

    # A byte with different nibbles, to catch a swapped nibble or bit order
    flash.mem[0x1000] = 0xA5   # 1010 0101
    flash.mem[0x1001] = 0x3C   # 0011 1100
    assert spi_read_quad(flash, 0x1000, 2) == bytes([0xA5, 0x3C])

    # Wrap-around at the end of memory (model behavior)
    flash.mem[ADDR_MASK] = 0xAB
    assert spi_read(flash, ADDR_MASK, 2) == bytes([0xAB, 0x00])
    assert spi_read_quad(flash, ADDR_MASK, 2) == bytes([0xAB, 0x00])

    # 6Bh is refused when the Quad Enable bit is 0
    no_qe = W25Q128JV(bytes(range(256)), qe=False)
    _send_header(no_qe, FAST_READ_QUAD_OUTPUT, 0x10)
    for _ in range(DUMMY_CLOCKS + 16):
        no_qe.clk_rise(0)
        no_qe.clk_fall()
    assert no_qe.io == [None] * 4, "with QE = 0 the flash must ignore 6Bh"
    no_qe.cs_rise()

    # Unsupported command: flash must stay silent
    _send_header(flash, 0xC7 ^ 0xFF, 0)
    for _ in range(32):
        flash.clk_rise(0)
        flash.clk_fall()
    assert flash.io == [None] * 4
    flash.cs_rise()

    # --- JEDEC ID (9Fh) ---
    assert spi_command(flash, [JEDEC_ID], 3) == bytes([0xEF, 0x70, 0x18])

    # --- Writing needs Write Enable first ---
    f = W25Q128JV(qe=False)
    spi_command(f, [SECTOR_ERASE, 0, 0, 0])                    # no 06h before
    assert f.log == [], "erase without Write Enable must be ignored"

    # --- Set QE through Write Status Register-2 ---
    assert spi_command(f, [READ_STATUS_2], 1)[0] & 0x02 == 0
    spi_command(f, [WRITE_ENABLE])
    assert spi_command(f, [READ_STATUS_1], 1)[0] & 0x02, "WEL should be set"
    spi_command(f, [WRITE_STATUS_2, 0x02])
    wait_not_busy(f)
    assert spi_command(f, [READ_STATUS_2], 1)[0] & 0x02, "QE should now be 1"
    assert f.qe

    # --- Erase + program + read back ---
    f.mem[0:4096] = bytes([0x00]) * 4096                      # old data in sector 0
    spi_command(f, [WRITE_ENABLE])
    spi_command(f, [SECTOR_ERASE, 0, 0, 0])
    assert spi_command(f, [READ_STATUS_1], 1)[0] & 0x01, "BUSY during erase"
    spi_command(f, [READ_DATA, 0, 0, 0], 1)                    # ignored while busy
    wait_not_busy(f)
    assert spi_read(f, 0, 4) == b"\xff\xff\xff\xff", "erased sector reads 0xFF"
    page = bytes((i * 7) & 0xFF for i in range(256))
    spi_command(f, [WRITE_ENABLE])
    spi_command(f, [PAGE_PROGRAM, 0, 0, 0] + list(page))
    wait_not_busy(f)
    assert spi_read(f, 0, 256) == page
    assert not f.wel, "WEL clears after a program"

    # Program without erase can only clear bits
    spi_command(f, [WRITE_ENABLE])
    spi_command(f, [PAGE_PROGRAM, 0, 0x10, 0, 0xF0])
    wait_not_busy(f)
    spi_command(f, [WRITE_ENABLE])
    spi_command(f, [PAGE_PROGRAM, 0, 0x10, 0, 0x0F])
    wait_not_busy(f)
    assert spi_read(f, 0x1000, 1) == b"\x00", "1 -> 0 only: F0 then 0F gives 00"

    # /CS rising in the middle of a byte cancels the command
    spi_command(f, [WRITE_ENABLE])
    f.cs_fall()
    for b in (SECTOR_ERASE, 0, 0, 0):
        _clock_byte_in(f, b)
    f.clk_rise(0)
    f.clk_fall()                                               # one extra bit
    f.cs_rise()
    assert spi_read(f, 0, 1) == bytes([page[0]]), "erase must not happen off-boundary"

    # --- /HOLD: with QE = 0, a floating or low IO3 pauses the chip ---
    h = W25Q128JV(qe=False)
    h.hold_n = None
    h.cs_fall()
    _clock_byte_in(h, JEDEC_ID)
    for _ in range(8):
        h.clk_rise(0)
        h.clk_fall()
    assert h.io == [None] * 4 and h.total_bits == 0, "held chip must ignore the clock"
    h.cs_rise()
    h.hold_n = 1
    assert spi_command(h, [JEDEC_ID], 3) == bytes([0xEF, 0x70, 0x18])

    print("All flash_sim self-tests passed")
