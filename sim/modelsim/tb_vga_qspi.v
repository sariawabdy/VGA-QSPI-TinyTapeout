// tb_vga_qspi.v - ModelSim testbench for tt_um_sari_leen_vga_qspi
//
// What it does:
//   - 25 MHz clock, reset, ui_in[0] = LATE_SAMPLE
//   - connects the uio pins to flash_model.v (loaded with image.hex), like the QSPI Pmod
//   - runs one whole frame plus the start of the next one
//   - checks every VGA pixel against image.hex, and checks HSYNC / VSYNC positions
//   - checks that the chip and the flash never drive the same IO pin at once
//   - saves the second frame as frame.bmp (double-click on Windows) and frame.ppm
//   - prints PASS or FAIL
//
// Parameters (change with vsim -g, see run_late.do):
//   LATE_SAMPLE = value of ui_in[0]   FLASH_DELAY = pin round trip in ns

`timescale 1ns / 1ps

module tb_vga_qspi;

    parameter LATE_SAMPLE = 0;
    parameter FLASH_DELAY = 0;
    parameter IMAGE_FILE  = "image.hex";

    localparam IMG_W = 160, IMG_H = 120;
    localparam H_TOTAL = 800, V_TOTAL = 525;

    // ---------------- the chip ----------------
    reg        clk = 1'b0;
    reg        rst_n = 1'b0;
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    wire [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_sari_leen_vga_qspi dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (1'b1),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    always #20 clk = ~clk;                       // 40 ns period = 25 MHz

    // ---------------- the uio pins, like the real board ----------------
    // Each pin is driven by the chip only when uio_oe says so; otherwise the flash can drive it.
    wire [7:0] uio_pin;
    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : pins
            assign uio_pin[k] = uio_oe[k] ? uio_out[k] : 1'bz;
            pullup (uio_pin[k]);                 // a floating pin reads 1 instead of X
        end
    endgenerate
    assign uio_in = uio_pin;

    // QSPI Pmod pinout: uio[0]=/CS, uio[1]=IO0, uio[2]=IO1, uio[3]=SCK, uio[4]=IO2, uio[5]=IO3
    flash_model #(.IMAGE_FILE(IMAGE_FILE), .OUT_DELAY(FLASH_DELAY)) flash (
        .cs_n (uio_pin[0]),
        .sck  (uio_pin[3]),
        .io0  (uio_pin[1]),
        .io1  (uio_pin[2]),
        .io2  (uio_pin[4]),
        .io3  (uio_pin[5])
    );

    // ---------------- expected image ----------------
    reg [7:0] image [0:IMG_W*IMG_H-1];
    initial $readmemh(IMAGE_FILE, image);

    // ---------------- checks ----------------
    integer errors       = 0;
    integer pixel_checks = 0;
    integer fights       = 0;
    integer n            = 0;                    // rising clock edges since reset was released
    integer h, v, frame, col, row;
    reg [7:0] got, want;
    reg [5:0] frame1 [0:640*480-1];              // captured frame 1, 00RRGGBB without the top bits

    // Bus fight: the chip and the flash drive the same data pin
    always @(posedge uio_pin[3] or negedge uio_pin[3]) begin
        if ((flash.out_en[0] && uio_oe[1]) || (flash.out_en[1] && uio_oe[2]) ||
            (flash.out_en[2] && uio_oe[4]) || (flash.out_en[3] && uio_oe[5])) begin
            fights = fights + 1;
            if (fights <= 3) $display("[%0t] ERROR: bus fight on the flash data pins", $time);
        end
    end

    always @(posedge clk) if (rst_n) n <= n + 1;

    // Sample in the middle of each clock period
    always @(negedge clk) if (rst_n) begin
        h     = n % H_TOTAL;
        v     = (n / H_TOTAL) % V_TOTAL;
        frame = n / (H_TOTAL * V_TOTAL);

        // decode Tiny VGA pins -> 00RRGGBB
        got = {2'b00, uo_out[0], uo_out[4], uo_out[1], uo_out[5], uo_out[2], uo_out[6]};

        if (h < 640 && v < 480) begin
            if (frame == 1) frame1[v * 640 + h] = got[5:0];
            // check the inside of every 4x4 block (tolerant to a 1-clock offset);
            // skip line 0 of the very first frame: nothing could be prefetched before reset
            if ((h % 4 == 1 || h % 4 == 2) && (v % 4 == 1 || v % 4 == 2) && !(frame == 0 && v < 4)) begin
                col  = h / 4;
                row  = v / 4;
                want = image[row * IMG_W + col];
                pixel_checks = pixel_checks + 1;
                if (got !== want) begin
                    errors = errors + 1;
                    if (errors <= 5)
                        $display("[%0t] ERROR: frame %0d line %0d x %0d: got %02h, expected %02h",
                                 $time, frame, v, h, got, want);
                end
            end
        end

        // sync positions (middle of each region, so a 1-clock offset doesn't matter)
        if (h == 700 && uo_out[7] !== 1'b0) begin errors = errors + 1; $display("ERROR: HSYNC not low at x=700, line %0d", v); end
        if (h == 300 && uo_out[7] !== 1'b1) begin errors = errors + 1; $display("ERROR: HSYNC not high at x=300, line %0d", v); end
        if (h == 400 && v == 491 && uo_out[3] !== 1'b0) begin errors = errors + 1; $display("ERROR: VSYNC not low on line 491"); end
        if (h == 400 && v == 300 && uo_out[3] !== 1'b1) begin errors = errors + 1; $display("ERROR: VSYNC not high on line 300"); end
    end

    // write a value as n little-endian bytes (for the BMP file)
    task write_le(input integer fd, input integer value, input integer n);
        integer j;
        for (j = 0; j < n; j = j + 1)
            $fwrite(fd, "%c", (value >> (8 * j)) & 8'hFF);
    endtask

    // ---------------- run ----------------
    integer f, p, r, g, b;
    initial begin
        ui_in = LATE_SAMPLE ? 8'd1 : 8'd0;
        $display("tb_vga_qspi: LATE_SAMPLE=%0d FLASH_DELAY=%0d ns", LATE_SAMPLE, FLASH_DELAY);

        repeat (10) @(posedge clk);
        @(negedge clk) rst_n = 1'b1;

        // frame 0, then all of frame 1, then the first lines of frame 2
        wait (n == 2 * H_TOTAL * V_TOTAL + 8 * H_TOTAL);
        @(negedge clk);

        // save frame 1 as a picture (PPM, 2 bits per color -> max value 3)
        f = $fopen("frame.ppm", "w");
        $fwrite(f, "P3\n640 480\n3\n");
        for (p = 0; p < 640 * 480; p = p + 1) begin
            r = frame1[p][5:4]; g = frame1[p][3:2]; b = frame1[p][1:0];
            $fwrite(f, "%0d %0d %0d\n", r, g, b);
        end
        $fclose(f);

        // also save it as frame.bmp (24-bit BMP), which Windows opens with a double-click
        f = $fopen("frame.bmp", "wb");
        write_le(f, 16'h4D42, 2);                // "BM"
        write_le(f, 54 + 640 * 480 * 3, 4);      // file size
        write_le(f, 0, 4);                       // reserved
        write_le(f, 54, 4);                      // offset to pixel data
        write_le(f, 40, 4);                      // header size
        write_le(f, 640, 4);                     // width
        write_le(f, 480, 4);                     // height (rows stored bottom-up)
        write_le(f, 1, 2);                       // planes
        write_le(f, 24, 2);                      // bits per pixel
        write_le(f, 0, 4);                       // no compression
        write_le(f, 640 * 480 * 3, 4);           // image size
        write_le(f, 2835, 4);                    // 72 dpi
        write_le(f, 2835, 4);
        write_le(f, 0, 4);
        write_le(f, 0, 4);
        for (r = 479; r >= 0; r = r - 1)
            for (p = 0; p < 640; p = p + 1) begin
                write_le(f, frame1[r * 640 + p][1:0] * 85, 1);   // blue  (0..3 -> 0..255)
                write_le(f, frame1[r * 640 + p][3:2] * 85, 1);   // green
                write_le(f, frame1[r * 640 + p][5:4] * 85, 1);   // red
            end
        $fclose(f);

        $display("------------------------------------------------------------");
        $display("pixels checked: %0d   pixel/sync errors: %0d   bus fights: %0d",
                 pixel_checks, errors, fights);
        if (errors == 0 && fights == 0 && pixel_checks > 0)
            $display("PASS  (picture saved as frame.bmp and frame.ppm)");
        else
            $display("FAIL");
        $display("------------------------------------------------------------");
        $stop;
    end

endmodule
