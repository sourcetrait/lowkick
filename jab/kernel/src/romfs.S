.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"
.include "jab.inc"

# RomFS on a disk, read through the block layer (block.S). The format is
# Linux's romfs: a volume header of the magic, the accessible size, a
# checksum and the volume's name, then a chain of file headers, each the
# next header's offset with the mode in its low four bits, the spec
# info, the size, a checksum, and the name; everything sits on a 16-byte
# boundary and every longword is big-endian. Nothing is abstracted away:
# a handle is a header's offset in the image, exactly as romfs itself
# points, and the mode nibble reaches a program where the image keeps
# it.
#
# Headers and the partial ends of a read go through one bounce buffer,
# which remembers the sectors it holds, so a listing walking a chain
# inside it costs one read rather than one per entry; the whole sectors
# of a file's data go straight from the device into the program's own
# buffer. What the image cannot support ends the run with a line on the
# UART - a bad checksum, a handle that is not a header, a header whose
# kind is wrong for the call - since every handle the kernel hands out
# is none of those and a program that invents one has a bug.

# "-rom" and "1fs-" as the little-endian words a load sees
.set ROMFS_MAGIC_LOW, 0x6d6f722d
.set ROMFS_MAGIC_HIGH, 0x2d736631
.set ROMFS_HEADER, 16
.set ROMFS_BOUNCE_SECTORS, 4
.set ROMFS_BOUNCE_BYTES, (ROMFS_BOUNCE_SECTORS * JAB_BLOCK_SECTOR)
# Past this a name is not long but corrupt: the bounce could not hold it
# beside its own header.
.set ROMFS_NAME_LIMIT, 1008
.set ROMFS_LINK_LIMIT, 8

.section .text

# sys_romfs_list (jab.romfs.list): a0 is the buffer, a1 the disk, a2 the
# directory's header offset (JAB_ROMFS_ROOT for the volume's root), a3
# the offset this page starts at (0 for the directory's first entry), a4
# how many records the buffer holds. a0 becomes the records written and
# a1 the offset to start the next page at, 0 once the chain has ended.
.global sys_romfs_list
sys_romfs_list:
    call block_probe
    ld a0, 88(sp)
    call romfs_disk
    mv s0, a0
    ld s3, 104(sp)
    bnez s3, 1f
    mv a0, s0
    ld a1, 96(sp)
    call romfs_chain
    mv s3, a0
1:
    ld s4, 112(sp)
    li s5, 0
2:
    beqz s3, 3f
    bgeu s5, s4, 3f
    # each record is checked as it is written, so a capacity larger than
    # the buffer costs the run only where it would write outside it
    li t0, JAB_ROMFS_ENTRY
    mul t0, s5, t0
    ld t1, 80(sp)
    add s6, t1, t0
    mv a0, s6
    li a1, JAB_ROMFS_ENTRY
    call buffer_bounds
    mv a0, s0
    mv a1, s3
    mv a2, s6
    call romfs_entry
    lwu t0, JAB_ROMFS_NEXT(s6)
    andi s3, t0, -16
    addi s5, s5, 1
    j 2b
3:
    sd s5, 80(sp)
    sd s3, 88(sp)
    j trap_return

# sys_romfs_find (jab.romfs.find): a0 is a one-record buffer, a1 the
# disk, a2 the directory to start from (JAB_ROMFS_ROOT for the root), a3
# a path inside the program's window. Components are separated by /, a
# leading / starts at the root, and an empty component is skipped; a
# hard link is followed, so . and .. lead where romfs points them and
# the record carries the header they point at. a0 becomes 0 with the
# record written, 1 when nothing of that name is there, or 2 when a
# component along the way is not a directory; a1 becomes the entry's own
# offset.
.global sys_romfs_find
sys_romfs_find:
    call block_probe
    ld a0, 88(sp)
    call romfs_disk
    mv s0, a0
    ld a0, 80(sp)
    li a1, JAB_ROMFS_ENTRY
    call buffer_bounds
    ld a0, 104(sp)
    call message_bounds
    mv a2, a0
    mv a3, a1
    mv a0, s0
    ld a1, 96(sp)
    call romfs_lookup
    mv s1, a0
    mv s2, a1
    bnez s1, 1f
    ld a0, 80(sp)
    la a1, romfs_scratch
    li a2, JAB_ROMFS_ENTRY
    call copy_bytes
1:
    sd s1, 80(sp)
    sd s2, 88(sp)
    j trap_return

