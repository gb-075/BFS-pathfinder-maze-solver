// bfs_maze_top.sv
// Top-level integration: maze loader + BFS hardware pathfinder + VGA
// controller + renderer. This is the module a board-specific top-level
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
// IMPORTANT SIMPLIFICATION (same as noted in the earlier CPU+VGA
// attempt): clk is assumed to already be the ~25 MHz VGA pixel clock,
// and everything in this design shares that single clock domain. Real
// hardware needs a board-specific PLL to derive this from the actual
// oscillator - not added yet since no target board is chosen.

`timescale 1ns/1ps

module bfs_maze_top #(
    parameter int GRID_WIDTH      = 19,
    parameter int GRID_HEIGHT     = 15,
    parameter int SLOWDOWN_FACTOR = 60000 // clocks per BFS step; tune for animation speed
) (
    input  logic clk,
    input  logic rst_n,

    output logic       vga_hsync,
    output logic       vga_vsync,
    output logic [3:0] vga_red,
    output logic [3:0] vga_green,
    output logic [3:0] vga_blue
);

    localparam int NUM_CELLS = GRID_WIDTH * GRID_HEIGHT;
    localparam logic [$clog2(GRID_WIDTH)-1:0]  START_COL = '0;
    localparam logic [$clog2(GRID_HEIGHT)-1:0] START_ROW = '0;
    localparam logic [$clog2(GRID_WIDTH)-1:0]  END_COL   = GRID_WIDTH - 1;
    localparam logic [$clog2(GRID_HEIGHT)-1:0] END_ROW   = GRID_HEIGHT - 1;

    // ---------------- Maze loader ----------------
    logic wall_write_en, wall_write_data, load_done, bfs_start;
    logic [$clog2(NUM_CELLS)-1:0] wall_write_addr;

    maze_loader #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_loader (
        .clk(clk), .rst_n(rst_n),
        .wall_write_en(wall_write_en),
        .wall_write_addr(wall_write_addr),
        .wall_write_data(wall_write_data),
        .load_done(load_done),
        .bfs_start(bfs_start)
    );

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
        .start_col(START_COL), .start_row(START_ROW),
        .end_col(END_COL), .end_row(END_ROW),
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
        .pixel_x(pixel_x), .pixel_y(pixel_y), .video_on(video_on),
        .start_col(START_COL), .start_row(START_ROW),
        .end_col(END_COL), .end_row(END_ROW),
        .read_addr(read_addr), .read_cell(read_cell),
        .red(vga_red), .green(vga_green), .blue(vga_blue)
    );

endmodule
