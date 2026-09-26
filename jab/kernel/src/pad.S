.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"
.include "jab.inc"

# The pad: a gamepad the host passed through as QEMU's
# virtio-input-host-device, a virtio-input device told from the
# keyboard and the tablet by carrying BTN_SOUTH in its EV_KEY bits and
# ABS_X in its EV_ABS bits. Its event queue is the wide one, PADQ_SIZE
# eight-byte events the device fills, since a pad sends several events
# a report at over a hundred reports a second and the kernel drains
# only when the program asks or waits. A drain keeps EV_KEY events,
# setting or clearing the key's bit in the mask, and EV_ABS events,
# storing the axis's raw value, and pushes both into a ring of PAD_RING
# events for jab.pad.input; EV_SYN and EV_MSC are dropped. Each axis's
# range comes from the device's config space when the pad comes up,
# and its raw value starts at rest, the middle of its range or its
# minimum for the one-sided ABS_GAS and ABS_BRAKE, so an axis that has
# not moved reads 0 once normalised. jab.pad.read normalises every axis
# into the program's record at the call.
.set PAD_RING, 256
.set PAD_ENTRY_SIZE, 8
.set PAD_KEYS_BITS, 32
.set BTN_SOUTH_BYTE, (JAB_BTN_SOUTH / 8)
.set BTN_SOUTH_BIT, (JAB_BTN_SOUTH % 8)
.set ABS_BITMAP_BYTES, (JAB_PAD_AXIS_COUNT / 8)

.section .text

# sys_pad_read (jab.pad.read): a0 is the record, JAB_PAD_ENTRY bytes
# inside the program's window. a0 becomes 0 with the record written,
# the keys held and every axis normalised, or 1 with no pad on the
# machine.
.global sys_pad_read
sys_pad_read:
    ld a0, 80(sp)
    li a1, JAB_PAD_ENTRY
    call buffer_bounds
    call pad_open
    bnez a0, 9f
    call pad_drain
    # the keys, a byte at a time, since the record sits where the
    # program put it
    ld t0, 80(sp)
    la t1, pad_keys
    lwu t1, 0(t1)
    sb t1, JAB_PAD_KEYS(t0)
    srli t2, t1, 8
    sb t2, (JAB_PAD_KEYS + 1)(t0)
    srli t2, t1, 16
    sb t2, (JAB_PAD_KEYS + 2)(t0)
    srli t2, t1, 24
    sb t2, (JAB_PAD_KEYS + 3)(t0)
    # every axis, normalised
    li s0, 0
1:
    mv a0, s0
    call pad_normalise
    ld t0, 80(sp)
    slli t1, s0, 1
    add t1, t1, t0
    sb a0, JAB_PAD_AXES(t1)
    srli a0, a0, 8
    sb a0, (JAB_PAD_AXES + 1)(t1)
    addi s0, s0, 1
    li t0, JAB_PAD_AXIS_COUNT
    bltu s0, t0, 1b
    li a0, 0
    j 8f
9:
    li a0, 1
8:
    sd a0, 80(sp)
    j trap_return

# sys_pad_input (jab.pad.input): a0 becomes the oldest waiting event's
# type, or 0 when none waits; a1 its code; a2 its value. The pad comes
# up on the first call; with no pad on the machine there is never an
# event.
.global sys_pad_input
sys_pad_input:
    call pad_open
    bnez a0, 1f
    call pad_drain
    call pad_take
    sd a0, 80(sp)
    sd a1, 88(sp)
    sd a2, 96(sp)
    j trap_return
1:
    sd zero, 80(sp)
    sd zero, 88(sp)
    sd zero, 96(sp)
    j trap_return

# sys_pad_axis (jab.pad.axis): a0 is a buffer of JAB_PAD_AXIS_ENTRY
# bytes inside the program's window, a1 an axis code. a0 becomes 0
# with the axis's absinfo written as virtio reported it; 1 with no pad;
# 2 when the pad has no such axis.
.global sys_pad_axis
sys_pad_axis:
    ld a0, 80(sp)
    li a1, JAB_PAD_AXIS_ENTRY
    call buffer_bounds
    call pad_open
    bnez a0, 7f
    ld a0, 88(sp)
    li t0, JAB_PAD_AXIS_COUNT
    bgeu a0, t0, 8f
    call pad_axis_present
    beqz a0, 8f
    ld a1, 88(sp)
    li t0, JAB_PAD_AXIS_ENTRY
    mul a1, a1, t0
    la t0, pad_absinfo
    add a1, a1, t0
    ld a0, 80(sp)
    li a2, JAB_PAD_AXIS_ENTRY
    call copy_bytes
    li a0, 0
    j 9f
