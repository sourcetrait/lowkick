.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"
.include "jab.inc"

# The disks: QEMU's virtio-blk devices over the same mmio transport
# every other Jab device uses, driven as sectors and nothing more. The
# first block or romfs call finds every transport carrying device id 2,
# brings it up, and gives it an id in transport order, learning its
# capacity from the config space, its serial from a GET_ID request, and
# what is on it from its first sector. All of that is kept in the
# program-facing record of jab.inc, so a listing is a copy rather than a
# translation. A request is three descriptors - the header the device
# reads, the data, and the status byte it writes - run one at a time per
# disk with the hart halted until the device answers, as the display's
# commands are. A disk that refuses the kernel is still counted, with
# JAB_BLOCK_KIND_NONE and no capacity, so a program sees that the
# machine carries a disk there and reads why from the code it gets back.
# A format reads through this layer: romfs.S.

.section .text

# sys_block_list (jab.block.list): a0 is the buffer, a1 the id of the
# disk to start at (0 for the first), a2 how many records the buffer
# holds. a0 becomes the records written, a1 the id to start the next
# page at, or 0 once the last disk is in the buffer.
.global sys_block_list
sys_block_list:
    call block_probe
    ld s0, 88(sp)
    la t0, block_count
    ld s1, 0(t0)
    beqz s0, 1f
    addi s0, s0, -1             # an id is one more than its index
1:
    bgeu s0, s1, 8f
    sub s2, s1, s0              # disks from here on
    ld s3, 96(sp)
    bltu s3, s2, 2f
    mv s3, s2                   # never more than there are
2:
    beqz s3, 8f
    li t0, JAB_BLOCK_ENTRY
    mul s4, s3, t0              # bytes to write
    mul s5, s0, t0              # where they start
    ld a0, 80(sp)
    mv a1, s4
    call buffer_bounds
    ld a0, 80(sp)
    la a1, block_records
    add a1, a1, s5
    mv a2, s4
    call copy_bytes
    add t0, s0, s3
    li a1, 0
    bgeu t0, s1, 3f
    addi a1, t0, 1
3:
    mv a0, s3
    j 9f
8:
    li a0, 0
    li a1, 0
9:
    sd a0, 80(sp)
    sd a1, 88(sp)
    j trap_return

# sys_block_find (jab.block.find): a0 is a NUL-terminated serial inside
# the program's window. a0 becomes the id of the first disk carrying it,
# or 0 when none does.
.global sys_block_find
sys_block_find:
    call block_probe
    ld a0, 80(sp)
    call message_bounds
    mv s0, a0                   # the serial asked for
    mv s1, a1                   # the window's end
    la s2, block_records
    li s3, 0
    la t0, block_count
    ld s4, 0(t0)
1:
    bgeu s3, s4, 8f
    mv t0, s0
    addi t1, s2, JAB_BLOCK_SERIAL
    li t2, JAB_BLOCK_SERIAL_BYTES
2:
    bgeu t0, s1, 8f             # the string runs past the window
    lbu t3, 0(t0)
    lbu t4, 0(t1)
    bne t3, t4, 4f
    beqz t3, 7f                 # both ended here
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    bnez t2, 2b
    # twenty bytes matched, which is all virtio carries, so the serial
    # matches only if the program's string ends here too
    bgeu t0, s1, 8f
    lbu t3, 0(t0)
    beqz t3, 7f
4:
    addi s3, s3, 1
    li t0, JAB_BLOCK_ENTRY
    add s2, s2, t0
    j 1b
7:
    addi a0, s3, 1
    j 9f
8:
    li a0, 0
9:
    sd a0, 80(sp)
    j trap_return

# sys_block_read (jab.block.read): a0 is the buffer, a1 the disk, a2 the
# first sector, a3 how many sectors. The device writes the program's
# buffer itself, so nothing is copied.
.global sys_block_read
sys_block_read:
    li s0, VIRTIO_BLK_T_IN
    li s1, VIRTQ_DESC_F_WRITE
    j block_transfer

# sys_block_write (jab.block.write): the same, the other way, so the
# device reads the buffer.
.global sys_block_write
sys_block_write:
    li s0, VIRTIO_BLK_T_OUT
    li s1, 0
    j block_transfer

