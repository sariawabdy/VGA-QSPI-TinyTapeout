// pll_25.v - 50 MHz in, 25 MHz out, for the DE10-Lite (MAX 10).
//
// Same module the Quartus IP Catalog (ALTPLL) would generate, written by hand
// so the project compiles without the wizard. `altpll` is Intel's built-in PLL
// block; Quartus knows it, other simulators don't (that's expected).
//
// If Quartus ever complains about this file: delete it from the project and make
// the PLL in IP Catalog -> ALTPLL instead, named pll_25, input 50 MHz, output
// c0 = 25 MHz, "locked" output on, "areset" off. The ports are the same.

`timescale 1ps / 1ps

module pll_25 (
    input  wire inclk0,   // 50 MHz
    output wire c0,       // 25 MHz
    output wire locked    // 1 = clock is stable
);

    wire [4:0] clk_out;
    assign c0 = clk_out[0];

    altpll altpll_component (
        .inclk              ({1'b0, inclk0}),
        .clk                (clk_out),
        .locked             (locked),
        .areset             (1'b0),
        .activeclock        (),
        .clkbad             (),
        .clkena             ({6{1'b1}}),
        .clkloss            (),
        .clkswitch          (1'b0),
        .configupdate       (1'b0),
        .enable0            (),
        .enable1            (),
        .extclk             (),
        .extclkena          ({4{1'b1}}),
        .fbin               (1'b1),
        .fbmimicbidir       (),
        .fbout              (),
        .fref               (),
        .icdrclk            (),
        .pfdena             (1'b1),
        .phasecounterselect ({4{1'b1}}),
        .phasedone          (),
        .phasestep          (1'b1),
        .phaseupdown        (1'b1),
        .pllena             (1'b1),
        .scanaclr           (1'b0),
        .scanclk            (1'b0),
        .scanclkena         (1'b1),
        .scandata           (1'b0),
        .scandataout        (),
        .scandone           (),
        .scanread           (1'b0),
        .scanwrite          (1'b0),
        .sclkout0           (),
        .sclkout1           (),
        .vcooverrange       (),
        .vcounderrange      ()
    );

    defparam
        altpll_component.bandwidth_type          = "AUTO",
        altpll_component.clk0_divide_by          = 2,
        altpll_component.clk0_duty_cycle         = 50,
        altpll_component.clk0_multiply_by        = 1,
        altpll_component.clk0_phase_shift        = "0",
        altpll_component.compensate_clock        = "CLK0",
        altpll_component.inclk0_input_frequency  = 20000,      // 20000 ps = 50 MHz
        altpll_component.intended_device_family  = "MAX 10",
        altpll_component.lpm_hint                = "CBX_MODULE_PREFIX=pll_25",
        altpll_component.lpm_type                = "altpll",
        altpll_component.operation_mode          = "NORMAL",
        altpll_component.pll_type                = "AUTO",
        altpll_component.port_activeclock        = "PORT_UNUSED",
        altpll_component.port_areset             = "PORT_UNUSED",
        altpll_component.port_clkbad0            = "PORT_UNUSED",
        altpll_component.port_clkbad1            = "PORT_UNUSED",
        altpll_component.port_clkloss            = "PORT_UNUSED",
        altpll_component.port_clkswitch          = "PORT_UNUSED",
        altpll_component.port_configupdate       = "PORT_UNUSED",
        altpll_component.port_fbin               = "PORT_UNUSED",
        altpll_component.port_inclk0             = "PORT_USED",
        altpll_component.port_inclk1             = "PORT_UNUSED",
        altpll_component.port_locked             = "PORT_USED",
        altpll_component.port_pfdena             = "PORT_UNUSED",
        altpll_component.port_phasecounterselect = "PORT_UNUSED",
        altpll_component.port_phasedone          = "PORT_UNUSED",
        altpll_component.port_phasestep          = "PORT_UNUSED",
        altpll_component.port_phaseupdown        = "PORT_UNUSED",
        altpll_component.port_pllena             = "PORT_UNUSED",
        altpll_component.port_scanaclr           = "PORT_UNUSED",
        altpll_component.port_scanclk            = "PORT_UNUSED",
        altpll_component.port_scanclkena         = "PORT_UNUSED",
        altpll_component.port_scandata           = "PORT_UNUSED",
        altpll_component.port_scandataout        = "PORT_UNUSED",
        altpll_component.port_scandone           = "PORT_UNUSED",
        altpll_component.port_scanread           = "PORT_UNUSED",
        altpll_component.port_scanwrite          = "PORT_UNUSED",
        altpll_component.port_clk0               = "PORT_USED",
        altpll_component.port_clk1               = "PORT_UNUSED",
        altpll_component.port_clk2               = "PORT_UNUSED",
        altpll_component.port_clk3               = "PORT_UNUSED",
        altpll_component.port_clk4               = "PORT_UNUSED",
        altpll_component.port_clk5               = "PORT_UNUSED",
        altpll_component.port_clkena0            = "PORT_UNUSED",
        altpll_component.port_clkena1            = "PORT_UNUSED",
        altpll_component.port_clkena2            = "PORT_UNUSED",
        altpll_component.port_clkena3            = "PORT_UNUSED",
        altpll_component.port_clkena4            = "PORT_UNUSED",
        altpll_component.port_clkena5            = "PORT_UNUSED",
        altpll_component.port_extclk0            = "PORT_UNUSED",
        altpll_component.port_extclk1            = "PORT_UNUSED",
        altpll_component.port_extclk2            = "PORT_UNUSED",
        altpll_component.port_extclk3            = "PORT_UNUSED",
        altpll_component.self_reset_on_loss_lock = "OFF",
        altpll_component.width_clock             = 5;

endmodule
