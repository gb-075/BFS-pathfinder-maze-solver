# template.xdc
# Xilinx Vivado pin/timing constraints template for bfs_maze_top.
#
# THIS IS A TEMPLATE, NOT A WORKING CONSTRAINTS FILE. Every PACKAGE_PIN
# value below is a placeholder - it will not synthesize correctly until
# real pin numbers are filled in for a specific board. See README.md in
# this folder for what to do once a board is chosen.
#
# Fill in each PACKAGE_PIN by looking up your board's official pin
# assignment table (Xilinx/Digilent boards like Basys 3 or Nexys
# typically ship a starter .xdc with these already filled in and
# commented out - uncommenting and renaming the relevant signals from
# that file is usually easier than typing pin numbers by hand).

# ---------------- Clock and reset ----------------
set_property PACKAGE_PIN XX [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 40.000 -name sys_clk [get_ports clk]
# 40.000 ns period = 25 MHz, matching the ~25.175 MHz VGA pixel clock
# this design assumes. NOTE: clk here must already be at that rate, not
# the board's raw oscillator - this design does not yet include a
# clocking wizard / MMCM to derive it. See the README's "What's left"
# section.

set_property PACKAGE_PIN XX [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ---------------- VGA output ----------------
set_property PACKAGE_PIN XX [get_ports vga_hsync]
set_property PACKAGE_PIN XX [get_ports vga_vsync]
set_property PACKAGE_PIN XX [get_ports {vga_red[0]}]
set_property PACKAGE_PIN XX [get_ports {vga_red[1]}]
set_property PACKAGE_PIN XX [get_ports {vga_red[2]}]
set_property PACKAGE_PIN XX [get_ports {vga_red[3]}]
set_property PACKAGE_PIN XX [get_ports {vga_green[0]}]
set_property PACKAGE_PIN XX [get_ports {vga_green[1]}]
set_property PACKAGE_PIN XX [get_ports {vga_green[2]}]
set_property PACKAGE_PIN XX [get_ports {vga_green[3]}]
set_property PACKAGE_PIN XX [get_ports {vga_blue[0]}]
set_property PACKAGE_PIN XX [get_ports {vga_blue[1]}]
set_property PACKAGE_PIN XX [get_ports {vga_blue[2]}]
set_property PACKAGE_PIN XX [get_ports {vga_blue[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_red[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_green[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_blue[*]}]

# ---------------- PS/2 keyboard input ----------------
set_property PACKAGE_PIN XX [get_ports ps2_clk]
set_property PACKAGE_PIN XX [get_ports ps2_data]
set_property IOSTANDARD LVCMOS33 [get_ports ps2_clk]
set_property IOSTANDARD LVCMOS33 [get_ports ps2_data]

# NOTE: PS/2 lines are open-collector with external pull-ups on real
# hardware. Check your board's schematic for whether the PS/2 port
# already has pull-ups built in before assuming this works as-is.
