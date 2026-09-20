# bfs_cpu_control.asm - configure and start the hardware BFS accelerator
# through the MMIO block at 0x300, then poll status until it is done.

addi t0, zero, 0x300       # t0 = MMIO base

addi t1, zero, 0           # start_col = 0
sw   t1, 0(t0)
addi t1, zero, 0           # start_row = 0
sw   t1, 4(t0)
addi t1, zero, 4           # end_col = 4
sw   t1, 8(t0)
addi t1, zero, 4           # end_row = 4
sw   t1, 12(t0)

addi t1, zero, 1           # control.start = 1
sw   t1, 16(t0)

poll_status:
lw   t2, 20(t0)            # bit 1 = done
andi t3, t2, 2
beq  t3, zero, poll_status

halt:
jal  zero, halt
