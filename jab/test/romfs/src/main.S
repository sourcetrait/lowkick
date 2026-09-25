# romfs: the filesystem. Reports what the kernel makes of a fixture
# image the test built, and lets the test be the judge of all of it:
# every path it was told to look for, as `f <code> <type> <size>
# <name>`; the whole of a binary file, read in pages that never line up
# with a sector and written out as hex, 64 bytes to a line as `x <hex>`,
# then `png bytes <n>`; an empty file, as `empty <bytes> <next>`; and
# the entries of a directory holding a name longer than a record can
# carry, as `over <type> <name>`.
.include "jab.inc"

.set DISK, 1
.set PAGE, 4000
.set COLUMNS, 64

.section .text
.global _start
_start:
    la s0, paths
1:
    ld s1, 0(s0)
    beqz s1, 2f
    mv a0, s1
    call find_one
    mv s2, a0
    call line_reset
    la a0, word_f
    call line_str
    mv a0, s2
    call line_dec
    bnez s2, 3f
    li a0, ' '
    call line_char
    la t0, rec
    lwu a0, JAB_ROMFS_NEXT(t0)
    andi a0, a0, JAB_ROMFS_TYPE
    call line_dec
    li a0, ' '
    call line_char
    la t0, rec
    lwu a0, JAB_ROMFS_SIZE(t0)
    call line_dec
    li a0, ' '
    call line_char
    la a0, rec
    addi a0, a0, JAB_ROMFS_NAME
    call line_str
3:
    call line_nl
    jab.uart.print line
    addi s0, s0, 8
    j 1b

2:
    # the binary file, in pages that never line up with a sector, every
    # byte of it written out for the test to hold against the original
    la a0, path_png
    call find_one
    bnez a0, 9f
    la t0, rec
    lwu s3, JAB_ROMFS_OFFSET(t0)
    li s4, 0                    # where in the file the next page starts
    li s6, 0                    # how many bytes came back
4:
    la t0, buf
    li t1, DISK
    mv t2, s3
    mv t3, s4
    li t4, PAGE
    jab.romfs.read t0, t1, t2, t3, t4
    beqz a0, 5f
    mv s7, a0
    mv s4, a1
    li s8, 0
6:
    bgeu s8, s7, 7f
    call line_reset
    la a0, word_x
    call line_str
    li s9, 0
8:
    bgeu s8, s7, 10f
    li t0, COLUMNS
    bgeu s9, t0, 10f
    la t0, buf
    add t0, t0, s8
    lbu a0, 0(t0)
    call line_hex
    addi s8, s8, 1
    addi s9, s9, 1
    j 8b
10:
    call line_nl
    jab.uart.print line
    j 6b
7:
    add s6, s6, s7
    bnez s4, 4b
5:
    call line_reset
    la a0, word_png
    call line_str
    mv a0, s6
    call line_dec
    call line_nl
    jab.uart.print line

    # the empty file: no bytes, and no offset to go on from
    la a0, path_empty
    call find_one
    bnez a0, 9f
    la t0, rec
    lwu s3, JAB_ROMFS_OFFSET(t0)
    la t0, buf
    li t1, DISK
    mv t2, s3
    li t3, 0
    li t4, PAGE
    jab.romfs.read t0, t1, t2, t3, t4
    mv s4, a0
    mv s5, a1
    call line_reset
    la a0, word_empty
    call line_str
    mv a0, s4
    call line_dec
    li a0, ' '
    call line_char
    mv a0, s5
    call line_dec
    call line_nl
    jab.uart.print line

    # the directory holding a name longer than a record carries
    la a0, path_over_dir
    call find_one
    bnez a0, 9f
    mv s3, a1
    la t0, recs
    li t1, DISK
    mv t2, s3
    jab.romfs.list t0, t1, t2
    mv s4, a0
    la s5, recs
    li s6, 0
11:
    bgeu s6, s4, 12f
    call line_reset
    la a0, word_over
    call line_str
    lwu a0, JAB_ROMFS_NEXT(s5)
    andi a0, a0, JAB_ROMFS_TYPE
    call line_dec
    li a0, ' '
    call line_char
    addi a0, s5, JAB_ROMFS_NAME
    call line_str
    call line_nl
    jab.uart.print line
    addi s6, s6, 1
    li t0, JAB_ROMFS_ENTRY
    add s5, s5, t0
    j 11b
12:
    jab.exit 0
9:
    jab.exit 1

# find_one: a0 is a path. The SDK's macro takes a label, which is what a
# program writing one out does; walking a table of them reaches the same
# call the macro does, an ecall with the arguments in place.
find_one:
    mv a3, a0
    la a0, rec
    li a1, DISK
    li a2, JAB_ROMFS_ROOT
    li a7, JAB_SYS_ROMFS_FIND
    ecall
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

# line_nl: end the line, and terminate it where it ends, so a short line
# never shows the tail of a longer one before it.
line_nl:
    la t1, lineptr
    ld t0, 0(t1)
    li t2, '\n'
    sb t2, 0(t0)
    addi t0, t0, 1
    sb zero, 0(t0)
    sd t0, 0(t1)
    ret

# line_str: a0 is a NUL-terminated string.
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

# line_dec: a0 is an unsigned value, written in decimal.
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

# line_hex: a0 is a byte, written as two hex digits.
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
    .quad path_readme
    .quad path_empty
    .quad path_png
    .quad path_font
    .quad path_symlink
    .quad path_hardlink
    .quad path_fifo
    .quad path_block
    .quad path_char
    .quad path_socket
    .quad path_folder
    .quad path_max
    .quad path_over
    .quad 0

path_readme:
    .asciz "/README.md"
path_empty:
    .asciz "/EMPTY"
path_png:
    .asciz "/asset/img/logo/lowkick.480x640.png"
path_font:
    .asciz "/jab/kernel/src/font.S"
path_symlink:
    .asciz "/mode/symlink/points"
path_hardlink:
    .asciz "/mode/hardlink/same"
path_fifo:
    .asciz "/mode/fifo/pipe"
path_block:
    .asciz "/mode/block/loop"
path_char:
    .asciz "/mode/char/zero"
path_socket:
    .asciz "/mode/socket/sock"
path_folder:
    .asciz "/mode/directory/folder"
# 127 characters, the most a record carries and a linux mount reads
path_max:
    .ascii "/name/max/one/two/three/four/five/"
    .ascii "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm"
    .ascii "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm"
    .ascii "mmmmmmmmmmmmmmmmmm"
    .asciz ".max.name"
# 165 characters, which is past both
path_over:
    .ascii "/name/overflow/one/two/three/"
    .ascii "oooooooooooooooooooooooooooooooooooooooooooooooooo"
    .ascii "oooooooooooooooooooooooooooooooooooooooooooooooooo"
    .ascii "oooooooooooooooooooooooooooooooooooooooooooooooooo"
    .ascii "o"
    .asciz ".overflow.name"
path_over_dir:
    .asciz "/name/overflow/one/two/three"

word_f:
    .asciz "f "
word_x:
    .asciz "x "
word_png:
    .asciz "png bytes "
word_empty:
    .asciz "empty "
word_over:
    .asciz "over "

.section .bss
.balign 8
rec:
    .skip JAB_ROMFS_ENTRY
recs:
    .skip JAB_ROMFS_LIST_SIZE
buf:
    .skip 4096
line:
    .skip 512
lineptr:
    .skip 8
digits:
    .skip 32
