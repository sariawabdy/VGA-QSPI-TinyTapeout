// flash_model.v - simulation model of the Winbond W25Q128JV (testbench only).
//
// Supports what our chip uses:
//   03h  Read Data              (single SPI, data on IO1)
//   6Bh  Fast Read Quad Output  (8 dummy clocks, then 4 bits per SCK on IO3..IO0)
// SPI Mode 0: command/address latched on SCK rising edges, data driven on falling edges.
//
// OUT_DELAY models the round trip through the chip's pins: the flash's answer
// shows up OUT_DELAY ns after the SCK falling edge (0 = ideal).

`timescale 1ns / 1ps

module flash_model #(
    parameter IMAGE_FILE = "image.hex",
    parameter OUT_DELAY  = 0,             // ns
    parameter IMG_BYTES  = 19200          // bytes in IMAGE_FILE
) (
    input  wire cs_n,
    input  wire sck,
    inout  wire io0,
    inout  wire io1,
    inout  wire io2,
    inout  wire io3
);

    // 64 KB is plenty for a 19,200-byte image; addresses wrap inside it.
    reg [7:0] mem [0:65535];
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 8'hFF;                       // erased flash reads 0xFF
        $readmemh(IMAGE_FILE, mem, 0, IMG_BYTES - 1);
    end

    localparam S_CMD = 0, S_ADDR = 1, S_DUMMY = 2, S_DATA1 = 3, S_DATA4 = 4, S_IGNORE = 5;

    integer   state;
    integer   count;
    reg [7:0] cmd;
    reg [23:0] addr;
    reg [7:0] out_byte;
    integer   out_bit;                            // bits (03h) or nibbles (6Bh) already sent

    reg [3:0] out_en;                             // 1 = flash drives that IO pin
    reg [3:0] out_val;

    assign io0 = out_en[0] ? out_val[0] : 1'bz;
    assign io1 = out_en[1] ? out_val[1] : 1'bz;
    assign io2 = out_en[2] ? out_val[2] : 1'bz;
    assign io3 = out_en[3] ? out_val[3] : 1'bz;

    initial begin
        out_en  = 4'b0000;
        out_val = 4'b0000;
        state   = S_CMD;
    end

    // /CS low starts a transaction, /CS high ends it and releases the pins
    always @(negedge cs_n) begin
        state = S_CMD;
        count = 0;
        cmd   = 8'h00;
        addr  = 24'h000000;
    end

    always @(posedge cs_n) begin
        out_en <= #(OUT_DELAY) 4'b0000;
        state = S_IGNORE;
    end

    // Rising edge: latch IO0
    always @(posedge sck) if (!cs_n) begin
        case (state)
            S_CMD: begin
                cmd   = {cmd[6:0], io0};
                count = count + 1;
                if (count == 8) begin
                    count = 0;
                    if (cmd == 8'h03 || cmd == 8'h6B) state = S_ADDR;
                    else                               state = S_IGNORE;
                end
            end
            S_ADDR: begin
                addr  = {addr[22:0], io0};
                count = count + 1;
                if (count == 24) begin
                    count = 0;
                    if (cmd == 8'h03) begin
                        out_byte = mem[addr[15:0]];
                        out_bit  = 0;
                        state    = S_DATA1;       // first bit goes out on the next falling edge
                    end else begin
                        state = S_DUMMY;
                    end
                end
            end
            S_DUMMY: begin
                count = count + 1;
                if (count == 8) begin
                    out_byte = mem[addr[15:0]];
                    out_bit  = 0;
                    state    = S_DATA4;       // high nibble goes out on the next falling edge
                end
            end
            default: ;
        endcase
    end

    // Falling edge: drive the next bit(s)
    always @(negedge sck) if (!cs_n) begin
        if (state == S_DATA1) begin
            out_en  <= #(OUT_DELAY) 4'b0010;
            out_val <= #(OUT_DELAY) {2'b00, out_byte[7 - out_bit], 1'b0};
            out_bit = out_bit + 1;
            if (out_bit == 8) begin
                addr     = addr + 24'd1;
                out_byte = mem[addr[15:0]];
                out_bit  = 0;
            end
        end else if (state == S_DATA4) begin
            out_en  <= #(OUT_DELAY) 4'b1111;
            out_val <= #(OUT_DELAY) (out_bit == 0) ? out_byte[7:4] : out_byte[3:0];
            out_bit = out_bit + 1;
            if (out_bit == 2) begin
                addr     = addr + 24'd1;
                out_byte = mem[addr[15:0]];
                out_bit  = 0;
            end
        end
    end

endmodule