7:
    li a0, 1
    j 9f
8:
    li a0, 2
9:
    sd a0, 80(sp)
    j trap_return

# pad_open: find the pad and bring it up, its queue stocked, its line
# let through, and its axes' ranges read. Returns 0, or 1 with no pad
# on the machine, 2 when the device refuses the kernel; asked again it
# answers as before at once. Keeps the s registers.
.global pad_open
pad_open:
    la t0, pad_state
    ld t0, 0(t0)
    beqz t0, 1f
    addi a0, t0, -1
    ret
1:
    addi sp, sp, -16
    sd ra, 8(sp)
    call pad_find
    beqz a0, 5f
    la t0, pad_base
    sd a0, 0(t0)
.ifdef DEBUG
    la a0, msg_pad_at
    call debug_puts
    la t0, pad_base
    ld a0, 0(t0)
    call debug_put_hex
    li a0, '\n'
    call debug_putc
    la t0, pad_base
    ld a0, 0(t0)
.pushsection .rodata
msg_pad_at:
    .asciz "jab: pad at "
.popsection
.endif
    call virtio_init
    bnez a0, 6f
    call pad_queue_setup
    bnez a0, 6f
    # every descriptor an event buffer the device may write, all
    # offered at once
    la t0, pad_queue
    la t1, pad_events
    li t2, 0
2:
    slli t3, t2, 4
    add t3, t3, t0
    sd t1, (PADQ_DESC + VIRTQ_DESC_ADDR)(t3)
    li t4, VIRTIO_INPUT_EVENT_SIZE
    sw t4, (PADQ_DESC + VIRTQ_DESC_LEN)(t3)
    li t4, VIRTQ_DESC_F_WRITE
    sh t4, (PADQ_DESC + VIRTQ_DESC_FLAGS)(t3)
    sh zero, (PADQ_DESC + VIRTQ_DESC_NEXT)(t3)
    slli t3, t2, 1
    add t3, t3, t0
    sh t2, (PADQ_AVAIL + VIRTQ_AVAIL_RING)(t3)
    addi t1, t1, VIRTIO_INPUT_EVENT_SIZE
    addi t2, t2, 1
    li t3, PADQ_SIZE
    bltu t2, t3, 2b
    fence w, w
    sh t2, (PADQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    fence rw, rw
    la t0, pad_base
    ld a0, 0(t0)
    call virtio_driver_ok
    la t0, pad_base
    ld a0, 0(t0)
    sw zero, VIRTIO_MMIO_QUEUE_NOTIFY(a0)
    call virtio_irq_enable
    call pad_ranges
    la t0, pad_state
    li t1, 1
    sd t1, 0(t0)
    li a0, 0
    j 8f
5:
.ifdef DEBUG
    la a0, msg_no_pad
    call debug_puts
.pushsection .rodata
msg_no_pad:
    .asciz "jab: no pad\n"
.popsection
.endif
    la t0, pad_state
    li t1, 2
    sd t1, 0(t0)
    li a0, 1
    j 8f
6:
    la t0, pad_state
    li t1, 3
    sd t1, 0(t0)
    li a0, 2
8:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# pad_queue_setup: give the pad's event queue, queue 0, the wide
# record's rings, PADQ_SIZE entries. Returns 0, or 1 when the device
# offers fewer.
pad_queue_setup:
    la t2, pad_base
    ld a0, 0(t2)
    la a2, pad_queue
    sw zero, VIRTIO_MMIO_QUEUE_SEL(a0)
    lwu t0, VIRTIO_MMIO_QUEUE_NUM_MAX(a0)
    li t1, PADQ_SIZE
    bltu t0, t1, 1f
    sw t1, VIRTIO_MMIO_QUEUE_NUM(a0)
    addi t0, a2, PADQ_DESC
    srli t1, t0, 32
    sw t0, VIRTIO_MMIO_QUEUE_DESC_LOW(a0)
    sw t1, VIRTIO_MMIO_QUEUE_DESC_HIGH(a0)
    addi t0, a2, PADQ_AVAIL
    srli t1, t0, 32
    sw t0, VIRTIO_MMIO_QUEUE_DRIVER_LOW(a0)
    sw t1, VIRTIO_MMIO_QUEUE_DRIVER_HIGH(a0)
    addi t0, a2, PADQ_USED
    srli t1, t0, 32
    sw t0, VIRTIO_MMIO_QUEUE_DEVICE_LOW(a0)
    sw t1, VIRTIO_MMIO_QUEUE_DEVICE_HIGH(a0)
    li t0, 1
    sw t0, VIRTIO_MMIO_QUEUE_READY(a0)
    li a0, 0
    ret
1:
    li a0, 1
    ret

# pad_find: the base of the first virtio-input transport whose EV_KEY
# bits include BTN_SOUTH and whose EV_ABS bits include ABS_X, or 0.
pad_find:
    li t0, QEMU_VIRT_VIRTIO0
    li t1, QEMU_VIRT_VIRTIO_COUNT
    li t2, VIRTIO_MAGIC
    li t3, VIRTIO_VERSION_MODERN
    li t5, QEMU_VIRT_VIRTIO_STRIDE
    li t6, VIRTIO_ID_INPUT
1:
    lwu t4, VIRTIO_MMIO_MAGIC_VALUE(t0)
    bne t4, t2, 2f
    lwu t4, VIRTIO_MMIO_VERSION(t0)
    bne t4, t3, 2f
    lwu t4, VIRTIO_MMIO_DEVICE_ID(t0)
    bne t4, t6, 2f
    # the key bitmap: BTN_SOUTH
    li t4, VIRTIO_INPUT_CFG_EV_BITS
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SELECT)(t0)
    li t4, EV_KEY
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SUBSEL)(t0)
    lbu t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SIZE)(t0)
    li a0, BTN_SOUTH_BYTE
    bleu t4, a0, 2f
    lbu t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_DATA + BTN_SOUTH_BYTE)(t0)
    srli t4, t4, BTN_SOUTH_BIT
    andi t4, t4, 1
    beqz t4, 2f
    # the axis bitmap: ABS_X
    li t4, VIRTIO_INPUT_CFG_EV_BITS
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SELECT)(t0)
    li t4, EV_ABS
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SUBSEL)(t0)
    lbu t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SIZE)(t0)
    beqz t4, 2f
    lbu t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_DATA)(t0)
    andi t4, t4, 1
    bnez t4, 3f
