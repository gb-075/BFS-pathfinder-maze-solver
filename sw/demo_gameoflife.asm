# demo_gameoflife.asm
# Conway's Game of Life on an 8x8 toroidal (wraparound) grid.
# Runs a "glider" pattern for 4 generations and prints each row as a
# packed 8-bit value (bit c = cell (r,c)) via the memory-mapped console,
# so the evolving grid can be rendered as ASCII art by a small host-side
# script (sw/render_gol.py) or read directly as bit patterns.
#
# This is a genuine subroutine-call program: do_generation is called 4
# times from main (alternating between two grid buffers), and calls
# neighbor_sum 64 times internally (once per cell). Since do_generation
# itself is called by main AND calls neighbor_sum, its own return address
# must be saved before making nested calls - handled here by copying ra
# (x1) into a dedicated saved register (x20) on entry, since this design
# only ever nests one level deep and doesn't need a real stack.
#
# Register allocation:
#   x1        = ra (return address, standard RISC-V convention)
#   x5, x6    = r, c   (row/col loop counters; also inputs to neighbor_sum)
#   x7, x8    = cur_base, next_base (do_generation's grid buffer inputs)
#   x9        = neighbor_sum's return value / internal accumulator
#   x10-x17   = neighbor_sum scratch (never touched outside it)
#   x20       = do_generation's saved return address
#   x21       = current cell's alive value
#   x22       = computed next-generation alive value
#   x23       = packed row accumulator (printed once per row)
#   x24-x27   = do_generation scratch (address math, loop test, shifting)
#   x28       = console address constant (0x100), set once in main

# ---- Initialize a glider in buffer A (base address 0) ----
# Pattern (row,col), all others dead:
#   (0,1)
#   (1,2)
#   (2,0) (2,1) (2,2)
addi x1, x0, 1
addi x2, x0, 4           # addr(0,1) = 0*32 + 1*4
sw   x1, 0(x2)
addi x2, x0, 40           # addr(1,2) = 1*32 + 2*4
sw   x1, 0(x2)
addi x2, x0, 64           # addr(2,0) = 2*32 + 0*4
sw   x1, 0(x2)
addi x2, x0, 68           # addr(2,1) = 2*32 + 1*4
sw   x1, 0(x2)
addi x2, x0, 72           # addr(2,2) = 2*32 + 2*4
sw   x1, 0(x2)

addi x28, x0, 0x100        # console address, valid for the rest of the program

# ---- Run 4 generations, alternating buffer A (0) and buffer B (512) ----
addi x7, x0, 0
addi x8, x0, 512
jal  x1, do_generation

addi x7, x0, 512
addi x8, x0, 0
jal  x1, do_generation

addi x7, x0, 0
addi x8, x0, 512
jal  x1, do_generation

addi x7, x0, 512
addi x8, x0, 0
jal  x1, do_generation

jal x0, program_end

# ============================================================
# do_generation(cur_base=x7, next_base=x8): computes one full
# generation and prints each resulting row (packed bits) to console.
# ============================================================
do_generation:
addi x20, x1, 0            # save our own return address

addi x5, x0, 0               # r = 0
row_loop:
addi x6, x0, 0                  # c = 0
addi x23, x0, 0                    # row_pack = 0

col_loop:
slli x25, x5, 5                       # x25 = r*32
slli x26, x6, 2                        # x26 = c*4
add  x27, x25, x26                       # x27 = r*32 + c*4
add  x27, x27, x7                          # x27 = cur cell address
lw   x21, 0(x27)                             # x21 = current alive value

jal  x1, neighbor_sum                          # x9 = neighbor count (reads x5,x6,x7)

beq  x21, x0, dead_case
alive_case:
addi x24, x9, -2
beq  x24, x0, set_alive
addi x24, x9, -3
beq  x24, x0, set_alive
jal  x0, set_dead
dead_case:
addi x24, x9, -3
beq  x24, x0, set_alive
jal  x0, set_dead
set_alive:
addi x22, x0, 1
jal  x0, store_result
set_dead:
addi x22, x0, 0
store_result:
sll  x24, x22, x6                         # x24 = next_alive << c
or   x23, x23, x24                          # pack into row accumulator

add  x27, x25, x26                            # recompute base offset (r*32+c*4)
add  x27, x27, x8                               # next cell address
sw   x22, 0(x27)

addi x6, x6, 1
addi x24, x6, -8
bne  x24, x0, col_loop

sw   x23, 0(x28)              # print this row's packed bit pattern (console)

addi x5, x5, 1
addi x24, x5, -8
bne  x24, x0, row_loop

jalr x0, 0(x20)                # return to caller

# ============================================================
# neighbor_sum(r=x5, c=x6, base=x7) -> x9 = count of alive neighbors
# Leaf subroutine (toroidal wraparound via AND 7, since 8 is a power of 2)
# ============================================================
neighbor_sum:
addi x9, x0, 0

# (-1,-1)
addi x10, x5, -1
andi x11, x10, 7
addi x12, x6, -1
andi x13, x12, 7
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

# (-1,0)
addi x10, x5, -1
andi x11, x10, 7
addi x13, x6, 0
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

# (-1,+1)
addi x10, x5, -1
andi x11, x10, 7
addi x12, x6, 1
andi x13, x12, 7
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

# (0,-1)
addi x11, x5, 0
addi x12, x6, -1
andi x13, x12, 7
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

# (0,+1)
addi x11, x5, 0
addi x12, x6, 1
andi x13, x12, 7
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

# (+1,-1)
addi x10, x5, 1
andi x11, x10, 7
addi x12, x6, -1
andi x13, x12, 7
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

# (+1,0)
addi x10, x5, 1
andi x11, x10, 7
addi x13, x6, 0
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

# (+1,+1)
addi x10, x5, 1
andi x11, x10, 7
addi x12, x6, 1
andi x13, x12, 7
slli x14, x11, 5
slli x15, x13, 2
add  x16, x14, x15
add  x16, x16, x7
lw   x17, 0(x16)
add  x9, x9, x17

jalr x0, 0(x1)

program_end:
jal x0, program_end    # halt: spin here forever rather than falling off
                        # the end of instruction memory into undefined
                        # behavior. This is standard bare-metal practice -
                        # a program must never just "run out" of code.
