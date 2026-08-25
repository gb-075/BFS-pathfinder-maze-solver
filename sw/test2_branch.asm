# test2_branch.asm
# Loop that sums 1..5 using BNE, plus a BEQ that must NOT be taken.
#
# Expected final register values:
#   x5 = 15      (1+2+3+4+5, built via a countdown loop)
#   x6 = 0       (loop counter, ends at 0)
#   x7 = 1       (proves the beq below was correctly NOT taken)

addi x5, x0, 0       # sum = 0
addi x6, x0, 5       # counter = 5

loop:
add  x5, x5, x6      # sum += counter
addi x6, x6, -1      # counter--
bne  x6, x0, loop    # loop while counter != 0

beq  x5, x0, skip    # sum == 15, so this branch is NOT taken
addi x7, x0, 1        # executes because beq fell through
jal  x0, done

skip:
addi x7, x0, 0xDEAD  # should NEVER execute

done:
jal x0, done          # halt: spin here forever rather than
                       # falling off the end of instruction memory
