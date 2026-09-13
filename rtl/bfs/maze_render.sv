// maze_render.sv - colors each VGA pixel based on the maze cell it's in

`timescale 1ns/1ps

module maze_render #(
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

    input  logic [$clog2(GRID_WIDTH)-1:0]  start_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] start_row,
    input  logic [$clog2(GRID_WIDTH)-1:0]  end_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] end_row,
    input  logic [$clog2(GRID_WIDTH)-1:0]  cursor_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] cursor_row,

    output logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0] read_addr,
    input  logic [5:0] read_cell,

    output logic [3:0] red,
    output logic [3:0] green,
    output logic [3:0] blue
);

    logic [$clog2(GRID_WIDTH)-1:0]  cell_col;
    logic [$clog2(GRID_HEIGHT)-1:0] cell_row;

    pixel_to_cell #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT),
        .CELL_PX_W(CELL_PX_W), .CELL_PX_H(CELL_PX_H)
    ) u_pixel_to_cell (
        .clk(clk), .rst_n(rst_n),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .video_on(video_on),
        .cell_col(cell_col), .cell_row(cell_row)
    );

    assign read_addr = cell_row * GRID_WIDTH + cell_col;

    logic is_wall, is_visited, is_on_path;
    logic is_start, is_end, is_cursor;

    assign is_wall     = read_cell[0];
    assign is_visited  = read_cell[1];
    assign is_on_path  = read_cell[5];
    assign is_start    = (cell_row == start_row) && (cell_col == start_col);
    assign is_end      = (cell_row == end_row)   && (cell_col == end_col);
    assign is_cursor   = (cell_row == cursor_row) && (cell_col == cursor_col);

    // cursor checked first so it's always visible even on top of start/end/etc
    always_comb begin
        if (!video_on) begin
            {red, green, blue} = 12'h000;
        end else if (is_cursor) begin
            {red, green, blue} = 12'hFF0;
        end else if (is_start) begin
            {red, green, blue} = 12'h0F0;
        end else if (is_end) begin
            {red, green, blue} = 12'hF00;
        end else if (is_wall) begin
            {red, green, blue} = 12'h000;
        end else if (is_on_path) begin
            {red, green, blue} = 12'h0A0;
        end else if (is_visited) begin
            {red, green, blue} = 12'h99F;
        end else begin
            {red, green, blue} = 12'hFFF;
        end
    end

endmodule