# a0 becomes 0; 1 when no disk carries that id; 2 when the disk would
# not come up; 3 when the device reported an error; 4 when those sectors
# are not on that disk.
block_transfer:
    call block_probe
    ld s2, 88(sp)               # the disk
    ld s3, 96(sp)               # the first sector
    ld s4, 104(sp)              # how many
    la t0, block_count
    ld t0, 0(t0)
    li a0, 1
    beqz s2, 9f
    bgtu s2, t0, 9f
    addi t1, s2, -1
    li t2, JAB_BLOCK_ENTRY
    mul t1, t1, t2
    la s5, block_records
    add s5, s5, t1
    lbu t3, JAB_BLOCK_KIND(s5)
    li a0, 2
    beqz t3, 9f                 # the disk never came up
    li a0, 4
    beqz s4, 9f
    ld t4, JAB_BLOCK_SECTORS(s5)
    bgtu s3, t4, 9f
    sub t5, t4, s3
    bgtu s4, t5, 9f
    li t6, JAB_BLOCK_SECTOR
    mul s6, s4, t6              # the bytes it moves
    ld a0, 80(sp)
    mv a1, s6
    call buffer_bounds
    # the queue first: block_base leaves a1 alone, where block_queue
    # would clobber any t register holding the transport
    addi s7, s2, -1
    mv a0, s7
    call block_queue
    mv a1, a0
    mv a0, s7
    call block_base
    mv a2, s0
    mv a3, s3
    ld a4, 80(sp)
    mv a5, s6
    mv a6, s1
    call block_request
    li t0, VIRTIO_BLK_S_OK
    beq a0, t0, 8f
    li a0, 3
    j 9f
8:
    li a0, 0
9:
    sd a0, 80(sp)
    j trap_return

# block_base: a0 is a disk's index; a0 becomes its transport's address.
.global block_base
block_base:
    slli t0, a0, 3
    la t1, block_bases
    add t1, t1, t0
    ld a0, 0(t1)
    ret

# block_queue: a0 is a disk's index; a0 becomes its virtqueue record.
.global block_queue
block_queue:
    li t0, VQ_STRIDE
    mul t0, a0, t0
    la t1, block_queues
    add a0, t1, t0
    ret

# block_record: a0 is a disk's index; a0 becomes its record.
.global block_record
block_record:
    li t0, JAB_BLOCK_ENTRY
    mul t0, a0, t0
    la t1, block_records
    add a0, t1, t0
    ret

# block_count_of: a0 becomes how many disks the machine carries, once
# they have been probed.
.global block_count_of
block_count_of:
    la t0, block_count
    ld a0, 0(t0)
    ret

# block_probe: find every virtio-blk disk and bring it up, once. The
# transports are walked in address order, so a disk's id is where it
# sits on the machine and not the order QEMU's command line named it.
.global block_probe
block_probe:
    la t0, block_probed
    ld t0, 0(t0)
    bnez t0, 9f
    addi sp, sp, -48
    sd ra, 40(sp)
    la t0, block_probed
    li t1, 1
    sd t1, 0(t0)                # once, whatever comes of it
    li t0, QEMU_VIRT_VIRTIO0
    sd t0, 0(sp)                # the transport being looked at
    li t0, QEMU_VIRT_VIRTIO_COUNT
    sd t0, 8(sp)                # transports left
    sd zero, 16(sp)             # disks found so far
1:
    ld t0, 8(sp)
    beqz t0, 8f
    ld t0, 0(sp)
    li t1, VIRTIO_MAGIC
    lwu t2, VIRTIO_MMIO_MAGIC_VALUE(t0)
    bne t2, t1, 7f
    li t1, VIRTIO_VERSION_MODERN
    lwu t2, VIRTIO_MMIO_VERSION(t0)
    bne t2, t1, 7f
    li t1, VIRTIO_ID_BLOCK
    lwu t2, VIRTIO_MMIO_DEVICE_ID(t0)
    bne t2, t1, 7f
    # a disk: its record carries its id from the start, so a device that
    # refuses the kernel is still one a program can see and ask about
    ld a0, 16(sp)
    call block_record
    sd a0, 24(sp)
    ld t0, 16(sp)
    addi t1, t0, 1
    sb t1, JAB_BLOCK_ID(a0)
    sb zero, JAB_BLOCK_KIND(a0)
    ld a0, 16(sp)
    call block_queue
    sd a0, 32(sp)
    ld t0, 16(sp)
    slli t0, t0, 3
    la t1, block_bases
    add t1, t1, t0
    ld t2, 0(sp)
    sd t2, 0(t1)
    ld a0, 0(sp)
    call virtio_init
    bnez a0, 6f
    ld a0, 0(sp)
    li a1, 0
    ld a2, 32(sp)
    call virtio_queue_setup
    bnez a0, 6f
    ld a0, 0(sp)
    call virtio_driver_ok
    ld a0, 0(sp)
    call virtio_irq_enable
    # the capacity, two words of the config space since the transport
    # answers four bytes at a time
    ld t0, 0(sp)
    lwu t1, (VIRTIO_MMIO_CONFIG + VIRTIO_BLK_CFG_CAPACITY_LOW)(t0)
    lwu t2, (VIRTIO_MMIO_CONFIG + VIRTIO_BLK_CFG_CAPACITY_HIGH)(t0)
    slli t2, t2, 32
    or t1, t1, t2
    ld t3, 24(sp)
    sd t1, JAB_BLOCK_SECTORS(t3)
    # the serial, straight into the record: QEMU writes the terminator
    # only when it fits, so the field is cleared first
    addi t4, t3, JAB_BLOCK_SERIAL
    sd zero, 0(t4)
    sd zero, 8(t4)
    sw zero, 16(t4)
    ld a0, 0(sp)
    ld a1, 32(sp)
    li a2, VIRTIO_BLK_T_GET_ID
    li a3, 0
    ld a4, 24(sp)
    addi a4, a4, JAB_BLOCK_SERIAL
    li a5, VIRTIO_BLK_ID_BYTES
    li a6, VIRTQ_DESC_F_WRITE
    call block_request
    # what is on it, by asking each format we know about the first
    # sector; anything unrecognised is raw sectors and nothing more
    ld a0, 0(sp)
    ld a1, 32(sp)
    li a2, VIRTIO_BLK_T_IN
    li a3, 0
    la a4, block_bounce
    li a5, JAB_BLOCK_SECTOR
    li a6, VIRTQ_DESC_F_WRITE
    call block_request
    ld t3, 24(sp)
    li t0, JAB_BLOCK_KIND_RAW
    sb t0, JAB_BLOCK_KIND(t3)
    bnez a0, 6f
    la a0, block_bounce
    call romfs_magic
    beqz a0, 6f
    ld t3, 24(sp)
    li t0, JAB_BLOCK_KIND_ROMFS
    sb t0, JAB_BLOCK_KIND(t3)
