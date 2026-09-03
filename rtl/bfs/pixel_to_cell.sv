// pixel_to_cell.sv
// Converts a VGA pixel position into a grid cell coordinate WITHOUT
// division - the earlier version of maze_render.sv used `pixel_x /
// CELL_PX_W`, which is correct in simulation but infers a wide
// combinational divider that's a poor fit for FPGA timing closure at
// real pixel clock speeds. This version instead maintains small
// counters that increment in step with the pixel clock and roll over
// at each cell boundary - the standard technique for this problem.
//
// Column tracking resets whenever pixel_x==0 during the visible area -
// this is reliably a single clock cycle per line (pixel_x is forced to
// 0 throughout horizontal blanking too, but video_on is false then, so
// gating on both together isolates exactly the one real cycle per line
// where a new line's first pixel is being drawn).
//
// An earlier version of this module tried to detect "start of a new
// line" via edge-detecting video_on's rising edge instead (a registered
// video_on_d compared against video_on). That introduced an extra
// cycle of latency - the edge detector's own register added a cycle on
// top of video_on already being a registered-derived signal from
// vga_controller, so cell boundaries fell one pixel clock later than
// correct. Verified against a full-frame division-based reference
// before the bug was caught; see README for details. Using pixel_x==0
// directly, rather than detecting a transition, avoids the whole class
// of bug by not needing an edge detector at all.

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

    logic line_start;
    assign line_start = video_on && (pixel_x == 10'd0);

    // ---------------- Column tracking (every visible line) ----------------
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
                // if already at the last column, stay there (handles the
                // narrower final column when CELL_PX_W doesn't divide evenly)
            end else begin
                col_px_count <= col_px_count + 1'b1;
            end
        end
    end

    // ---------------- Row tracking (once per line, reset once per frame) ----------------
    logic [$clog2(CELL_PX_H)-1:0] row_px_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_px_count <= '0;
            cell_row     <= '0;
        end else if (line_start) begin
            if (pixel_y == 10'd0) begin
                // First visible line of a new frame.
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
