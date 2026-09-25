.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"

# virtio over mmio, the transport of every Jab device: finding a device
# by id among QEMU virt's transports, bringing it up, giving it a split
# virtqueue, letting its interrupt line through the PLIC, running one
# request through a queue at a time, and waiting for the device with
# the hart halted rather than spinning. Every routine takes the
# transport's base in a0 and clobbers t registers, plus a0 for what it
# returns, unless it says otherwise.
.section .text

# virtio_find: a0 is a device id. Returns the base of the first modern
# transport carrying it, or 0.
.global virtio_find
virtio_find:
    li t0, QEMU_VIRT_VIRTIO0
    li t1, QEMU_VIRT_VIRTIO_COUNT
    li t2, VIRTIO_MAGIC
    li t3, VIRTIO_VERSION_MODERN
    li t5, QEMU_VIRT_VIRTIO_STRIDE
1:
    lwu t4, VIRTIO_MMIO_MAGIC_VALUE(t0)
    bne t4, t2, 2f
    lwu t4, VIRTIO_MMIO_VERSION(t0)
    bne t4, t3, 2f
    lwu t4, VIRTIO_MMIO_DEVICE_ID(t0)
    beq t4, a0, 3f
2:
    add t0, t0, t5
    addi t1, t1, -1
    bnez t1, 1b
    li a0, 0
    ret
3:
    mv a0, t0
    ret

# virtio_init: reset the device at a0, acknowledge it, claim it, offer
# VIRTIO_F_VERSION_1 and nothing else, and confirm the features. Returns
# 0, or 1 when the device refuses them.
.global virtio_init
virtio_init:
    sw zero, VIRTIO_MMIO_STATUS(a0)
    li t0, VIRTIO_STATUS_ACKNOWLEDGE
    sw t0, VIRTIO_MMIO_STATUS(a0)
    li t0, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER
    sw t0, VIRTIO_MMIO_STATUS(a0)
    sw zero, VIRTIO_MMIO_DRIVER_FEATURES_SEL(a0)
    sw zero, VIRTIO_MMIO_DRIVER_FEATURES(a0)
    li t0, VIRTIO_F_VERSION_1_WORD
    sw t0, VIRTIO_MMIO_DRIVER_FEATURES_SEL(a0)
    li t0, VIRTIO_F_VERSION_1_BIT
    sw t0, VIRTIO_MMIO_DRIVER_FEATURES(a0)
    li t0, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK
    sw t0, VIRTIO_MMIO_STATUS(a0)
    lwu t1, VIRTIO_MMIO_STATUS(a0)
    andi t1, t1, VIRTIO_STATUS_FEATURES_OK
    beqz t1, 1f
    li a0, 0
    ret
1:
    li a0, 1
    ret

# virtio_queue_setup: give queue a1 of the device at a0 the rings of the
# virtqueue record at a2, VIRTQ_SIZE entries, interrupts wanted.
# Returns 0, or 1 when the device offers fewer entries than that.
.global virtio_queue_setup
virtio_queue_setup:
    sw a1, VIRTIO_MMIO_QUEUE_SEL(a0)
    lwu t0, VIRTIO_MMIO_QUEUE_NUM_MAX(a0)
    li t1, VIRTQ_SIZE
    bltu t0, t1, 1f
    sw t1, VIRTIO_MMIO_QUEUE_NUM(a0)
    addi t0, a2, VQ_DESC
    srli t1, t0, 32
    sw t0, VIRTIO_MMIO_QUEUE_DESC_LOW(a0)
    sw t1, VIRTIO_MMIO_QUEUE_DESC_HIGH(a0)
    addi t0, a2, VQ_AVAIL
    srli t1, t0, 32
    sw t0, VIRTIO_MMIO_QUEUE_DRIVER_LOW(a0)
    sw t1, VIRTIO_MMIO_QUEUE_DRIVER_HIGH(a0)
    addi t0, a2, VQ_USED
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

# virtio_driver_ok: the device at a0 may now be driven.
.global virtio_driver_ok
virtio_driver_ok:
    li t0, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK | VIRTIO_STATUS_DRIVER_OK
    sw t0, VIRTIO_MMIO_STATUS(a0)
    ret

