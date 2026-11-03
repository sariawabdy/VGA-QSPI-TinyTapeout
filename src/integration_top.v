`default_nettype none
`timescale 1ns / 1ps

module integration_top (

    input  wire       clk,
    input  wire       rst_n,

    // QSPI read timing (see qspi_reader.v):
    // 0 = early sampling, 1 = late sampling for slow real-chip pins.
    input  wire       late_sample,

    // Source image dimensions.
    // We keep these configurable during simulation.
    // Later, the Tiny Tapeout wrapper may fix them to 160x120.
    input  wire [7:0] img_width,
    input  wire [6:0] img_height,

    // ============================================================
    // VGA outputs
    // ============================================================

    output wire [1:0] red,
    output wire [1:0] green,
    output wire [1:0] blue,
    output wire       hsync,
    output wire       vsync,

    // ============================================================
    // QSPI Flash interface
    // ============================================================

    output wire       qspi_sck,
    output wire       qspi_cs_n,

    // io_out = values driven toward the Flash.
    // Bit order is IO3..IO0.
    output wire [3:0] qspi_io_out,

    // io_oe controls whether each QSPI pin is driven.
    //
    // 1 = ASIC drives the pin
    // 0 = pin is high impedance / Flash drives it
    output wire [3:0] qspi_io_oe,

    // Values coming back from the Flash.
    input  wire [3:0] qspi_io_in
);


    // ============================================================
    // VGA <-> QSPI Handshake Signals
    // ============================================================

    // VGA asks QSPI to begin preparing a new source-image row.
    wire        row_start;

    // Byte offset of the source row that QSPI should begin reading.
    wire [14:0] qspi_row_base;

    // VGA tells QSPI that the current pixel byte has been consumed.
    wire        pixel_take;

    // QSPI sends the current source pixel byte to VGA.
    wire [7:0]  pixel_data;

    // Indicates that pixel_data contains a valid byte.
    wire        pixel_valid;


    // ============================================================
    // VGA Controller
    // ============================================================

    vga_controller vga_inst (

        .clk            (clk),
        .rst_n          (rst_n),

        // Pixel stream coming from the QSPI reader
        .pixel_data     (pixel_data),
        .pixel_valid    (pixel_valid),

        // Source image dimensions
        .img_width      (img_width),
        .img_height     (img_height),

        // Handshake toward QSPI
        .row_start      (row_start),
        .qspi_row_base  (qspi_row_base),
        .pixel_take     (pixel_take),

        // VGA output
        .red            (red),
        .green          (green),
        .blue           (blue),
        .hsync          (hsync),
        .vsync          (vsync)
    );


    // ============================================================
    // QSPI Reader
    // ============================================================

    qspi_reader #(
        // Image begins at Flash address 0x000000.
        .IMAGE_BASE(24'h000000)
    )
    qspi_inst (

        .clk          (clk),
        .rst_n        (rst_n),
        .late_sample  (late_sample),

        // Handshake coming from the VGA controller
        .row_start    (row_start),
        .row_base     (qspi_row_base),
        .pixel_take   (pixel_take),

        // Pixel stream toward the VGA controller
        .pixel_data   (pixel_data),
        .pixel_valid  (pixel_valid),

        // Physical QSPI interface
        .sck          (qspi_sck),
        .cs_n         (qspi_cs_n),
        .io_out       (qspi_io_out),
        .io_oe        (qspi_io_oe),
        .io_in        (qspi_io_in)
    );


endmodule

`default_nettype wire