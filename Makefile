RTL = rtl/alu.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/regfile.sv \
      rtl/instr_mem.sv rtl/data_mem.sv rtl/cpu.sv
TB  = tb/tb_cpu.sv

.PHONY: all compile test test-cpu test-vga test-bfs test-bfs-maze test-cpu-bfs \
        test-ps2 test-scan-decoder test-cursor test-pixel-to-cell test-all clean

all: test

compile:
	iverilog -g2012 -o sim/tb_cpu.vvp $(RTL) $(TB)

test: compile
	python3 sw/check_runner.py

test-cpu: test

test-vga:
	iverilog -g2012 -o sim/tb_vga.vvp rtl/vga/vga_controller.sv tb/tb_vga_controller.sv
	vvp sim/tb_vga.vvp

test-bfs:
	iverilog -g2012 -o sim/tb_bfs.vvp rtl/bfs/bfs_engine.sv tb/tb_bfs_engine.sv
	vvp sim/tb_bfs.vvp

test-bfs-maze:
	iverilog -g2012 -o sim/tb_bfs_maze.vvp \
		rtl/bfs/bfs_engine.sv rtl/bfs/maze_loader.sv rtl/bfs/pixel_to_cell.sv \
		rtl/bfs/maze_render.sv rtl/vga/vga_controller.sv \
		rtl/ps2/ps2_receiver.sv rtl/ps2/scan_code_decoder.sv rtl/ps2/cursor_controller.sv \
		rtl/bfs/bfs_maze_top.sv tb/tb_bfs_maze_top.sv
	vvp sim/tb_bfs_maze.vvp +MAZEFILE=rtl/bfs/maze_data/maze1.mem

test-cpu-bfs:
	python3 sw/assembler.py sw/bfs_cpu_control.asm sw/bfs_cpu_control.hex
	iverilog -g2012 -o sim/tb_cpu_bfs.vvp \
		rtl/alu.sv rtl/imm_gen.sv rtl/control_unit.sv rtl/regfile.sv \
		rtl/instr_mem.sv rtl/data_mem.sv rtl/cpu.sv \
		rtl/bfs/bfs_engine.sv rtl/bfs/maze_loader.sv rtl/bfs/pixel_to_cell.sv \
		rtl/bfs/maze_render.sv rtl/vga/vga_controller.sv \
		rtl/ps2/ps2_receiver.sv rtl/ps2/scan_code_decoder.sv rtl/ps2/cursor_controller.sv \
		rtl/bfs/cpu_bfs_top.sv tb/tb_cpu_bfs_top.sv
	vvp sim/tb_cpu_bfs.vvp +HEXFILE=sw/bfs_cpu_control.hex +MAZEFILE=rtl/bfs/maze_data/maze5x5.mem

test-ps2:
	iverilog -g2012 -o sim/tb_ps2.vvp rtl/ps2/ps2_receiver.sv tb/tb_ps2_receiver.sv
	vvp sim/tb_ps2.vvp

test-scan-decoder:
	iverilog -g2012 -o sim/tb_scan_decoder.vvp rtl/ps2/scan_code_decoder.sv tb/tb_scan_code_decoder.sv
	vvp sim/tb_scan_decoder.vvp

test-cursor:
	iverilog -g2012 -o sim/tb_cursor.vvp rtl/ps2/scan_code_decoder.sv rtl/ps2/cursor_controller.sv tb/tb_cursor_controller.sv
	vvp sim/tb_cursor.vvp

test-pixel-to-cell:
	iverilog -g2012 -o sim/tb_p2c.vvp rtl/vga/vga_controller.sv rtl/bfs/pixel_to_cell.sv tb/tb_pixel_to_cell.sv
	vvp sim/tb_p2c.vvp

gen-maze:
	python3 sw/bfs/gen_maze.py

test-all: test-cpu test-vga test-bfs test-ps2 test-scan-decoder test-cursor test-pixel-to-cell test-bfs-maze test-cpu-bfs

run: compile
	python3 sw/assembler.py sw/$(TEST).asm sw/$(TEST).hex
	vvp sim/tb_cpu.vvp +HEXFILE=sw/$(TEST).hex +CYCLES=$(CYCLES)

clean:
	rm -f sim/*.vvp sw/*.hex waveform.vcd
