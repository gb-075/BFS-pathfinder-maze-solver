# test4_jump.asm
# Exercises JAL, JALR, LUI, AUIPC.
#
# Expected final register values:
#   x2 = 42            (only reached via the jal target)
#   x5 = 0x12345000    (lui)
#   x6 = 7             (only reached via the jalr target, using x0 base)
#   x1, x3 hold return addresses (not checked exactly, just sanity values)

jal  x1, target        # jump to 'target', save return addr in x1
addi x9, x0, 0xDEA      # SKIPPED: not on the taken path

target:
addi x2, x0, 42
lui  x5, 0x12345        # x5 = 0x12345000

jalr x3, jalr_target(x0) # rs1=x0, so address = jalr_target's absolute addr
addi x11, x0, 0xBAD      # SKIPPED: not on the taken path

jalr_target:
addi x6, x0, 7
