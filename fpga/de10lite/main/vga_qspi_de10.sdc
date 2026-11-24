# 50 MHz board clock; the PLL makes the 25 MHz design clock from it
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_pll_clocks
derive_clock_uncertainty
# Buttons, switches, LEDs, VGA and the QSPI pins: no board-level timing model here.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to [get_ports {LEDR[*] VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
set_false_path -from [get_ports {GPIO[*]}]
set_false_path -to [get_ports {GPIO[*]}]
