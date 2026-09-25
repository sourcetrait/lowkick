# framecap: the frame cap. Sixty-four flips in a row with no waiting:
# the first goes through and the rest come too early, which the kernel
# refuses without showing them. Then sixty-four frames the proper way,
# await then flip, half of them whole and half a rectangle, which take
# two seconds at thirty-two a second while the hart halts between them.
# Then a rectangle reaching past the screen's edge, which the kernel
# must refuse. Reports on the UART.
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
    mv a0, s0
    la a1, refused_digits
    call two_digits
    jab.uart.print refused
    # thirty-two whole frames, awaited
    li s1, FLIPS / 2
3:
    jab.display.await
    jab.display.flip
    bnez a0, flip_failed
    addi s1, s1, -1
    bnez s1, 3b
    # thirty-two rectangles, awaited
    li s1, FLIPS / 2
4:
    jab.display.await
    li a0, 100
    li a1, 100
    li a2, 50
    li a3, 50
    jab.display.flip.rect
    bnez a0, flip_failed
    addi s1, s1, -1
    bnez s1, 4b
    # a rectangle past the right edge: badrect=N
    jab.display.await
    li a0, 1900
    li a1, 0
    li a2, 100
    li a3, 10
    jab.display.flip.rect
    la a1, badrect_digits
    call two_digits
    jab.uart.print badrect
    jab.uart.print paced
    jab.exit 0

no_display:
    jab.uart.print msg_no_display
    jab.exit 1

flip_failed:
    jab.uart.print msg_flip_failed
    jab.exit 2

# two_digits: write a0, under a hundred, as two decimal digits at a1.
two_digits:
    li t1, 10
    divu t2, a0, t1
    remu t3, a0, t1
    addi t2, t2, '0'
    addi t3, t3, '0'
    sb t2, 0(a1)
    sb t3, 1(a1)
    ret

.section .data
refused:
    .ascii "refused="
refused_digits:
    .asciz "00\n"
badrect:
    .ascii "badrect="
badrect_digits:
    .asciz "00\n"

.section .rodata
paced:
    .asciz "paced\n"
msg_no_display:
    .asciz "framecap: no display\n"
msg_flip_failed:
    .asciz "framecap: a flip after await failed\n"
