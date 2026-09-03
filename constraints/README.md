# Pin Constraints

**Board chosen: Digilent Nexys A7-100T** (Xilinx Artix-7, `xc7a100tcsg324-1`).

`nexys_a7_100t.xdc` has real, confirmed pin numbers for this specific
board, taken directly from Digilent's official master XDC
(github.com/Digilent/digilent-xdc) - not guessed. It covers clock,
reset, VGA (all 12 color bits + sync), and PS/2 keyboard input.

`template.qsf` and `template.xdc` are generic placeholder templates
kept for reference (useful if this project ever targets a different
board later), but `nexys_a7_100t.xdc` is the one to actually use for
this board.

## Why the Nexys A7-100T

- **VGA port uses exactly 4 bits per color channel** - the same as this
  project's `vga_red`/`vga_green`/`vga_blue[3:0]` outputs, with no
  conversion needed.
- **PS/2 keyboard input works out of the box.** The board doesn't have a
  legacy PS/2 mini-DIN connector - instead, a USB-A "USB Host" port
  (labeled J5) accepts a regular modern USB keyboard, and an onboard
  PIC24 microcontroller emulates a PS/2 device, feeding genuine PS/2
  clock+data signals to the FPGA. `ps2_receiver.sv` works completely
  unmodified.
- **Vivado is AMD's current FPGA toolchain** (AMD acquired Xilinx in
  2022), directly relevant experience for that specific target company.
- Alternatives considered and ruled out: the cheaper Basys 3 has VGA but
  no keyboard input capability at all; the DE10-Lite (Intel/Quartus) has
  neither VGA nor PS/2 built in and would need extra adapter hardware -
  in both cases, the "cheaper" price is misleading once you account for
  what's actually needed for this design.

## What's left before this actually runs on the board

1. **Generate the Clocking Wizard IP.** `rtl/bfs/nexys_a7_top.sv` is
   already written as the actual Vivado top-level module — it wraps
   `bfs_maze_top` with the 100 MHz → ~25 MHz clock conversion this
   board needs. The only piece that can't be written ahead of time as
   plain RTL is the Clocking Wizard IP itself (`clk_wiz_0`), since
   Vivado generates its actual implementation — see the setup comment
   at the top of `nexys_a7_top.sv` for the exact settings.
2. Set `nexys_a7_top` (not `bfs_maze_top`) as the synthesis top module
   in Vivado, add `nexys_a7_100t.xdc` as the constraints file, and add
   the generated Clocking Wizard IP to the project.
3. Run through synthesis and implementation, check the timing report for
   violations, and check resource utilization (LUTs/FFs/BRAM).
4. Program the board and verify against a real monitor and keyboard.

None of this could be done without knowing the actual board - that's
now resolved, so this is the concrete remaining path to real hardware.
