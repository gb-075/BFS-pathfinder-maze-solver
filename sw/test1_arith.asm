# test1_arith.asm
# Exercises R-type and I-type ALU instructions.
# Expected final register values (checked by tb_cpu.sv):
#   x5  = 15   (5 + 10)
#   x6  = -5   (5 - 10)          -> 0xFFFFFFFB
#   x7  = 0    (0xF0 & 0x0F)
#   x8  = 0xFF (0xF0 | 0x0F)
#   x9  = 1    (5 < 10 signed)
#   x10 = 8    (1 << 3)
#   x11 = 20   (10 + 10 via addi)

addi x1, x0, 5
addi x2, x0, 10
add  x5, x1, x2      # 15
sub  x6, x1, x2       # -5
addi x3, x0, 0xF0
addi x4, x0, 0x0F
and  x7, x3, x4       # 0
or   x8, x3, x4       # 0xFF
slt  x9, x1, x2       # 1
addi x12, x0, 1
addi x13, x0, 3
sll  x10, x12, x13    # 8
addi x11, x2, 10      # 20