# virtio_irq_enable: let the line of the transport at a0 through the
# PLIC to hart 0's supervisor context: priority 1, enabled, threshold 0.
.global virtio_irq_enable
virtio_irq_enable:
    li t0, QEMU_VIRT_VIRTIO0
    sub t1, a0, t0
    li t0, QEMU_VIRT_VIRTIO_STRIDE
    divu t1, t1, t0
    addi t1, t1, QEMU_VIRT_VIRTIO_IRQ0
    li t0, QEMU_VIRT_PLIC
    slli t2, t1, 2
    add t2, t2, t0
    li t3, 1
    sw t3, QEMU_VIRT_PLIC_PRIORITY(t2)
    li t2, QEMU_VIRT_PLIC + QEMU_VIRT_PLIC_ENABLE + QEMU_VIRT_PLIC_ENABLE_STRIDE * QEMU_VIRT_HART0_S_CONTEXT
    lwu t3, 0(t2)
    li t4, 1
    sll t4, t4, t1
    or t3, t3, t4
    sw t3, 0(t2)
    li t2, QEMU_VIRT_PLIC + QEMU_VIRT_PLIC_CONTEXT + QEMU_VIRT_PLIC_CONTEXT_STRIDE * QEMU_VIRT_HART0_S_CONTEXT
    sw zero, QEMU_VIRT_PLIC_THRESHOLD(t2)
    ret

# plic_service: take every line the PLIC holds for hart 0's supervisor
# context, acknowledge the transport that raised it, and complete it,
# so the line drops. Only virtio lines are ever enabled.
.global plic_service
plic_service:
    li t0, QEMU_VIRT_PLIC + QEMU_VIRT_PLIC_CONTEXT + QEMU_VIRT_PLIC_CONTEXT_STRIDE * QEMU_VIRT_HART0_S_CONTEXT
1:
    lwu t1, QEMU_VIRT_PLIC_CLAIM(t0)
    beqz t1, 2f
    addi t2, t1, -QEMU_VIRT_VIRTIO_IRQ0
    li t3, QEMU_VIRT_VIRTIO_STRIDE
    mul t2, t2, t3
    li t3, QEMU_VIRT_VIRTIO0
    add t2, t2, t3
    lwu t3, VIRTIO_MMIO_INTERRUPT_STATUS(t2)
    sw t3, VIRTIO_MMIO_INTERRUPT_ACK(t2)
    sw t1, QEMU_VIRT_PLIC_CLAIM(t0)
    j 1b
2:
    ret

# virtio_wait_used: halt until the used ring of the virtqueue record at
# a0 has moved past what the kernel last saw, waking on the transport's
# line; the line is serviced before returning. a0 is kept.
.global virtio_wait_used
virtio_wait_used:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a0, 0(sp)
    li t4, SIE_SEIE
    csrs sie, t4
1:
    ld a0, 0(sp)
    fence rw, rw
    lhu t0, (VQ_USED + VIRTQ_USED_IDX)(a0)
    ld t1, VQ_LAST_USED(a0)
    bne t0, t1, 2f
    wfi
    call plic_service
    j 1b
2:
    call plic_service
    li t4, SIE_SEIE
    csrc sie, t4
    ld a0, 0(sp)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# virtio_request: run one request through queue a1 of the device at a0
# with the virtqueue record at a2: the device reads a3 bytes at a4 and
# writes its response into a5, a6 bytes long. Descriptors 0 and 1 carry
# every request; returns once the device has used them, the hart
# halted meanwhile.
.global virtio_request
virtio_request:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a4, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_ADDR)(a2)
    sw a3, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_LEN)(a2)
    li t0, VIRTQ_DESC_F_NEXT
    sh t0, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_FLAGS)(a2)
    li t0, 1
    sh t0, (VQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_NEXT)(a2)
    sd a5, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_ADDR)(a2)
    sw a6, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_LEN)(a2)
    li t0, VIRTQ_DESC_F_WRITE
    sh t0, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_FLAGS)(a2)
    sh zero, (VQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_NEXT)(a2)
    # offer descriptor 0 in the next slot of the available ring
    lhu t0, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(a2)
    andi t1, t0, VIRTQ_SIZE - 1
    slli t1, t1, 1
    add t1, t1, a2
    sh zero, (VQ_AVAIL + VIRTQ_AVAIL_RING)(t1)
    fence w, w
    addi t0, t0, 1
    sh t0, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(a2)
    fence rw, rw
    sw a1, VIRTIO_MMIO_QUEUE_NOTIFY(a0)
    mv a0, a2
    call virtio_wait_used
    ld t2, VQ_LAST_USED(a0)
    addi t2, t2, 1
    li t0, 0xffff
    and t2, t2, t0
    sd t2, VQ_LAST_USED(a0)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret
