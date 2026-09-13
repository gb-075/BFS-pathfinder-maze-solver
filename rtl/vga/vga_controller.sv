// vga_controller.sv - generates standard 640x480@60Hz VGA timing

`timescale 1ns/1ps

module vga_controller (
    input  logic clk,
    input  logic rst_n,

    output logic       hsync,
    output logic       vsync,
    output logic       video_on,
    output logic [9:0] pixel_x,
    output logic [9:0] pixel_y
);

    localparam int H_VISIBLE     = 640;
    localparam int H_FRONT_PORCH = 16;
    localparam int H_SYNC        = 96;
    localparam int H_BACK_PORCH  = 48;
    localparam int H_TOTAL       = H_VISIBLE + H_FRONT_PORCH + H_SYNC + H_BACK_PORCH;

    localparam int V_VISIBLE     = 480;
    localparam int V_FRONT_PORCH = 10;
    localparam int V_SYNC        = 2;
    localparam int V_BACK_PORCH  = 33;
    localparam int V_TOTAL       = V_VISIBLE + V_FRONT_PORCH + V_SYNC + V_BACK_PORCH;

    logic [9:0] h_count;
    logic [9:0] v_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) h_count <= 10'd0;
        else if (h_count == H_TOTAL - 1) h_count <= 10'd0;
        else h_count <= h_count + 10'd1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_count <= 10'd0;
        end else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1) v_count <= 10'd0;
            else v_count <= v_count + 10'd1;
        end
    end

    assign hsync = ~(h_count >= (H_VISIBLE + H_FRONT_PORCH) &&
                      h_count <  (H_VISIBLE + H_FRONT_PORCH + H_SYNC));

    assign vsync = ~(v_count >= (V_VISIBLE + V_FRONT_PORCH) &&
                      v_count <  (V_VISIBLE + V_FRONT_PORCH + V_SYNC));

    assign video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
    assign pixel_x  = (h_count < H_VISIBLE) ? h_count : 10'd0;
    assign pixel_y  = (v_count < V_VISIBLE) ? v_count : 10'd0;

endmodule