6:
    ld t0, 16(sp)
    addi t0, t0, 1
    sd t0, 16(sp)
7:
    ld t0, 0(sp)
    li t1, QEMU_VIRT_VIRTIO_STRIDE
    add t0, t0, t1
    sd t0, 0(sp)
    ld t0, 8(sp)
    addi t0, t0, -1
    sd t0, 8(sp)
    j 1b
8:
    ld t0, 16(sp)
    la t1, block_count
    sd t0, 0(t1)
    ld ra, 40(sp)
    addi sp, sp, 48
9:
    ret

# block_request: run one request on the disk whose transport is at a0
# with the virtqueue record at a1: type a2, sector a3, the data buffer
# at a4 of a5 bytes, which the device writes when a6 carries
# VIRTQ_DESC_F_WRITE and reads otherwise. Three descriptors, offered as
# one chain; a0 becomes the device's status byte, 0 for OK.
.global block_request
block_request:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    la t0, block_header
    sw a2, VIRTIO_BLK_REQ_TYPE(t0)
    sw zero, VIRTIO_BLK_REQ_IOPRIO(t0)
    sd a3, VIRTIO_BLK_REQ_SECTOR(t0)
    la t1, block_status
    li t2, 0xff
    sb t2, 0(t1)                # so an unanswered request cannot read OK
    mv t3, a1
    # the header the device reads
    sd t0, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_ADDR)(t3)
    li t4, VIRTIO_BLK_REQ_SIZE
    sw t4, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_LEN)(t3)
    li t4, VIRTQ_DESC_F_NEXT
    sh t4, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_FLAGS)(t3)
    li t4, 1
    sh t4, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_NEXT)(t3)
    # the data
    sd a4, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_ADDR)(t3)
    sw a5, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_LEN)(t3)
    ori t4, a6, VIRTQ_DESC_F_NEXT
    sh t4, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_FLAGS)(t3)
    li t4, 2
    sh t4, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_NEXT)(t3)
    # the status byte the device writes
    sd t1, (VQ_DESC + 2 * VIRTQ_DESC_SIZE + VIRTQ_DESC_ADDR)(t3)
    li t4, 1
    sw t4, (VQ_DESC + 2 * VIRTQ_DESC_SIZE + VIRTQ_DESC_LEN)(t3)
    li t4, VIRTQ_DESC_F_WRITE
    sh t4, (VQ_DESC + 2 * VIRTQ_DESC_SIZE + VIRTQ_DESC_FLAGS)(t3)
    sh zero, (VQ_DESC + 2 * VIRTQ_DESC_SIZE + VIRTQ_DESC_NEXT)(t3)
    # offer the chain's head in the next slot of the available ring
    lhu t4, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(t3)
    andi t5, t4, VIRTQ_SIZE - 1
    slli t5, t5, 1
    add t5, t5, t3
    sh zero, (VQ_AVAIL + VIRTQ_AVAIL_RING)(t5)
    fence w, w
    addi t4, t4, 1
    sh t4, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(t3)
    fence rw, rw
    ld t0, 0(sp)
    sw zero, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
    ld a0, 8(sp)
    call virtio_wait_used
    ld t2, VQ_LAST_USED(a0)
    addi t2, t2, 1
    li t0, 0xffff
    and t2, t2, t0
    sd t2, VQ_LAST_USED(a0)
    la t0, block_status
    lbu a0, 0(t0)
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

.section .bss
.balign 16
block_queues:
    .skip JAB_BLOCK_MAX * VQ_STRIDE
.balign 8
block_records:
    .skip JAB_BLOCK_LIST_SIZE
block_bases:
    .skip JAB_BLOCK_MAX * 8
block_count:
    .skip 8
block_probed:
    .skip 8
block_header:
    .skip VIRTIO_BLK_REQ_SIZE
block_status:
    .skip 8
.balign 8
.global block_bounce
block_bounce:
    .skip JAB_BLOCK_SECTOR
