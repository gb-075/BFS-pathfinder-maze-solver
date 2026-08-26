// tb_bfs_maze_top.sv
// End-to-end verification of bfs_maze_top: loads the real 19x15 maze,
// runs the search (at full speed - SLOWDOWN_FACTOR=1 - for fast
// simulation, unlike the real display instantiation which throttles
// for visible animation), then samples specific pixels and checks
// their color against the Python-computed ground truth path.
//
// Ground truth (from sw/bfs/gen_maze.py, GRID_WIDTH=19, GRID_HEIGHT=15):
//   start=(0,0), end=(14,18)
//   Path includes: (0,0) (2,2) (10,2) (14,10) (14,18)
//   Known wall (not on path): (0,1)

`timescale 1ns/1ps

module tb_bfs_maze_top;

    localparam int GRID_WIDTH  = 19;
    localparam int GRID_HEIGHT = 15;
    localparam int CELL_PX_W   = 34;
    localparam int CELL_PX_H   = 32;

    logic clk, rst_n;
    logic vga_hsync, vga_vsync;
    logic [3:0] vga_red, vga_green, vga_blue;

    bfs_maze_top #(
        .SLOWDOWN_FACTOR(1) // full speed for fast simulation
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .vga_hsync(vga_hsync), .vga_vsync(vga_vsync),
        .vga_red(vga_red), .vga_green(vga_green), .vga_blue(vga_blue)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int errors = 0;

    task check_cell_color(input int row, input int col, input string expect_color, input string label);
        int x, y;
        logic found;
        x = col * CELL_PX_W + (CELL_PX_W / 2);
        y = row * CELL_PX_H + (CELL_PX_H / 2);
        found = 0;
        while (!found) begin
            @(posedge clk);
            #1;
            if (dut.pixel_x == x[9:0] && dut.pixel_y == y[9:0]) found = 1;
        end

        if (expect_color == "black") begin
            if (vga_red==4'h0 && vga_green==4'h0 && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is black", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected black, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end else if (expect_color == "brightgreen") begin
            if (vga_red==4'h0 && vga_green==4'hF && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is bright green (start)", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected bright green, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end else if (expect_color == "red") begin
            if (vga_red==4'hF && vga_green==4'h0 && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is red (end)", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected red, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end else if (expect_color == "path") begin
            if (vga_red==4'h0 && vga_green==4'hA && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is on-path green", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected path green, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Loading (285 cells) + full BFS search on this maze takes well
        // under 5000 cycles at full speed - give generous margin.
        repeat (10000) @(posedge clk);

        check_cell_color(0, 1, "black", "known wall cell");
        check_cell_color(0, 0, "brightgreen", "start cell");
        check_cell_color(14, 18, "red", "end cell");
        check_cell_color(2, 2, "path", "on-path cell");
        check_cell_color(10, 2, "path", "on-path cell");
        check_cell_color(14, 10, "path", "on-path cell");

        if (errors == 0)
            $display("\nALL BFS MAZE TOP CHECKS PASSED");
        else
            $display("\n%0d BFS MAZE TOP CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