2:
    add t0, t0, t5
    addi t1, t1, -1
    bnez t1, 1b
    li a0, 0
    ret
3:
    mv a0, t0
    ret

# pad_ranges: the axes the pad has, from its EV_ABS bitmap, and each
# one's absinfo from the config space into the table; and each raw
# value set to rest, the middle of the range, or its minimum for the
# one-sided ABS_GAS and ABS_BRAKE. Keeps the s registers.
pad_ranges:
    addi sp, sp, -32
    sd ra, 24(sp)
    la t0, pad_base
    ld t0, 0(t0)
    li t4, VIRTIO_INPUT_CFG_EV_BITS
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SELECT)(t0)
    li t4, EV_ABS
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SUBSEL)(t0)
    lbu t1, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SIZE)(t0)
    li t2, ABS_BITMAP_BYTES
    bleu t1, t2, 1f
    mv t1, t2
1:
    la t2, pad_abs_bits
    li t3, 0
2:
    bgeu t3, t1, 3f
    add t4, t0, t3
    lbu t5, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_DATA)(t4)
    add t6, t2, t3
    sb t5, 0(t6)
    addi t3, t3, 1
    j 2b
3:
    sd zero, 0(sp)              # the code
4:
    ld t3, 0(sp)
    li t4, JAB_PAD_AXIS_COUNT
    bgeu t3, t4, 9f
    mv a0, t3
    call pad_axis_present
    beqz a0, 8f
    la t0, pad_base
    ld t0, 0(t0)
    li t4, VIRTIO_INPUT_CFG_ABS_INFO
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SELECT)(t0)
    ld t3, 0(sp)
    sb t3, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SUBSEL)(t0)
    lbu t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SIZE)(t0)
    li t5, VIRTIO_INPUT_ABS_SIZE
    bltu t4, t5, 8f             # nothing said: the range stays zero
    li t4, JAB_PAD_AXIS_ENTRY
    mul t4, t4, t3
    la t5, pad_absinfo
    add t5, t5, t4              # the entry
    li t6, 0
5:
    add t1, t0, t6
    lbu t2, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_DATA)(t1)
    add t1, t5, t6
    sb t2, 0(t1)
    addi t6, t6, 1
    li t1, VIRTIO_INPUT_ABS_SIZE
    bltu t6, t1, 5b
    # rest
    lw t1, JAB_PAD_AXIS_MIN(t5)
    lw t2, JAB_PAD_AXIS_MAX(t5)
    ld t3, 0(sp)
    li t4, JAB_ABS_GAS
    beq t3, t4, 6f
    li t4, JAB_ABS_BRAKE
    beq t3, t4, 6f
    add t1, t1, t2
    li t2, 2
    div t1, t1, t2
