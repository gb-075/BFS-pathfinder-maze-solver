// bfs_maze_top.sv
// Top-level integration: maze loader + BFS hardware pathfinder + VGA
// controller + renderer + PS/2 keyboard input for interactive
// start/end selection. This is the module a board-specific top-level
// (with real pin assignments) would eventually instantiate.
//
// A slow step_en pulse throttles how fast the BFS search visibly
// progresses - without this, the entire ~1700-cycle search would finish
// in well under 1ms (a tiny fraction of one 1/60s video frame), so a
// human watching the display would never see the frontier expand; it
// would just appear solved instantly. SLOWDOWN_FACTOR is tuned so the
// full search takes a few seconds, matching how the reference project
// this is modeled on visibly animated its search.
//
// Keyboard controls: arrow keys move a selection cursor (shown in
// yellow), '1' sets the start point to the cursor's position, '2' sets
// the end point, Enter re-runs the search with the current start/end.
// On power-up, before any key is pressed, the maze automatically runs
// once with default start/end points (top-left to bottom-right) -
// keyboard input is optional, not required to see the design work.
//
// IMPORTANT SIMPLIFICATION (same as noted in the earlier CPU+VGA
// attempt): clk is assumed to already be the ~25 MHz VGA pixel clock,
// and everything in this design - including the PS/2 receiver's system
// clock - shares that single clock domain. Real hardware needs a
// board-specific PLL to derive this from the actual oscillator - not
// added yet since no target board is chosen.

`timescale 1ns/1ps

import key_pkg::*;

module bfs_maze_top #(
    parameter int GRID_WIDTH      = 19,
    parameter int GRID_HEIGHT     = 15,
    parameter int SLOWDOWN_FACTOR = 60000 // clocks per BFS step; tune for animation speed
) (
    input  logic clk,
    input  logic rst_n,

    input  logic ps2_clk,
    input  logic ps2_data,

    output logic       vga_hsync,
    output logic       vga_vsync,
    output logic [3:0] vga_red,
    output logic [3:0] vga_green,
    output logic [3:0] vga_blue
);

    localparam int NUM_CELLS = GRID_WIDTH * GRID_HEIGHT;

    // ---------------- PS/2 input pipeline ----------------
    logic [7:0] ps2_scan_code;
    logic ps2_data_valid, ps2_frame_error;

    ps2_receiver u_ps2_rx (
        .clk(clk), .rst_n(rst_n),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .scan_code(ps2_scan_code), .data_valid(ps2_data_valid), .frame_error(ps2_frame_error)
    );

    key_event_t key_event;
    logic key_event_valid;

    scan_code_decoder u_decoder (
        .clk(clk), .rst_n(rst_n),
        .scan_code(ps2_scan_code), .data_valid(ps2_data_valid),
        .key_event(key_event), .key_event_valid(key_event_valid)
    );

    logic [$clog2(GRID_WIDTH)-1:0]  cursor_col, sel_start_col, sel_end_col;
    logic [$clog2(GRID_HEIGHT)-1:0] cursor_row, sel_start_row, sel_end_row;
    logic keyboard_trigger;

    cursor_controller #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_cursor (
        .clk(clk), .rst_n(rst_n),
        .key_event(key_event), .key_event_valid(key_event_valid),
        .cursor_col(cursor_col), .cursor_row(cursor_row),
        .start_col(sel_start_col), .start_row(sel_start_row),
        .end_col(sel_end_col), .end_row(sel_end_row),
        .trigger_search(keyboard_trigger)
    );

    // ---------------- Maze loader ----------------
    logic wall_write_en, wall_write_data, load_done, loader_bfs_start;
    logic [$clog2(NUM_CELLS)-1:0] wall_write_addr;

    maze_loader #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_loader (
        .clk(clk), .rst_n(rst_n),
        .wall_write_en(wall_write_en),
        .wall_write_addr(wall_write_addr),
        .wall_write_data(wall_write_data),
        .load_done(load_done),
        .bfs_start(loader_bfs_start)
    );

    // Search starts either automatically once (right after the maze
    // loads, using cursor_controller's default corner-to-corner points)
    // or whenever the user presses Enter with new points selected.
    logic bfs_start;
    assign bfs_start = loader_bfs_start | keyboard_trigger;

    // ---------------- Step-rate throttle ----------------
    logic [31:0] slow_counter;
    logic step_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slow_counter <= '0;
        end else if (slow_counter == SLOWDOWN_FACTOR - 1) begin
            slow_counter <= '0;
        end else begin
            slow_counter <= slow_counter + 1'b1;
        end
    end

    assign step_en = (slow_counter == '0);

    // ---------------- BFS engine ----------------
    logic done, path_found, busy;
    logic [$clog2(NUM_CELLS)-1:0] read_addr;
    logic [5:0] read_cell;

    bfs_engine #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_bfs (
        .clk(clk), .rst_n(rst_n),
        .start(bfs_start),
        .step_en(step_en),
        .start_col(sel_start_col), .start_row(sel_start_row),
        .end_col(sel_end_col), .end_row(sel_end_row),
        .wall_write_en(wall_write_en),
        .wall_write_addr(wall_write_addr),
        .wall_write_data(wall_write_data),
        .done(done), .path_found(path_found), .busy(busy),
        .read_addr(read_addr), .read_cell(read_cell)
    );

    // ---------------- VGA controller ----------------
    logic       video_on;
    logic [9:0] pixel_x, pixel_y;

    vga_controller u_vga_ctrl (
        .clk(clk), .rst_n(rst_n),
        .hsync(vga_hsync), .vsync(vga_vsync),
        .video_on(video_on), .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    // ---------------- Renderer ----------------
    maze_render #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_render (
        .clk(clk), .rst_n(rst_n),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .video_on(video_on),
        .start_col(sel_start_col), .start_row(sel_start_row),
        .end_col(sel_end_col), .end_row(sel_end_row),
        .cursor_col(cursor_col), .cursor_row(cursor_row),
        .read_addr(read_addr), .read_cell(read_cell),
        .red(vga_red), .green(vga_green), .blue(vga_blue)
    );

endmodule
