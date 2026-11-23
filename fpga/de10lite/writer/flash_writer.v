// flash_writer.v - writes the image into the W25Q128JV once, from the FPGA.
//
// Sequence (single SPI, Mode 0, all from the datasheet):
//   1. wait for the flash to power up
//   2. 9Fh JEDEC ID             -> must be EF xx 18 (Winbond, 128 Mbit), else ERROR 1
//   3. 35h read Status Reg-2    -> if QE = 0: 06h Write Enable, 31h write SR2 with QE = 1,
//                                  wait, read again. Still 0 -> ERROR 2
//   4. for each 4 KB sector:      06h, 20h Sector Erase, wait until not busy
//   5. for each 256-byte page:    06h, 02h Page Program (bytes from the image ROM), wait
//   6. 03h read the whole image back and compare with the ROM. Any difference -> ERROR 3
// "Wait" = repeat 05h Read Status Register-1 until BUSY (bit 0) is 0.
//
// With QE = 0, IO2 is /WP and IO3 is /HOLD. The QSPI Pmod has no pull-ups on them,
// so this module drives both HIGH the whole time (wp_n, hold_n), otherwise a
// floating /HOLD could pause the flash.

`default_nettype none
`timescale 1ns / 1ps

module flash_writer #(
    parameter        IMG_SIZE   = 19200,          // bytes in the image
    parameter        IMAGE_FILE = "image.hex",    // one hex byte per line
    parameter [23:0] BASE       = 24'h000000,     // flash address of the image (4 KB aligned)
    parameter        DIV        = 4,              // SCK half-period in clk cycles (50 MHz / 8 = 6.25 MHz)
    parameter        STARTUP    = 500000          // clk cycles to wait first (10 ms at 50 MHz)
) (
    input  wire        clk,
    input  wire        rst_n,

    // flash pins (single SPI)
    output reg         sck,
    output reg         cs_n,
    output reg         mosi,     // IO0 (DI)
    input  wire        miso,     // IO1 (DO)
    output wire        wp_n,     // IO2, held high
    output wire        hold_n,   // IO3, held high

    // status
    output reg         running,
    output reg         done,
    output reg         ok,
    output reg  [1:0]  err,         // 0 none, 1 bad ID, 2 QE won't set, 3 verify mismatch
    output reg  [23:0] id,          // JEDEC ID that was read
    output reg  [15:0] mismatches   // bytes that differed in the verify pass
);

    assign wp_n   = 1'b1;
    assign hold_n = 1'b1;

    localparam [15:0] IMG_SIZE16 = IMG_SIZE;
    localparam NPAGES = (IMG_SIZE + 255) / 256;
    localparam NSECT  = (IMG_SIZE + 4095) / 4096;

    // ------------------------------------------------------------
    // Image ROM (Quartus turns this into on-chip memory, filled from IMAGE_FILE)
    // ------------------------------------------------------------
    reg [7:0]  rom [0:IMG_SIZE-1];
    initial $readmemh(IMAGE_FILE, rom);

    reg [15:0] ptr;        // next ROM byte to send / compare
    reg [7:0]  rom_q;
    always @(posedge clk)
        rom_q <= rom[ptr];

    // ------------------------------------------------------------
    // Byte engine: sends tx and receives rx at the same time, 8 SCK clocks.
    // Same Mode 0 rhythm as before: change MOSI on falling, sample MISO on rising.
    // ------------------------------------------------------------
    reg        eng_go;
    reg [7:0]  eng_tx;
    reg        eng_busy;
    reg        eng_done;
    reg [7:0]  eng_rx;
    reg [7:0]  eng_sh;
    reg [2:0]  eng_cnt;
    reg [15:0] div_cnt;
    wire       tick = (div_cnt == DIV - 1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            eng_busy <= 1'b0;
            eng_done <= 1'b0;
            eng_rx   <= 8'd0;
            eng_sh   <= 8'd0;
            eng_cnt  <= 3'd0;
            div_cnt  <= 16'd0;
            sck      <= 1'b0;
            mosi     <= 1'b0;
        end else begin
            eng_done <= 1'b0;
            if (!eng_busy) begin
                div_cnt <= 16'd0;
                sck     <= 1'b0;
                if (eng_go) begin
                    eng_busy <= 1'b1;
                    eng_sh   <= eng_tx;
                    mosi     <= eng_tx[7];          // first bit ready before the first rising edge
                    eng_cnt  <= 3'd0;
                end
            end else begin
                div_cnt <= tick ? 16'd0 : div_cnt + 16'd1;
                if (tick) begin
                    if (!sck) begin
                        sck    <= 1'b1;             // rising: flash latches MOSI, we sample MISO
                        eng_rx <= {eng_rx[6:0], miso};
                    end else begin
                        sck <= 1'b0;                // falling: next bit
                        if (eng_cnt == 3'd7) begin
                            eng_busy <= 1'b0;
                            eng_done <= 1'b1;
                        end else begin
                            eng_cnt <= eng_cnt + 3'd1;
                            eng_sh  <= eng_sh << 1;
                            mosi    <= eng_sh[6];
                        end
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------
    // Main sequencer
    // ------------------------------------------------------------
    localparam [4:0]
        M_STARTUP  = 5'd0,
        M_ID       = 5'd1,
        M_ID_CHK   = 5'd2,
        M_RDSR2    = 5'd3,
        M_QE_CHK   = 5'd4,
        M_WREN_QE  = 5'd5,
        M_WRSR2    = 5'd6,
        M_POLL     = 5'd7,
        M_POLL_CHK = 5'd8,
        M_ER_WREN  = 5'd9,
        M_ER_CMD   = 5'd10,
        M_ER_NEXT  = 5'd11,
        M_PG_WREN  = 5'd12,
        M_PG_CMD   = 5'd13,
        M_PG_NEXT  = 5'd14,
        M_VERIFY   = 5'd15,
        M_DONE     = 5'd16,
        M_ERROR    = 5'd17,
        T_CSLOW    = 5'd20,   // transaction: /CS low
        T_SEND     = 5'd21,   //   start one byte
        T_WAIT     = 5'd22,   //   wait for the byte to finish
        T_CSHIGH   = 5'd23;   //   /CS high for a few clocks, then return

    localparam [7:0] OP_READ = 8'h03, OP_PROG = 8'h02, OP_RDSR1 = 8'h05, OP_RDSR2 = 8'h35,
                     OP_WREN = 8'h06, OP_WRSR2 = 8'h31, OP_ERASE = 8'h20, OP_JEDEC = 8'h9F;

    reg [4:0]  state, t_after, busy_next;
    reg [31:0] startup_cnt;
    reg [7:0]  sr1, sr2;
    reg        qe_tried;
    reg [15:0] sector, page;

    // current transaction
    reg [7:0]  t_op;
    reg        t_has_addr;
    reg [23:0] t_addr;
    reg [8:0]  t_nout;      // data bytes to send (0..256)
    reg        t_from_rom;  // data bytes come from the ROM (else t_wval)
    reg [7:0]  t_wval;
    reg [15:0] t_nin;       // data bytes to receive
    reg [15:0] t_idx;       // byte number inside the transaction
    reg [3:0]  gap;

    wire [15:0] t_hdr   = t_has_addr ? 16'd4 : 16'd1;          // opcode (+ 3 address bytes)
    wire [15:0] t_total = t_hdr + {7'd0, t_nout} + t_nin;
    wire        t_is_in = (t_idx >= t_hdr + {7'd0, t_nout});   // current byte is a receive byte

    wire [31:0] page_addr = {page, 8'h00};
    wire [31:0] remaining = IMG_SIZE - page_addr;

    // Start a transaction; when it ends, go to `after`.
    task txn(input [7:0] op, input has_addr, input [23:0] addr, input [8:0] nout,
             input from_rom, input [7:0] wval, input [15:0] nin, input [4:0] after);
        begin
            t_op       <= op;
            t_has_addr <= has_addr;
            t_addr     <= addr;
            t_nout     <= nout;
            t_from_rom <= from_rom;
            t_wval     <= wval;
            t_nin      <= nin;
            t_after    <= after;
            state      <= T_CSLOW;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= M_STARTUP;
            t_after     <= M_STARTUP;
            busy_next   <= M_STARTUP;
            startup_cnt <= 32'd0;
            cs_n        <= 1'b1;
            eng_go      <= 1'b0;
            eng_tx      <= 8'd0;
            ptr         <= 16'd0;
            sr1         <= 8'd0;
            sr2         <= 8'd0;
            qe_tried    <= 1'b0;
            sector      <= 16'd0;
            page        <= 16'd0;
            t_op        <= 8'd0;
            t_has_addr  <= 1'b0;
            t_addr      <= 24'd0;
            t_nout      <= 9'd0;
            t_from_rom  <= 1'b0;
            t_wval      <= 8'd0;
            t_nin       <= 16'd0;
            t_idx       <= 16'd0;
            gap         <= 4'd0;
            running     <= 1'b0;
            done        <= 1'b0;
            ok          <= 1'b0;
            err         <= 2'd0;
            id          <= 24'd0;
            mismatches  <= 16'd0;
        end else begin
            eng_go <= 1'b0;

            case (state)
                // ---------------- steps ----------------
                M_STARTUP: begin
                    running <= 1'b1;
                    if (startup_cnt >= STARTUP)
                        state <= M_ID;
                    else
                        startup_cnt <= startup_cnt + 32'd1;
                end

                M_ID:      txn(OP_JEDEC, 1'b0, 24'd0, 9'd0, 1'b0, 8'd0, 16'd3, M_ID_CHK);

                M_ID_CHK: begin
                    if (id[23:16] == 8'hEF && id[7:0] == 8'h18)
                        state <= M_RDSR2;
                    else begin
                        err   <= 2'd1;
                        state <= M_ERROR;
                    end
                end

                M_RDSR2:   txn(OP_RDSR2, 1'b0, 24'd0, 9'd0, 1'b0, 8'd0, 16'd1, M_QE_CHK);

                M_QE_CHK: begin
                    if (sr2[1]) begin
                        sector <= 16'd0;
                        state  <= M_ER_WREN;
                    end else if (qe_tried) begin
                        err   <= 2'd2;
                        state <= M_ERROR;
                    end else begin
                        state <= M_WREN_QE;
                    end
                end

                M_WREN_QE: begin
                    qe_tried <= 1'b1;
                    txn(OP_WREN, 1'b0, 24'd0, 9'd0, 1'b0, 8'd0, 16'd0, M_WRSR2);
                end

                M_WRSR2: begin
                    busy_next <= M_RDSR2;                      // after the write, check QE again
                    txn(OP_WRSR2, 1'b0, 24'd0, 9'd1, 1'b0, sr2 | 8'h02, 16'd0, M_POLL);
                end

                // wait until the flash is not busy, then go to busy_next
                M_POLL:     txn(OP_RDSR1, 1'b0, 24'd0, 9'd0, 1'b0, 8'd0, 16'd1, M_POLL_CHK);
                M_POLL_CHK: state <= sr1[0] ? M_POLL : busy_next;

                M_ER_WREN:  txn(OP_WREN, 1'b0, 24'd0, 9'd0, 1'b0, 8'd0, 16'd0, M_ER_CMD);

                M_ER_CMD: begin
                    busy_next <= M_ER_NEXT;
                    txn(OP_ERASE, 1'b1, BASE + {sector[11:0], 12'h000}, 9'd0, 1'b0, 8'd0, 16'd0, M_POLL);
                end

                M_ER_NEXT: begin
                    if (sector == NSECT - 1) begin
                        page  <= 16'd0;
                        state <= M_PG_WREN;
                    end else begin
                        sector <= sector + 16'd1;
                        state  <= M_ER_WREN;
                    end
                end

                M_PG_WREN:  txn(OP_WREN, 1'b0, 24'd0, 9'd0, 1'b0, 8'd0, 16'd0, M_PG_CMD);

                M_PG_CMD: begin
                    busy_next <= M_PG_NEXT;
                    ptr       <= page_addr[15:0];
                    txn(OP_PROG, 1'b1, BASE + page_addr[23:0],
                        (remaining < 256) ? remaining[8:0] : 9'd256,
                        1'b1, 8'd0, 16'd0, M_POLL);
                end

                M_PG_NEXT: begin
                    if (page == NPAGES - 1) begin
                        state <= M_VERIFY;
                    end else begin
                        page  <= page + 16'd1;
                        state <= M_PG_WREN;
                    end
                end

                M_VERIFY: begin
                    ptr        <= 16'd0;
                    mismatches <= 16'd0;
                    txn(OP_READ, 1'b1, BASE, 9'd0, 1'b0, 8'd0, IMG_SIZE16, M_DONE);
                end

                M_DONE: begin
                    running <= 1'b0;
                    done    <= 1'b1;
                    ok      <= (mismatches == 16'd0);
                    err     <= (mismatches == 16'd0) ? 2'd0 : 2'd3;
                end

                M_ERROR: begin
                    running <= 1'b0;
                    done    <= 1'b1;
                    ok      <= 1'b0;
                end

                // ---------------- one transaction ----------------
                T_CSLOW: begin
                    cs_n  <= 1'b0;
                    t_idx <= 16'd0;
                    state <= T_SEND;
                end

                T_SEND: begin
                    if (t_idx == 16'd0)
                        eng_tx <= t_op;
                    else if (t_has_addr && t_idx == 16'd1)
                        eng_tx <= t_addr[23:16];
                    else if (t_has_addr && t_idx == 16'd2)
                        eng_tx <= t_addr[15:8];
                    else if (t_has_addr && t_idx == 16'd3)
                        eng_tx <= t_addr[7:0];
                    else if (!t_is_in) begin                 // a data byte we send
                        if (t_from_rom) begin
                            eng_tx <= rom_q;
                            ptr    <= ptr + 16'd1;
                        end else begin
                            eng_tx <= t_wval;
                        end
                    end else
                        eng_tx <= 8'h00;                     // receiving: what we send doesn't matter
                    eng_go <= 1'b1;
                    state  <= T_WAIT;
                end

                T_WAIT: begin
                    if (eng_done) begin
                        if (t_is_in) begin                   // a byte arrived from the flash
                            case (t_op)
                                OP_JEDEC: id  <= {id[15:0], eng_rx};
                                OP_RDSR1: sr1 <= eng_rx;
                                OP_RDSR2: sr2 <= eng_rx;
                                OP_READ: begin
                                    if (eng_rx != rom_q && mismatches != 16'hFFFF)
                                        mismatches <= mismatches + 16'd1;
                                    ptr <= ptr + 16'd1;
                                end
                                default: ;
                            endcase
                        end
                        if (t_idx + 16'd1 == t_total) begin
                            gap   <= 4'd0;
                            state <= T_CSHIGH;
                        end else begin
                            t_idx <= t_idx + 16'd1;
                            state <= T_SEND;
                        end
                    end
                end

                T_CSHIGH: begin
                    // /CS high: the flash runs 06h/20h/02h/31h now. Keep it high a few
                    // clocks (datasheet tSHSL: 10 ns for reads, 50 ns after writes).
                    cs_n <= 1'b1;
                    gap  <= gap + 4'd1;
                    if (gap == 4'd7)
                        state <= t_after;
                end

                default: state <= M_ERROR;
            endcase
        end
    end

endmodule

`default_nettype wire
