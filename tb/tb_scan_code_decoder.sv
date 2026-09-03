// tb_scan_code_decoder.sv
// Verifies scan_code_decoder.sv against realistic PS/2 byte sequences:
// a plain key press, an extended (arrow) key press, a full press+release
// cycle (release must NOT fire an event), and an unrecognized key
// (must also not fire an event).

`timescale 1ns/1ps

import key_pkg::*;

module tb_scan_code_decoder;

    logic clk, rst_n;
    logic [7:0] scan_code;
    logic data_valid;
    key_event_t key_event;
    logic key_event_valid;

    scan_code_decoder dut (
        .clk(clk), .rst_n(rst_n),
        .scan_code(scan_code), .data_valid(data_valid),
        .key_event(key_event), .key_event_valid(key_event_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int errors = 0;

    task feed_byte(input [7:0] b);
        @(posedge clk);
        scan_code  <= b;      // nonblocking: avoids a same-edge race with the
        data_valid <= 1'b1;   // DUT's own always_ff, which is sensitive to
                               // this same clock edge
        @(posedge clk);       // DUT correctly samples data_valid=1 here
        data_valid <= 1'b0;
        scan_code  <= 8'h00;
        #1; // let this edge's key_event_valid nonblocking update settle
    endtask

    task check_event(input logic expect_valid, input key_event_t expect_key, input string label);
        if (key_event_valid !== expect_valid) begin
            $display("FAIL: %s - expected key_event_valid=%b, got %b", label, expect_valid, key_event_valid);
            errors++;
        end else if (expect_valid && key_event !== expect_key) begin
            $display("FAIL: %s - expected key_event=%p, got %p", label, expect_key, key_event);
            errors++;
        end else begin
            $display("PASS: %s", label);
        end
    endtask

    initial begin
        rst_n = 0;
        data_valid = 0;
        scan_code = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Test 1: plain key press ('1' -> KEY_SET_START)
        feed_byte(8'h16);
        check_event(1'b1, KEY_SET_START, "'1' key press fires KEY_SET_START");

        // Test 2: '2' -> KEY_SET_END
        feed_byte(8'h1E);
        check_event(1'b1, KEY_SET_END, "'2' key press fires KEY_SET_END");

        // Test 3: Enter -> KEY_CONFIRM
        feed_byte(8'h5A);
        check_event(1'b1, KEY_CONFIRM, "Enter key press fires KEY_CONFIRM");

        // Test 4: extended key press - Up arrow (0xE0 0x75)
        feed_byte(8'hE0);
        check_event(1'b0, KEY_NONE, "extended prefix alone fires nothing yet");
        feed_byte(8'h75);
        check_event(1'b1, KEY_UP, "Up arrow (extended) fires KEY_UP");

        // Test 5: full press+release cycle for Right arrow - release must fire nothing
        feed_byte(8'hE0);
        feed_byte(8'h74); // Right arrow press
        check_event(1'b1, KEY_RIGHT, "Right arrow press fires KEY_RIGHT");
        feed_byte(8'hF0); // break prefix
        check_event(1'b0, KEY_NONE, "break prefix alone fires nothing");
        feed_byte(8'hE0); // release is also prefixed with extended for arrow keys
        check_event(1'b0, KEY_NONE, "extended prefix during release fires nothing");
        feed_byte(8'h74); // Right arrow release (same code as press)
        check_event(1'b0, KEY_NONE, "Right arrow RELEASE correctly fires no event");

        // Test 6: unrecognized key (e.g. 0x1A = 'S' key) should fire nothing
        feed_byte(8'h1A);
        check_event(1'b0, KEY_NONE, "unrecognized key correctly fires no event");

        // Test 7: press+release of a plain (non-extended) key - release must fire nothing
        feed_byte(8'h16); // '1' press
        check_event(1'b1, KEY_SET_START, "'1' press fires KEY_SET_START again");
        feed_byte(8'hF0); // break prefix
        feed_byte(8'h16); // '1' release
        check_event(1'b0, KEY_NONE, "'1' RELEASE correctly fires no event");

        if (errors == 0)
            $display("\nALL SCAN CODE DECODER CHECKS PASSED");
        else
            $display("\n%0d SCAN CODE DECODER CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
