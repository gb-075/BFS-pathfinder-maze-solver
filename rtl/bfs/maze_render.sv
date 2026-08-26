// maze_render.sv
// Combinational rendering logic: maps a VGA pixel coordinate to a color
// based on the current BFS grid state, read one cell at a time via
// bfs_engine's read_addr/read_cell interface (NOT an unpacked array
// port - that pattern caused an unresolved X-propagation bug in an
// earlier version of this project; see README).
//
// Cell colors:
//   wall              -> black
//   open, unvisited   -> white
//   visited (frontier)-> light blue   (shows BFS's search progress)
//   on_path           -> green        (the final shortest path)
//   start cell        -> bright green (overrides other states)
//   end cell          -> red          (overrides other states)
//
// NOTE: like gol_render.sv before it, this uses '/' for cell_row/cell_col
// (constant-divisor division) which is correct in simulation but not
// necessarily the best choice for FPGA timing closure at high pixel
// clocks - noted as a known follow-up, not an oversight.

`timescale 1ns/1ps

module maze_render #(
    parameter int GRID_WIDTH  = 19,
    parameter int GRID_HEIGHT = 15,
    parameter int CELL_PX_W   = 34, // 640 / 19, rounded up (last column is narrower)
    parameter int CELL_PX_H   = 32  // 480 / 15, exact
) (
    input  logic [9:0] pixel_x,
    input  logic [9:0] pixel_y,
    input  logic       video_on,

    input  logic [$clog2(GRID_WIDTH)-1:0]  start_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] start_row,
    input  logic [$clog2(GRID_WIDTH)-1:0]  end_col,
    input  logic [$clog2(GRID_HEIGHT)-1:0] end_row,

    // Read port into the BFS engine's grid memory
    output logic [$clog2(GRID_WIDTH*GRID_HEIGHT)-1:0] read_addr,
    input  logic [5:0] read_cell,   // {on_path, parent_dir[2:0], visited, wall}

    output logic [3:0] red,
    output logic [3:0] green,
    output logic [3:0] blue
);

    logic [$clog2(GRID_WIDTH)-1:0]  cell_col;
    logic [$clog2(GRID_HEIGHT)-1:0] cell_row;

    assign cell_col = pixel_x / CELL_PX_W;
    assign cell_row = pixel_y / CELL_PX_H;

    assign read_addr = cell_row * GRID_WIDTH + cell_col;

    logic is_wall, is_visited, is_on_path;
    logic is_start, is_end;

    assign is_wall     = read_cell[0];
    assign is_visited  = read_cell[1];
    assign is_on_path  = read_cell[5];
    assign is_start    = (cell_row == start_row) && (cell_col == start_col);
    assign is_end      = (cell_row == end_row)   && (cell_col == end_col);

    always_comb begin
        if (!video_on) begin
            {red, green, blue} = 12'h000;
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
