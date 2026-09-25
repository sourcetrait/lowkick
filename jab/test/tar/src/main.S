# tar: an archive the program holds itself. Reads /foo.tar out of the
# romfs disk into memory, then reports what the kernel makes of it: each
# entry as `t <type> <size> <data> <name>`, then a find as
# `f <code> <size> <name>`, then one for a name that is not there. The
# test is the judge.
.include "jab.inc"

.set DISK, 1
.set BUFFER, 32768

.section .text
.global _start
_start:
    # the archive, out of romfs and into the program's own memory
    la t0, rec
    li t1, DISK
    jab.romfs.find t0, t1, zero, path_tar
    bnez a0, 9f
    la t0, rec
    lwu s0, JAB_ROMFS_OFFSET(t0)
    li s1, 0                    # where in the file
    li s2, 0                    # how much is here
1:
    la t0, archive
    add t0, t0, s2
    li t1, DISK
    mv t2, s0
    mv t3, s1
    li t4, BUFFER
    sub t4, t4, s2
    jab.romfs.read t0, t1, t2, t3, t4
    beqz a0, 2f
    add s2, s2, a0
    mv s1, a1
    bnez s1, 1b
2:
    la t0, archive_len
    sd s2, 0(t0)
    call line_reset
    la a0, word_archive
    call line_str
    mv a0, s2
    call line_dec
    call line_nl
    jab.uart.print line

    # every entry, a page at a time
    li s3, 0                    # the cursor
3:
    la t0, recs
    la t1, archive
    mv t2, s2
    mv t3, s3
    jab.tar.list t0, t1, t2, t3, 4
    mv s4, a0
    mv s3, a1
    la s5, recs
    li s6, 0
4:
    bgeu s6, s4, 5f
    call line_reset
    la a0, word_t
    call line_str
    lbu a0, JAB_TAR_TYPE(s5)
    call line_char
    li a0, ' '
    call line_char
    ld a0, JAB_TAR_SIZE(s5)
    call line_dec
    li a0, ' '
    call line_char
    ld a0, JAB_TAR_DATA(s5)
    call line_dec
    li a0, ' '
    call line_char
    addi a0, s5, JAB_TAR_NAME
    call line_str
    call line_nl
    jab.uart.print line
    addi s6, s6, 1
    li t0, JAB_TAR_ENTRY
    add s5, s5, t0
    j 4b
5:
    bnez s3, 3b

    # a name that is there, and one that is not
    la a0, path_note
    call find_one
    la a0, path_missing
    call find_one
    jab.exit 0
9:
    jab.exit 1

# find_one: a0 is a path; reports the code, and the size and name when
# it is there.
find_one:
    addi sp, sp, -16
    sd ra, 8(sp)
    mv t3, a0
    la t0, rec
    la t1, archive
    la t2, archive_len
    ld t2, 0(t2)
    mv a3, t3
    mv a2, t2
    mv a1, t1
    mv a0, t0
    li a7, JAB_SYS_TAR_FIND
    ecall
    mv s7, a0                   # a t register would not survive the calls
    call line_reset
    la a0, word_f
    call line_str
    mv a0, s7
    call line_dec
    bnez s7, 1f
    li a0, ' '
    call line_char
    la t0, rec
    ld a0, JAB_TAR_SIZE(t0)
    call line_dec
    li a0, ' '
    call line_char
    la a0, rec
    addi a0, a0, JAB_TAR_NAME
    call line_str
1:
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

.section .rodata
path_tar:
    .asciz "/foo.tar"
path_note:
    .asciz "foo/note.txt"
path_missing:
    .asciz "foo/nothing.here"
word_archive:
    .asciz "archive "
word_t:
    .asciz "t "
word_f:
    .asciz "f "

.section .bss
.balign 8
archive_len:
    .skip 8
rec:
    .skip JAB_TAR_ENTRY
recs:
    .skip JAB_TAR_LIST_SIZE
archive:
    .skip BUFFER
line:
    .skip 512
lineptr:
    .skip 8
digits:
    .skip 32
