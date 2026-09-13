// nexys_a7_top.sv - board wrapper for Nexys A7, converts the board's
// 100MHz clock down to the ~25MHz this design needs via a Vivado
// Clocking Wizard IP (clk_wiz_0 - has to be generated in Vivado itself,
// settings: 100MHz in, 25MHz out, active-low reset)

`timescale 1ns/1ps

module nexys_a7_top (
    input  logic clk100mhz,
    input  logic rst_n,

    input  logic ps2_clk,
    input  logic ps2_data,

    output logic       vga_hsync,
    output logic       vga_vsync,
    output logic [3:0] vga_red,
    output logic [3:0] vga_green,
    output logic [3:0] vga_blue
);

    logic clk_25mhz;
    logic pll_locked;

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk100mhz),
        .reset    (rst_n),
        .clk_out1 (clk_25mhz),
        .locked   (pll_locked)
    );

    logic rst_n_synced;
    assign rst_n_synced = rst_n & pll_locked;

    bfs_maze_top u_design (
        .clk      (clk_25mhz),
        .rst_n    (rst_n_synced),
        .ps2_clk  (ps2_clk),
        .ps2_data (ps2_data),
        .vga_hsync(vga_hsync),
        .vga_vsync(vga_vsync),
        .vga_red  (vga_red),
        .vga_green(vga_green),
        .vga_blue (vga_blue)
    );

endmodule
