# nexys_a7_100t.xdc
# Real, confirmed pin constraints for bfs_maze_top on the Digilent
# Nexys A7-100T (device xc7a100tcsg324-1). Pin numbers below are taken
# directly from Digilent's official master XDC for this board
# (github.com/Digilent/digilent-xdc), not guessed or estimated.
#
# UNLIKE constraints/template.xdc, this file is ready to use as-is for
# this specific board - the only remaining step before synthesis is the
# clock domain issue described below.
#
# ============================================================
# IMPORTANT: clk100mhz is the board's raw 100 MHz oscillator - this
# design needs a ~25 MHz VGA pixel clock instead. Use
# rtl/bfs/nexys_a7_top.sv as your actual Vivado top-level (NOT
# bfs_maze_top directly) - it wraps bfs_maze_top with a Clocking Wizard
# IP instance that does this conversion. See the comment at the top of
# that file for the exact Clocking Wizard setup steps (this can't be
# done ahead of time as plain RTL since the IP itself is Vivado-generated).
# ============================================================

# ---------------- Clock (100 MHz oscillator - see note above) ----------------
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk100mhz }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk100mhz }];

# ---------------- Reset ----------------
# CPU_RESETN is the board's dedicated reset button, active-LOW - matches
# this project's rst_n convention exactly (active-low throughout), so it
# connects directly with no inversion needed.
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

# ---------------- VGA output (4 bits per color, matches this project's RGB[3:0] exactly) ----------------
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { vga_hsync }];
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports { vga_vsync }];

set_property -dict { PACKAGE_PIN A3  IOSTANDARD LVCMOS33 } [get_ports { vga_red[0] }];
set_property -dict { PACKAGE_PIN B4  IOSTANDARD LVCMOS33 } [get_ports { vga_red[1] }];
set_property -dict { PACKAGE_PIN C5  IOSTANDARD LVCMOS33 } [get_ports { vga_red[2] }];
set_property -dict { PACKAGE_PIN A4  IOSTANDARD LVCMOS33 } [get_ports { vga_red[3] }];

set_property -dict { PACKAGE_PIN C6  IOSTANDARD LVCMOS33 } [get_ports { vga_green[0] }];
set_property -dict { PACKAGE_PIN A5  IOSTANDARD LVCMOS33 } [get_ports { vga_green[1] }];
set_property -dict { PACKAGE_PIN B6  IOSTANDARD LVCMOS33 } [get_ports { vga_green[2] }];
set_property -dict { PACKAGE_PIN A6  IOSTANDARD LVCMOS33 } [get_ports { vga_green[3] }];

set_property -dict { PACKAGE_PIN B7  IOSTANDARD LVCMOS33 } [get_ports { vga_blue[0] }];
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports { vga_blue[1] }];
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports { vga_blue[2] }];
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 } [get_ports { vga_blue[3] }];

# ---------------- PS/2 keyboard input ----------------
# The Nexys A7 does NOT have a physical PS/2 mini-DIN connector - instead,
# it has a USB-A "USB Host" port (labeled J5) where you plug in a regular
# modern USB keyboard. An onboard PIC24 microcontroller emulates a PS/2
# device and feeds genuine PS/2 clock+data signals to these two FPGA
# pins - so ps2_receiver.sv works completely unmodified, and no actual
# legacy PS/2 keyboard is needed.
set_property -dict { PACKAGE_PIN F4  IOSTANDARD LVCMOS33 } [get_ports { ps2_clk }];
set_property -dict { PACKAGE_PIN B2  IOSTANDARD LVCMOS33 } [get_ports { ps2_data }];
