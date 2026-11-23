// de10lite_flash_writer_top.v - DE10-Lite design that writes the image into the
// QSPI Pmod's flash. Load it once, wait for the green light, then load de10lite_top.
//
// Same GPIO wiring as de10lite_top.v (QSPI Pmod on GPIO[7:0]), so you don't
// re-wire anything between the two designs.
//
//   KEY[0]       press = start over
//   HEX5..HEX0   the flash's JEDEC ID, should read  E F 7 0 1 8
//   LEDR[0]      working
//   LEDR[1]      DONE, everything OK (image written and verified)
//   LEDR[2]      ERROR, code on LEDR[5:4]:
//                  01 = wrong/no ID  -> check wiring and 3.3 V
//                  10 = QE could not be set
//                  11 = read-back didn't match the image
//   LEDR[9]      heartbeat (blinks = design is running)

`default_nettype none
`timescale 1ns / 1ps

module de10lite_flash_writer_top (
    input  wire        MAX10_CLK1_50,
    input  wire [1:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,
    output wire [7:0]  HEX0,
    output wire [7:0]  HEX1,
    output wire [7:0]  HEX2,
    output wire [7:0]  HEX3,
    output wire [7:0]  HEX4,
    output wire [7:0]  HEX5,
    inout  wire [35:0] GPIO
);

    wire clk = MAX10_CLK1_50;   // 50 MHz; the writer divides it down for SCK

    // Reset from KEY[0], released in sync with the clock
    reg [1:0] rst_sync;
    always @(posedge clk or negedge KEY[0]) begin
        if (!KEY[0]) rst_sync <= 2'b00;
        else         rst_sync <= {rst_sync[0], 1'b1};
    end
    wire rst_n = rst_sync[1];

    wire        sck, cs_n, mosi, wp_n, hold_n;
    wire        running, done, ok;
    wire [1:0]  err;
    wire [23:0] id;
    wire [15:0] mismatches;

    flash_writer #(
        .IMG_SIZE   (19200),
        .IMAGE_FILE ("image.hex"),
        .BASE       (24'h000000),
        .DIV        (4),          // SCK = 50 MHz / 8 = 6.25 MHz, gentle on jumper wires
        .STARTUP    (500000)      // 10 ms
    ) writer (
        .clk        (clk),
        .rst_n      (rst_n),
        .sck        (sck),
        .cs_n       (cs_n),
        .mosi       (mosi),
        .miso       (GPIO[2]),
        .wp_n       (wp_n),
        .hold_n     (hold_n),
        .running    (running),
        .done       (done),
        .ok         (ok),
        .err        (err),
        .id         (id),
        .mismatches (mismatches)
    );

    // QSPI Pmod on GPIO[7:0], same pins as de10lite_top.v
    assign GPIO[0]    = cs_n;     // uio[0] flash /CS
    assign GPIO[1]    = mosi;     // uio[1] IO0 (DI)
    assign GPIO[2]    = 1'bz;     // uio[2] IO1 (DO) - input
    assign GPIO[3]    = sck;      // uio[3] SCK
    assign GPIO[4]    = wp_n;     // uio[4] IO2 = /WP, held high
    assign GPIO[5]    = hold_n;   // uio[5] IO3 = /HOLD, held high
    assign GPIO[6]    = 1'b1;     // uio[6] RAM A /CS, off
    assign GPIO[7]    = 1'b1;     // uio[7] RAM B /CS, off
    assign GPIO[35:8] = {28{1'bz}};

    // Seven-segment: hex digit -> segments (active low, decimal point off)
    function [7:0] seg;
        input [3:0] d;
        case (d)
            4'h0: seg = 8'hC0;  4'h1: seg = 8'hF9;  4'h2: seg = 8'hA4;  4'h3: seg = 8'hB0;
            4'h4: seg = 8'h99;  4'h5: seg = 8'h92;  4'h6: seg = 8'h82;  4'h7: seg = 8'hF8;
            4'h8: seg = 8'h80;  4'h9: seg = 8'h90;  4'hA: seg = 8'h88;  4'hB: seg = 8'h83;
            4'hC: seg = 8'hC6;  4'hD: seg = 8'hA1;  4'hE: seg = 8'h86;  default: seg = 8'h8E;
        endcase
    endfunction

    assign HEX5 = seg(id[23:20]);
    assign HEX4 = seg(id[19:16]);
    assign HEX3 = seg(id[15:12]);
    assign HEX2 = seg(id[11:8]);
    assign HEX1 = seg(id[7:4]);
    assign HEX0 = seg(id[3:0]);

    reg [24:0] beat;
    always @(posedge clk) beat <= beat + 25'd1;

    assign LEDR[0]   = running;
    assign LEDR[1]   = done & ok;
    assign LEDR[2]   = done & ~ok;
    assign LEDR[3]   = 1'b0;
    assign LEDR[5:4] = err;
    assign LEDR[8:6] = 3'b000;
    assign LEDR[9]   = beat[24];

    wire _unused = &{SW, KEY[1], mismatches, 1'b0};

endmodule

`default_nettype wire
