.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# Tar, read where the program already holds it. Unlike romfs, which
# lives on a disk, a tar archive is bytes in the program's own memory -
# usually a .tar.gz read out of romfs and inflated - so every offset
# here is into that block and nothing is read from a device. An entry's
# data needs no call of its own: it sits 512 bytes after its header, and
# the record says where.
#
# The format is ustar: a 512-byte header of a 100-byte name, the mode,
# owner and group, the size as octal text, the time, a checksum, a type
# byte, a link name, the magic `ustar`, and a 155-byte prefix that goes
# before the name with a separator when it is used. Data follows padded
# to 512, and two zeroed blocks end the archive. A header whose name is
# empty, or whose checksum does not answer for it, is the end.

.set TAR_NAME, 0
.set TAR_NAME_BYTES, 100
.set TAR_SIZE, 124
.set TAR_SIZE_BYTES, 12
.set TAR_CHECKSUM, 148
.set TAR_CHECKSUM_BYTES, 8
.set TAR_TYPE, 156
.set TAR_MAGIC, 257
.set TAR_MAGIC_BYTES, 5
.set TAR_PREFIX, 345
.set TAR_PREFIX_BYTES, 155

.section .text

# sys_tar_list (jab.tar.list): a0 is the buffer, a1 the archive, a2 its
# length, a3 the offset of the header this page starts at, a4 how many
# records the buffer holds. a0 becomes the records written and a1 the
# offset to start the next page at, 0 once the archive has ended.
.global sys_tar_list
sys_tar_list:
    ld a0, 88(sp)
    ld a1, 96(sp)
    call buffer_bounds
    ld s0, 88(sp)               # the archive
    ld s1, 96(sp)               # its length
    ld s2, 104(sp)              # the cursor
    ld s3, 112(sp)              # how many records fit
    li s4, 0
1:
    bgeu s4, s3, 2f
    li t0, JAB_TAR_ENTRY
    mul t0, s4, t0
    ld t1, 80(sp)
    add s5, t1, t0
    mv a0, s5
    li a1, JAB_TAR_ENTRY
    call buffer_bounds
    mv a0, s0
    mv a1, s1
    mv a2, s2
    mv a3, s5
    call tar_entry
    beqz a0, 2f
    mv s2, a0
    addi s4, s4, 1
    j 1b
2:
    # a page that filled the buffer still has to say whether anything
    # follows, so the next header is looked at without being written
    bltu s4, s3, 3f
    mv a0, s0
    mv a1, s1
    mv a2, s2
    li a3, 0
    call tar_entry
    beqz a0, 3f
    mv a0, s4
    mv a1, s2
    j 4f
3:
    mv a0, s4
    li a1, 0
4:
    sd a0, 80(sp)
    sd a1, 88(sp)
    j trap_return

# sys_tar_find (jab.tar.find): a0 is a one-record buffer, a1 the
# archive, a2 its length, a3 a path inside the program's window. a0
# becomes 0 with the record written, or 1 when the archive holds no such
# name; a1 becomes the entry's own offset.
.global sys_tar_find
sys_tar_find:
    ld a0, 88(sp)
    ld a1, 96(sp)
    call buffer_bounds
    ld a0, 80(sp)
    li a1, JAB_TAR_ENTRY
    call buffer_bounds
    ld a0, 104(sp)
    call message_bounds
    mv s6, a0                   # the path
    ld s0, 88(sp)
    ld s1, 96(sp)
    li s2, 0
1:
    mv a0, s0
    mv a1, s1
    mv a2, s2
    la a3, tar_scratch
    call tar_entry
    beqz a0, 8f
    mv s7, s2                   # this entry's own offset
    mv s2, a0
    la a0, tar_scratch
    addi a0, a0, JAB_TAR_NAME
    mv a1, s6
    call tar_name_equal
    beqz a0, 1b
    ld a0, 80(sp)
    la a1, tar_scratch
    li a2, JAB_TAR_ENTRY
    call copy_bytes
    li a0, 0
    mv a1, s7
    j 9f
8:
    li a0, 1
    li a1, 0
9:
    sd a0, 80(sp)
    sd a1, 88(sp)
    j trap_return

