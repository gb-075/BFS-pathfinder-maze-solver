# test3_memory.asm - lw/sw round trip, plus a nonzero offset
# note: addi immediate is 12-bit signed (-2048..2047), values below fit that
# expected values:
#   x7 = 0x123   (291, stored then loaded back from addr 0)
#   x8 = 0x2AB   (683, stored then loaded back from addr 20)

addi x1, x0, 0x123
addi x2, x0, 0          # base address 0
sw   x1, 0(x2)
lw   x7, 0(x2)           # x7 = 0x123

addi x3, x0, 0x2AB
addi x4, x0, 4
sw   x3, 16(x4)           # address = x4(4) + 16 = 20
lw   x8, 16(x4)           # x8 = loaded from address 20 = 0x2AB
