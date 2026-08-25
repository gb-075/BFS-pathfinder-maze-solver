# demo_bubblesort.asm
# Bubble sort, implemented directly in RV32I assembly and run on this
# core. Sorts a 5-element array stored in data memory, then prints the
# sorted result via the memory-mapped console.
#
# Initial array: [5, 3, 4, 1, 2]
# Expected sorted output (printed in order): 1, 2, 3, 4, 5

# ---- Initialize array at addresses 0, 4, 8, 12, 16 ----
addi x1, x0, 5
sw   x1, 0(x0)
addi x1, x0, 3
sw   x1, 4(x0)
addi x1, x0, 4
sw   x1, 8(x0)
addi x1, x0, 1
sw   x1, 12(x0)
addi x1, x0, 2
sw   x1, 16(x0)

# ---- Bubble sort: 4 outer passes, 4 comparisons each ----
addi x10, x0, 4          # outer pass counter

outer:
addi x11, x0, 0            # x11 = byte address of current element (starts at 0)
addi x12, x0, 4              # inner comparison counter

inner:
lw   x13, 0(x11)               # arr[j]
lw   x14, 4(x11)                 # arr[j+1]
blt  x14, x13, do_swap             # if arr[j+1] < arr[j], swap
jal  x0, no_swap
do_swap:
sw   x14, 0(x11)
sw   x13, 4(x11)
no_swap:
addi x11, x11, 4                       # advance to next pair
addi x12, x12, -1                        # inner--
bne  x12, x0, inner                        # loop while inner != 0

addi x10, x10, -1        # outer--
bne  x10, x0, outer         # loop while outer != 0

# ---- Print sorted array ----
addi x1, x0, 0              # read address = 0
addi x2, x0, 5                # element count
addi x4, x0, 0x100              # console address

print_loop:
lw   x3, 0(x1)
sw   x3, 0(x4)
addi x1, x1, 4
addi x2, x2, -1
bne  x2, x0, print_loop

halt:
jal x0, halt          # halt: spin here forever rather than
                       # falling off the end of instruction memory