# romfs_lookup: a0 is a disk's index, a1 the directory to start from
# (JAB_ROMFS_ROOT for the root), a2 a path and a3 where it ends. The
# walk of jab.romfs.find: a0 becomes 0 with the entry's record in
# romfs_scratch, 1 when nothing of that name is there, or 2 when a
# component along the way is not a directory; a1 the entry's own
# offset, hard links followed. What png.S uses to find a sprite's
# directory and each frame in it.
.global romfs_lookup
romfs_lookup:
    addi sp, sp, -80
    sd ra, 72(sp)
    sd s0, 64(sp)
    sd s1, 56(sp)
    sd s2, 48(sp)
    sd s3, 40(sp)
    sd s4, 32(sp)
    sd s5, 24(sp)
    sd s6, 16(sp)
    sd s7, 8(sp)
    mv s0, a0
    mv s3, a1
    mv s1, a2
    mv s2, a3
    bgeu s1, s2, 1f
    lbu t0, 0(s1)
    li t1, '/'
    bne t0, t1, 1f
    li s3, JAB_ROMFS_ROOT
1:
    mv a0, s0
    mv a1, s3
    call romfs_chain
    mv s3, a0
2:
    # the next component: separators first, then its length
    bgeu s1, s2, 7f
    lbu t0, 0(s1)
    beqz t0, 7f
    li t1, '/'
    bne t0, t1, 3f
    addi s1, s1, 1
    j 2b
3:
    mv s4, s1
    li s5, 0
4:
    bgeu s1, s2, 5f
    lbu t0, 0(s1)
    beqz t0, 5f
    li t1, '/'
    beq t0, t1, 5f
    addi s1, s1, 1
    addi s5, s5, 1
    j 4b
5:
    mv s6, s3
6:
    beqz s6, 7f
    mv a0, s0
    mv a1, s6
    la a2, romfs_scratch
    call romfs_entry
    mv a0, s4
    mv a1, s5
    call romfs_name_equal
    bnez a0, 8f
    la t0, romfs_scratch
    lwu t0, JAB_ROMFS_NEXT(t0)
    andi s6, t0, -16
    j 6b
7:
    li a0, 1
    li a1, 0
    j 0f
8:
    # found: a hard link stands for what it points at
    mv a0, s0
    mv a1, s6
    call romfs_resolve
    mv s6, a0
    # is there another component after this one
    mv s7, s1
9:
    bgeu s7, s2, 10f
    lbu t0, 0(s7)
    beqz t0, 10f
    li t1, '/'
    bne t0, t1, 11f
    addi s7, s7, 1
    j 9b
10:
    li a0, 0
    mv a1, s6
    j 0f
11:
    la t0, romfs_scratch
    lwu t1, JAB_ROMFS_NEXT(t0)
    andi t1, t1, JAB_ROMFS_TYPE
    li t2, JAB_ROMFS_DIRECTORY
    bne t1, t2, 12f
    lwu s3, JAB_ROMFS_SPEC(t0)
    mv s1, s7
    j 2b
12:
    li a0, 2
    li a1, 0
0:
    ld ra, 72(sp)
    ld s0, 64(sp)
    ld s1, 56(sp)
    ld s2, 48(sp)
    ld s3, 40(sp)
    ld s4, 32(sp)
    ld s5, 24(sp)
    ld s6, 16(sp)
    ld s7, 8(sp)
    addi sp, sp, 80
    ret

# sys_romfs_read (jab.romfs.read): a0 is the buffer, a1 the disk, a2 the
# file's header offset, a3 the byte of it to start at, a4 how many bytes
# at most. The whole sectors go from the device into the buffer and the
# partial ends through the kernel's bounce. a0 becomes the bytes
# written and a1 the offset to read from next, 0 at the file's end.
.global sys_romfs_read
sys_romfs_read:
    call block_probe
    ld a0, 88(sp)
    call romfs_disk
    mv s0, a0
    ld s2, 96(sp)
    ld s3, 104(sp)
    ld s4, 112(sp)
    mv a0, s0
    mv a1, s2
    la a2, romfs_scratch
    call romfs_entry
    mv s5, a0                   # the metadata's length: the data follows
    la t0, romfs_scratch
    lwu t1, JAB_ROMFS_NEXT(t0)
    andi t1, t1, JAB_ROMFS_TYPE
    li t2, JAB_ROMFS_REGULAR
    beq t1, t2, 1f
    li t2, JAB_ROMFS_SYMLINK
    beq t1, t2, 1f
    mv a0, s2
    j romfs_fault_kind
