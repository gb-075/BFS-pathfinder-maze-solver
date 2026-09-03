// tb_pixel_to_cell.sv
// Verifies pixel_to_cell.sv (counter-based, synthesis-friendly) against
// a division-based reference computed directly in the testbench, across
// EVERY pixel of a full VGA frame - not just a few samples. Division is
// fine to use here since this is verification code, not synthesized
// hardware; the point is confirming the counter-based RTL produces
// identical results to the "obviously correct" reference.

`timescale 1ns/1ps

module tb_pixel_to_cell;

    localparam int GRID_WIDTH  = 19;
    localparam int GRID_HEIGHT = 15;
    localparam int CELL_PX_W   = 34;
    localparam int CELL_PX_H   = 32;

    logic clk, rst_n;
    logic hsync, vsync, video_on;
    logic [9:0] pixel_x, pixel_y;

    vga_controller u_vga (
        .clk(clk), .rst_n(rst_n),
        .hsync(hsync), .vsync(vsync), .video_on(video_on),
        .pixel_x(pixel_x), .pixel_y(pixel_y)
    );

    logic [$clog2(GRID_WIDTH)-1:0]  cell_col;
    logic [$clog2(GRID_HEIGHT)-1:0] cell_row;

    pixel_to_cell #(
        .GRID_WIDTH(GRID_WIDTH), .GRID_HEIGHT(GRID_HEIGHT),
        .CELL_PX_W(CELL_PX_W), .CELL_PX_H(CELL_PX_H)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .pixel_x(pixel_x), .pixel_y(pixel_y), .video_on(video_on),
        .cell_col(cell_col), .cell_row(cell_row)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    int errors = 0;
    int checked = 0;
    int expected_col, expected_row;

    // pixel_to_cell is REGISTERED (sequential), so its outputs reflect
    // the PREVIOUS cycle's pixel_x/pixel_y - this is normal, expected
    // pipeline latency for any synchronous circuit, not a bug. To
    // compare correctly, we track pixel_x/pixel_y/video_on delayed by
    // one cycle to match what the DUT is actually responding to.
    logic [9:0] pixel_x_d, pixel_y_d;
    logic video_on_d;

    always_ff @(posedge clk) begin
        pixel_x_d <= pixel_x;
        pixel_y_d <= pixel_y;
        video_on_d <= video_on;
    end

    initial begin
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        // Run for slightly more than one full frame (420000 clocks) plus
        // margin, checking every visible pixel.
        repeat (425000) begin
            @(posedge clk);
            #1; // let this cycle's registered outputs (both DUT and our delayed reference) settle
            if (video_on_d) begin
                expected_col = pixel_x_d / CELL_PX_W;
                expected_row = pixel_y_d / CELL_PX_H;
                checked++;
                if (cell_col != expected_col[$clog2(GRID_WIDTH)-1:0] ||
                    cell_row != expected_row[$clog2(GRID_HEIGHT)-1:0]) begin
                    if (errors < 10) // don't flood output if something's badly wrong
                        $display("FAIL: pixel(%0d,%0d) expected cell(%0d,%0d), got cell(%0d,%0d)",
                                  pixel_x_d, pixel_y_d, expected_row, expected_col, cell_row, cell_col);
                    errors++;
                end
            end
        end

        $display("\nChecked %0d visible pixels across a full frame", checked);
        if (errors == 0)
            $display("ALL PIXEL_TO_CELL CHECKS PASSED (exact match with division reference)");
        else
            $display("%0d PIXEL_TO_CELL MISMATCH(ES) (see above, capped at first 10)", errors);

        $finish;
    end

endmodule
