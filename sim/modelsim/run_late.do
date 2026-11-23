# run_late.do - same test, but with slow pins: the flash answers 50 ns late,
# and the chip uses late sampling (ui_in[0] = 1). Should still PASS.
transcript on
if {[file exists work]} { vdel -lib work -all }
vlib work
vlog -work work ../../src/tt_um_sari_leen_vga_qspi.v ../../src/integration_top.v ../../src/qspi_reader.v ../../src/vga_controller.v
vlog -work work flash_model.v tb_vga_qspi.v
vsim -voptargs=+acc -gLATE_SAMPLE=1 -gFLASH_DELAY=50 work.tb_vga_qspi
run -all
