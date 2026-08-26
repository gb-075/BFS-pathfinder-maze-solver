RTL = rtl/alu.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/regfile.sv \
      rtl/instr_mem.sv rtl/data_mem.sv rtl/cpu.sv
TB  = tb/tb_cpu.sv

.PHONY: all compile test test-cpu test-vga test-bfs test-all clean

all: test

compile:
	iverilog -g2012 -o sim/tb_cpu.vvp $(RTL) $(TB)

# CPU regression suite (directed tests + demo programs)
test: compile
	python3 sw/check_runner.py

test-cpu: test

# VGA controller timing verification (checked against VESA 640x480@60Hz spec)
test-vga:
	iverilog -g2012 -o sim/tb_vga.vvp rtl/vga/vga_controller.sv tb/tb_vga_controller.sv
	vvp sim/tb_vga.vvp

# BFS hardware pathfinder verification (checked against a hand-solved maze)
test-bfs:
	iverilog -g2012 -o sim/tb_bfs.vvp rtl/bfs/bfs_engine.sv tb/tb_bfs_engine.sv
	vvp sim/tb_bfs.vvp

# Full BFS maze pipeline: maze loader + BFS engine + VGA controller + renderer,
# checked against a real 19x15 generated maze (ground truth computed in Python)
test-bfs-maze:
	iverilog -g2012 -o sim/tb_bfs_maze.vvp \
		rtl/bfs/bfs_engine.sv rtl/bfs/maze_loader.sv rtl/bfs/maze_render.sv \
		rtl/vga/vga_controller.sv rtl/bfs/bfs_maze_top.sv tb/tb_bfs_maze_top.sv
	vvp sim/tb_bfs_maze.vvp +MAZEFILE=rtl/bfs/maze_data/maze1.mem

# Regenerate the maze (uses a fixed random seed, so output is reproducible)
gen-maze:
	python3 sw/bfs/gen_maze.py

# Run everything
test-all: test-cpu test-vga test-bfs test-bfs-maze

# Run a single CPU test/demo by name and show the full instruction trace + regs,
# e.g. `make run TEST=test1_arith CYCLES=20`
run: compile
	python3 sw/assembler.py sw/$(TEST).asm sw/$(TEST).hex
	vvp sim/tb_cpu.vvp +HEXFILE=sw/$(TEST).hex +CYCLES=$(CYCLES)

clean:
	rm -f sim/*.vvp sw/*.hex waveform.vcd
