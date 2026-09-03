# FPGA Hardware Portfolio: RV32I CPU + VGA Controller + BFS Maze Solver

This repo contains five independently-verified hardware components,
built and tested via simulation (Icarus Verilog), aimed at an
ASIC/FPGA-focused digital design portfolio:

1. **A single-cycle RV32I-subset CPU** (SystemVerilog) — a working
   general-purpose processor with an automated regression suite and
   real demo programs.
2. **A VGA timing controller** — a standard 640x480@60Hz signal
   generator, timing-verified against the VESA spec.
3. **A hardware BFS maze pathfinder** — a genuine FSM + hardware-queue
   accelerator (not software) that solves mazes in hardware, verified
   against a hand-solved test case.
4. **A complete maze-solving visual demo** — a generated maze, loaded
   from a file, solved by the BFS engine, and rendered live to VGA
   colors: walls, the explored search frontier, and the final shortest
   path all rendered distinctly, verified against independent
   Python-computed ground truth.
5. **PS/2 keyboard input** — a full protocol receiver, scan-code
   decoder, and cursor/selection controller, letting you move a cursor
   with the arrow keys and interactively pick new start/end points,
   verified with a simulated keyboard bit-banging real PS/2 timing.

The CPU stands on its own (Part 1). Parts 2, 3, and 5 were built and
verified independently before being wired together in Part 4 —
deliberately, so each piece could be checked in isolation before
integration, the same reason the CPU has its own regression suite before
anything gets built on top of it.

**Quick orientation, if you're skimming this for the first time:**
`make test-all` runs every regression suite from a clean state (currently
0 failures across ~700+ individual checks). The most substantial single
piece is `rtl/bfs/bfs_engine.sv` (Part 3) if you only have time to read
one file. The target board is a Digilent Nexys A7-100T, with real pin
constraints already filled in at `constraints/nexys_a7_100t.xdc` — see
**Choosing a Real Board** further down for why, and **What's left** at
the very bottom for the one remaining category of work (physical
synthesis and bring-up, which needs the actual board and Vivado).

---

# Part 1: Single-Cycle RV32I-Subset CPU

A single-cycle RISC-V (RV32I subset) processor implemented in SystemVerilog,
with a directed testbench, an automated regression suite, and a minimal
custom assembler for writing test programs.

## What's implemented

**Instructions (standard RV32I encodings):**
- R-type ALU: `add sub and or xor sll srl sra slt sltu`
- I-type ALU: `addi andi ori xori slti sltiu slli srli srai`
- Memory: `lw sw` (word-aligned only — no byte/halfword variants)
- Control flow: `beq bne blt bge bltu bgeu jal jalr`
- Upper immediate: `lui auipc`

**Not implemented:** `fence`, `ecall`/`ebreak`, CSR instructions, and
byte/halfword loads/stores (`lb`, `lh`, `sb`, `sh`). These were left out
to keep the first version scoped and fully verified rather than partially
correct across a larger instruction set.

## Architecture

Classic single-cycle datapath: one instruction fetches, decodes, executes,
accesses memory, and writes back, all within one clock cycle.

```
        ┌─────────┐
        │   PC    │
        └────┬────┘
             │
        ┌────▼────┐      ┌──────────────┐
        │ Instr   │─────▶│ Control Unit │
        │ Memory  │      └──────┬───────┘
        └─────────┘             │
             │                  │ (alu_ctrl, reg_write,
             │                  │  mem_read/write, wb_sel, ...)
        ┌────▼─────┐            │
        │ Register │◀───────────┘
        │  File    │
        └────┬─────┘
             │
        ┌────▼────┐      ┌──────────┐
        │   ALU   │─────▶│   Data   │
        └─────────┘      │  Memory  │
                          └──────────┘
```

