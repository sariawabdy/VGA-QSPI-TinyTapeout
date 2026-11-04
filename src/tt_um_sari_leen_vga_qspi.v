`default_nettype none
`timescale 1ns / 1ps

module tt_um_sari_leen_vga_qspi (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,

    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,

    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ============================================================
    // Internal VGA signals
    // ============================================================

    wire [1:0] red;
    wire [1:0] green;
    wire [1:0] blue;

    wire hsync;
    wire vsync;


    // ============================================================
    // Internal QSPI signals
    // ============================================================

    wire       qspi_sck;
    wire       qspi_cs_n;

    // IO3..IO0
    wire [3:0] qspi_io_out;
    wire [3:0] qspi_io_oe;
    wire [3:0] qspi_io_in;


    // ============================================================
    // Integrated VGA + QSPI design
    // ============================================================

    integration_top system_inst (

        .clk        (clk),
        .rst_n      (rst_n),

        // ui_in[0] picks the QSPI read timing:
        // 0 = early sampling (fast pins, e.g. FPGA)
        // 1 = late sampling (slow pins on the real Tiny Tapeout chip)
        .late_sample (ui_in[0]),

        // First tapeout configuration:
        //
        // fixed 160x120 source image
        //
        // 4x scaling gives 640x480.
        .img_width  (8'd160),
        .img_height (7'd120),

        // VGA
        .red        (red),
        .green      (green),
        .blue       (blue),
        .hsync      (hsync),
        .vsync      (vsync),

        // QSPI
        .qspi_sck     (qspi_sck),
        .qspi_cs_n    (qspi_cs_n),
        .qspi_io_out  (qspi_io_out),
        .qspi_io_oe   (qspi_io_oe),
        .qspi_io_in   (qspi_io_in)
    );


    // ============================================================
    // Tiny VGA output mapping
    // ============================================================

    // Official Tiny VGA pin order:
    //
    // uo_out[0] = R1
    // uo_out[1] = G1
    // uo_out[2] = B1
    // uo_out[3] = VSYNC
    // uo_out[4] = R0
    // uo_out[5] = G0
    // uo_out[6] = B0
    // uo_out[7] = HSYNC

    assign uo_out[0] = red[1];
    assign uo_out[1] = green[1];
    assign uo_out[2] = blue[1];
    assign uo_out[3] = vsync;

    assign uo_out[4] = red[0];
    assign uo_out[5] = green[0];
    assign uo_out[6] = blue[0];
    assign uo_out[7] = hsync;


    // ============================================================
    // QSPI Pmod input mapping
    // ============================================================

    // Official Tiny Tapeout QSPI Pmod:
    //
    // uio[0] = Flash CS
    // uio[1] = IO0 / MOSI
    // uio[2] = IO1 / MISO
    // uio[3] = SCK
    // uio[4] = IO2
    // uio[5] = IO3
    // uio[6] = RAM A CS
    // uio[7] = RAM B CS
    //
    // qspi_io_in uses:
    //
    // [3] = IO3
    // [2] = IO2
    // [1] = IO1
    // [0] = IO0

    assign qspi_io_in[0] = uio_in[1];
    assign qspi_io_in[1] = uio_in[2];
    assign qspi_io_in[2] = uio_in[4];
    assign qspi_io_in[3] = uio_in[5];


    // ============================================================
    // QSPI Pmod output mapping
    // ============================================================

    assign uio_out[0] = qspi_cs_n;

    assign uio_out[1] = qspi_io_out[0];
    assign uio_out[2] = qspi_io_out[1];

    assign uio_out[3] = qspi_sck;

    assign uio_out[4] = qspi_io_out[2];
    assign uio_out[5] = qspi_io_out[3];


    // RAM chip selects are unused.
    //
    // Keep both HIGH so the external PSRAM devices,
    // if present on the QSPI Pmod, remain deselected.

    assign uio_out[6] = 1'b1;
    assign uio_out[7] = 1'b1;


    // ============================================================
    // Bidirectional-pin output enables
    // ============================================================

    // Flash CS# and SCK are always driven by our ASIC.

    assign uio_oe[0] = 1'b1;
    assign uio_oe[3] = 1'b1;


    // QSPI IO0..IO3 switch direction according to qspi_reader.

    assign uio_oe[1] = qspi_io_oe[0];
    assign uio_oe[2] = qspi_io_oe[1];
    assign uio_oe[4] = qspi_io_oe[2];
    assign uio_oe[5] = qspi_io_oe[3];


    // Unused RAM chip selects are outputs driven HIGH.

    assign uio_oe[6] = 1'b1;
    assign uio_oe[7] = 1'b1;


    // ============================================================
    // Unused Tiny Tapeout inputs
    // ============================================================

    // ena and ui_in[7:1] are intentionally unused in the current design.
    // ui_in[0] selects the QSPI read timing (late_sample).
    //
    // img_width and img_height are fixed to 160x120 above.

    wire _unused = &{ena, ui_in[7:1], 1'b0};


endmodule

`default_nettype wire