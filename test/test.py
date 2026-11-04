
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer


@cocotb.test()
async def test_vga_qspi_reset(dut):
    # 25 MHz clock
    cocotb.start_soon(Clock(dut.clk, 40, unit="ns").start())

    # Initialize Tiny Tapeout inputs
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
 
    # Hold reset for several cycles
    await ClockCycles(dut.clk, 5)
    await Timer(1, unit="ns")

    # VGA output during reset:
    # uo[7] = HSYNC, uo[3] = VSYNC, RGB = black
    assert int(dut.uo_out.value) == 0b10001000, (
        f"Unexpected VGA reset outputs: {dut.uo_out.value}"
    )

    # Flash CS# high, Flash SCK low
    uio = int(dut.uio_out.value)
    assert (uio & 0x01) != 0, "Flash CS# must be high"
    assert (uio & 0x08) == 0, "Flash SCK must be low"

    # Unused RAM chip selects must remain high
    assert (uio & 0xC0) == 0xC0

    # Release reset
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)
    await Timer(1, unit="ns")

    # QSPI reader should remain idle initially
    assert (int(dut.uio_out.value) & 0x01) != 0

    dut._log.info("VGA/QSPI reset and pin checks passed")
