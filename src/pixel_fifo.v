
module pixel_fifo (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,

    input  wire [7:0] data_in,
    input  wire       wr_en,

    input  wire       rd_en,
    output wire [7:0] data_out,

    output wire       full,
    output wire       empty
);

    // Memory: 32 bytes, each 8 bits
    reg [7:0] mem [0:31];

    // Pointer to next write location
    reg [4:0] write_ptr;

    // Pointer to next read location
    reg [4:0] read_ptr;

    // Number of bytes currently stored
    reg [5:0] count;

    // FIFO status flags
    assign empty = (count == 6'd0);
    assign full  = (count == 6'd32);

    assign data_out = mem[read_ptr];

    
    wire do_write = wr_en && !full;
    wire do_read  = rd_en && !empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 5'd0;
            read_ptr  <= 5'd0;
            count     <= 6'd0;
        end
        else if (clear) begin
            write_ptr <= 5'd0;
            read_ptr  <= 5'd0;
            count     <= 6'd0;
        end
        else begin

            // Write a byte into the FIFO
            if (do_write) begin
                mem[write_ptr] <= data_in;
                write_ptr <= write_ptr + 1'b1;
            end

            // Consume the oldest byte
            if (do_read) begin
                read_ptr <= read_ptr + 1'b1;
            end

            // Update number of stored bytes
            case ({do_write, do_read})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase

        end
    end

      

endmodule
