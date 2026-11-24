# waves.do - add the interesting signals, rerun, and zoom to a flash read.
# Use it after run.do or run_late.do:   do waves.do
# (restart keeps the same settings, e.g. the late-sampling ones)

restart -f
delete wave *

add wave -divider "Clock / reset / setting"
add wave -label clk          sim:/tb_vga_qspi/clk
add wave -label rst_n        sim:/tb_vga_qspi/rst_n
add wave -label late_sample  sim:/tb_vga_qspi/dut/system_inst/qspi_inst/late_sample

add wave -divider "VGA controller"
add wave -label h_count -unsigned sim:/tb_vga_qspi/dut/system_inst/vga_inst/h_count
add wave -label v_count -unsigned sim:/tb_vga_qspi/dut/system_inst/vga_inst/v_count
add wave -label hsync        sim:/tb_vga_qspi/dut/system_inst/vga_inst/hsync
add wave -label vsync        sim:/tb_vga_qspi/dut/system_inst/vga_inst/vsync
add wave -label active_image sim:/tb_vga_qspi/dut/system_inst/vga_inst/active_image

add wave -divider "Handshake VGA <-> QSPI"
add wave -label row_start    sim:/tb_vga_qspi/dut/system_inst/qspi_inst/row_start
add wave -label row_base -unsigned sim:/tb_vga_qspi/dut/system_inst/qspi_inst/row_base
add wave -label pixel_valid  sim:/tb_vga_qspi/dut/system_inst/qspi_inst/pixel_valid
add wave -label pixel_take   sim:/tb_vga_qspi/dut/system_inst/qspi_inst/pixel_take
add wave -label pixel_data -hex sim:/tb_vga_qspi/dut/system_inst/qspi_inst/pixel_data

add wave -divider "QSPI reader inside"
add wave -label state -unsigned sim:/tb_vga_qspi/dut/system_inst/qspi_inst/state
add wave -label bit_cnt -unsigned sim:/tb_vga_qspi/dut/system_inst/qspi_inst/bit_cnt
add wave -label rx -hex      sim:/tb_vga_qspi/dut/system_inst/qspi_inst/rx
add wave -label rx_full      sim:/tb_vga_qspi/dut/system_inst/qspi_inst/rx_full
add wave -label io_oe -binary sim:/tb_vga_qspi/dut/system_inst/qspi_inst/io_oe

add wave -divider "Flash pins (as the flash sees them)"
add wave -label CS_n         sim:/tb_vga_qspi/flash/cs_n
add wave -label SCK          sim:/tb_vga_qspi/flash/sck
add wave -label IO0          sim:/tb_vga_qspi/flash/io0
add wave -label IO1          sim:/tb_vga_qspi/flash/io1
add wave -label IO2          sim:/tb_vga_qspi/flash/io2
add wave -label IO3          sim:/tb_vga_qspi/flash/io3
add wave -label flash_state -unsigned sim:/tb_vga_qspi/flash/state

run -all

# The first flash read: row_start happens at about 26 us,
# then command + address + dummy + the first bytes.
wave zoom range 25900ns 30000ns
