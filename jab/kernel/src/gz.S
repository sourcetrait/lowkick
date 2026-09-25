.include "riscv.inc"
.include "jab.inc"

# gzip, the reading half: the thin jacket RFC 1952 puts around a DEFLATE
# stream (deflate.S). Ten bytes of header, optional extra field, name
# and comment, then the compressed bytes, then a CRC-32 of what comes
# out and its length. Both ends of the jacket are checked, so a program
# that gets JAB_GZ_OK back knows the bytes are the bytes that went in.
#
# The length in the trailer is what makes one-shot decompression the
# right shape here: a program reads it with jab.gz.size, sizes its
# buffer, and inflates in one call. DEFLATE cannot be entered in the
# middle, since a match may reach back 32 KiB and the Huffman state is
# built as the stream is read, so a resumable cursor would mean the
# kernel holding decoder state between calls - which is the one thing
# every other call here avoids.

.set GZ_MAGIC0, 0x1f
.set GZ_MAGIC1, 0x8b
.set GZ_DEFLATE, 8
.set GZ_FHCRC, 2
.set GZ_FEXTRA, 4
.set GZ_FNAME, 8
.set GZ_FCOMMENT, 16
.set GZ_HEADER, 10
.set GZ_TRAILER, 8

.section .text

# sys_gz_size (jab.gz.size): a0 is the gzip bytes and a1 how many. a0
# becomes the length the contents will be, which the trailer carries,
# and a1 JAB_GZ_OK or JAB_GZ_NOT_GZIP.
.global sys_gz_size
sys_gz_size:
    ld a0, 80(sp)
    ld a1, 88(sp)
    call buffer_bounds
    ld s0, 80(sp)
    ld s1, 88(sp)
    mv a0, s0
    mv a1, s1
    call gz_check
    bnez a0, 8f
    add t0, s0, s1
    addi t0, t0, -4
    lbu t1, 0(t0)
    lbu t2, 1(t0)
    slli t2, t2, 8
    or t1, t1, t2
    lbu t2, 2(t0)
    slli t2, t2, 16
    or t1, t1, t2
    lbu t2, 3(t0)
    slli t2, t2, 24
    or t1, t1, t2
    sd t1, 80(sp)
    sd zero, 88(sp)
    j trap_return
8:
    sd zero, 80(sp)
    li t0, JAB_GZ_NOT_GZIP
    sd t0, 88(sp)
    j trap_return

# sys_gz_read (jab.gz.read): a0 is the buffer, a1 the gzip bytes, a2 how
# many, a3 how much the buffer holds. a0 becomes the bytes written and
# a1 one of the JAB_GZ_* codes.
.global sys_gz_read
sys_gz_read:
    ld a0, 88(sp)
    ld a1, 96(sp)
    call buffer_bounds
    ld a0, 80(sp)
    ld a1, 104(sp)
    call buffer_bounds
    ld s0, 88(sp)               # the gzip bytes
    ld s1, 96(sp)               # how many
    mv a0, s0
    mv a1, s1
    call gz_check
    beqz a0, 1f
    li t0, JAB_GZ_NOT_GZIP
    j 8f
1:
    # past the header, and whatever of it is optional
    mv a0, s0
    mv a1, s1
    call gz_body
    bltz a0, 7f
    mv s2, a0                   # where the compressed bytes start
    sub s3, s1, s2
    addi s3, s3, -GZ_TRAILER    # and how many of them there are
    blez s3, 7f
    ld a0, 80(sp)
    ld a1, 104(sp)
    add a2, s0, s2
    mv a3, s3
    call deflate_inflate
    mv s4, a0                   # the bytes written
    beqz a1, 2f
    addi t0, a1, 4              # a deflate code, in this call's range
    j 8f
2:
    # the trailer answers for what came out: first its length
    add t0, s0, s1
    addi t0, t0, -4
    call gz_le32
    bne a0, s4, 5f
    # then its CRC
    ld a0, 80(sp)
    mv a1, s4
    call gz_crc32
    mv s5, a0
    add t0, s0, s1
    addi t0, t0, -GZ_TRAILER
    call gz_le32
    bne a0, s5, 6f
    mv a0, s4
    li t0, JAB_GZ_OK
    j 9f
5:
    li t0, JAB_GZ_LENGTH
    mv a0, s4
    j 9f
6:
    li t0, JAB_GZ_CRC
    mv a0, s4
    j 9f
7:
    li t0, JAB_GZ_TRUNCATED
