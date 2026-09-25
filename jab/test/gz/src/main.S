# gz: the decompressor. Reads a set of .gz files out of the romfs disk,
# asks each how long its contents will be, inflates it in one call, and
# reports `g <code> <bytes> <said>` for each: the code the call gave,
# the bytes that came out, and the length the trailer promised. The
# kernel checks the CRC-32 itself, so JAB_GZ_OK already means the bytes
# are the bytes that went in; the first file is also written out as hex
# so the test can see that for itself once.
.include "jab.inc"

.set DISK, 1
.set GZBUF, 65536
.set OUTBUF, 65536
.set COLUMNS, 64

.section .text
.global _start
_start:
    la s0, paths
1:
    ld s1, 0(s0)
    beqz s1, 8f
    # the compressed file, out of romfs and into memory
    mv a3, s1
    la a0, rec
    li a1, DISK
    li a2, JAB_ROMFS_ROOT
    li a7, JAB_SYS_ROMFS_FIND
    ecall
    bnez a0, 9f
    la t0, rec
    lwu s2, JAB_ROMFS_OFFSET(t0)
    li s3, 0                    # where in the file
    li s4, 0                    # how much is here
2:
    la t0, gzbuf
    add t0, t0, s4
    li t1, DISK
    mv t2, s2
    mv t3, s3
    li t4, GZBUF
    sub t4, t4, s4
    jab.romfs.read t0, t1, t2, t3, t4
    beqz a0, 3f
    add s4, s4, a0
    mv s3, a1
    bnez s3, 2b
3:
    # how long the contents will be, then all of them at once
    la t0, gzbuf
    mv t1, s4
    jab.gz.size t0, t1
    mv s5, a0
    mv s6, a1
    la t0, outbuf
    la t1, gzbuf
    mv t2, s4
    mv t3, s5
    jab.gz.read t0, t1, t2, t3
    mv s7, a0                   # the bytes that came out
    mv s8, a1                   # and what the call made of it
    call line_reset
    la a0, word_g
    call line_str
    mv a0, s8
    call line_dec
    li a0, ' '
    call line_char
    mv a0, s7
    call line_dec
    li a0, ' '
    call line_char
    mv a0, s5
    call line_dec
    li a0, ' '
    call line_char
    mv a0, s6
    call line_dec
    call line_nl
    jab.uart.print line
    # the first file, byte by byte, so the test sees one whole answer
    la t0, paths
    bne s0, t0, 7f
    li s9, 0
4:
    bgeu s9, s7, 7f
    call line_reset
    la a0, word_x
    call line_str
    li s10, 0
5:
    bgeu s9, s7, 6f
    li t0, COLUMNS
    bgeu s10, t0, 6f
    la t0, outbuf
    add t0, t0, s9
    lbu a0, 0(t0)
    call line_hex
    addi s9, s9, 1
    addi s10, s10, 1
    j 5b
6:
    call line_nl
    jab.uart.print line
    j 4b
7:
    addi s0, s0, 8
    j 1b
8:
    jab.exit 0
9:
    jab.exit 1

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

# line_nl: end the line and terminate it where it ends.
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
paths:
    .quad path_text
    .quad path_random
    .quad path_tiny
    .quad path_empty
    .quad path_png
    .quad path_font
    .quad 0

path_text:
    .asciz "/text.txt.gz"
path_random:
    .asciz "/random.bin.gz"
path_tiny:
    .asciz "/tiny.txt.gz"
path_empty:
    .asciz "/empty.gz"
path_png:
    .asciz "/logo.png.gz"
path_font:
    .asciz "/font.S.gz"

word_g:
    .asciz "g "
word_x:
    .asciz "x "

.section .bss
.balign 8
rec:
    .skip JAB_ROMFS_ENTRY
gzbuf:
    .skip GZBUF
outbuf:
    .skip OUTBUF
line:
    .skip 512
lineptr:
    .skip 8
digits:
    .skip 32
