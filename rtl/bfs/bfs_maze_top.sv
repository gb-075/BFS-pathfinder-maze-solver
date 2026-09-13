// bfs_maze_top.sv - wires the maze loader, BFS engine, VGA controller,
// renderer, and PS/2 input together into one system

`timescale 1ns/1ps

import key_pkg::*;

module bfs_maze_top #(
    parameter int GRID_WIDTH      = 19,
    parameter int GRID_HEIGHT     = 15,
    parameter int SLOWDOWN_FACTOR = 60000
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

    logic bfs_start;
    assign bfs_start = loader_bfs_start | keyboard_trigger;

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

    logic       video_on;
    logic [9:0] pixel_x, pixel_y;

    vga_controller u_vga_ctrl (
        .clk(clk), .rst_n(rst_n),
        .hsync(vga_hsync), .vsync(vga_vsync),
        .video_on(video_on), .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

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
