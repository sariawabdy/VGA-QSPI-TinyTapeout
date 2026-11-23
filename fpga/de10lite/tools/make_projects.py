"""Writes the Quartus .qpf/.qsf/.sdc files for both DE10-Lite projects."""
import sys
from pathlib import Path

KIT = Path(sys.argv[1])

CLK = {"MAX10_CLK1_50": "P11"}
KEY = ["B8", "A7"]
SW = ["C10", "C11", "D12", "C12", "A12", "B12", "A13", "A14", "B14", "F15"]
LEDR = ["A8", "A9", "A10", "B10", "D13", "C13", "E14", "D14", "A11", "B11"]
HEX = {  # segments 0..6, then DP
    0: ["C14", "E15", "C15", "C16", "E16", "D17", "C17", "D15"],
    1: ["C18", "D18", "E18", "B16", "A17", "A18", "B17", "A16"],
    2: ["B20", "A20", "B19", "A21", "B21", "C22", "B22", "A19"],
    3: ["F21", "E22", "E21", "C19", "C20", "D19", "E17", "D22"],
    4: ["F18", "E20", "E19", "J18", "H19", "F19", "F20", "F17"],
    5: ["J20", "K20", "L18", "N18", "M20", "N19", "N20", "L19"],
}
VGA_R = ["AA1", "V1", "Y2", "Y1"]
VGA_G = ["W1", "T2", "R2", "R1"]
VGA_B = ["P1", "T1", "P4", "N2"]
VGA_SYNC = {"VGA_HS": "N3", "VGA_VS": "N1"}
GPIO = ["V10", "W10", "V9", "W9", "V8", "W8", "V7", "W7", "W6", "V5", "W5", "AA15",
        "AA14", "W13", "W12", "AB13", "AB12", "Y11", "AB11", "W11", "AB10", "AA10",
        "AA9", "Y8", "AA8", "Y7", "AA7", "Y6", "AA6", "Y5", "AA5", "Y4", "AB3", "Y3",
        "AB2", "AA2"]


def pins(use_vga, use_hex):
    out = []
    def pin(name, loc):
        out.append(f'set_location_assignment PIN_{loc} -to {name}')
        out.append(f'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to {name}')
    for n, l in CLK.items(): pin(n, l)
    for i, l in enumerate(KEY): pin(f"KEY[{i}]", l)
    for i, l in enumerate(SW): pin(f"SW[{i}]", l)
    for i, l in enumerate(LEDR): pin(f"LEDR[{i}]", l)
    if use_hex:
        for h, locs in HEX.items():
            for i, l in enumerate(locs): pin(f"HEX{h}[{i}]", l)
    if use_vga:
        for i, l in enumerate(VGA_R): pin(f"VGA_R[{i}]", l)
        for i, l in enumerate(VGA_G): pin(f"VGA_G[{i}]", l)
        for i, l in enumerate(VGA_B): pin(f"VGA_B[{i}]", l)
        for n, l in VGA_SYNC.items(): pin(n, l)
    for i, l in enumerate(GPIO): pin(f"GPIO[{i}]", l)
    return "\n".join(out)


def project(folder, name, top, files, use_vga, use_hex, sdc):
    d = KIT / folder
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{name}.qpf").write_text(f'QUARTUS_VERSION = "20.1"\nPROJECT_REVISION = "{name}"\n')
    file_lines = "\n".join(f"set_global_assignment -name VERILOG_FILE {f}" for f in files)
    (d / f"{name}.qsf").write_text(f"""# {name}.qsf - DE10-Lite (MAX 10 10M50DAF484C7G)
# Pin locations from the Terasic DE10-Lite user manual.

set_global_assignment -name FAMILY "MAX 10"
set_global_assignment -name DEVICE 10M50DAF484C7G
set_global_assignment -name TOP_LEVEL_ENTITY {top}
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 256
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85
set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"

# MAX 10 needs this mode to allow on-chip memory with initial contents (the image ROM).
set_global_assignment -name INTERNAL_FLASH_UPDATE_MODE "SINGLE IMAGE WITH ERAM"

{file_lines}
set_global_assignment -name SDC_FILE {name}.sdc

{pins(use_vga, use_hex)}
""")
    (d / f"{name}.sdc").write_text(sdc)


project("writer", "flash_writer_de10", "de10lite_flash_writer_top",
        ["de10lite_flash_writer_top.v", "flash_writer.v"],
        use_vga=False, use_hex=True,
        sdc="""# 50 MHz board clock
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty
# Buttons, switches, LEDs and the flash pins are slow / asynchronous here.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
set_false_path -from [get_ports {GPIO[*]}]
set_false_path -to [get_ports {GPIO[*]}]
""")

project("main", "vga_qspi_de10", "de10lite_top",
        ["de10lite_top.v", "pll_25.v",
         "../../../src/tt_um_sari_leen_vga_qspi.v", "../../../src/integration_top.v",
         "../../../src/qspi_reader.v", "../../../src/vga_controller.v"],
        use_vga=True, use_hex=False,
        sdc="""# 50 MHz board clock; the PLL makes the 25 MHz design clock from it
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_pll_clocks
derive_clock_uncertainty
# Buttons, switches, LEDs, VGA and the QSPI pins: no board-level timing model here.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to [get_ports {LEDR[*] VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
set_false_path -from [get_ports {GPIO[*]}]
set_false_path -to [get_ports {GPIO[*]}]
""")
print("ok")