**Modules (`rtl/`):**
| File | Purpose |
|---|---|
| `cpu.sv` | Top-level datapath: PC logic, wiring, branch/jump resolution |
| `control_unit.sv` | Decodes opcode/funct3/funct7 into control signals |
| `alu.sv` | Arithmetic/logic unit |
| `regfile.sv` | 32×32-bit register file, x0 hardwired to zero |
| `imm_gen.sv` | Extracts and sign-extends I/S/B/U/J-type immediates |
| `instr_mem.sv` | Instruction ROM, loaded from a hex file at sim start |
| `data_mem.sv` | Word-addressable data RAM |

Branch condition evaluation reuses the ALU rather than adding a separate
comparator: `beq`/`bne` use `ALU_SUB` + the zero flag, `blt`/`bge` use
`ALU_SLT`, and `bltu`/`bgeu` use `ALU_SLTU` — matching how the RV32I
funct3 encoding is actually structured (bit 2 selects equality vs.
less-than, bit 0 inverts the result for the "not" variants).

## Verification

Verification tool: **Icarus Verilog** (open-source, `iverilog`/`vvp`).

- `tb/tb_cpu.sv` — testbench that loads a program, runs a fixed number of
  cycles, prints a per-cycle instruction trace, dumps a VCD waveform, and
  dumps the final register file.
- `sw/check_runner.py` — automated regression runner: assembles each test
  program, simulates it, parses the final register dump, and checks
  specific registers against expected values. This is what `make test`
  runs.

**Test programs (`sw/`):**
| Test | Covers |
|---|---|
| `test1_arith` | R-type and I-type ALU ops (add/sub/logic/shift/slt) |
| `test2_branch` | A countdown loop using `bne`, plus a `beq` that must NOT be taken |
| `test3_memory` | `sw`/`lw` round-trip at two different addresses (checks address computation) |
| `test4_jump` | `jal`/`jalr` (including verifying skipped instructions are actually skipped), `lui` |
| `test5_edge_cases` | x0 write immutability, signed (`slt`) vs. unsigned (`sltu`) comparison on negative operands, arithmetic (`sra`) vs. logical (`srl`) shift |

All five currently pass. Run them yourself:
```
make test
```

Run a single test and see the full instruction trace:
```
make run TEST=test1_arith CYCLES=20
```

## Demo programs

Beyond the directed correctness tests, this core runs two small real
programs that produce actual visible output — not just final register
values checked internally. Output is produced through a memory-mapped
"console": any store instruction to address `0x100` prints the stored
value to the simulation console (see the note in `rtl/data_mem.sv` — this
is a simulation-only convenience, not real hardware I/O; on an FPGA it
would be replaced by a real peripheral like UART or LEDs).

**`demo_fibonacci`** — computes and prints the first 10 Fibonacci numbers:
```
$ make run TEST=demo_fibonacci CYCLES=70
CONSOLE: 0 (0x00000000)
CONSOLE: 1 (0x00000001)
CONSOLE: 1 (0x00000001)
CONSOLE: 2 (0x00000002)
CONSOLE: 3 (0x00000003)
CONSOLE: 5 (0x00000005)
CONSOLE: 8 (0x00000008)
CONSOLE: 13 (0x0000000d)
CONSOLE: 21 (0x00000015)
CONSOLE: 34 (0x00000022)
```

**`demo_bubblesort`** — sorts a 5-element array (`[5, 3, 4, 1, 2]`) in
data memory using bubble sort implemented directly in RV32I assembly
(nested loops, branches, loads/stores), then prints the sorted result:
```
$ make run TEST=demo_bubblesort CYCLES=250
CONSOLE: 1 (0x00000001)
CONSOLE: 2 (0x00000002)
CONSOLE: 3 (0x00000003)
CONSOLE: 4 (0x00000004)
CONSOLE: 5 (0x00000005)
```

