.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"
.include "jab.inc"

# The keyboard: QEMU's virtio-keyboard-device, a virtio-input device
# told from the tablet, the other one, by carrying the letter keys in
# its EV_KEY bits. Its event queue holds VIRTQ_SIZE eight-byte events
# the device fills; the kernel drains them into its own ring of
# KEYBOARD_RING key events, refilling the queue, when the program asks
# for a key or awaits one. Only EV_KEY events are kept: the code and
# the value, 0 released, 1 pressed, 2 held, as Linux defines them.
.set KEYBOARD_RING, 64
.set KEYBOARD_ENTRY_SIZE, 8

.section .text

# sys_keyboard_input (jab.keyboard.input): a0 becomes the next key
# event's code, or 0 when none is waiting; a1 its value. The keyboard
# comes up on the first call; with no keyboard on the machine there is
# never an event.
.global sys_keyboard_input
sys_keyboard_input:
    call keyboard_open
    bnez a0, 1f
    call keyboard_drain
    call keyboard_take
    sd a0, 80(sp)
    sd a1, 88(sp)
    j trap_return
1:
    sd zero, 80(sp)
    sd zero, 88(sp)
    j trap_return

# keyboard_open: find the keyboard and bring it up, its queue stocked
# and its line let through. Returns 0, or 1 with no keyboard on the
# machine, 2 when the device refuses the kernel. Open already: 0.
.global keyboard_open
keyboard_open:
    la t0, keyboard_state
    ld t0, 0(t0)
    beqz t0, 1f
    li a0, 0
    ret
1:
    addi sp, sp, -16
    sd ra, 8(sp)
    call keyboard_find
    beqz a0, 5f
    la t0, keyboard_base
    sd a0, 0(t0)
.ifdef DEBUG
    la a0, msg_keyboard_at
    call debug_puts
    la t0, keyboard_base
    ld a0, 0(t0)
    call debug_put_hex
    li a0, '\n'
    call debug_putc
    la t0, keyboard_base
    ld a0, 0(t0)
.pushsection .rodata
msg_keyboard_at:
    .asciz "jab: keyboard at "
.popsection
.endif
    call virtio_init
    bnez a0, 6f
    la t0, keyboard_base
    ld a0, 0(t0)
    li a1, 0
    la a2, keyboard_queue
    call virtio_queue_setup
    bnez a0, 6f
    # every descriptor an event buffer the device may write, all
    # offered at once
    la t0, keyboard_queue
    la t1, keyboard_events
    li t2, 0
2:
    slli t3, t2, 4
    add t3, t3, t0
    sd t1, (VQ_DESC + VIRTQ_DESC_ADDR)(t3)
    li t4, VIRTIO_INPUT_EVENT_SIZE
    sw t4, (VQ_DESC + VIRTQ_DESC_LEN)(t3)
    li t4, VIRTQ_DESC_F_WRITE
    sh t4, (VQ_DESC + VIRTQ_DESC_FLAGS)(t3)
    sh zero, (VQ_DESC + VIRTQ_DESC_NEXT)(t3)
    slli t3, t2, 1
    add t3, t3, t0
    sh t2, (VQ_AVAIL + VIRTQ_AVAIL_RING)(t3)
    addi t1, t1, VIRTIO_INPUT_EVENT_SIZE
    addi t2, t2, 1
    li t3, VIRTQ_SIZE
    bltu t2, t3, 2b
    fence w, w
    sh t2, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    fence rw, rw
    la t0, keyboard_base
    ld a0, 0(t0)
    call virtio_driver_ok
    la t0, keyboard_base
    ld a0, 0(t0)
    sw zero, VIRTIO_MMIO_QUEUE_NOTIFY(a0)
    call virtio_irq_enable
    la t0, keyboard_state
    li t1, 1
    sd t1, 0(t0)
    li a0, 0
    j 8f
5:
.ifdef DEBUG
    la a0, msg_no_keyboard
    call debug_puts
.pushsection .rodata
msg_no_keyboard:
    .asciz "jab: no keyboard\n"
.popsection
.endif
    li a0, 1
    j 8f
6:
    li a0, 2
8:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# keyboard_find: the base of the first virtio-input transport whose
# EV_KEY bits include JAB_KEY_A, or 0.
keyboard_find:
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
    # ask for the EV_KEY bitmap and look for the letter
    li t4, VIRTIO_INPUT_CFG_EV_BITS
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SELECT)(t0)
    li t4, EV_KEY
    sb t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SUBSEL)(t0)
    lbu t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_SIZE)(t0)
    li a0, JAB_KEY_A / 8
    bleu t4, a0, 2f
    lbu t4, (VIRTIO_MMIO_CONFIG + VIRTIO_INPUT_CFG_DATA + JAB_KEY_A / 8)(t0)
    srli t4, t4, JAB_KEY_A % 8
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

# keyboard_drain: move every event the device has delivered into the
# ring, keeping EV_KEY events only, and hand the buffers back.
.global keyboard_drain
keyboard_drain:
    la t0, keyboard_queue
    ld t1, VQ_LAST_USED(t0)
    li t6, 0
1:
    fence rw, rw
    lhu t2, (VQ_USED + VIRTQ_USED_IDX)(t0)
    beq t2, t1, 6f
    # the used element, its descriptor id, that descriptor's event
    andi t2, t1, VIRTQ_SIZE - 1
    slli t2, t2, 3
    add t2, t2, t0
    lwu t3, (VQ_USED + VIRTQ_USED_RING + VIRTQ_USED_ELEM_ID)(t2)
    slli t4, t3, 3
    la t5, keyboard_events
    add t4, t4, t5
    lhu t5, VIRTIO_INPUT_EVENT_TYPE(t4)
    li t2, EV_KEY
    bne t5, t2, 3f
    # a key event: into the ring unless it is full
    la t2, key_head
    ld t2, 0(t2)
    la t5, key_tail
    ld t5, 0(t5)
    sub t5, t2, t5
    li a0, KEYBOARD_RING
    bgeu t5, a0, 3f
    andi t5, t2, KEYBOARD_RING - 1
    slli t5, t5, 3
    la a0, key_ring
    add t5, t5, a0
    lhu a0, VIRTIO_INPUT_EVENT_CODE(t4)
    sh a0, 0(t5)
    lwu a0, VIRTIO_INPUT_EVENT_VALUE(t4)
    sh a0, 2(t5)
    addi t2, t2, 1
    la t5, key_head
    sd t2, 0(t5)
3:
    # the buffer back to the device
    lhu t2, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    andi t4, t2, VIRTQ_SIZE - 1
    slli t4, t4, 1
    add t4, t4, t0
    sh t3, (VQ_AVAIL + VIRTQ_AVAIL_RING)(t4)
    fence w, w
    addi t2, t2, 1
    sh t2, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    addi t1, t1, 1
    li t2, 0xffff
    and t1, t1, t2
    sd t1, VQ_LAST_USED(t0)
    li t6, 1
    j 1b
6:
    beqz t6, 7f
    fence rw, rw
    la t0, keyboard_base
    ld t0, 0(t0)
    sw zero, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
7:
    ret

# keyboard_pending: a0 becomes 1 when a key event is waiting in the
# ring or with the device, else 0.
.global keyboard_pending
keyboard_pending:
    la t0, key_head
    ld t0, 0(t0)
    la t1, key_tail
    ld t1, 0(t1)
    bne t0, t1, 1f
    la t0, keyboard_queue
    fence rw, rw
    lhu t1, (VQ_USED + VIRTQ_USED_IDX)(t0)
    ld t2, VQ_LAST_USED(t0)
    bne t1, t2, 1f
    li a0, 0
    ret
1:
    li a0, 1
    ret

# keyboard_take: a0 becomes the oldest key event's code and a1 its
# value, or both 0 when the ring is empty.
keyboard_take:
    la t0, key_head
    ld t0, 0(t0)
    la t1, key_tail
    ld t2, 0(t1)
    beq t0, t2, 1f
    andi t3, t2, KEYBOARD_RING - 1
    slli t3, t3, 3
    la t4, key_ring
    add t3, t3, t4
    lhu a0, 0(t3)
    lhu a1, 2(t3)
    addi t2, t2, 1
    sd t2, 0(t1)
    ret
1:
    li a0, 0
    li a1, 0
    ret

.section .bss
.balign 16
keyboard_queue:
    .skip VQ_BYTES
.balign 8
keyboard_events:
    .skip VIRTQ_SIZE * VIRTIO_INPUT_EVENT_SIZE
key_ring:
    .skip KEYBOARD_RING * KEYBOARD_ENTRY_SIZE
key_head:
    .skip 8
key_tail:
    .skip 8
keyboard_base:
    .skip 8
keyboard_state:
    .skip 8
