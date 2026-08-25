// vga_controller.sv
// Standard 640x480 @ 60Hz VGA timing generator (VESA industry-standard
// timing). Assumes `clk` is already the VGA pixel clock (~25.175 MHz,
// commonly approximated as 25 MHz) - on real hardware this would come
// from a PLL dividing down the board's oscillator (e.g. 50 MHz), NOT
// directly from the board's main clock. That PLL is board-specific and
// is one of the things that has to be added once a target board is
// known (see README "What's left for real hardware" section).
//
// Horizontal timing (in pixel clocks): 640 visible + 16 front porch +
//   96 sync + 48 back porch = 800 total
// Vertical timing (in lines):          480 visible + 10 front porch +
//   2 sync + 33 back porch = 525 total
// Both HSYNC and VSYNC are active-LOW for this timing standard.

`timescale 1ns/1ps

module vga_controller (
    input  logic clk,          // pixel clock (~25 MHz)
    input  logic rst_n,

    output logic       hsync,      // active LOW
    output logic       vsync,      // active LOW
    output logic       video_on,   // HIGH during the visible 640x480 area
    output logic [9:0] pixel_x,    // 0-639 valid when video_on
    output logic [9:0] pixel_y     // 0-479 valid when video_on
);

    localparam int H_VISIBLE     = 640;
    localparam int H_FRONT_PORCH = 16;
    localparam int H_SYNC        = 96;
    localparam int H_BACK_PORCH  = 48;
    localparam int H_TOTAL       = H_VISIBLE + H_FRONT_PORCH + H_SYNC + H_BACK_PORCH; // 800

    localparam int V_VISIBLE     = 480;
    localparam int V_FRONT_PORCH = 10;
    localparam int V_SYNC        = 2;
    localparam int V_BACK_PORCH  = 33;
    localparam int V_TOTAL       = V_VISIBLE + V_FRONT_PORCH + V_SYNC + V_BACK_PORCH; // 525

    logic [9:0] h_count; // 0 .. H_TOTAL-1
    logic [9:0] v_count; // 0 .. V_TOTAL-1

    // ---------------- Horizontal counter ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) h_count <= 10'd0;
        else if (h_count == H_TOTAL - 1) h_count <= 10'd0;
        else h_count <= h_count + 10'd1;
    end

    // ---------------- Vertical counter (advances once per line) ----------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1) v_count <= 10'd0;
            else v_count <= v_count + 10'd1;
        end
    end

    // ---------------- Sync pulses (active low) ----------------
    assign hsync = ~(h_count >= (H_VISIBLE + H_FRONT_PORCH) &&
                      h_count <  (H_VISIBLE + H_FRONT_PORCH + H_SYNC));

    assign vsync = ~(v_count >= (V_VISIBLE + V_FRONT_PORCH) &&
                      v_count <  (V_VISIBLE + V_FRONT_PORCH + V_SYNC));

    // ---------------- Visible area / pixel coordinates ----------------
    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign pixel_x  = (h_count < H_VISIBLE) ? h_count : 10'd0;
    assign pixel_y  = (v_count < V_VISIBLE) ? v_count : 10'd0;

endmodule
