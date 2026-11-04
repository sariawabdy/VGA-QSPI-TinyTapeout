# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0
#
# Tests for tt_um_sari_leen_vga_qspi: VGA controller + QSPI flash reader.
#
# These tests only use the chip's pins (through tb.v), so the same file runs
#   - as the normal RTL test:         cd test; make
#   - as the gate-level (GL) test:    the gds action runs it on the synthesized netlist
# A Python model of the W25Q128JV flash (flash_sim.py) is connected to the uio pins.

import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, Timer

from flash_sim import W25Q128JV

IMG_W, IMG_H = 160, 120
H_TOTAL, V_TOTAL = 800, 525

# Test image in the agreed format 00RRGGBB. Neighbouring pixels differ, so a
# shifted byte or a wrong row shows up immediately.
IMAGE = bytes((i * 37 + 11) & 0x3F for i in range(IMG_W * IMG_H))

GL_TEST = os.environ.get("GATES") == "yes"

# Pin numbers on the QSPI Pmod (uio) for flash IO0..IO3
IO_PIN = [1, 2, 4, 5]


def to_int(value):
    """Pin value as an int; anything not 0/1 yet (X/Z right after power-up) reads as 0."""
    try:
        return int(value)
    except ValueError:
        return 0


# ---------------------------------------------------------------------------
# The "wires" between the chip's uio pins and the flash model
# ---------------------------------------------------------------------------

def connect_flash(dut, flash, delay_ns=0):
    """delay_ns: extra round-trip delay of the real pins/wires (0 = ideal)."""
    problems = []

    async def set_later(value):
        await Timer(delay_ns, unit="ns")
        dut.uio_in.value = value

    def drive_flash_outputs():
        value = 0
        for io, pin in enumerate(IO_PIN):
            if flash.io[io]:              # None (high-Z) reads as 0
                value |= 1 << pin
        if delay_ns:
            cocotb.start_soon(set_later(value))
        else:
            dut.uio_in.value = value

    def check_contention(where):
        oe = to_int(dut.uio_oe.value)
        for io, pin in enumerate(IO_PIN):
            if flash.io[io] is not None and (oe >> pin) & 1:
                problems.append(f"bus fight on IO{io} ({where})")

    async def watch_cs():
        while True:
            await FallingEdge(dut.flash_cs_n)
            flash.cs_fall()
            await RisingEdge(dut.flash_cs_n)
            flash.cs_rise()
            drive_flash_outputs()

    async def watch_sck_rise():
        while True:
            await RisingEdge(dut.flash_sck)
            if to_int(dut.flash_cs_n.value) == 0:
                flash.clk_rise((to_int(dut.uio_out.value) >> 1) & 1)   # IO0 = uio[1]
                check_contention("rising")

    async def watch_sck_fall():
        while True:
            await FallingEdge(dut.flash_sck)
            if to_int(dut.flash_cs_n.value) == 0:
                flash.clk_fall()
                check_contention("falling")
                drive_flash_outputs()

    cocotb.start_soon(watch_cs())
    cocotb.start_soon(watch_sck_rise())
    cocotb.start_soon(watch_sck_fall())
    return problems


async def start(dut, late_sample=0, delay_ns=0):
    """Clock + reset. Returns the flash connection's problem list.
    Reset is released on a falling clock edge, so after N rising edges the
    VGA position is h = N % 800, v = N // 800."""
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())   # 25 MHz
    dut.ena.value = 1
    dut.ui_in.value = late_sample          # ui_in[0] = QSPI late sampling
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    problems = connect_flash(dut, W25Q128JV(IMAGE, qe=True), delay_ns)
    await ClockCycles(dut.clk, 10)
    await FallingEdge(dut.clk)
    dut.rst_n.value = 1
    return problems


def read_rgb(dut):
    """Decode the Tiny VGA pins back into a 00RRGGBB byte."""
    uo = to_int(dut.uo_out.value)
    bit = lambda n: (uo >> n) & 1
    red = (bit(0) << 1) | bit(4)
    green = (bit(1) << 1) | bit(5)
    blue = (bit(2) << 1) | bit(6)
    return (red << 4) | (green << 2) | blue


class Scanner:
    """Steps the clock to exact (line, x) screen positions and reads the pixel there."""

    def __init__(self, dut):
        self.dut = dut
        self.edges = 0          # rising edges since reset was released

    async def goto(self, line, x):
        target = line * H_TOTAL + x
        assert target >= self.edges, "positions must be visited in order"
        if target > self.edges:
            await ClockCycles(self.dut.clk, target - self.edges)
            self.edges = target
        await FallingEdge(self.dut.clk)     # middle of the clock: outputs are stable

    async def image_row(self, row, line_in_row=1, frame=0):
        """Read one image row from the screen, sampling the middle of each 4x4 block."""
        line = frame * V_TOTAL + 4 * row + line_in_row
        seen = []
        for col in range(IMG_W):
            await self.goto(line, 4 * col + 2)
            seen.append(read_rgb(self.dut))
        return bytes(seen)


