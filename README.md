# RISC-V CPU & Hardware Maze Solver

This project was started to learn digital design through a hands-on project alongside doing courses/learning platforms like nand2Tetris and HDLBits. The goal was to understand how a CPU really works at the RTL level, and eventually build toward FPGA/ASIC design work. It began as a single-cycle RISC-V CPU, and once that was working I wanted to build something more interesting on top of it, which turned into a hardware maze solver with a live VGA display and keyboard input.

Everything here runs in simulation (Icarus Verilog). I don't have an FPGA board yet, so the project hasn't been synthesized yet for real hardware. However, a Digilent Nexys A7-100T will be ordered soon, and constraints/ has pin assignments already prepared for it.

I've been working on this project (including planning and the first few lines of SystemVerilog) since June, 2026. It took me until the end of August, however, to finally start learning how to use Git by completing a few courses so that I could put my work in a repository. I am still constantly learning as I make more commits!

## What's in here

- A single-cycle RV32I-subset CPU, written in SystemVerilog
- A hardware BFS maze solver (an FSM-driven accelerator, not software running on the CPU)
- A CPU-to-accelerator MMIO path so RISC-V software can configure, start, and poll the BFS hardware
- A VGA controller that renders the maze live: walls, the search frontier as it explores, and the final path, all in different colors
- PS/2 keyboard support so you can move a cursor and pick your own start/end points
- A regression suite covering the CPU, BFS, VGA/PS2 path, and CPU/BFS integration

## The CPU

`rtl/alu.sv`, `rtl/regfile.sv`, `rtl/control_unit.sv`, `rtl/imm_gen.sv`, `rtl/instr_mem.sv`, `rtl/data_mem.sv`, `rtl/cpu.sv`

It uses a single-cycle datapath, so one instruction fetches, decodes, executes, accesses memory, and writes back, all in one clock cycle. It implements a working subset of RV32I:

- R-type and I-type ALU ops: `add sub and or xor sll srl sra slt sltu addi andi ori xori slti sltiu slli srli srai`
- Memory: `lw sw` (word-aligned only)
- Control flow: `beq bne blt bge bltu bgeu jal jalr`
- Upper immediate: `lui auipc`

I left out `fence`, `ecall`/`ebreak`, CSR instructions, and byte/halfword loads/stores since the goal was a fully working, fully verified subset rather than a larger instruction set with gaps in it.

There's a small custom assembler (`sw/assembler.py`) so test programs can be written in readable assembly instead of hand-encoded hex, and a handful of test programs (arithmetic, a loop with branches, memory load/store, jumps, some deliberately tricky edge cases, and a couple of small programs like a sort and a simple simulation just to exercise the CPU on something closer to a real workload).

## The maze solver

`rtl/bfs/`

Once the CPU worked, I wanted to build something that actually does something visible, so I built a hardware breadth-first search engine that solves mazes (a real FSM with a hardware queue and a grid-state memory, not a program running on the CPU). It's a separate piece of hardware in the same repo.

- **`bfs_engine.sv`** — the search itself. Standard 4-directional BFS: enqueue the start cell, repeatedly dequeue a cell and check its neighbors, mark visited cells and record which direction leads back toward the start, then once the end cell is found, backtrack from end to start to mark the final path.
- **`maze_loader.sv`** — reads a maze definition from a `.mem` text file (one wall bit per line) and loads it into the BFS engine at startup. The maze file can be created manually or generated with the optional Python utility.
- **`pixel_to_cell.sv`** and **`maze_render.sv`** — figure out which maze cell a given VGA pixel belongs to, and color it: black for walls, white for open/unexplored, light blue for cells the search has visited, green for the final path, plus distinct colors for the start cell, end cell, and a selection cursor.
- **`vga_controller.sv`** — standard 640x480@60Hz VGA timing (the industry-standard signal timing, not something I made up).
- **`ps2_receiver.sv`**, **`scan_code_decoder.sv`**, **`cursor_controller.sv`** — PS/2 keyboard support. Arrow keys move a cursor, `1`/`2` set the start/end point, Enter re-runs the search with your selection. Without touching the keyboard at all it just solves the maze automatically once, using default corner-to-corner points.
- **`bfs_maze_top.sv`** — ties all of the above together into one working system.

The search runs much faster than a human can see, so `bfs_engine.sv` has a throttle that spreads the search out over a couple of seconds when actually displayed, instead of finishing instantly.

### CPU-controlled BFS

`rtl/bfs/cpu_bfs_top.sv` connects the CPU to the BFS engine through memory-mapped I/O. The CPU is held in reset until the maze loader finishes, then a small assembly program writes the start/end coordinates, writes the control register once to start the accelerator, and polls the status register until the search is done. The BFS algorithm itself still runs entirely in hardware.

MMIO map:

| Address | Register | Access |
| --- | --- | --- |
| `0x300` | BFS start column | R/W |
| `0x304` | BFS start row | R/W |
| `0x308` | BFS end column | R/W |
| `0x30C` | BFS end row | R/W |
| `0x310` | BFS control (`bit 0 = start`) | W |
| `0x314` | BFS status (`bit 0 = busy`, `bit 1 = done`, `bit 2 = path_found`) | R |
| `0x318` | keyboard cursor column | R |
| `0x31C` | keyboard cursor row | R |
| `0x320` | keyboard-selected start `{row,col}` | R |
| `0x324` | keyboard-selected end `{row,col}` | R |

