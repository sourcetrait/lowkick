# framecap: the frame cap. Sixty-four flips in a row with no waiting:
# the first goes through and the rest come too early, which the kernel
# refuses without showing them. Then sixty-four frames the proper way,
# await then flip, which take two seconds at thirty-two a second while
# the hart halts between them. Reports the refusals on the UART.
.include "jab.inc"

.set FLIPS, 64

.section .text
.global _start
_start:
    jab.display.open
    bnez a0, no_display
    li s0, 0
    li s1, FLIPS
1:
    jab.display.flip
    li t0, 1
    bne a0, t0, 2f
    addi s0, s0, 1
2:
    addi s1, s1, -1
    bnez s1, 1b
    # refused=NN
    la t0, digits
    li t1, 10
    divu t2, s0, t1
    remu t3, s0, t1
    addi t2, t2, '0'
    addi t3, t3, '0'
    sb t2, 0(t0)
    sb t3, 1(t0)
    jab.uart.print refused
    li s1, FLIPS
3:
    jab.display.await
    jab.display.flip
    bnez a0, flip_failed
    addi s1, s1, -1
    bnez s1, 3b
    jab.uart.print paced
    jab.exit 0

no_display:
    jab.uart.print msg_no_display
    jab.exit 1

flip_failed:
    jab.uart.print msg_flip_failed
    jab.exit 2

.section .data
refused:
    .ascii "refused="
digits:
    .asciz "00\n"

.section .rodata
paced:
    .asciz "paced\n"
msg_no_display:
    .asciz "framecap: no display\n"
msg_flip_failed:
    .asciz "framecap: a flip after await failed\n"