def expected_row(row):
    return IMAGE[row * IMG_W:(row + 1) * IMG_W]


def first_mismatch(seen, want):
    for col, (a, b) in enumerate(zip(seen, want)):
        if a != b:
            return f"first wrong pixel at column {col}: got {a:02x}, expected {b:02x}"
    return "lengths differ"


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_vga_qspi_reset(dut):
    """Sari's reset test: during reset the VGA outputs are black with both syncs high,
    flash /CS is high, SCK low, RAM chip selects high; right after reset the reader is idle."""
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())   # 25 MHz
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 5)
    await Timer(1, unit="ns")

    # uo[7] = HSYNC, uo[3] = VSYNC, RGB = black
    assert int(dut.uo_out.value) == 0b10001000, f"Unexpected VGA reset outputs: {dut.uo_out.value}"

    uio = int(dut.uio_out.value)
    assert (uio & 0x01) != 0, "Flash CS# must be high"
    assert (uio & 0x08) == 0, "Flash SCK must be low"
    assert (uio & 0xC0) == 0xC0, "Unused RAM chip selects must remain high"

    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    await Timer(1, unit="ns")
    assert (int(dut.uio_out.value) & 0x01) != 0, "QSPI reader should remain idle initially"


@cocotb.test()
async def test_pins_and_hsync(dut):
    """After reset: flash /CS, SCK and both RAM chip selects are outputs, the RAMs are
    deselected, and HSYNC has the right 640x480 timing (96-clock pulse every 800)."""
    await start(dut)
    await ClockCycles(dut.clk, 5)
    await FallingEdge(dut.clk)

    oe = to_int(dut.uio_oe.value)
    out = to_int(dut.uio_out.value)
    for pin in (0, 3, 6, 7):
        assert (oe >> pin) & 1, f"uio[{pin}] should be an output"
    assert (out >> 6) & 1 and (out >> 7) & 1, "RAM A/B chip selects must be held high"

    await FallingEdge(dut.vga_hsync)
    await FallingEdge(dut.clk)
    low = 0
    while to_int(dut.vga_hsync.value) == 0:
        await FallingEdge(dut.clk)
        low += 1
    high = 0
    while to_int(dut.vga_hsync.value) == 1:
        await FallingEdge(dut.clk)
        high += 1
    assert low == 96, f"HSYNC low for {low} clocks, expected 96"
    assert low + high == H_TOTAL, f"line is {low + high} clocks, expected 800"


@cocotb.test()
async def test_image_first_rows(dut):
    """Flash -> QSPI reader -> VGA: the first three image rows appear on screen correctly
    (this also covers moving from one image row to the next every 4 lines)."""
    problems = await start(dut, late_sample=0)
    scan = Scanner(dut)
    for row in range(3):
        seen = await scan.image_row(row)
        assert seen == expected_row(row), f"row {row}: {first_mismatch(seen, expected_row(row))}"
    assert not problems, problems[:3]


@cocotb.test()
async def test_late_sample_with_slow_pins(dut):
    """ui_in[0] = 1 (late sampling) still shows the right image when the pins add a
    50 ns round trip - the case early sampling can't handle."""
    problems = await start(dut, late_sample=1, delay_ns=50)
    scan = Scanner(dut)
    for row in range(2):
        seen = await scan.image_row(row)
        assert seen == expected_row(row), f"row {row}: {first_mismatch(seen, expected_row(row))}"
    assert not problems, problems[:3]


@cocotb.test(skip=GL_TEST)
async def test_frame_end_and_next_frame(dut):
    """RTL only (a whole frame is slow at gate level): the last image row, VSYNC in the
    right place, and the first line of the NEXT frame (prefetched during line 524)."""
    problems = await start(dut)
    scan = Scanner(dut)

    seen = await scan.image_row(IMG_H - 1)
    assert seen == expected_row(IMG_H - 1), f"last row: {first_mismatch(seen, expected_row(IMG_H - 1))}"

    await scan.goto(489, 0)
    assert to_int(dut.vga_vsync.value) == 1, "VSYNC should still be high on line 489"
    await scan.goto(490, 0)
    assert to_int(dut.vga_vsync.value) == 0, "VSYNC should be low on line 490"
    await scan.goto(492, 0)
    assert to_int(dut.vga_vsync.value) == 1, "VSYNC should be high again on line 492"

    seen = await scan.image_row(0, line_in_row=0, frame=1)   # line 0 of frame 2
    assert seen == expected_row(0), f"next frame, line 0: {first_mismatch(seen, expected_row(0))}"
    assert not problems, problems[:3]
