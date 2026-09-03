// nexys_a7_top.sv
// Board-level top module for the Nexys A7-100T. Wraps bfs_maze_top with
// the clock conversion the real board needs: the oscillator (pin E3) is
// 100 MHz, but this design needs a ~25 MHz VGA pixel clock.
//
// This is the module Vivado should be told is the top-level, NOT
// bfs_maze_top directly - port names here match constraints/nexys_a7_100t.xdc.
//
// ============================================================
// BEFORE THIS WILL SYNTHESIZE: you must generate a Vivado Clocking
// Wizard IP named `clk_wiz_0` with these settings:
//   - Input frequency: 100 MHz
//   - Output clk_out1 frequency: 25 MHz (or 25.175 MHz to hit the exact
//     VESA spec - plain 25 MHz works fine in practice)
//   - Reset type: Active Low (to match this project's rst_n convention)
// Steps in Vivado: IP Catalog -> search "Clocking Wizard" -> configure
// as above -> Generate. This can't be done ahead of time outside Vivado
// since the IP's actual output files are tool-generated, not plain RTL -
// but the instantiation below matches the Clocking Wizard's standard
// port names, so once the IP exists with the name `clk_wiz_0`, this
// wrapper should connect to it without further changes.
// ============================================================

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

    // Vivado Clocking Wizard IP instance - see the note above for setup.
    // Standard port names for a Clocking Wizard generated with a single
    // output clock. Since the IP is configured with "Active Low" reset
    // type (per the setup note above), its `reset` port is genuinely
    // active-low - matching rst_n directly, no inversion needed. (If you
    // instead generate the IP with the default "Active High" setting,
    // change this to `.reset(~rst_n)` and update the note above to match -
    // whichever you choose, the GUI setting and this connection must
    // agree, or the design will either never come out of reset or never
    // go into it.)
    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk100mhz),
        .reset    (rst_n),
        .clk_out1 (clk_25mhz),
        .locked   (pll_locked)
    );

    // Hold the whole design in reset until the PLL has locked, in
    // addition to the board's own reset button - a real (if minor)
    // requirement, not paranoia: using clk_25mhz before it's stable
    // could cause the CPU/VGA/BFS logic to power up in an undefined
    // state.
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
