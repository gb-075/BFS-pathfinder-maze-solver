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
    logic ps2_clk, ps2_data;

    bfs_maze_top #(
        .SLOWDOWN_FACTOR(1) // full speed for fast simulation
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .vga_hsync(vga_hsync), .vga_vsync(vga_vsync),
        .vga_red(vga_red), .vga_green(vga_green), .vga_blue(vga_blue)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int errors = 0;

    // Real PS/2 bit-banging, same technique verified in tb_ps2_receiver.sv -
    // this drives the actual ps2_clk/ps2_data top-level ports, so key
    // presses flow through the real receiver + decoder + cursor
    // controller, exactly as real hardware would receive them.
    task send_bit(input logic bit_val);
        ps2_data = bit_val;
        #200;
        ps2_clk = 0;
        #400;
        ps2_clk = 1;
        #200;
    endtask

    task send_scan_code(input [7:0] b);
        logic parity;
        parity = ~(^b);
        send_bit(1'b0);
        for (int i = 0; i < 8; i++) send_bit(b[i]);
        send_bit(parity);
        send_bit(1'b1);
    endtask

    task press_key(input [7:0] code, input bit extended);
        if (extended) send_scan_code(8'hE0);
        send_scan_code(code);
        #2000; // let the decoder/cursor controller settle between presses
    endtask

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
        end else if (expect_color == "cursor") begin
            if (vga_red==4'hF && vga_green==4'hF && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is yellow (cursor)", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected yellow cursor, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end else if (expect_color == "brightgreen") begin
            if (vga_red==4'h0 && vga_green==4'hF && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is bright green (start)", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected bright green, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end else if (expect_color == "red") begin
            if (vga_red==4'hF && vga_green==4'h0 && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is red (end)", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected red, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end else if (expect_color == "path") begin
            if (vga_red==4'h0 && vga_green==4'hA && vga_blue==4'h0) $display("PASS: %s (%0d,%0d) is on-path green", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected path green, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end else if (expect_color == "white") begin
            if (vga_red==4'hF && vga_green==4'hF && vga_blue==4'hF) $display("PASS: %s (%0d,%0d) is white (open, unvisited)", label, row, col);
            else begin $display("FAIL: %s (%0d,%0d) expected white, got R=%h G=%h B=%h", label, row, col, vga_red, vga_green, vga_blue); errors++; end
        end
    endtask

    initial begin
        rst_n = 0;
        ps2_clk = 1;   // idle-high: no keyboard activity in this test,
        ps2_data = 1;  // just verifying the automatic default-corner run
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Loading (285 cells) + full BFS search on this maze takes well
        // under 5000 cycles at full speed - give generous margin.
        repeat (10000) @(posedge clk);

        check_cell_color(0, 1, "black", "known wall cell");
        // NOTE: (0,0) is both the default start point AND the cursor's
        // default position (before any key is pressed) - the cursor
        // renders with the highest priority (see maze_render.sv), so it
        // correctly shows yellow here, not the start cell's green. This
        // is intentional: you should always be able to see exactly
        // where the cursor is, even when it overlaps a special cell.
        check_cell_color(0, 0, "cursor", "start cell (currently showing cursor, which starts here too)");
        check_cell_color(14, 18, "red", "end cell");
        check_cell_color(2, 2, "path", "on-path cell");
        check_cell_color(10, 2, "path", "on-path cell");
        check_cell_color(14, 10, "path", "on-path cell");

        // ---- Now test the interactive PS/2 flow: re-select a NEW,
        // shorter end point and confirm the hardware re-solves for it ----
        // Move cursor from (0,0) to (2,2) via 2x DOWN + 2x RIGHT
        press_key(8'h72, 1); press_key(8'h72, 1); // Down, Down (extended)
        press_key(8'h74, 1); press_key(8'h74, 1); // Right, Right (extended)
        press_key(8'h1E, 0); // '2' - set end to cursor's position (2,2)
        press_key(8'h5A, 0); // Enter - trigger new search
        press_key(8'h72, 1); press_key(8'h72, 1); press_key(8'h72, 1); // move cursor away (Down x3) so it doesn't mask (2,2)'s true color

        // Ground truth: (0,0)->(2,2) is a prefix of the original path -
        // (0,0),(1,0),(2,0),(2,1),(2,2) - since this is a perfect maze
        // (exactly one path between any two cells), so the new search
        // should find exactly that same route.
        repeat (10000) @(posedge clk); // let the new (small, fast) search finish

        // NOTE: cursor was deliberately moved away from (2,2) above so
        // this checks the cell's TRUE color, not the cursor overlay.
        check_cell_color(2, 2, "red", "NEW end point (2,2) after keyboard re-selection");
        check_cell_color(1, 0, "path", "cell on the NEW shorter path");
        check_cell_color(14, 18, "white", "OLD end point - no longer marked, unreached by the new short search");

        if (errors == 0)
            $display("\nALL BFS MAZE TOP CHECKS PASSED");
        else
            $display("\n%0d BFS MAZE TOP CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
