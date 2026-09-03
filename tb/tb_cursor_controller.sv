// tb_cursor_controller.sv
// Verifies cursor_controller.sv: movement, boundary clamping (can't
// move off the grid edges), start/end selection, and the search
// trigger pulse.

`timescale 1ns/1ps

import key_pkg::*;

module tb_cursor_controller;

    localparam int W = 19;
    localparam int H = 15;

    logic clk, rst_n;
    key_event_t key_event;
    logic key_event_valid;
    logic [$clog2(W)-1:0] cursor_col, start_col, end_col;
    logic [$clog2(H)-1:0] cursor_row, start_row, end_row;
    logic trigger_search;

    cursor_controller #(.GRID_WIDTH(W), .GRID_HEIGHT(H)) dut (
        .clk(clk), .rst_n(rst_n),
        .key_event(key_event), .key_event_valid(key_event_valid),
        .cursor_col(cursor_col), .cursor_row(cursor_row),
        .start_col(start_col), .start_row(start_row),
        .end_col(end_col), .end_row(end_row),
        .trigger_search(trigger_search)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int errors = 0;

    task press(input key_event_t k);
        @(posedge clk);
        key_event       <= k;
        key_event_valid <= 1'b1;
        @(posedge clk);
        key_event_valid <= 1'b0;
        #1;
    endtask

    task check(input logic cond, input string msg);
        if (!cond) begin $display("FAIL: %s", msg); errors++; end
        else $display("PASS: %s", msg);
    endtask

    initial begin
        rst_n = 0;
        key_event = KEY_NONE;
        key_event_valid = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        check(cursor_row == 0 && cursor_col == 0, "cursor starts at (0,0)");
        check(start_row == 0 && start_col == 0, "start defaults to (0,0)");
        check(end_row == H-1 && end_col == W-1, "end defaults to bottom-right corner");

        // Try to move up/left from the origin - should clamp, not wrap or go negative
        press(KEY_UP);
        check(cursor_row == 0, "moving UP at row 0 stays clamped at 0");
        press(KEY_LEFT);
        check(cursor_col == 0, "moving LEFT at col 0 stays clamped at 0");

        // Move to a specific interior point: down x3, right x5
        press(KEY_DOWN); press(KEY_DOWN); press(KEY_DOWN);
        press(KEY_RIGHT); press(KEY_RIGHT); press(KEY_RIGHT); press(KEY_RIGHT); press(KEY_RIGHT);
        check(cursor_row == 3 && cursor_col == 5, "cursor moved to (3,5) via 3 downs + 5 rights");

        // Set start here
        press(KEY_SET_START);
        check(start_row == 3 && start_col == 5, "'1' sets start to cursor's current position (3,5)");

        // Move further and set end
        press(KEY_DOWN); press(KEY_DOWN);
        press(KEY_RIGHT); press(KEY_RIGHT);
        check(cursor_row == 5 && cursor_col == 7, "cursor moved to (5,7)");
        press(KEY_SET_END);
        check(end_row == 5 && end_col == 7, "'2' sets end to cursor's current position (5,7)");

        // Confirm should pulse trigger_search for exactly one cycle
        @(posedge clk);
        key_event <= KEY_CONFIRM;
        key_event_valid <= 1'b1;
        @(posedge clk);
        key_event_valid <= 1'b0;
        #1;
        check(trigger_search == 1'b1, "Enter pulses trigger_search");
        @(posedge clk);
        #1;
        check(trigger_search == 1'b0, "trigger_search deasserts after one cycle");

        // Test clamping at the opposite corners too
        repeat (30) press(KEY_DOWN); // way more than needed - should clamp at H-1
        repeat (30) press(KEY_RIGHT); // should clamp at W-1
        check(cursor_row == H-1, "moving DOWN repeatedly clamps at bottom row");
        check(cursor_col == W-1, "moving RIGHT repeatedly clamps at rightmost col");

        if (errors == 0)
            $display("\nALL CURSOR CONTROLLER CHECKS PASSED");
        else
            $display("\n%0d CURSOR CONTROLLER CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
