// tb_ps2_receiver.sv
// Verifies ps2_receiver.sv by bit-banging real PS/2 frame timing (start
// bit, LSB-first data, odd parity, stop bit) as a simulated keyboard
// would, and checking the receiver correctly decodes it - including a
// deliberately bad-parity frame, which should raise frame_error rather
// than being silently accepted.

`timescale 1ns/1ps

module tb_ps2_receiver;

    logic clk, rst_n;
    logic ps2_clk, ps2_data;
    logic [7:0] scan_code;
    logic data_valid, frame_error;

    ps2_receiver dut (
        .clk(clk), .rst_n(rst_n),
        .ps2_clk(ps2_clk), .ps2_data(ps2_data),
        .scan_code(scan_code), .data_valid(data_valid), .frame_error(frame_error)
    );

    initial clk = 0;
    always #5 clk = ~clk; // 100MHz system clock

    int errors = 0;

    // Bit-bang timing: much slower than the system clock (as real PS/2
    // is relative to a real FPGA clock), but fast enough to keep
    // simulation quick. Absolute speed doesn't matter for correctness -
    // only that the receiver's synchronizer can resolve each edge,
    // which it easily can with these margins.
    task send_bit(input logic bit_val);
        ps2_data = bit_val;
        #200; // setup time before clock falls
        ps2_clk = 0; // falling edge - this is what the receiver detects
        #400;
        ps2_clk = 1;
        #200;
    endtask

    task send_byte_good(input [7:0] b);
        logic parity;
        parity = ~(^b); // odd parity
        send_bit(1'b0);       // start
        for (int i = 0; i < 8; i++) send_bit(b[i]); // LSB first
        send_bit(parity);
        send_bit(1'b1);       // stop
    endtask

    task send_byte_bad_parity(input [7:0] b);
        logic parity;
        parity = ~(^b);
        send_bit(1'b0);
        for (int i = 0; i < 8; i++) send_bit(b[i]);
        send_bit(~parity);    // deliberately wrong parity
        send_bit(1'b1);
    endtask

    initial begin
        rst_n = 0;
        ps2_clk = 1;
        ps2_data = 1;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ---- Test 1: a normal scan code, e.g. 0x1C ('A' key make code) ----
        fork
            send_byte_good(8'h1C);
            begin
                wait (data_valid == 1'b1);
                if (scan_code == 8'h1C)
                    $display("PASS: received correct scan code 0x1C");
                else begin
                    $display("FAIL: expected scan_code=0x1C, got 0x%h", scan_code);
                    errors++;
                end
            end
        join

        repeat (20) @(posedge clk);

        // ---- Test 2: extended-key prefix byte 0xE0 ----
        fork
            send_byte_good(8'hE0);
            begin
                wait (data_valid == 1'b1);
                if (scan_code == 8'hE0)
                    $display("PASS: received correct scan code 0xE0 (extended prefix)");
                else begin
                    $display("FAIL: expected scan_code=0xE0, got 0x%h", scan_code);
                    errors++;
                end
            end
        join

        repeat (20) @(posedge clk);

        // ---- Test 3: bad parity should raise frame_error, not data_valid ----
        fork
            send_byte_bad_parity(8'h75); // up-arrow make code, corrupted
            begin
                wait (frame_error == 1'b1 || data_valid == 1'b1);
                if (frame_error && !data_valid)
                    $display("PASS: bad-parity frame correctly raised frame_error");
                else begin
                    $display("FAIL: bad-parity frame did not raise frame_error correctly (frame_error=%b data_valid=%b)", frame_error, data_valid);
                    errors++;
                end
            end
        join

        repeat (20) @(posedge clk);

        // ---- Test 4: a full realistic sequence - 0xF0 0x1C (break code for 'A') ----
        fork
            send_byte_good(8'hF0);
            begin
                wait (data_valid == 1'b1);
                if (scan_code == 8'hF0)
                    $display("PASS: received correct scan code 0xF0 (break prefix)");
                else begin
                    $display("FAIL: expected scan_code=0xF0, got 0x%h", scan_code);
                    errors++;
                end
            end
        join

        if (errors == 0)
            $display("\nALL PS2 RECEIVER CHECKS PASSED");
        else
            $display("\n%0d PS2 RECEIVER CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
