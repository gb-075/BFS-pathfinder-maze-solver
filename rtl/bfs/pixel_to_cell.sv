// pixel_to_cell.sv - figures out which maze cell a VGA pixel belongs to,
// using counters instead of division (better for real FPGA timing)

`timescale 1ns/1ps

module pixel_to_cell #(
    parameter int GRID_WIDTH  = 19,
    parameter int GRID_HEIGHT = 15,
    parameter int CELL_PX_W   = 34,
    parameter int CELL_PX_H   = 32
) (
    input  logic clk,
    input  logic rst_n,

    input  logic [9:0] pixel_x,
    input  logic [9:0] pixel_y,
    input  logic       video_on,

    output logic [$clog2(GRID_WIDTH)-1:0]  cell_col,
    output logic [$clog2(GRID_HEIGHT)-1:0] cell_row
);

    // NOTE: tried edge-detecting video_on going 0->1 here originally,
    // but that added an extra cycle of delay on top of video_on already
    // being registered, so cell boundaries landed one pixel clock late.
    // checking pixel_x==0 directly instead sidesteps the whole problem.
    logic line_start;
    assign line_start = video_on && (pixel_x == 10'd0);

    logic [$clog2(CELL_PX_W)-1:0] col_px_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col_px_count <= '0;
            cell_col     <= '0;
        end else if (line_start) begin
            col_px_count <= '0;
            cell_col     <= '0;
        end else if (video_on) begin
            if (col_px_count == CELL_PX_W - 1) begin
                col_px_count <= '0;
                if (cell_col != GRID_WIDTH - 1) cell_col <= cell_col + 1'b1;
            end else begin
                col_px_count <= col_px_count + 1'b1;
            end
        end
    end

    logic [$clog2(CELL_PX_H)-1:0] row_px_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_px_count <= '0;
            cell_row     <= '0;
        end else if (line_start) begin
            if (pixel_y == 10'd0) begin
                row_px_count <= '0;
                cell_row     <= '0;
            end else begin
                if (row_px_count == CELL_PX_H - 1) begin
                    row_px_count <= '0;
                    if (cell_row != GRID_HEIGHT - 1) cell_row <= cell_row + 1'b1;
                end else begin
                    row_px_count <= row_px_count + 1'b1;
                end
            end
        end
    end

endmodule
