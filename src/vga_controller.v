`default_nettype none
`timescale 1ns / 1ps

module vga_controller (
    input  wire       clk,
    input  wire       rst_n,

    // Pixel stream from Leen's QSPI reader
    input  wire [7:0] pixel_data,
    input  wire       pixel_valid,

    // Source image dimensions
    input  wire [7:0] img_width,
    input  wire [6:0] img_height,

    // Handshake toward Leen's QSPI reader
    output wire        row_start,
    output wire [14:0] qspi_row_base,
    output wire        pixel_take,

    // VGA outputs
    output wire [1:0] red,
    output wire [1:0] green,
    output wire [1:0] blue,
    output wire       hsync,
    output wire       vsync
);

    // ============================================================
    // VGA Timing Parameters - 640x480
    // ============================================================

    // Horizontal timing:
    //
    // | Visible | Front Porch | HSYNC | Back Porch |
    // |   640   |     16      |   96  |     48     |
    //
    // Total = 800 pixel clock cycles per line

    localparam H_VISIBLE = 640;
    localparam H_FRONT   = 16;
    localparam H_SYNC    = 96;
    localparam H_BACK    = 48;
    localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;


    // Vertical timing:
    //
    // | Visible | Front Porch | VSYNC | Back Porch |
    // |   480   |     10      |   2   |     33     |
    //
    // Total = 525 lines per frame

    localparam V_VISIBLE = 480;
    localparam V_FRONT   = 10;
    localparam V_SYNC    = 2;
    localparam V_BACK    = 33;
    localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;


    // ============================================================
    // VGA Position Counters
    // ============================================================

    // h_count represents the current horizontal position in a line.
    // v_count represents the current vertical line in a frame.
    //
    // 10 bits are enough because:
    // h_count ranges from 0 to 799
    // v_count ranges from 0 to 524

    reg [9:0] h_count;
    reg [9:0] v_count;


    // ============================================================
    // Image Size and Centering
    // ============================================================

    // The source image can be up to 160x120 pixels.
    // Each source pixel will later be displayed as a 4x4 block,
    // so the displayed image dimensions are 4 times larger.
    //
    // Example:
    // Source image = 100x80
    // Display size = 400x320
    //
    // The offsets represent the number of VGA pixels between the
    // edge of the 640x480 visible area and the centered image.
    //
    // x_offset = (640 - display_width) / 2
    // y_offset = (480 - display_height) / 2

    wire [9:0] display_width;
    wire [8:0] display_height;

    wire [9:0] x_offset;
    wire [8:0] y_offset;

    // Appending two zero bits is equivalent to multiplying by 4.
    // 160x120 therefore becomes 640x480.
    assign display_width  = {img_width,  2'b00};
    assign display_height = {img_height, 2'b00};

    // Calculate the offsets required to center the image.
    // Right shifting by one bit is equivalent to dividing by 2.
    assign x_offset = (H_VISIBLE - display_width) >> 1;
    assign y_offset = (V_VISIBLE - display_height) >> 1;


    // ============================================================
    // Visible Pixel Region
    // ============================================================

    // active_pixel is high only inside the visible 640x480 area.
    // During the front porch, sync, and back porch regions it is low.

    wire active_pixel;

    assign active_pixel =
        (h_count < H_VISIBLE) &&
        (v_count < V_VISIBLE);


    // ============================================================
    // Active Image Region
    // ============================================================

    // active_pixel tells us whether we are inside the visible
    // 640x480 VGA area.
    //
    // active_image tells us whether we are inside the smaller,
    // centered image inside that visible area.
    //
    // Pixels outside the centered image will be displayed as black.

    // active_pixel identifies the full visible 640x480 VGA area.
    // active_image identifies the actual centered image inside that area.
    //
    // Since our source images are at most 160x120 and are scaled by 4,
    // the displayed image can never be larger than 640x480.
    // Therefore, anything that is not active_image can safely be shown as black.
    //
    // We still keep active_pixel because it clearly separates VGA visibility
    // from image-placement logic and protects against drawing during porch/sync timing.

    wire active_image;

    assign active_image =
        active_pixel &&
        (h_count >= x_offset) &&
        (h_count <  x_offset + display_width) &&
        (v_count >= y_offset) &&
        (v_count <  y_offset + display_height);


    // ============================================================
    // Source Image Coordinates
    // ============================================================

    // Convert the current VGA coordinate into a coordinate inside
    // the original source image.
    //
    // First subtract the centering offset, then divide by 4 because
    // every source pixel is displayed as a 4x4 block.
    //
    // source_x ranges from 0 to 159  -> 8 bits
    // source_y ranges from 0 to 119  -> 7 bits

    wire [7:0] source_x;
    wire [6:0] source_y;

    assign source_x = active_image ?
                    (h_count - x_offset) >> 2 :
                    8'd0;

    assign source_y = active_image ?
                    (v_count - y_offset) >> 2 :
                    7'd0;


    // ============================================================
    // Pixel Index Calculation
    // ============================================================

    // Flash stores the image as a one-dimensional sequence of bytes.
    //
    // Normally:
    // pixel_index = source_y * img_width + source_x
    //
    // To avoid implementing a hardware multiplier, row_base stores
    // the address of the first pixel of the current source-image row.
    //
    // Example for img_width = 100:
    //
    // source row 0 -> row_base = 0
    // source row 1 -> row_base = 100
    // source row 2 -> row_base = 200
    //
    // The final pixel index is then calculated using only an addition:
    //
    // pixel_index = row_base + source_x

    reg  [14:0] row_base;
    wire [14:0] pixel_index;

    // Maximum image size is 160x120 = 19,200 pixels.
    // 15 bits are required because 2^14 = 16,384 is too small,
    // while 2^15 = 32,768 is enough.

    assign pixel_index = row_base + {7'd0, source_x};

    // Vertical position relative to the beginning of the image.
    // This is used to detect every fourth displayed VGA line.

    wire [9:0] image_y_position;

    assign image_y_position =
        v_count - {1'b0, y_offset};

    // Horizontal position relative to the beginning of the image.
    //
    // Each source pixel is displayed for 4 VGA clocks.
    // The bottom two bits therefore tell us which clock of the
    // 4-clock source pixel we are currently displaying.

    wire [9:0] image_x_position;

    assign image_x_position =
        h_count - x_offset;


    // ============================================================
    // QSPI Row Prefetch Interface
    // ============================================================

    // Leen's QSPI reader must begin fetching the next VGA line
    // during the current line's horizontal blanking period.
    //
    // row_start is therefore asserted for one clock when:
    //
    //     h_count = 640
    //
    // which is the first clock immediately after the visible
    // horizontal region.
    //
    // qspi_row_base contains the source-image row address that
    // will be needed by the NEXT VGA line, not the current line.

    wire [9:0] next_v_count;
    wire       next_line_has_image;

    // Determine which VGA line comes after the current one.
    //
    // Normally:
    // next_v_count = v_count + 1
    //
    // But after the final VGA line (524), the next line is
    // line 0 of the next frame.

    assign next_v_count =
        (v_count == V_TOTAL - 1) ?
        10'd0 :
        v_count + 10'd1;


    // Check whether the NEXT VGA line is vertically inside
    // the centered image.
    //
    // We only need to start a QSPI read if the next line
    // will actually display image pixels.

    assign next_line_has_image =
        (next_v_count >= y_offset) &&
        (next_v_count < y_offset + display_height);


    // row_start is a one-clock pulse at the beginning of
    // horizontal blanking (h_count = 640).
    //
    // This gives Leen's QSPI reader the blanking interval
    // to prepare the first pixel of the NEXT VGA line.

    assign row_start =
        (h_count == H_VISIBLE) &&
        next_line_has_image;


    // qspi_row_base is the Flash row address needed by the
    // NEXT VGA line.
    //
    // Case 1:
    // If the next line is the first displayed line of the image,
    // start again from source row 0.
    //
    // Case 2:
    // If the current VGA line is the fourth line representing
    // the current source-image row, the next VGA line needs
    // the next source row, so add img_width.
    //
    // Case 3:
    // Otherwise, the next VGA line repeats the same source row.

    assign qspi_row_base =
        (next_v_count == y_offset) ?
            15'd0 :
        (
            next_line_has_image &&
            (v_count >= y_offset) &&
            (v_count < y_offset + display_height) &&
            (image_y_position[1:0] == 2'b11)
        ) ?
            row_base + {7'd0, img_width} :
            row_base;


    // pixel_take tells the QSPI reader that the current byte
    // has finished being displayed.
    //
    // A source pixel occupies four VGA clocks:
    //
    // relative x = 0 -> 00
    // relative x = 1 -> 01
    // relative x = 2 -> 10
    // relative x = 3 -> 11  <- take current byte
    //
    // pixel_take is only generated while:
    //   - we are inside the actual image
    //   - the QSPI reader says pixel_data is valid

    assign pixel_take =
        active_image &&
        pixel_valid &&
        (image_x_position[1:0] == 2'b11);


    // ============================================================
    // VGA Synchronization Signals
    // ============================================================

    // HSYNC is active-low during the horizontal sync interval.
    // It provides the monitor with the horizontal timing reference
    // for each scan line.

    assign hsync = ~(
        (h_count >= H_VISIBLE + H_FRONT) &&
        (h_count <  H_VISIBLE + H_FRONT + H_SYNC)
    );


    // VSYNC is active-low during the vertical sync interval.
    // It provides the monitor with the vertical timing reference
    // for each frame.

    assign vsync = ~(
        (v_count >= V_VISIBLE + V_FRONT) &&
        (v_count <  V_VISIBLE + V_FRONT + V_SYNC)
    );


    // ============================================================
    // RGB222 Pixel Output
    // ============================================================

    // Pixel format:
    //
    // pixel_data = 00 RR GG BB
    //
    // RGB values are displayed only inside the active image region.
    // Everything outside the centered image is displayed as black.

    // Display RGB data only when:
    //   - we are inside the active image
    //   - the QSPI reader says pixel_data is valid
    //
    // If pixel_valid is low, the VGA timing continues normally,
    // but the pixel is displayed as black.

    assign red =
        (active_image && pixel_valid) ?
        pixel_data[5:4] :
        2'b00;

    assign green =
        (active_image && pixel_valid) ?
        pixel_data[3:2] :
        2'b00;

    assign blue =
        (active_image && pixel_valid) ?
        pixel_data[1:0] :
        2'b00;


    // ============================================================
    // VGA Timing Counters
    // ============================================================

    // h_count advances once every pixel clock.
    //
    // At the end of a horizontal line:
    //   - h_count returns to 0
    //   - v_count advances to the next line
    //
    // At the end of the final line:
    //   - both counters return to 0
    //   - a new frame begins

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end
        else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;

                if (v_count == V_TOTAL - 1)
                    v_count <= 10'd0;
                else
                    v_count <= v_count + 1'b1;
            end
            else begin
                h_count <= h_count + 1'b1;
            end
        end
    end


    // ============================================================
    // Source Row Base Address
    // ============================================================

    // row_base advances by img_width after every four VGA lines,
    // because four VGA lines represent one row of source-image pixels.
    //
    // The update happens at the end of the VGA line (h_count = 799),
    // so the new row_base is already ready before the next line begins.
    //
    // At the end of the full VGA frame, row_base returns to 0.

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_base <= 15'd0;
        end
        else begin

            // Only update row_base at the end of a VGA line
            if (h_count == H_TOTAL - 1) begin

                // A new VGA frame starts after the final line
                if (v_count == V_TOTAL - 1) begin
                    row_base <= 15'd0;
                end

                // If we are inside the image vertically and this is
                // the fourth VGA line of a source-image row,
                // advance to the beginning of the next source row.
                else if (
                    (v_count >= y_offset) &&
                    (v_count < y_offset + display_height) &&
                    (image_y_position[1:0] == 2'b11)
                ) begin
                    row_base <= row_base + {7'd0, img_width};
                end
            end
        end
    end

endmodule

`default_nettype wire