**`demo_gameoflife`** — Conway's Game of Life on an 8x8 toroidal
(wraparound) grid, running a "glider" pattern for 4 generations. This is
the most substantial program on the core: `do_generation` is a real
subroutine (called 4 times from the top level, alternating between two
grid buffers) that itself calls a second subroutine, `neighbor_sum`, 64
times per generation — one call per cell. Because `do_generation` is
non-leaf (it's called, and it calls something else), its own return
address has to survive those nested calls; this is handled by copying
`ra` into a dedicated saved register on entry rather than a full stack,
since the call depth here never exceeds two levels.

Each row is printed as a packed 8-bit value (bit *c* = cell (row, *c*)),
decoded into ASCII art by a small host-side script:
```
$ python3 sw/render_gol.py
-- Generation 0 --
........
#.#.....
.##.....
.#......
........
........
........
........

-- Generation 1 --
........
..#.....
#.#.....
.##.....
........
........
........
........

-- Generation 2 --
........
.#......
..##....
.##.....
........
........
........
........

-- Generation 3 --
........
..#.....
...#....
.###....
........
........
........
........
```
The glider visibly drifts diagonally, and the exact bit patterns above
match the textbook glider phase cycle — a useful independent check that
this isn't just internally self-consistent but actually correct Game of
Life behavior.

All three demos are included in `make test` via `sw/check_runner.py`,
which checks the exact sequence of printed values rather than just "did
it crash."


### Assertions

`cpu.sv` also includes two immediate assertions (checked every cycle,
independent of which program is running):
- `x0` must always read as zero
- `PC` must always be word-aligned

These aren't redundant with the directed tests above — they check
*design invariants* rather than *program-specific expected values*, so
they'd catch a class of bug the directed tests might miss entirely
(e.g. a future change that breaks x0 handling in a way that happens not
to affect any of the five test programs' checked registers). I verified
these actually catch bugs, not just silently pass, by deliberately
breaking x0's write protection in `regfile.sv` and confirming the
simulation reports `ASSERTION FAILED: x0 read as nonzero` — then
reverted the change.

(Concurrent SVA syntax — `property`/`assert property` — was tried first,
but Icarus Verilog's support for it is incomplete; immediate assertions
inside `always_ff` check the same invariants and are fully supported.)

### A real bug this caught

Early on, `cpu.sv` declared its instruction-decode fields like this:
```systemverilog
logic [6:0] opcode = instr[6:0];
```
This compiles, but in SystemVerilog that `=` initializer only assigns
**once, at time zero** — it does not describe a continuous combinational
connection. Every register write downstream silently used the opcode from
the very first fetched instruction, forever. The regression suite caught
it immediately (every test failed with all registers reading zero), and
the fix was switching to explicit `assign` statements. Worth mentioning
because it's a real, easy-to-miss SystemVerilog footgun, and finding it
through the testbench rather than by inspection is the verification
process working as intended.

## Assembler

`sw/assembler.py` is a small custom assembler (not a general RISC-V
assembler) supporting exactly the instruction subset this core
implements, plus labels for branches/jumps. See the docstring at the top
of the file for syntax. It exists so test programs can be written in
readable assembly instead of hand-encoded hex.

## Building and running

Requires Icarus Verilog (`apt install iverilog`) and Python 3.

```
make test              # CPU: compile + run full regression suite
make test-vga           # VGA controller timing verification
make test-bfs            # BFS engine verification (5x5 hand-solved maze)
make test-bfs-maze        # full maze pipeline: loader + BFS + VGA + renderer
make test-all              # run everything above
make gen-maze              # regenerate the 19x15 maze (fixed seed, reproducible)
make run TEST=test1_arith CYCLES=20   # run one CPU test/demo, print full trace
make clean             # remove build artifacts
```

## Known limitations

- **Single-cycle only.** Every instruction takes one full clock cycle
  regardless of complexity, which caps achievable clock frequency far
  below what a pipelined design could reach.
- **No FPGA deployment yet.** Verified in simulation only; not yet
  synthesized or run on real hardware.
- **No formal timing/area analysis yet.** No synthesis has been run, so
  there's no Fmax, LUT/FF, or power data yet.
- **Partial ISA.** No CSR/exception/interrupt support, no byte/halfword
  memory ops.
- **regfile inspected via hierarchical reference in the testbench**
  (`dut.u_regfile.regs[i]`) rather than through a dedicated debug
  interface — fine for a single-cycle core in simulation, but not a
  pattern that would scale to a real verification environment.

## CPU next steps

This was scoped deliberately small so it could be *fully* verified
rather than partially correct across more features. Planned extensions,
roughly in order:

1. **Pipeline it** (single-cycle → 3-stage → 5-stage), adding hazard
   detection and forwarding. This is also a natural place to start a
   real design-space exploration: compare max clock frequency, CPI, and
   resource usage across pipeline depths.
2. **FPGA deployment** — synthesize and run on real hardware (e.g. an
   Intel/Altera or Xilinx board), closing real timing rather than just
   simulating.
3. **Add a simple cache** in front of data memory and sweep
   configuration (direct-mapped vs. set-associative, size) to quantify
   the impact on performance.
4. **Constrained-random and coverage-driven verification** on top of the
   current directed tests, plus more SystemVerilog assertions on
   internal invariants (a couple already exist — see the Assertions
   section above — but this could grow into a real functional coverage
   plan).
5. Eventually, push a block through an open-source ASIC flow
   (OpenLane/Sky130) to get real area/timing numbers rather than
   FPGA-only estimates.

---

# Part 2: VGA Timing Controller

`rtl/vga/vga_controller.sv` is a standard 640x480@60Hz VGA sync signal
generator, following the VESA industry-standard timing spec:

- **Horizontal:** 640 visible + 16 front porch + 96 sync + 48 back porch
  = 800 total pixel clocks per line
- **Vertical:** 480 visible + 10 front porch + 2 sync + 33 back porch =
  525 total lines per frame
- Both `hsync` and `vsync` are active-low, per spec

It assumes `clk` is already the ~25.175 MHz pixel clock (commonly
approximated as 25 MHz). On real hardware this comes from a PLL dividing
down the board's oscillator (typically 50 MHz) — that PLL is
board-specific and hasn't been added yet since no target board is
chosen (see Project status below).

## Verification

`tb/tb_vga_controller.sv` measures actual signal edge timing (not just
internal counter values) and checks it against the spec exactly:

```
$ make test-vga
PASS: hsync pulse width: expected 96, got 96
PASS: total line length: expected 800, got 800
PASS: vsync pulse width: expected 1600 (2 lines), got 1600
PASS: total frame length: expected 420000, got 420000
PASS: pixel_x sweeps 0..639 correctly during the visible area
ALL VGA TIMING CHECKS PASSED
```

420000 = 525 lines × 800 clocks — the exact full-frame length per the
spec, measured directly from `vsync` edge timing rather than assumed.

---

# Part 3: Hardware BFS Maze Pathfinder

`rtl/bfs/bfs_engine.sv` is a genuine hardware accelerator implementing
breadth-first search over a 2D grid maze — an FSM driving a hardware
queue (FIFO) and a grid-state memory, **not** software running on the
CPU from Part 1. This is deliberate: a purpose-built algorithm
accelerator is a stronger signal for ASIC/FPGA digital design work than
a general CPU executing another program.

## Algorithm

Standard 4-directional grid BFS:
1. Enqueue the start cell, mark it visited.
2. While the queue isn't empty: dequeue a cell, check its four
   neighbors (up/down/left/right). Any neighbor that's in-bounds, not a
   wall, and not yet visited gets marked visited, gets its
   **parent direction** recorded (which way to go to get back toward the
   start), and gets enqueued.
3. Once the end cell is dequeued, backtrack from the end to the start by
   repeatedly following parent-direction pointers, marking each cell
   `on_path` along the way.

Per-cell state (6 bits, packed into a single memory):
```
bit 0     : wall        (1 = wall, static maze data)
bit 1     : visited
bits [4:2]: parent_dir   (which direction to move to reach the parent)
bit 5     : on_path      (set during backtrack - the final rendered path)
```

## Verification

Rather than trust the algorithm by inspection, `tb/tb_bfs_engine.sv`
checks it against a **hand-solved** 5x5 test maze:

```
S . # . .
. . # . .
. # # . .
. . . . .
# # # . E
```

I manually traced BFS by hand to get the true shortest path —
`(0,0)→(1,0)→(2,0)→(3,0)→(3,1)→(3,2)→(3,3)→(4,3)→(4,4)`, 9 cells — and
the testbench checks the hardware's `on_path` bit for **every one of the
25 cells**, not just spot-checking a few:

```
$ make test-bfs
PASS: path_found asserted
PASS: all 25 cells' on_path bits match the hand-computed path exactly
ALL BFS ENGINE CHECKS PASSED
```

A separate testbench also checks the "no path exists" case (a maze with
a solid wall completely separating start from end) correctly reports
failure rather than hanging or returning a wrong answer.

### A real bug this caught

The first version of the direction encoding was backwards: when
discovering a neighbor by moving *up* from the current cell, I initially
stored "parent direction = up" for that neighbor — but the parent is
actually *below* the neighbor (that's the direction you came from), so
backtracking would have walked in exactly the wrong direction. Tracing
through the hand-solved maze before writing the testbench caught this
before it ever ran, which is a big part of why the maze was hand-solved
in the first place rather than just trusting the RTL by inspection.

---

# Part 4: Full Maze Pipeline — Loader + BFS Engine + VGA Display

`rtl/bfs/bfs_maze_top.sv` wires everything from Parts 1-3 (minus the CPU,
which isn't needed here) into a complete pipeline: a maze file gets
loaded into the BFS engine at startup, the search runs automatically,
and the result renders live to VGA output.

## Components

- **`maze_loader.sv`** — reads a maze definition (one wall bit per line,
  row-major, via `$readmemb`) and sequentially writes it into the BFS
  engine's wall interface at startup, then pulses `start` once loading
  finishes. This mirrors how `instr_mem.sv` loads CPU programs — the
  maze data lives in a plain text file, not hardcoded RTL.
- **`maze_render.sv`** — maps a VGA pixel coordinate to a maze cell and
  queries the BFS engine's `read_addr`/`read_cell` interface to get that
  cell's state, then outputs a color: wall → black, open/unexplored →
  white, visited (BFS frontier) → light blue, on the final path → green,
  start cell → bright green, end cell → red. (Two more states — a
  yellow selection cursor, and a synthesis-friendlier way of computing
  the pixel-to-cell coordinate — were added later; see Parts 5 and 6.)
- **`bfs_maze_top.sv`** — ties the loader, BFS engine, VGA controller,
  and renderer together, plus a `SLOWDOWN_FACTOR`-controlled throttle
  (see below).

## Why the search needs to be artificially slowed down

At full clock speed, this BFS engine solves the entire maze below in
well under 2000 cycles — a tiny fraction of even one 1/60s video frame
(420,000 clocks). Without throttling, a human watching the display would
never see the search happen; it would just appear instantly solved. A
`step_en` input on `bfs_engine.sv` freezes FSM progress except once
every `SLOWDOWN_FACTOR` clocks (wall loading and `start` detection are
never throttled — only the active search/backtrack states are), tuned so
the full search takes a few seconds — matching how the reference project
this is modeled on visibly animated its own search.

## The maze

Generated by `sw/bfs/gen_maze.py` using a randomized recursive
backtracker (the standard "real maze" generation algorithm — guarantees
exactly one path between any two open cells, with genuine dead ends,
rather than a trivial or degenerate layout). Fixed random seed, so it's
reproducible. 19x15 grid, 53-cell shortest path:

```
S#.....#...#.......
.###.###.#.#.#####.
...#...#.#.#.#...#.
##.#.#.#.#.#.#.###.
.#.#.#...#.#.#.#...
.#.#.#####.#.#.#.##
.#.#.#.....#.#.#...
.#.###.#####.#.###.
.#.#...#...#.#.#...
.#.#.###.#.#.#.#.#.
...#.#...#.....#.#.
.###.#.#######.#.#.
.#.......#...#.#.#.
.#########.#.###.#.
...........#.....#E
```

The Python generator also runs its own BFS on this maze independently,
giving a ground-truth shortest path to check the hardware against — the
same principle as the hand-solved 5x5 maze in Part 3, just computed
rather than traced by hand since 285 cells is too many to trace
manually.

## Verification

`tb/tb_bfs_maze_top.sv` runs the complete pipeline (at full speed —
`SLOWDOWN_FACTOR=1` — for fast simulation, unlike the real display
instantiation which throttles for visible animation) and samples actual
rendered pixel colors at specific coordinates, checked against the
Python ground truth:

```
$ make test-bfs-maze
PASS: known wall cell (0,1) is black
PASS: start cell (currently showing cursor, which starts here too) (0,0) is yellow (cursor)
PASS: end cell (14,18) is red (end)
PASS: on-path cell (2,2) is on-path green
PASS: on-path cell (10,2) is on-path green
PASS: on-path cell (14,10) is on-path green
PASS: NEW end point (2,2) after keyboard re-selection (2,2) is red (end)
PASS: cell on the NEW shorter path (1,0) is on-path green
PASS: OLD end point - no longer marked, unreached by the new short search (14,18) is white (open, unvisited)

ALL BFS MAZE TOP CHECKS PASSED
```

(The last three checks verify the PS/2 keyboard flow — moving the
selection cursor and re-running the search with a new end point — added
in Part 5 below; the cursor and yellow highlighting are also from Part 5.)

### Two more real bugs this caught

**Icarus + string task arguments:** a testbench task using a `case`
statement to switch on a `string`-typed argument crashed the simulator
outright (`Net arg not a signal?` / an internal assertion failure) —
this is an Icarus limitation, not a logic bug, but it took isolating the
exact failing construct (a minimal reproduction, then adding pieces back
one at a time) to find. Fixed by rewriting the `case` as `if`/`else if`
string comparisons instead, which Icarus handles fine.

**Explicit parameter overrides matching the defaults still crashed
Icarus:** instantiating `bfs_maze_top` with `.GRID_WIDTH(19)` explicitly
(the same value as the default) triggered a different Icarus crash than
omitting the override entirely and just relying on the default. Found by
noticing a minimal reproduction worked *without* the redundant override
but failed *with* it — a good reminder that "should be a no-op" isn't
the same as "is a no-op," especially across tool version quirks.

---

# Project status & next steps

**What's fully working right now:**
- The CPU (Part 1): complete, 8/8 automated tests passing.
- The VGA controller (Part 2): complete, timing-verified exactly against
  spec.
- The BFS engine (Part 3): complete, verified against a hand-solved
  maze including the no-path-exists edge case.
- **The full maze pipeline (Part 4): complete** — a real generated maze,
  loaded from a file, solved by the hardware BFS engine, and rendered
  live to VGA colors, all verified against independent Python-computed
  ground truth.
- **PS/2 keyboard input (Part 5): complete** — a full protocol receiver,
  scan-code decoder, and cursor/selection controller, letting you
  interactively pick new start/end points and re-run the search, verified
  end-to-end including a real bit-banged keyboard simulation.
- **Synthesis-friendly pixel-to-cell math (Part 6): complete** —
  replaced the division-based coordinate conversion with a
  counter-based approach, verified against the division-based reference
  across every pixel of a full frame.
- **A concrete target board is chosen: Digilent Nexys A7-100T**, with
  real (not placeholder) pin constraints in `constraints/nexys_a7_100t.xdc`.

An earlier attempt at a *different* CPU+VGA integration (routing Game of
Life output through memory-mapped registers to a display) hit a
persistent bug — an unpacked SystemVerilog array port propagating `X`
(undefined) values across module boundaries in Icarus — that wasn't
worth chasing further. That attempt was abandoned in favor of this
BFS-based direction, which sidesteps the same pitfall by using a plain
address/data read interface instead of an unpacked array port.

---

# Part 5: PS/2 Keyboard Input

Three modules, each independently verified before integration:

- **`rtl/ps2/ps2_receiver.sv`** — the protocol layer. Synchronizes the
  async `ps2_clk`/`ps2_data` lines (2-stage synchronizer), detects the
  falling edge the PS/2 protocol samples on, and assembles complete
  11-bit frames (start bit, 8 data bits LSB-first, odd parity, stop
  bit) into a byte + valid pulse. Raises `frame_error` instead of
  silently accepting a bad frame.
- **`rtl/ps2/scan_code_decoder.sv`** — interprets the raw byte stream
  into discrete key-press events for the keys this project cares about
  (arrow keys, `1`, `2`, Enter), correctly tracking the `0xE0` extended
  prefix and `0xF0` break (release) prefix, and firing nothing at all
  on a key release.
- **`rtl/ps2/cursor_controller.sv`** — tracks a selection cursor (moved
  by arrow keys, clamped to grid bounds), the current start/end cell,
  and pulses `trigger_search` on Enter.

**Controls:** arrow keys move a yellow selection cursor; `1` sets the
start point to the cursor's position; `2` sets the end point; Enter
re-runs the search with the current selection. On power-up, before any
key is pressed, the maze automatically solves once using default
corner-to-corner points — keyboard input is an enhancement, not a
requirement to see the design work.

## Verification

Each module has its own testbench, all using a **real PS/2 keyboard
simulation** — bit-banging actual protocol timing (start bit, LSB-first
data, odd parity, stop bit) — rather than shortcutting past the
protocol layer:

```
$ make test-ps2
PASS: received correct scan code 0x1C
PASS: received correct scan code 0xE0 (extended prefix)
PASS: bad-parity frame correctly raised frame_error
PASS: received correct scan code 0xF0 (break prefix)
ALL PS2 RECEIVER CHECKS PASSED

$ make test-scan-decoder
[12 checks covering plain keys, extended keys, press+release cycles,
 and unrecognized keys]
ALL SCAN CODE DECODER CHECKS PASSED

$ make test-cursor
[13 checks covering movement, boundary clamping, start/end selection,
 and the search trigger pulse]
ALL CURSOR CONTROLLER CHECKS PASSED
```

The full integration test (`make test-bfs-maze`) goes further: it
bit-bangs a real sequence of key presses through the actual top-level
design — move the cursor, set a new end point, press Enter — and
verifies the hardware re-solves for the new selection correctly,
including confirming the *old* end point correctly reverts to unvisited
once the new search runs.

### Real bugs this caught

**A classic same-edge testbench race.** Early versions of these
testbenches drove `data_valid`/`scan_code` with *blocking* assignments
immediately after `@(posedge clk)`. Since the DUT's own `always_ff` is
sensitive to that same edge, this created a genuine race: depending on
simulator scheduling, the DUT could see the *new* stimulus value on the
same edge it was set, instead of the value from before the edge — every
single positive test case failed as a result. The fix is standard
practice: drive testbench stimulus with *nonblocking* assignments, so
timing relative to the DUT's own registers is unambiguous. This is a
textbook Verilog testbench-writing lesson, caught here for real rather
than just known abstractly.

---

# Part 6: Synthesis-Friendly Pixel-to-Cell Conversion

`maze_render.sv` originally computed which grid cell a VGA pixel
belongs to using division (`pixel_x / CELL_PX_W`). That's correct in
simulation, but a wide combinational divider is a poor fit for FPGA
timing closure at real pixel clock speeds — this was flagged as a known
follow-up as far back as Part 4's `gol_render.sv` predecessor.

`rtl/bfs/pixel_to_cell.sv` replaces it with the standard technique:
small counters that increment in step with the pixel clock and roll
over at each cell boundary, rather than dividing every cycle.

## Verification

Rather than spot-check a few pixels, `tb/tb_pixel_to_cell.sv` checks
**every single visible pixel across a full frame** (311,240 pixels)
against a division-based reference computed directly in the testbench:

```
$ make test-pixel-to-cell
Checked 311240 visible pixels across a full frame
ALL PIXEL_TO_CELL CHECKS PASSED (exact match with division reference)
```

### Two real bugs this caught

**An edge-detector with hidden latency.** The first version detected
"start of a new line" by registering `video_on` and comparing it
against its own delayed copy (a classic rising-edge detector). Since
`video_on` is itself already a registered-derived signal, this added an
*extra* cycle of latency on top, shifting every cell boundary one pixel
clock later than correct. The fix was simpler than the original
approach: check `pixel_x == 0` directly (reliably a single cycle during
the visible period) instead of edge-detecting a proxy signal at all.

**Comparing a registered output against a zero-latency reference.**
After fixing the above, the full-frame test *still* failed at every
cell boundary — but this time it wasn't a design bug. `pixel_to_cell` is
now sequential, so its output reflects the *previous* cycle's inputs by
definition — completely normal pipeline latency for synchronous
hardware. The testbench's reference calculation needed to account for
that same one-cycle delay to compare correctly. Once fixed, all 311,240
pixels matched exactly. Worth noting as a design characteristic: the
final rendered image is shifted by one pixel clock out of ~34 per cell
(under 3% of one cell's width) — imperceptible, and not something this
project corrected for further.

---

# Choosing a Real Board: Digilent Nexys A7-100T

With the design otherwise complete, an actual FPGA board was chosen —
**Digilent Nexys A7-100T** (Xilinx Artix-7, `xc7a100tcsg324-1`) — and
real pin constraints filled in (`constraints/nexys_a7_100t.xdc`),
replacing what had been generic placeholder templates.

**Why this board specifically:**
- Its VGA port uses exactly 4 bits per color channel — identical to
  this project's `vga_red`/`vga_green`/`vga_blue[3:0]` outputs, no
  conversion needed.
- PS/2 keyboard input works with a **regular modern USB keyboard** — the
  board has no legacy PS/2 connector, but a USB-A "USB Host" port and an
  onboard microcontroller that emulates a PS/2 device, feeding genuine
  PS/2 protocol signals to the FPGA. `ps2_receiver.sv` needs no
  modification.
- Vivado is AMD's current FPGA toolchain (AMD acquired Xilinx in 2022).
- Considered and ruled out: the cheaper Basys 3 has VGA but no keyboard
  input capability at all; the DE10-Lite (Intel/Quartus) has neither
  VGA nor PS/2 built in and would need extra adapter hardware — in both
  cases the lower sticker price is misleading once real functional
  requirements are accounted for.

See `constraints/README.md` for the concrete remaining steps before
this actually runs on the board — chiefly, adding a Vivado Clocking
Wizard to derive the ~25 MHz VGA pixel clock from the board's 100 MHz
oscillator, which can't be done generically ahead of time since it's
Vivado-IP-generated rather than plain RTL.

---

# What's left

1. **Physical synthesis and hardware bring-up** — requires the actual
   board (on order) and Vivado, neither of which is available in this
   development environment. Everything up to this point has been
   verified as thoroughly as simulation allows; this is the one
   category of verification simulation genuinely cannot provide.
2. Optionally, a proper design-space exploration once this is on real
   hardware: how does maze size affect resource usage? How does
   `SLOWDOWN_FACTOR` trade off against how "live" the animation feels?
   This is the kind of quantitative comparison that's especially
   relevant for FPGA-architecture-focused research (see the CPU's
   "Next steps" section for the same idea applied there).