The integration uses `0x300` and above so it stays clear of the two 256-byte Game of Life buffers at `0x000-0x0FF` and `0x200-0x2FF`. In the normal CPU-only configuration MMIO is disabled, so the original CPU tests and demo programs keep using the regular data memory exactly as before.

### Maze input

The maze layout is supplied to the hardware as a `.mem` file. Each entry is one cell in row-major order: `1` means wall and `0` means open. The maze does **not** have to come from Python. A `.mem` file can be created manually and passed to the loader, so the hardware can solve a user-supplied maze without changing the BFS RTL.

For simulation, `maze_loader.sv` can take a maze file through the `+MAZEFILE=<path>` plusarg. The repository also includes `sw/bfs/gen_maze.py` as an optional utility that generates a reproducible randomized maze and writes it into the same `.mem` format.

The maze layout and the start/end points are separate inputs. The maze comes from the `.mem` file, while the CPU-controlled version writes the start and end coordinates through MMIO before starting the BFS accelerator.

## How I verified all of this

I tried to test everything like how real verification work looks like:

- **Directed testbenches** for every module, checking specific expected values.
- **A hand-solved test maze** (5x5, small enough to trace by hand) to check the BFS engine's actual output against a shortest path I computed myself, cell by cell — not just "did it find a path."
- **Independent ground truth from Python** for the full-size maze, since it's too big to trace by hand — a separate BFS implementation in `gen_maze.py` computes the real shortest path, and the hardware's result is checked against that.
- **A simulated PS/2 keyboard** that bit-bangs actual PS/2 protocol timing (start bit, parity, stop bit) to test the keyboard input path, including a full end-to-end test where it moves the cursor, picks a new end point, and confirms the hardware re-solves correctly.
- **A couple of small SystemVerilog assertions** in the CPU checking invariants that should always hold (e.g. register x0 always reads zero) regardless of what program is running.
- **Waveform dumps** (VCD) for debugging when something didn't behave as expected.
- **An automated regression suite** — `make test-all` runs every testbench from a clean build and reports pass/fail, rather than me manually re-running things and half-remembering what I already checked.
- **CPU/BFS integration test** — runs real RISC-V assembly and checks the CPU MMIO writes, coordinate latches, one-cycle start pulse, repeated status polling, busy-to-done behavior, and the final 5x5 hand-computed path without forcing the accelerator inputs.

Current state: the full Icarus Verilog regression passes cleanly, including the original CPU tests (8/8), VGA timing, BFS engine, PS/2 receiver, scan-code decoder, cursor controller, pixel-to-cell mapping, the original keyboard/VGA maze system, and the CPU/MMIO/BFS end-to-end integration. The integration test verifies the five expected MMIO writes, latched coordinates, exactly one CPU-caused start pulse, repeated status polling, busy-to-done progression, `path_found`, and the full hand-computed 5x5 shortest path.

## Bugs and difficulties I overcame

A few bugs worth mentioning, since figuring them out was helpful in learning:

- **An initialization bug that looked fine but wasn't.** I declared some signals in the CPU using `logic x = some_expression;`, which in SystemVerilog only runs once at time zero (it's not a continuous connection). Every downstream signal quietly used a stale value forever. The regression suite caught it immediately (everything read zero), and the fix was switching to explicit `assign` statements.
- **A testbench race condition.** In a few of the PS/2 testbenches, I was driving stimulus signals with blocking assignments right after a clock edge, but since the actual hardware module was also reacting to that same edge, there was a real race depending on simulator scheduling, and every test failed in a confusing way. The fix is standard practice once you know it: drive testbench stimulus with nonblocking assignments so there's no ambiguity about which cycle's value the hardware sees.
- **Pipeline latency I didn't account for.** When I rewrote the pixel-to-cell coordinate logic to use counters instead of division (better for real FPGA timing), the new version was registered instead of combinational. This meant that its output is naturally one cycle behind its input, which is completely normal for synchronous hardware. My testbench's reference calculation didn't account for that at first, so it looked broken when the actual logic was correct.

## Building and running

Requires Icarus Verilog and Python 3. On Windows, Git Bash is recommended for the Makefile because it uses standard Unix shell commands such as `rm`.

```
make test-all          # run every testbench from a clean build
make test              # just the CPU regression
make test-bfs           # just the BFS engine (5x5 hand-solved maze)
make test-bfs-maze       # the full maze pipeline (loader + BFS + VGA + PS/2)
make test-cpu-bfs         # CPU -> MMIO -> hardware BFS integration
make gen-maze             # optionally generate a maze file (fixed random seed, reproducible)
make clean                 # remove build artifacts
```

There are a few more granular targets in the Makefile (`test-vga`, `test-ps2`, `test-scan-decoder`, `test-cursor`, `test-pixel-to-cell`) for testing individual pieces on their own.

## What's next

The design is complete in simulation. What's left is hardware deployment:

1. **Get the Nexys A7-100T set up.** `constraints/nexys_a7_100t.xdc` has real pin numbers for this board (VGA, PS/2, clock, reset), and `rtl/bfs/nexys_a7_top.sv` is the board-level wrapper — it still needs a Vivado Clocking Wizard IP generated to convert the board's 100 MHz oscillator down to the ~25 MHz this design assumes, which can't be done outside of Vivado itself.
2. Actually synthesize it, check timing closure and resource usage, and see if it works on a real monitor and keyboard.
3. If I keep going after that: pipelining the CPU (single-cycle → multi-stage) would be a natural next step, and doing an actual design-space comparison (clock frequency vs. resource usage at different pipeline depths) once I have real synthesis numbers to work with instead of just simulation.