1:
    la t0, romfs_scratch
    lwu s6, JAB_ROMFS_SIZE(t0)
    bgeu s3, s6, 8f
    sub t0, s6, s3
    mv s7, s4
    bgeu t0, s7, 2f
    mv s7, t0
2:
    beqz s7, 8f
    ld a0, 80(sp)
    mv a1, s7
    call buffer_bounds
    add s8, s2, s5
    add s8, s8, s3              # the image byte this read starts at
    li s9, 0
3:
    beqz s7, 7f
    add s10, s8, s9
    andi s11, s10, JAB_BLOCK_SECTOR - 1
    bnez s11, 5f
    srli t0, s7, 9
    beqz t0, 5f
    # on a sector boundary with whole sectors to go, so the device
    # writes the program's buffer itself
    # the queue first: block_base leaves a1 alone, where block_queue
    # would clobber any t register holding the transport
    mv s11, t0
    mv a0, s0
    call block_queue
    mv a1, a0
    mv a0, s0
    call block_base
    li a2, VIRTIO_BLK_T_IN
    srli a3, s10, 9
    ld a4, 80(sp)
    add a4, a4, s9
    slli a5, s11, 9
    li a6, VIRTQ_DESC_F_WRITE
    call block_request
    bnez a0, 9f
    slli t0, s11, 9
    add s9, s9, t0
    sub s7, s7, t0
    j 3b
5:
    # a partial sector, through the kernel's own buffer
    mv a0, s0
    mv a1, s10
    call romfs_window
    mv t0, a0
    mv t1, a1
    li t2, JAB_BLOCK_SECTOR
    sub t2, t2, s11             # what is left of this sector
    mv t3, s7
    bgeu t2, t3, 6f
    mv t3, t2
6:
    bltu t1, t3, 10f            # the image ends inside what it promised
    ld a0, 80(sp)
    add a0, a0, s9
    mv a1, t0
    mv a2, t3
    call copy_bytes
    add s9, s9, t3
    sub s7, s7, t3
    j 3b
7:
    add t0, s3, s9
    li a1, 0
    bgeu t0, s6, 4f
    mv a1, t0
4:
    sd s9, 80(sp)
    sd a1, 88(sp)
    j trap_return
8:
    sd zero, 80(sp)
    sd zero, 88(sp)
    j trap_return
9:
    j romfs_fault_disk
10:
    mv a0, s2
    j romfs_fault_header

# romfs_magic: a0 is a disk's first sector; a0 becomes 1 when it opens
# with the volume magic. block.S asks this to name a disk's kind.
.global romfs_magic
romfs_magic:
    lwu t0, 0(a0)
    lwu t1, 4(a0)
    li t2, ROMFS_MAGIC_LOW
    li t3, ROMFS_MAGIC_HIGH
    li a0, 0
    bne t0, t2, 1f
    bne t1, t3, 1f
    li a0, 1
1:
    ret

# romfs_disk: a0 is the id a program gave; a0 becomes that disk's index.
# Ends the run when the machine has no such disk or it carries no romfs,
# both of which a program can see for itself with jab.block.list.
.global romfs_disk
romfs_disk:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a0, 0(sp)
    call block_count_of
    mv t0, a0
    ld a0, 0(sp)
    beqz a0, 8f
    bgtu a0, t0, 8f
    addi a0, a0, -1
    sd a0, 0(sp)
    call block_record
    lbu t0, JAB_BLOCK_KIND(a0)
    li t1, JAB_BLOCK_KIND_ROMFS
    bne t0, t1, 9f
    ld a0, 0(sp)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret
8:
    ld a0, 0(sp)
    j romfs_fault_disk_id
9:
    ld a0, 0(sp)
    addi a0, a0, 1
    j romfs_fault_not_romfs

# romfs_volume: a0 is a disk's index. a0 becomes the root header's
# offset and a1 the volume's accessible size, both remembered after the
# first call. Ends the run when the disk holds no sound volume.
romfs_volume:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 0(sp)
    slli t0, a0, 3
    la t1, romfs_roots
    add t1, t1, t0
    ld t2, 0(t1)
    beqz t2, 1f
    la t1, romfs_sizes
    add t1, t1, t0
    ld a1, 0(t1)
    mv a0, t2
    j 9f
