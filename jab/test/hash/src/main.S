# hash: XXH3-64. Fills a buffer with a ramp, then hashes prefixes of it
# at lengths chosen to reach every one of the algorithm's four paths and
# the boundaries between them, writing each as `h <length> <16 hex>`.
# The test holds every one against the reference implementation.
.include "jab.inc"

.set LONGEST, 20000
.set MODULUS, 251

.section .text
.global _start
_start:
    la t0, buf
    li t1, 0
1:
    li t2, LONGEST
    bgeu t1, t2, 2f
    add t3, t0, t1
    li t4, MODULUS
    remu t4, t1, t4
    sb t4, 0(t3)
    addi t1, t1, 1
    j 1b
2:
    la s0, lengths
3:
    ld s1, 0(s0)
    li t0, -1
    beq s1, t0, 9f
    la t0, buf
    mv t1, s1
    jab.hash t0, t1
    mv s2, a0
    call line_reset
    la a0, word_h
    call line_str
    mv a0, s1
    call line_dec
    li a0, ' '
    call line_char
    li s3, 56
4:
    srl a0, s2, s3
    andi a0, a0, 0xff
    call line_hex
    addi s3, s3, -8
    bgez s3, 4b
    call line_nl
    jab.uart.print line
    addi s0, s0, 8
    j 3b
9:
    jab.exit 0

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

line_dec:
    mv t2, a0
    la t1, lineptr
    ld t0, 0(t1)
    la t4, digits
    addi t4, t4, 31
    sb zero, 0(t4)
    li t5, 10
1:
    remu t6, t2, t5
    divu t2, t2, t5
    addi t6, t6, '0'
    addi t4, t4, -1
    sb t6, 0(t4)
    bnez t2, 1b
2:
    lbu t6, 0(t4)
    beqz t6, 3f
    sb t6, 0(t0)
    addi t0, t0, 1
    addi t4, t4, 1
    j 2b
3:
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
.balign 8
# the four paths and the boundaries between them
lengths:
    .quad 0, 1, 2, 3, 4, 5, 8, 9, 12, 16
    .quad 17, 32, 33, 64, 96, 128
    .quad 129, 160, 240
    .quad 241, 512, 1024, 1025, 2048, 20000
    .quad -1
word_h:
    .asciz "h "

.section .bss
.balign 8
buf:
    .skip LONGEST
line:
    .skip 128
lineptr:
    .skip 8
digits:
    .skip 32
