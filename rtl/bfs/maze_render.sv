// maze_render.sv
// Maps a VGA pixel coordinate to a color based on the current BFS grid
// state, read one cell at a time via bfs_engine's read_addr/read_cell
// interface (NOT an unpacked array port - that pattern caused an
// unresolved X-propagation bug in an earlier version of this project;
// see README).
//
// Cell colors:
//   cursor (highest priority) -> yellow (always visible, shows selection)
//   start cell              -> bright green
//   end cell                -> red
//   wall                    -> black
//   on_path                 -> green
//   visited (frontier)      -> light blue
//   open, unexplored        -> white
//
// Pixel-to-cell coordinate conversion is delegated to pixel_to_cell.sv,
// which uses counters instead of division (a wide combinational divider
// is a poor fit for FPGA timing closure at real pixel clocks - this
// module used to do `pixel_x / CELL_PX_W` directly; see
// pixel_to_cell.sv for the full story, including a one-cycle-latency
// bug that a full-frame verification against a division-based reference
// caught before it shipped).
//
// Because pixel_to_cell is registered, cell_col/cell_row (and therefore
// read_addr/read_cell and the final color) reflect the PREVIOUS pixel
// clock's position - one cycle of pipeline latency, which is normal for
// synchronous hardware. This shifts the rendered image by one pixel
// clock out of ~34 per cell (under 3% of one cell's width) - well below
// any perceptible threshold, so it isn't corrected for here. If exact
// per-pixel alignment ever mattered, video_on/pixel_x/pixel_y would
// need matching one-cycle delays before use elsewhere in this module.

`timescale 1ns/1ps

module maze_render #(
    parameter int GRID_WIDTH  = 19,
    parameter int GRID_HEIGHT = 15,
    parameter int CELL_PX_W   = 34, // 640 / 19, rounded up (last column is narrower)
    parameter int CELL_PX_H   = 32  // 480 / 15, exact
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

    // Read port into the BFS engine's grid memory
    output logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0] read_addr,
    input  logic [5:0] read_cell,   // {on_path, parent_dir[2:0], visited, wall}

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

    always_comb begin
        if (!video_on) begin
            {red, green, blue} = 12'h000;
        end else if (is_cursor) begin
            {red, green, blue} = 12'hFF0; // yellow - highest priority, always visible
        end else if (is_start) begin
            {red, green, blue} = 12'h0F0; // bright green
        end else if (is_end) begin
            {red, green, blue} = 12'hF00; // red
        end else if (is_wall) begin
            {red, green, blue} = 12'h000; // black
        end else if (is_on_path) begin
            {red, green, blue} = 12'h0A0; // medium green
        end else if (is_visited) begin
            {red, green, blue} = 12'h99F; // light blue - the explored frontier
        end else begin
            {red, green, blue} = 12'hFFF; // white - open, unexplored
        end
    end

endmodule
