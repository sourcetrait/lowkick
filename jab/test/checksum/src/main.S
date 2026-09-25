# checksum: SHA3-256. Takes the digest of four things and writes each
# out as hex, `d <64 hex digits>`: nothing at all, the three bytes the
# standard's own vector uses, a short ramp, and a long one that runs to
# many blocks. The test holds the first two against the published
# answers and the others against what the host computes.
.include "jab.inc"

.set RAMP, 200
.set LONG, 100000

.section .text
.global _start
_start:
    # the ramps, before anything is taken of them
    la t0, ramp
    li t1, 0
1:
    li t2, RAMP
    bgeu t1, t2, 2f
    add t3, t0, t1
    sb t1, 0(t3)
    addi t1, t1, 1
    j 1b
2:
    la t0, long
    li t1, 0
3:
    li t2, LONG
    bgeu t1, t2, 4f
    add t3, t0, t1
    li t4, 251
    remu t4, t1, t4
    sb t4, 0(t3)
    addi t1, t1, 1
    j 3b
4:
    la t0, ramp
    li t1, 0
    call digest
    la t0, abc
    li t1, 3
    call digest
    la t0, ramp
    li t1, RAMP
    call digest
    la t0, long
    li t1, LONG
    call digest
    jab.exit 0

# digest: t0 is the bytes and t1 how many; writes the answer out as hex.
digest:
    addi sp, sp, -16
    sd ra, 8(sp)
    mv a1, t1
    mv a0, t0
    li a7, JAB_SYS_CHECKSUM
    ecall
    la t0, out
    sd a0, 0(t0)
    sd a1, 8(t0)
    sd a2, 16(t0)
    sd a3, 24(t0)
    call line_reset
    la a0, word_d
    call line_str
    li s0, 0
1:
    li t0, 32
    bgeu s0, t0, 2f
    la t0, out
    add t0, t0, s0
    lbu a0, 0(t0)
    call line_hex
    addi s0, s0, 1
    j 1b
2:
    call line_nl
    jab.uart.print line
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

line_reset:
    la t0, line
    la t1, lineptr
    sd t0, 0(t1)
    ret

line_char:
    la t1, lineptr
    ld t0, 0(t1)
    sb a0, 0(t0)
    addi t0, t0, 1
    sd t0, 0(t1)
    ret

line_nl:
    la t1, lineptr
    ld t0, 0(t1)
    li t2, '\n'
    sb t2, 0(t0)
    addi t0, t0, 1
    sb zero, 0(t0)
    sd t0, 0(t1)
    ret

line_str:
    mv t2, a0
    la t1, lineptr
    ld t0, 0(t1)
1:
    lbu t3, 0(t2)
    beqz t3, 2f
    sb t3, 0(t0)
    addi t0, t0, 1
    addi t2, t2, 1
    j 1b
2:
    sd t0, 0(t1)
    ret

line_hex:
    mv t2, a0
    la t1, lineptr
    ld t0, 0(t1)
    li t5, 10
    srli t3, t2, 4
    andi t3, t3, 15
    blt t3, t5, 1f
    addi t3, t3, 'a' - 10
    j 2f
1:
    addi t3, t3, '0'
2:
    sb t3, 0(t0)
    addi t0, t0, 1
    andi t3, t2, 15
    blt t3, t5, 3f
    addi t3, t3, 'a' - 10
    j 4f
3:
    addi t3, t3, '0'
4:
    sb t3, 0(t0)
    addi t0, t0, 1
    sd t0, 0(t1)
    ret

.section .rodata
abc:
    .ascii "abc"
word_d:
    .asciz "d "

.section .bss
.balign 8
out:
    .skip 32
ramp:
    .skip RAMP
long:
    .skip LONG
line:
    .skip 256
lineptr:
    .skip 8
