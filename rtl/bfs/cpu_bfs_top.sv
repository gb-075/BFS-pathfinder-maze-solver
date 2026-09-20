// cpu_bfs_top.sv - CPU-controlled version of the maze system.
// The CPU talks to the BFS accelerator through a small MMIO register block.

`timescale 1ns/1ps

import key_pkg::*;

module cpu_bfs_top #(
    parameter int GRID_WIDTH  = 19,
    parameter int GRID_HEIGHT = 15,
    parameter int SLOWDOWN_FACTOR = 1
) (
    input  logic clk,
    input  logic rst_n,

    input  logic ps2_clk,
    input  logic ps2_data,

    output logic       vga_hsync,
    output logic       vga_vsync,
    output logic [3:0] vga_red,
    output logic [3:0] vga_green,
    output logic [3:0] vga_blue,

    output logic [31:0] cpu_pc,
    output logic        bfs_busy,
    output logic        bfs_done,
    output logic        bfs_path_found
);

    localparam int NUM_CELLS = GRID_WIDTH * GRID_HEIGHT;
    localparam int COL_BITS  = $clog2(GRID_WIDTH);
    localparam int ROW_BITS  = $clog2(GRID_HEIGHT);

    localparam logic [31:0] BFS_START_COL = 32'h00000300;
    localparam logic [31:0] BFS_START_ROW = 32'h00000304;
    localparam logic [31:0] BFS_END_COL   = 32'h00000308;
    localparam logic [31:0] BFS_END_ROW   = 32'h0000030C;
    localparam logic [31:0] BFS_CONTROL   = 32'h00000310;
    localparam logic [31:0] BFS_STATUS    = 32'h00000314;
    localparam logic [31:0] CURSOR_COL    = 32'h00000318;
    localparam logic [31:0] CURSOR_ROW    = 32'h0000031C;
    localparam logic [31:0] KEY_START     = 32'h00000320;
    localparam logic [31:0] KEY_END       = 32'h00000324;

    // ------------------------------------------------------------------
    // Keyboard path. It remains useful for moving/selecting points on the
    // display, but Enter no longer starts BFS directly in this top level.
    // ------------------------------------------------------------------
    logic [7:0] ps2_scan_code;
    logic ps2_data_valid, ps2_frame_error;

    ps2_receiver u_ps2_rx (
        .clk(clk), .rst_n(rst_n),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .scan_code(ps2_scan_code), .data_valid(ps2_data_valid),
        .frame_error(ps2_frame_error)
    );

    key_event_t key_event;
    logic key_event_valid;

    scan_code_decoder u_decoder (
        .clk(clk), .rst_n(rst_n),
        .scan_code(ps2_scan_code), .data_valid(ps2_data_valid),
        .key_event(key_event), .key_event_valid(key_event_valid)
    );

    logic [COL_BITS-1:0] cursor_col, key_start_col, key_end_col;
    logic [ROW_BITS-1:0] cursor_row, key_start_row, key_end_row;
    logic keyboard_trigger_unused;

    cursor_controller #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_cursor (
        .clk(clk), .rst_n(rst_n),
        .key_event(key_event), .key_event_valid(key_event_valid),
        .cursor_col(cursor_col), .cursor_row(cursor_row),
        .start_col(key_start_col), .start_row(key_start_row),
        .end_col(key_end_col), .end_row(key_end_row),
        .trigger_search(keyboard_trigger_unused)
    );

    // ------------------------------------------------------------------
    // Maze loading. The loader's automatic bfs_start pulse is deliberately
    // ignored here: the CPU is the only thing allowed to start the search.
    // ------------------------------------------------------------------
    logic wall_write_en, wall_write_data, load_done, loader_bfs_start_unused;
    logic [$clog2(NUM_CELLS)-1:0] wall_write_addr;

    maze_loader #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_loader (
        .clk(clk), .rst_n(rst_n),
        .wall_write_en(wall_write_en),
        .wall_write_addr(wall_write_addr),
        .wall_write_data(wall_write_data),
        .load_done(load_done),
        .bfs_start(loader_bfs_start_unused)
    );

    // Keep the CPU stopped until every wall bit has been loaded.
    logic cpu_rst_n;
    assign cpu_rst_n = rst_n && load_done;

    // ------------------------------------------------------------------
    // CPU/MMIO bus
    // ------------------------------------------------------------------
    logic [31:0] cpu_instr;
    logic [31:0] mmio_addr, mmio_wdata, mmio_rdata;
    logic mmio_read, mmio_write;

    cpu #(
        .MMIO_ENABLE(1'b1),
        .MMIO_BASE(BFS_START_COL),
        .MMIO_LAST(KEY_END)
    ) u_cpu (
        .clk(clk), .rst_n(cpu_rst_n),
        .pc_out(cpu_pc), .instr_out(cpu_instr),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_read(mmio_read), .mmio_write(mmio_write),
        .mmio_rdata(mmio_rdata)
    );

    logic [COL_BITS-1:0] bfs_start_col_reg, bfs_end_col_reg;
    logic [ROW_BITS-1:0] bfs_start_row_reg, bfs_end_row_reg;
    logic bfs_start_pulse;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bfs_start_col_reg <= '0;
            bfs_start_row_reg <= '0;
            bfs_end_col_reg   <= GRID_WIDTH - 1;
            bfs_end_row_reg   <= GRID_HEIGHT - 1;
            bfs_start_pulse   <= 1'b0;
        end else begin
            bfs_start_pulse <= 1'b0;

            if (mmio_write) begin
                case (mmio_addr)
                    BFS_START_COL: bfs_start_col_reg <= mmio_wdata[COL_BITS-1:0];
                    BFS_START_ROW: bfs_start_row_reg <= mmio_wdata[ROW_BITS-1:0];
                    BFS_END_COL:   bfs_end_col_reg   <= mmio_wdata[COL_BITS-1:0];
                    BFS_END_ROW:   bfs_end_row_reg   <= mmio_wdata[ROW_BITS-1:0];
                    BFS_CONTROL:   if (mmio_wdata[0]) bfs_start_pulse <= 1'b1;
                    default: ;
                endcase
            end
        end
    end

    always_comb begin
        mmio_rdata = 32'd0;
        case (mmio_addr)
            BFS_START_COL: mmio_rdata = {{(32-COL_BITS){1'b0}}, bfs_start_col_reg};
            BFS_START_ROW: mmio_rdata = {{(32-ROW_BITS){1'b0}}, bfs_start_row_reg};
            BFS_END_COL:   mmio_rdata = {{(32-COL_BITS){1'b0}}, bfs_end_col_reg};
            BFS_END_ROW:   mmio_rdata = {{(32-ROW_BITS){1'b0}}, bfs_end_row_reg};
            BFS_STATUS:    mmio_rdata = {29'd0, bfs_path_found, bfs_done, bfs_busy};
            CURSOR_COL:    mmio_rdata = {{(32-COL_BITS){1'b0}}, cursor_col};
            CURSOR_ROW:    mmio_rdata = {{(32-ROW_BITS){1'b0}}, cursor_row};
            KEY_START:     mmio_rdata = {{(32-ROW_BITS-COL_BITS){1'b0}}, key_start_row, key_start_col};
            KEY_END:       mmio_rdata = {{(32-ROW_BITS-COL_BITS){1'b0}}, key_end_row, key_end_col};
            default:       mmio_rdata = 32'd0;
        endcase
    end

    // ------------------------------------------------------------------
    // BFS accelerator
    // ------------------------------------------------------------------
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

    logic [$clog2(NUM_CELLS)-1:0] read_addr;
    logic [5:0] read_cell;

    bfs_engine #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT)
    ) u_bfs (
        .clk(clk), .rst_n(rst_n),
        .start(bfs_start_pulse),
        .step_en(step_en),
        .start_col(bfs_start_col_reg), .start_row(bfs_start_row_reg),
        .end_col(bfs_end_col_reg), .end_row(bfs_end_row_reg),
        .wall_write_en(wall_write_en),
        .wall_write_addr(wall_write_addr),
        .wall_write_data(wall_write_data),
        .done(bfs_done), .path_found(bfs_path_found), .busy(bfs_busy),
        .read_addr(read_addr), .read_cell(read_cell)
    );

    // ------------------------------------------------------------------
    // VGA display. The CPU-programmed start/end points are what get drawn.
    // ------------------------------------------------------------------
    logic video_on;
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
        .start_col(bfs_start_col_reg), .start_row(bfs_start_row_reg),
        .end_col(bfs_end_col_reg), .end_row(bfs_end_row_reg),
        .cursor_col(cursor_col), .cursor_row(cursor_row),
        .read_addr(read_addr), .read_cell(read_cell),
        .red(vga_red), .green(vga_green), .blue(vga_blue)
    );

endmodule
