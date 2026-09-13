// ps2_receiver.sv - reads raw PS/2 clock/data lines, assembles bytes.
// keyboard drives the clock, host samples data on the falling edge.
// frame = start(0) + 8 data bits LSB-first + parity + stop(1)

`timescale 1ns/1ps

module ps2_receiver (
    input  logic clk,
    input  logic rst_n,

    input  logic ps2_clk,
    input  logic ps2_data,

    output logic [7:0] scan_code,
    output logic       data_valid,
    output logic       frame_error
);

    logic ps2_clk_s1, ps2_clk_s2, ps2_clk_s3;
    logic ps2_data_s1, ps2_data_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ps2_clk_s1 <= 1'b1; ps2_clk_s2 <= 1'b1; ps2_clk_s3 <= 1'b1;
            ps2_data_s1 <= 1'b1; ps2_data_s2 <= 1'b1;
        end else begin
            ps2_clk_s1 <= ps2_clk;
            ps2_clk_s2 <= ps2_clk_s1;
            ps2_clk_s3 <= ps2_clk_s2;
            ps2_data_s1 <= ps2_data;
            ps2_data_s2 <= ps2_data_s1;
        end
    end

    logic falling_edge;
    assign falling_edge = ps2_clk_s3 & ~ps2_clk_s2;

    logic [3:0] bit_count;
    logic [7:0] data_reg;
    logic       start_bit, parity_bit;
    logic       expected_parity;

    assign expected_parity = ~(^data_reg);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_count   <= '0;
            data_valid  <= 1'b0;
            frame_error <= 1'b0;
            scan_code   <= 8'd0;
        end else begin
            data_valid  <= 1'b0;
            frame_error <= 1'b0;

            if (falling_edge) begin
                case (bit_count)
                    4'd0: start_bit <= ps2_data_s2;
                    4'd1,4'd2,4'd3,4'd4,4'd5,4'd6,4'd7,4'd8:
                        data_reg[bit_count-1] <= ps2_data_s2;
                    4'd9:  parity_bit <= ps2_data_s2;
                    4'd10: begin
                        if (start_bit == 1'b0 && ps2_data_s2 == 1'b1 && parity_bit == expected_parity) begin
                            scan_code  <= data_reg;
                            data_valid <= 1'b1;
                        end else begin
                            frame_error <= 1'b1;
                        end
                    end
                endcase

                if (bit_count == 4'd10) bit_count <= '0;
                else                    bit_count <= bit_count + 1'b1;
            end
        end
    end

endmodule
