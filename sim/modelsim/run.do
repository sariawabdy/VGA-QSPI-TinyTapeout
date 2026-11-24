# run.do - compile and simulate in ModelSim / Questa
#   In ModelSim: File -> Change Directory... (pick this folder), then in the Transcript type:
#       do run.do
transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -work work ../../src/tt_um_sari_leen_vga_qspi.v ../../src/integration_top.v ../../src/qspi_reader.v ../../src/vga_controller.v
vlog -work work flash_model.v tb_vga_qspi.v

vsim -voptargs=+acc work.tb_vga_qspi

# a few useful signals in the Wave window
add wave -divider "chip pins"
add wave /tb_vga_qspi/clk /tb_vga_qspi/rst_n
add wave -hex /tb_vga_qspi/uo_out /tb_vga_qspi/uio_out /tb_vga_qspi/uio_oe
add wave -divider "flash bus (uio)"
add wave -label CS_n /tb_vga_qspi/uio_pin(0) -label SCK /tb_vga_qspi/uio_pin(3)
add wave -label IO0 /tb_vga_qspi/uio_pin(1) -label IO1 /tb_vga_qspi/uio_pin(2) -label IO2 /tb_vga_qspi/uio_pin(4) -label IO3 /tb_vga_qspi/uio_pin(5)
add wave -divider "QSPI reader"
add wave /tb_vga_qspi/dut/system_inst/qspi_inst/state
add wave /tb_vga_qspi/dut/system_inst/qspi_inst/row_start
add wave -hex /tb_vga_qspi/dut/system_inst/qspi_inst/row_base
add wave /tb_vga_qspi/dut/system_inst/qspi_inst/pixel_valid /tb_vga_qspi/dut/system_inst/qspi_inst/pixel_take
add wave -hex /tb_vga_qspi/dut/system_inst/qspi_inst/pixel_data

# ~34 ms of simulated time: one whole frame + the start of the next.
# The testbench stops by itself and prints PASS or FAIL in the Transcript.
run -all
wave zoom range 3400us 3420us
