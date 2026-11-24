# 50 MHz board clock
create_clock -name clk50 -period 20.000 [get_ports MAX10_CLK1_50]
derive_clock_uncertainty
# Buttons, switches, LEDs and the flash pins are slow / asynchronous here.
set_false_path -from [get_ports {KEY[*] SW[*]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
set_false_path -from [get_ports {GPIO[*]}]
set_false_path -to [get_ports {GPIO[*]}]