# tar_entry: a0 is the archive, a1 its length, a2 the offset of a
# header, a3 where the record goes or 0 for none. Returns the offset of
# the header after it, or 0 when the archive ends here - which an empty
# name or a checksum that does not answer for the header both mean, as
# every tar reader takes them.
tar_entry:
    addi sp, sp, -64
    sd ra, 56(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    sd a2, 16(sp)
    sd a3, 24(sp)
    # the whole header has to be inside the archive
    li t0, JAB_TAR_BLOCK
    add t1, a2, t0
    bltu t1, a2, 8f
    bgtu t1, a1, 8f
    add t2, a0, a2
    sd t2, 32(sp)               # the header
    lbu t3, TAR_NAME(t2)
    beqz t3, 8f                 # the end of the archive
    mv a0, t2
    call tar_checksum
    beqz a0, 8f
    # the size, and where the data sits
    ld t2, 32(sp)
    addi a0, t2, TAR_SIZE
    li a1, TAR_SIZE_BYTES
    call tar_octal
    sd a0, 40(sp)
    ld t0, 16(sp)
    li t1, JAB_TAR_BLOCK
    add t2, t0, t1              # the data follows the header
    sd t2, 48(sp)
    # the next header is that far on again, the data padded to a block
    ld t3, 40(sp)
    add t3, t3, t1
    addi t3, t3, -1
    li t4, JAB_TAR_BLOCK
    divu t3, t3, t4
    mul t3, t3, t4
    add t3, t2, t3
    # it has to be inside the archive too, or this was the last entry
    ld t5, 8(sp)
    bgtu t3, t5, 8f
    sd t3, 16(sp)
    ld a3, 24(sp)
    beqz a3, 9f
    # the record
    ld t0, 32(sp)
    ld t1, 24(sp)
    ld t2, 48(sp)
    ld t4, 40(sp)
    addi t5, t2, -JAB_TAR_BLOCK
    sd t5, JAB_TAR_OFFSET(t1)
    sd t2, JAB_TAR_DATA(t1)
    sd t4, JAB_TAR_SIZE(t1)
    lbu t6, TAR_TYPE(t0)
    bnez t6, 1f
    li t6, JAB_TAR_REGULAR      # an old archive leaves it zero
1:
    sb t6, JAB_TAR_TYPE(t1)
    # the name, over a cleared field: a ustar prefix goes before it with
    # a separator, which is how a path longer than a hundred characters
    # is written
    ld a0, 24(sp)
    addi a0, a0, JAB_TAR_NAME
    li a1, JAB_TAR_NAME_BYTES
    call zero_bytes
    ld t0, 32(sp)
    lbu t1, TAR_MAGIC(t0)
    li t2, 'u'
    bne t1, t2, 2f
    lbu t1, TAR_PREFIX(t0)
    beqz t1, 2f
    ld a0, 24(sp)
    addi a0, a0, JAB_TAR_NAME
    ld a1, 32(sp)
    addi a1, a1, TAR_PREFIX
    li a2, TAR_PREFIX_BYTES
    call tar_copy_field
    mv t3, a0                   # how much of the prefix there was
    ld t0, 24(sp)
    add t0, t0, t3
    addi t0, t0, JAB_TAR_NAME
    li t1, '/'
    sb t1, 0(t0)
    addi a0, t0, 1
    ld a1, 32(sp)
    addi a1, a1, TAR_NAME
    li a2, TAR_NAME_BYTES
    call tar_copy_field
    j 9f
2:
    ld a0, 24(sp)
    addi a0, a0, JAB_TAR_NAME
    ld a1, 32(sp)
    addi a1, a1, TAR_NAME
    li a2, TAR_NAME_BYTES
    call tar_copy_field
9:
    ld a0, 16(sp)
    ld ra, 56(sp)
    addi sp, sp, 64
    ret
8:
    li a0, 0
    ld ra, 56(sp)
    addi sp, sp, 64
    ret

# tar_copy_field: a0 is where it goes, a1 a field of a2 bytes which ends
# at a terminator or at the field's end. a0 becomes how many were
# copied.
tar_copy_field:
    li t0, 0
1:
    bgeu t0, a2, 2f
    add t1, a1, t0
    lbu t2, 0(t1)
    beqz t2, 2f
    add t3, a0, t0
    sb t2, 0(t3)
    addi t0, t0, 1
    j 1b
2:
    mv a0, t0
    ret

# tar_octal: a0 is octal text of a1 bytes, which ends at a space or a
# terminator. a0 becomes its value.
tar_octal:
    li t0, 0
    li t1, 0
1:
    bgeu t1, a1, 3f
    add t2, a0, t1
    lbu t3, 0(t2)
    li t4, '0'
    bltu t3, t4, 3f
    li t4, '7'
    bgtu t3, t4, 3f
    slli t0, t0, 3
    addi t3, t3, -'0'
    add t0, t0, t3
    addi t1, t1, 1
    j 1b
3:
    mv a0, t0
    ret

# tar_checksum: a0 is a header. a0 becomes 1 when the stored checksum
# answers for it, the field itself counted as spaces, as tar defines it.
tar_checksum:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a0, 0(sp)
    addi a0, a0, TAR_CHECKSUM
    li a1, TAR_CHECKSUM_BYTES
    call tar_octal
    mv t5, a0
    ld t0, 0(sp)
    li t1, 0                    # the sum
    li t2, 0                    # the byte
    li t3, JAB_TAR_BLOCK
1:
    bgeu t2, t3, 2f
    add t4, t0, t2
    lbu t6, 0(t4)
    li a1, TAR_CHECKSUM
    bltu t2, a1, 11f
    li a1, TAR_CHECKSUM + TAR_CHECKSUM_BYTES
    bgeu t2, a1, 11f
    li t6, ' '
11:
    add t1, t1, t6
    addi t2, t2, 1
    j 1b
2:
    li a0, 0
    bne t1, t5, 3f
    li a0, 1
3:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# tar_name_equal: a0 is a name in a record and a1 a NUL-terminated path
# in the program's window. a0 becomes 1 when they are the same, with a
# trailing separator on the record's name ignored, since tar writes a
# directory's name with one.
tar_name_equal:
    li t0, 0
1:
    add t1, a0, t0
    lbu t2, 0(t1)
    add t3, a1, t0
    lbu t4, 0(t3)
    beqz t4, 2f
    bne t2, t4, 8f
    addi t0, t0, 1
    j 1b
2:
    beqz t2, 9f
    li t3, '/'
    bne t2, t3, 8f
    add t1, a0, t0
    lbu t2, 1(t1)
    bnez t2, 8f
9:
    li a0, 1
    ret
8:
    li a0, 0
    ret

.section .bss
.balign 8
tar_scratch:
    .skip JAB_TAR_ENTRY
