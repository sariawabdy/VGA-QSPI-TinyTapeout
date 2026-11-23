// de10lite_top.v - runs our Tiny Tapeout design on a Terasic DE10-Lite (MAX 10).
//
// This file plays the role of the Tiny Tapeout demo board:
//   - makes the 25 MHz project clock from the board's 50 MHz clock (PLL)
//   - KEY[0] = reset (press to reset), SW[0] = ui_in[0] = late_sample
//   - VGA: our 2-bit colors go to the board's 4-bit VGA DAC
//   - QSPI Pmod: wired to the GPIO header (JP1), with real tri-state pins for uio
//
// Port names follow Terasic's DE10-Lite "golden top", so the pin assignments
// from Terasic's System Builder / DE10_LITE_Golden_Top.qsf match them directly.

`default_nettype none
`timescale 1ns / 1ps

module de10lite_top (
    input  wire        MAX10_CLK1_50,   // 50 MHz board clock

    input  wire [1:0]  KEY,             // push buttons, active low
    input  wire [9:0]  SW,              // slide switches
    output wire [9:0]  LEDR,            // red LEDs

    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,

    inout  wire [35:0] GPIO             // 40-pin header JP1 (3.3 V)
);

    // ------------------------------------------------------------
    // 25 MHz clock from the 50 MHz board clock.
    // pll_25 is generated in Quartus: IP Catalog -> ALTPLL,
    // input 50 MHz, output c0 = 25 MHz (25.175 is the exact VGA value,
    // 25.000 works on almost every monitor), with a "locked" output.
    // ------------------------------------------------------------
    wire clk_25;
    wire pll_locked;

    pll_25 pll_inst (
        .inclk0 (MAX10_CLK1_50),
        .c0     (clk_25),
        .locked (pll_locked)
    );

    // ------------------------------------------------------------
    // Reset: held while KEY[0] is pressed or the PLL isn't locked yet.
    // Released in sync with clk_25 (two flip-flops), like a clean reset.
    // ------------------------------------------------------------
    reg [1:0] rst_sync;
    always @(posedge clk_25 or negedge pll_locked) begin
        if (!pll_locked)
            rst_sync <= 2'b00;
        else if (!KEY[0])
            rst_sync <= 2'b00;
        else
            rst_sync <= {rst_sync[0], 1'b1};
    end
    wire rst_n = rst_sync[1];

    // ------------------------------------------------------------
    // The Tiny Tapeout design, unchanged
    // ------------------------------------------------------------
    wire [7:0] ui_in = {7'b0000000, SW[0]};   // SW[0] = late_sample (use 0 on the FPGA)
    wire [7:0] uo_out;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_sari_leen_vga_qspi tt_inst (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (1'b1),
        .clk     (clk_25),
        .rst_n   (rst_n)
    );

    // ------------------------------------------------------------
    // VGA: Tiny VGA pin order -> DE10-Lite VGA connector.
    // Our colors are 2 bits; the board's DAC takes 4. Repeating the
    // 2 bits ({c, c}) makes 11 -> 1111 (full brightness), 00 -> 0000.
    // ------------------------------------------------------------
    wire [1:0] red   = {uo_out[0], uo_out[4]};   // R1, R0
    wire [1:0] green = {uo_out[1], uo_out[5]};   // G1, G0
    wire [1:0] blue  = {uo_out[2], uo_out[6]};   // B1, B0

    assign VGA_R  = {red,   red};
    assign VGA_G  = {green, green};
    assign VGA_B  = {blue,  blue};
    assign VGA_HS = uo_out[7];
    assign VGA_VS = uo_out[3];

    // ------------------------------------------------------------
    // QSPI Pmod on GPIO[7:0], one wire per uio pin:
    //   GPIO[0] = uio[0] flash /CS     GPIO[4] = uio[4] IO2
    //   GPIO[1] = uio[1] IO0           GPIO[5] = uio[5] IO3
    //   GPIO[2] = uio[2] IO1           GPIO[6] = uio[6] RAM A /CS (held high)
    //   GPIO[3] = uio[3] SCK           GPIO[7] = uio[7] RAM B /CS (held high)
    // Each pin is a real tri-state: we drive it only when uio_oe says so,
    // otherwise we let go (high-Z) so the flash can drive it.
    // ------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : uio_pins
            assign GPIO[i]   = uio_oe[i] ? uio_out[i] : 1'bz;
            assign uio_in[i] = GPIO[i];
        end
    endgenerate

    assign GPIO[35:8] = {28{1'bz}};   // rest of the header unused

    // ------------------------------------------------------------
    // Status LEDs
    // ------------------------------------------------------------
    assign LEDR[0]   = pll_locked;   // on = 25 MHz clock running
    assign LEDR[1]   = rst_n;        // on = design running (not in reset)
    assign LEDR[2]   = SW[0];        // on = late sampling selected
    assign LEDR[3]   = ~uio_out[0];  // on = flash selected (/CS low), i.e. reading
    assign LEDR[9:4] = 6'b000000;

endmodule

`default_nettype wire
