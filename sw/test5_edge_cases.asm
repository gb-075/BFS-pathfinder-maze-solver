# test5_edge_cases.asm
# Corner cases that are easy to get subtly wrong:
#   - writes to x0 must be silently discarded
#   - slt (signed) vs sltu (unsigned) must differ on negative numbers
#   - sra (arithmetic, sign-extends) vs srl (logical, zero-fills) must differ
#
# Expected final register values:
#   x0 = 0          (attempted write of 99 to x0 must be ignored)
#   x5 = 1          slt:  -1 <  1  (signed)   -> true
#   x6 = 0          sltu: -1 <  1  (unsigned, -1 = 0xFFFFFFFF) -> false
#   x7 = 0xFFFFFFFC sra(-8, 1) = -4 (arithmetic: sign bit replicated)
#   x8 = 0x7FFFFFFC srl(-8, 1) treats -8 as 0xFFFFFFF8 (logical: zero-filled)

addi x1, x0, -1      # x1 = 0xFFFFFFFF (-1)
addi x2, x0, 1        # x2 = 1

add  x0, x1, x2        # attempt to write x0 (=0 here) -- must stay 0
slt  x5, x1, x2         # signed:   -1 < 1  -> 1
sltu x6, x1, x2         # unsigned: 0xFFFFFFFF < 1 -> 0

addi x3, x0, -8        # x3 = 0xFFFFFFF8
addi x4, x0, 1
sra  x7, x3, x4         # arithmetic: sign bit replicated -> 0xFFFFFFFC
srl  x8, x3, x4         # logical:    zero-filled top bit -> 0x7FFFFFFC
