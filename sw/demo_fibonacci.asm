# demo_fibonacci.asm
# Computes the first 10 Fibonacci numbers and "prints" each one as it's
# computed, by storing it to the memory-mapped console address (0xFFC).
# This is the first program run on the core that produces visible,
# human-readable output instead of just final register values.
#
# Fibonacci: 0, 1, 1, 2, 3, 5, 8, 13, 21, 34

addi x1, x0, 0        # a = fib(0) = 0
addi x2, x0, 1         # b = fib(1) = 1
addi x3, x0, 10         # counter = 10 numbers to print
addi x4, x0, 0x100       # console address (0x100 = 256, fits addi's 12-bit signed immediate)

loop:
sw   x1, 0(x4)             # print current value (a)
add  x5, x1, x2             # next = a + b
addi x1, x2, 0                # a = b
addi x2, x5, 0                  # b = next
addi x3, x3, -1                   # counter--
bne  x3, x0, loop                  # repeat until counter == 0

halt:
jal x0, halt          # halt: spin here forever rather than
                       # falling off the end of instruction memory