1:
    ld a0, 0(sp)
    li a1, 0
    call romfs_window
    sd a0, 8(sp)
    li t0, JAB_BLOCK_SECTOR
    bltu a1, t0, 8f
    ld a0, 8(sp)
    call romfs_magic
    beqz a0, 8f
    ld a0, 8(sp)
    addi a0, a0, 8
    call romfs_be32
    sd a0, 16(sp)               # the accessible size
    # the checksum covers the first sector, or a volume smaller than one
    mv a1, a0
    li t0, JAB_BLOCK_SECTOR
    bltu a1, t0, 2f
    mv a1, t0
2:
    andi a1, a1, -4
    ld a0, 8(sp)
    call romfs_checksum
    bnez a0, 8f
    # the root header follows the volume's name
    ld a0, 8(sp)
    addi a0, a0, ROMFS_HEADER
    li a1, ROMFS_NAME_LIMIT
    call romfs_strnlen
    bltz a0, 8f
    addi a0, a0, ROMFS_HEADER + 1
    addi a0, a0, 15
    andi a0, a0, -16
    ld t0, 0(sp)
    slli t1, t0, 3
    la t2, romfs_roots
    add t2, t2, t1
    sd a0, 0(t2)
    la t2, romfs_sizes
    add t2, t2, t1
    ld t3, 16(sp)
    sd t3, 0(t2)
    ld a1, 16(sp)
    j 9f
8:
    ld a0, 0(sp)
    addi a0, a0, 1
    j romfs_fault_not_romfs
9:
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# romfs_chain: a0 is a disk's index and a1 a directory's header offset,
# JAB_ROMFS_ROOT for the root. a0 becomes the offset of its first entry.
# A hard link is followed first, so the . and .. of any directory lead
# where they point. Ends the run when it is not a directory.
romfs_chain:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a0, 0(sp)
    bnez a1, 1f
    call romfs_volume
    mv a1, a0
    ld a0, 0(sp)
1:
    call romfs_resolve
    mv t0, a0
    la t1, romfs_scratch
    lwu t2, JAB_ROMFS_NEXT(t1)
    andi t2, t2, JAB_ROMFS_TYPE
    li t3, JAB_ROMFS_DIRECTORY
    bne t2, t3, 8f
    lwu a0, JAB_ROMFS_SPEC(t1)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret
8:
    mv a0, t0
    j romfs_fault_kind

# romfs_resolve: a0 is a disk's index and a1 a header's offset. Follows
# hard links to what they stand for and leaves that header in the
# scratch record; a0 becomes its offset. Ends the run on a chain of
# links with no end.
romfs_resolve:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    li t0, ROMFS_LINK_LIMIT
    sd t0, 16(sp)
1:
    ld a0, 0(sp)
    ld a1, 8(sp)
    la a2, romfs_scratch
    call romfs_entry
    la t0, romfs_scratch
    lwu t1, JAB_ROMFS_NEXT(t0)
    andi t1, t1, JAB_ROMFS_TYPE
    li t2, JAB_ROMFS_HARDLINK
    bne t1, t2, 9f
    lwu t3, JAB_ROMFS_SPEC(t0)
    sd t3, 8(sp)
    ld t0, 16(sp)
    addi t0, t0, -1
    sd t0, 16(sp)
    bnez t0, 1b
    ld a0, 8(sp)
    j romfs_fault_header