6:
    slli t4, t3, 2
    la t2, pad_raw
    add t2, t2, t4
    sw t1, 0(t2)
8:
    ld t3, 0(sp)
    addi t3, t3, 1
    sd t3, 0(sp)
    j 4b
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# pad_axis_present: a0 is an axis code; a0 becomes 1 when the pad has
# that axis, else 0.
pad_axis_present:
    srli t0, a0, 3
    la t1, pad_abs_bits
    add t1, t1, t0
    lbu t1, 0(t1)
    andi t0, a0, 7
    srl t1, t1, t0
    andi a0, t1, 1
    ret

# pad_drain: move every event the device has delivered into the state
# and the ring, keeping EV_KEY and EV_ABS events only, and hand the
# buffers back. Clobbers a0 to a3 and the t registers.
.global pad_drain
pad_drain:
    la t0, pad_queue
    ld t1, PADQ_LAST_USED(t0)
    li t6, 0
1:
    fence rw, rw
    lhu t2, (PADQ_USED + VIRTQ_USED_IDX)(t0)
    beq t2, t1, 6f
    # the used element, its descriptor id, that descriptor's event
    andi t2, t1, PADQ_SIZE - 1
    slli t2, t2, 3
    add t2, t2, t0
    lwu t3, (PADQ_USED + VIRTQ_USED_RING + VIRTQ_USED_ELEM_ID)(t2)
    slli t4, t3, 3
    la t5, pad_events
    add t4, t4, t5
    lhu t5, VIRTIO_INPUT_EVENT_TYPE(t4)
    li t2, EV_KEY
    beq t5, t2, 2f
    li t2, EV_ABS
    beq t5, t2, 2f
    j 3f
2:
    lhu a0, VIRTIO_INPUT_EVENT_CODE(t4)
    lw a1, VIRTIO_INPUT_EVENT_VALUE(t4)
    li t2, EV_KEY
    bne t5, t2, 21f
    # a key: its bit in the mask, when it is one of the gamepad's
    addi t2, a0, -JAB_BTN_GAMEPAD
    li a2, PAD_KEYS_BITS
    bgeu t2, a2, 22f
    li a2, 1
    sll a2, a2, t2
    la t2, pad_keys
    lwu a3, 0(t2)
    beqz a1, 211f
    or a3, a3, a2
    j 212f
211:
    not a2, a2
    and a3, a3, a2
212:
    sw a3, 0(t2)
    j 22f
21:
    # an axis: its raw value
    li a2, JAB_PAD_AXIS_COUNT
    bgeu a0, a2, 22f
    slli a2, a0, 2
    la a3, pad_raw
    add a3, a3, a2
    sw a1, 0(a3)
22:
    # into the ring unless it is full
    la t2, pad_head
    ld t2, 0(t2)
    la a2, pad_tail
    ld a2, 0(a2)
    sub a2, t2, a2
    li a3, PAD_RING
    bgeu a2, a3, 3f
    andi a2, t2, PAD_RING - 1
    slli a2, a2, 3
    la a3, pad_ring
    add a2, a2, a3
    sh t5, 0(a2)
    sh a0, 2(a2)
    sw a1, 4(a2)
    addi t2, t2, 1
    la a2, pad_head
    sd t2, 0(a2)
