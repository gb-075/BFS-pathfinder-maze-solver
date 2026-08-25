// tb_vga_controller.sv
// Verifies vga_controller.sv against the standard 640x480@60Hz VESA
// timing spec by measuring actual signal edge timing: hsync pulse
// width, total line length, total frame length, and pixel_x sweep
// behavior during the visible area.

`timescale 1ns/1ps

module tb_vga_controller;

    logic clk, rst_n;
    logic hsync, vsync, video_on;
    logic [9:0] pixel_x, pixel_y;

    localparam int CLK_PERIOD = 10; // ns

    vga_controller dut (
        .clk(clk), .rst_n(rst_n),
        .hsync(hsync), .vsync(vsync), .video_on(video_on),
        .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    int errors = 0;
    real t1, t2;
    int measured;

    task check(input logic cond, input string msg);
        if (!cond) begin
            $display("FAIL: %s", msg);
            errors++;
        end else begin
            $display("PASS: %s", msg);
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        // ---- hsync pulse width should be 96 clocks ----
        @(negedge hsync);
        t1 = $realtime;
        @(posedge hsync);
        t2 = $realtime;
        measured = $rtoi((t2 - t1) / CLK_PERIOD);
        check(measured == 96, $sformatf("hsync pulse width: expected 96, got %0d", measured));

        // ---- total line length should be 800 clocks (time between consecutive hsync negedges) ----
        @(negedge hsync);
        t1 = $realtime;
        @(negedge hsync);
        t2 = $realtime;
        measured = $rtoi((t2 - t1) / CLK_PERIOD);
        check(measured == 800, $sformatf("total line length: expected 800, got %0d", measured));

        // ---- vsync pulse width should be 2*800=1600 clocks (2 lines) ----
        @(negedge vsync);
        t1 = $realtime;
        @(posedge vsync);
        t2 = $realtime;
        measured = $rtoi((t2 - t1) / CLK_PERIOD);
        check(measured == 1600, $sformatf("vsync pulse width: expected 1600 (2 lines), got %0d", measured));

        // ---- total frame length should be 525*800=420000 clocks ----
        @(negedge vsync);
        t1 = $realtime;
        @(negedge vsync);
        t2 = $realtime;
        measured = $rtoi((t2 - t1) / CLK_PERIOD);
        check(measured == 420000, $sformatf("total frame length: expected 420000, got %0d", measured));

        // ---- pixel_x should sweep 0..639 monotonically during a visible line ----
        @(posedge video_on);
        check(pixel_x == 10'd0, $sformatf("pixel_x should start at 0, got %0d", pixel_x));
        for (int i = 0; i < 639; i++) begin
            @(posedge clk);
            #1; // let the DUT's nonblocking assignment settle before sampling
            check(pixel_x == i[9:0] + 10'd1,
                  $sformatf("pixel_x correct at step %0d: got %0d", i, pixel_x));
        end
        @(posedge clk);
        #1;
        check(video_on == 1'b0, "video_on should deassert right after pixel_x=639");

        if (errors == 0)
            $display("\nALL VGA TIMING CHECKS PASSED");
        else
            $display("\n%0d VGA TIMING CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