9:
    ld a0, 8(sp)
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# romfs_entry: a0 is a disk's index, a1 a header's offset, a2 where the
# record goes. Reads the header, holds it to its own checksum, and
# writes the record of jab.inc. a0 becomes the metadata's length, so a
# file's data begins that far after its header. A name longer than a
# record holds is reported cut, which is what a Linux mount of the same
# image reports, while the length used here is the real one, so the data
# still begins where it truly does.
.global romfs_entry
romfs_entry:
    addi sp, sp, -64
    sd ra, 48(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    sd a2, 16(sp)
    andi t0, a1, 15
    bnez t0, 8f                 # a header always sits on a boundary
    call romfs_volume
    mv t0, a1
    ld t1, 8(sp)
    bgeu t1, t0, 8f             # and inside the volume
    ld a0, 0(sp)
    ld a1, 8(sp)
    call romfs_window
    sd a0, 24(sp)
    sd a1, 32(sp)
    li t0, ROMFS_HEADER
    bltu a1, t0, 8f
    ld a0, 24(sp)
    addi a0, a0, ROMFS_HEADER
    ld a1, 32(sp)
    addi a1, a1, -ROMFS_HEADER
    li t0, ROMFS_NAME_LIMIT
    bltu a1, t0, 1f
    mv a1, t0
1:
    call romfs_strnlen
    bltz a0, 8f
    sd a0, 56(sp)               # the name's real length
    addi t1, a0, ROMFS_HEADER + 1
    addi t1, t1, 15
    andi t1, t1, -16
    sd t1, 40(sp)               # the metadata's length
    ld t2, 32(sp)
    bltu t2, t1, 8f
    ld a0, 24(sp)
    ld a1, 40(sp)
    call romfs_checksum
    bnez a0, 8f
    # the record: the handle it was asked about, then the header as the
    # image keeps it
    ld t0, 16(sp)
    ld t1, 8(sp)
    sw t1, JAB_ROMFS_OFFSET(t0)
    ld a0, 24(sp)
    call romfs_be32
    ld t0, 16(sp)
    sw a0, JAB_ROMFS_NEXT(t0)
    ld a0, 24(sp)
    addi a0, a0, 4
    call romfs_be32
    ld t0, 16(sp)
    sw a0, JAB_ROMFS_SPEC(t0)
    ld a0, 24(sp)
    addi a0, a0, 8
    call romfs_be32
    ld t0, 16(sp)
    sw a0, JAB_ROMFS_SIZE(t0)
    # the name, over a cleared field so a short one ends where it should
    # and a long one is cut where the record ends
    ld a0, 16(sp)
    addi a0, a0, JAB_ROMFS_NAME
    li a1, JAB_ROMFS_NAME_BYTES
    call zero_bytes
    ld t0, 56(sp)
    li t1, JAB_ROMFS_NAME_BYTES - 1
    bltu t0, t1, 2f
    mv t0, t1
2:
    ld a0, 16(sp)
    addi a0, a0, JAB_ROMFS_NAME
    ld a1, 24(sp)
    addi a1, a1, ROMFS_HEADER
    mv a2, t0
    call copy_bytes
    ld a0, 40(sp)
    ld ra, 48(sp)
    addi sp, sp, 64
    ret
8:
    ld a0, 8(sp)
    j romfs_fault_header

# romfs_window: a0 is a disk's index and a1 an offset in its image.
# Reads the sectors holding it into the bounce, as many as the bounce
# and the disk allow, and returns that byte's address in a0 with the
# bytes readable after it in a1. The bounce remembers what it holds, so
# a chain walked inside it is read once. Ends the run on a disk error or
# an offset past the disk.
.global romfs_window
romfs_window:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 0(sp)
    srli t0, a1, 9
    sd t0, 8(sp)                # the first sector
    andi t1, a1, JAB_BLOCK_SECTOR - 1
    sd t1, 16(sp)               # how far into it
    la t2, romfs_bounce_disk
    ld t3, 0(t2)
    addi t4, a0, 1
    bne t3, t4, 1f
    la t2, romfs_bounce_sector
    ld t3, 0(t2)
    beq t3, t0, 5f              # already here
1:
    ld a0, 0(sp)
    call block_record
    ld t0, JAB_BLOCK_SECTORS(a0)
    ld t1, 8(sp)
    bgeu t1, t0, 8f
    sub t2, t0, t1
    li t3, ROMFS_BOUNCE_SECTORS
    bgeu t2, t3, 2f
    mv t3, t2
2:
    sd t3, 24(sp)
    ld a0, 0(sp)
    call block_base
    sd a0, 32(sp)
    ld a0, 0(sp)
    call block_queue
    mv a1, a0
    ld a0, 32(sp)
    li a2, VIRTIO_BLK_T_IN
    ld a3, 8(sp)
    la a4, romfs_bounce
    ld a5, 24(sp)
    slli a5, a5, 9
    li a6, VIRTQ_DESC_F_WRITE
    call block_request
    bnez a0, 9f
    ld t0, 0(sp)
    addi t0, t0, 1
    la t1, romfs_bounce_disk
    sd t0, 0(t1)
    ld t0, 8(sp)
    la t1, romfs_bounce_sector
    sd t0, 0(t1)
    ld t0, 24(sp)
    la t1, romfs_bounce_count
    sd t0, 0(t1)
5:
    la t0, romfs_bounce_count
    ld t0, 0(t0)
    slli t0, t0, 9
    ld t1, 16(sp)
    sub a1, t0, t1
    la a0, romfs_bounce
    add a0, a0, t1
    ld ra, 40(sp)
    addi sp, sp, 48
    ret
8:
    ld a0, 8(sp)
    slli a0, a0, 9
    j romfs_fault_header
9:
    j romfs_fault_disk

# romfs_be32: a0 is an address; a0 becomes the big-endian longword
# there, which is how romfs writes every value.
romfs_be32:
    lbu t0, 0(a0)
    lbu t1, 1(a0)
    lbu t2, 2(a0)
    lbu t3, 3(a0)
    slli t0, t0, 24
    slli t1, t1, 16
    slli t2, t2, 8
    or t0, t0, t1
    or t0, t0, t2
    or a0, t0, t3
    ret

# romfs_checksum: a0 is an address and a1 a count of bytes, a multiple
# of four. a0 becomes the sum of the longwords there taken as 32 bits,
# which romfs makes zero over a sound volume or file header.
romfs_checksum:
    li t5, 0
1:
    beqz a1, 2f
    lbu t0, 0(a0)
    lbu t1, 1(a0)
    lbu t2, 2(a0)
    lbu t3, 3(a0)
    slli t0, t0, 24
    slli t1, t1, 16
    slli t2, t2, 8
    or t0, t0, t1
    or t0, t0, t2
    or t0, t0, t3
    add t5, t5, t0
    addi a0, a0, 4
    addi a1, a1, -4
    j 1b
2:
    slli a0, t5, 32
    srli a0, a0, 32
    ret

# romfs_strnlen: a0 is an address and a1 the most bytes to look at. a0
# becomes the length of the string there, or -1 when no terminator is
# within reach.
romfs_strnlen:
    li t0, 0
1:
    bgeu t0, a1, 8f
    add t1, a0, t0
    lbu t2, 0(t1)
    beqz t2, 2f
    addi t0, t0, 1
    j 1b
2:
    mv a0, t0
    ret
8:
    li a0, -1
    ret

# romfs_name_equal: a0 is a name in the program's window and a1 its
# length; a0 becomes 1 when the scratch record carries the same name.
romfs_name_equal:
    la t0, romfs_scratch
    addi t0, t0, JAB_ROMFS_NAME
    li t1, 0
1:
    bgeu t1, a1, 2f
    add t2, a0, t1
    lbu t3, 0(t2)
    add t2, t0, t1
    lbu t4, 0(t2)
    bne t3, t4, 8f
    addi t1, t1, 1
    j 1b
2:
    add t2, t0, t1
    lbu t3, 0(t2)
    bnez t3, 8f
    li a0, 1
    ret
8:
    li a0, 0
    ret

romfs_fault_disk_id:
    mv s0, a0
    la a0, msg_romfs_disk_id
    call uart_puts
    mv a0, s0
    call uart_put_dec
    j romfs_fault_end

romfs_fault_not_romfs:
    mv s0, a0
    la a0, msg_romfs_not_romfs
    call uart_puts
    mv a0, s0
    call uart_put_dec
    j romfs_fault_end

romfs_fault_header:
    mv s0, a0
    la a0, msg_romfs_header
    call uart_puts
    mv a0, s0
    call uart_put_hex
    j romfs_fault_end

romfs_fault_kind:
    mv s0, a0
    la a0, msg_romfs_kind
    call uart_puts
    mv a0, s0
    call uart_put_hex
    j romfs_fault_end

romfs_fault_disk:
    la a0, msg_romfs_disk_error
    call uart_puts
    j romfs_fault_end

romfs_fault_end:
    li a0, '\n'
    call uart_putc
    li a0, 1
    j qemu_exit

.section .bss
.balign 8
romfs_bounce:
    .skip ROMFS_BOUNCE_BYTES
.global romfs_scratch
romfs_scratch:
    .skip JAB_ROMFS_ENTRY
romfs_roots:
    .skip JAB_BLOCK_MAX * 8
romfs_sizes:
    .skip JAB_BLOCK_MAX * 8
romfs_bounce_disk:
    .skip 8
romfs_bounce_sector:
    .skip 8
romfs_bounce_count:
    .skip 8

.section .rodata
msg_romfs_disk_id:
    .asciz "jab: romfs: no disk "
msg_romfs_not_romfs:
    .asciz "jab: romfs: no romfs on disk "
msg_romfs_header:
    .asciz "jab: romfs: bad header at "
msg_romfs_kind:
    .asciz "jab: romfs: wrong kind at "
msg_romfs_disk_error:
    .asciz "jab: romfs: disk error"