3:
    # the buffer back to the device
    lhu t2, (PADQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    andi t4, t2, PADQ_SIZE - 1
    slli t4, t4, 1
    add t4, t4, t0
    sh t3, (PADQ_AVAIL + VIRTQ_AVAIL_RING)(t4)
    fence w, w
    addi t2, t2, 1
    sh t2, (PADQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    addi t1, t1, 1
    li t2, 0xffff
    and t1, t1, t2
    sd t1, PADQ_LAST_USED(t0)
    li t6, 1
    j 1b
6:
    beqz t6, 7f
    fence rw, rw
    la t0, pad_base
    ld t0, 0(t0)
    sw zero, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
7:
    ret

# pad_pending: a0 becomes 1 when a pad event is waiting in the ring or
# with the device, else 0. Keeps the s registers.
.global pad_pending
pad_pending:
    la t0, pad_head
    ld t0, 0(t0)
    la t1, pad_tail
    ld t1, 0(t1)
    bne t0, t1, 1f
    la t0, pad_queue
    fence rw, rw
    lhu t1, (PADQ_USED + VIRTQ_USED_IDX)(t0)
    ld t2, PADQ_LAST_USED(t0)
    bne t1, t2, 1f
    li a0, 0
    ret
1:
    li a0, 1
    ret

# pad_take: a0 becomes the oldest event's type, a1 its code, and a2
# its value, or all 0 when the ring is empty.
pad_take:
    la t0, pad_head
    ld t0, 0(t0)
    la t1, pad_tail
    ld t2, 0(t1)
    beq t0, t2, 1f
    andi t3, t2, PAD_RING - 1
    slli t3, t3, 3
    la t4, pad_ring
    add t3, t3, t4
    lhu a0, 0(t3)
    lhu a1, 2(t3)
    lw a2, 4(t3)
    addi t2, t2, 1
    sd t2, 0(t1)
    ret
1:
    li a0, 0
    li a1, 0
    li a2, 0
    ret

# pad_normalise: a0 is an axis code; a0 becomes its value normalised
# to -JAB_PAD_FULL through JAB_PAD_FULL from its own range, or 0 for
# an axis the pad lacks. A centred axis: the flat band about the
# middle of the range reads 0, and either side of it rescales to full
# scale at the range's end, so leaving the band is continuous. ABS_GAS
# and ABS_BRAKE are one-sided: min plus flat reads 0 and max reads
# full. A hat, -1 to 1 with no flat, lands on the three values.
pad_normalise:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a0, 0(sp)
    call pad_axis_present
    beqz a0, 8f
    ld a0, 0(sp)
    li t0, JAB_PAD_AXIS_ENTRY
    mul t0, t0, a0
    la t1, pad_absinfo
    add t1, t1, t0
    lw t2, JAB_PAD_AXIS_MIN(t1)
    lw t3, JAB_PAD_AXIS_MAX(t1)
    lw t4, JAB_PAD_AXIS_FLAT(t1)
    slli t0, a0, 2
    la t5, pad_raw
    add t5, t5, t0
    lw t5, 0(t5)                # the raw value
    li t0, JAB_ABS_GAS
    beq a0, t0, 5f
    li t0, JAB_ABS_BRAKE
    beq a0, t0, 5f
    # centred
    add t6, t2, t3
    li t0, 2
    div t6, t6, t0              # the middle
    add t0, t6, t4              # the band's top
    bgt t5, t0, 3f
    sub t0, t6, t4              # the band's bottom
    blt t5, t0, 4f
    li a0, 0
    j 9f
3:
    sub t1, t3, t0              # from the band's top to max
    blez t1, 7f
    sub t5, t5, t0
    li t2, JAB_PAD_FULL
    mul t5, t5, t2
    div a0, t5, t1
    j 6f
4:
    sub t1, t0, t2              # from min to the band's bottom
    blez t1, 71f
    sub t5, t0, t5
    li t2, JAB_PAD_FULL
    mul t5, t5, t2
    div a0, t5, t1
    neg a0, a0
    j 6f
5:
    # one-sided
    add t0, t2, t4              # min plus flat
    ble t5, t0, 8f
    sub t1, t3, t0
    blez t1, 7f
    sub t5, t5, t0
    li t2, JAB_PAD_FULL
    mul t5, t5, t2
    div a0, t5, t1
6:
    li t0, JAB_PAD_FULL
    ble a0, t0, 61f
    mv a0, t0
61:
    neg t0, t0
    bge a0, t0, 9f
    mv a0, t0
    j 9f
7:
    li a0, JAB_PAD_FULL
    j 9f
71:
    li a0, -JAB_PAD_FULL
    j 9f
8:
    li a0, 0
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

.section .bss
.balign 16
pad_queue:
    .skip PADQ_BYTES
.balign 8
pad_events:
    .skip PADQ_SIZE * VIRTIO_INPUT_EVENT_SIZE
pad_ring:
    .skip PAD_RING * PAD_ENTRY_SIZE
pad_head:
    .skip 8
pad_tail:
    .skip 8
pad_base:
    .skip 8
pad_state:
    .skip 8
pad_keys:
    .skip 8
pad_abs_bits:
    .skip 8
.balign 4
pad_raw:
    .skip JAB_PAD_AXIS_COUNT * 4
pad_absinfo:
    .skip JAB_PAD_AXIS_COUNT * JAB_PAD_AXIS_ENTRY