8:
    li a0, 0
9:
    sd a0, 80(sp)
    sd t0, 88(sp)
    j trap_return

# gz_check: a0 is the bytes and a1 how many. a0 becomes 0 when they open
# as a gzip of deflated data and are long enough to carry a trailer.
gz_check:
    li t0, GZ_HEADER + GZ_TRAILER
    bltu a1, t0, 8f
    lbu t1, 0(a0)
    li t2, GZ_MAGIC0
    bne t1, t2, 8f
    lbu t1, 1(a0)
    li t2, GZ_MAGIC1
    bne t1, t2, 8f
    lbu t1, 2(a0)
    li t2, GZ_DEFLATE
    bne t1, t2, 8f
    li a0, 0
    ret
8:
    li a0, 1
    ret

# gz_body: a0 is the bytes and a1 how many. a0 becomes the offset the
# compressed bytes start at, or -1 when the header runs off the end.
gz_body:
    lbu t0, 3(a0)               # the flags
    li t1, GZ_HEADER
    andi t2, t0, GZ_FEXTRA
    beqz t2, 1f
    addi t3, t1, 2
    bgtu t3, a1, 8f
    add t4, a0, t1
    lbu t5, 0(t4)
    lbu t6, 1(t4)
    slli t6, t6, 8
    or t5, t5, t6
    add t1, t3, t5
1:
    andi t2, t0, GZ_FNAME
    beqz t2, 2f
11:
    bgeu t1, a1, 8f
    add t3, a0, t1
    lbu t3, 0(t3)
    addi t1, t1, 1
    bnez t3, 11b
2:
    andi t2, t0, GZ_FCOMMENT
    beqz t2, 3f
21:
    bgeu t1, a1, 8f
    add t3, a0, t1
    lbu t3, 0(t3)
    addi t1, t1, 1
    bnez t3, 21b
3:
    andi t2, t0, GZ_FHCRC
    beqz t2, 4f
    addi t1, t1, 2
4:
    bgtu t1, a1, 8f
    mv a0, t1
    ret
8:
    li a0, -1
    ret

# gz_le32: t0 is an address; a0 becomes the little-endian longword
# there, which is how gzip writes both trailer fields.
gz_le32:
    lbu t1, 0(t0)
    lbu t2, 1(t0)
    slli t2, t2, 8
    or t1, t1, t2
    lbu t2, 2(t0)
    slli t2, t2, 16
    or t1, t1, t2
    lbu t2, 3(t0)
    slli t2, t2, 24
    or a0, t1, t2
    ret

# gz_crc32: a0 is a buffer and a1 how many bytes; a0 becomes their
# CRC-32, the reflected one gzip and zip both use. The table is built
# once, the first time anything asks.
gz_crc32:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    call gz_crc_table
    ld a0, 0(sp)
    ld a1, 8(sp)
    li t0, -1
    li t1, 0xffffffff
    and t0, t0, t1              # the register starts all ones
    li t2, 0
1:
    bgeu t2, a1, 2f
    add t3, a0, t2
    lbu t3, 0(t3)
    xor t4, t0, t3
    andi t4, t4, 0xff
    slli t4, t4, 2
    la t5, gz_crc
    add t4, t4, t5
    lwu t4, 0(t4)
    srli t0, t0, 8
    xor t0, t0, t4
    addi t2, t2, 1
    j 1b
2:
    li t1, 0xffffffff
    xor a0, t0, t1
    and a0, a0, t1
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# gz_crc_table: the 256 entries of the reflected CRC-32, built on first
# use so nothing sits in the image for a program that never asks.
gz_crc_table:
    la t0, gz_crc_ready
    ld t1, 0(t0)
    bnez t1, 9f
    li t1, 1
    sd t1, 0(t0)
    li t0, 0                    # the byte
1:
    li t1, 256
    bgeu t0, t1, 9f
    mv t2, t0                   # the entry
    li t3, 8
2:
    andi t4, t2, 1
    srli t2, t2, 1
    beqz t4, 3f
    li t4, 0xedb88320
    xor t2, t2, t4
3:
    addi t3, t3, -1
    bnez t3, 2b
    slli t4, t0, 2
    la t5, gz_crc
    add t4, t4, t5
    sw t2, 0(t4)
    addi t0, t0, 1
    j 1b
9:
    ret

.section .bss
.balign 8
gz_crc_ready:
    .skip 8
.balign 4
gz_crc:
    .skip 256 * 4
