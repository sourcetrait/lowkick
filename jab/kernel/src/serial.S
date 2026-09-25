.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"
.include "jab.inc"

# The ports: QEMU's virtio-serial-device over the same mmio transport as
# every other Jab device, one port per channel a build symbol asks for.
# DEBUG gives the kernel its debug channel, port SERIAL_DEBUG_PORT, where
# its own lines go instead of the console UART; a fault line stays on
# the UART in every build, since it has to work when a port has not come
# up. DATA gives the program its data channel, port SERIAL_DATA_PORT,
# bytes both ways between it and the host through jab.data.write,
# jab.data.read, and the JAB_AWAIT_DATA bit. With no symbol set this
# file assembles to nothing, so a release kernel carries no port code
# and no port text.
#
# The device is driven with its multiport feature (virtio.inc): the
# kernel stocks the control receive queue, tells the device it is ready,
# the device names each port it carries, the kernel answers for the
# ports it wants and opens them, and a port then carries bytes: one
# descriptor per write, the hart halted until the device has taken it,
# as every other request here. A port whose host side is a file or a
# pipe is open from the start; a write to a pipe nobody reads waits
# until somebody does.
.ifdef DEBUG
.set SERIAL_WANTED, 1
.set SERIAL_DEBUG_PORT, 1
.set SERIAL_DEBUG_TX_QUEUE, (2 * SERIAL_DEBUG_PORT + 3)
# A debug line gathers here and goes out whole at its newline, so a line
# lands in the log in one piece.
.set DEBUG_LINE_BYTES, 256
.endif
.ifdef DATA
.set SERIAL_WANTED, 1
.set SERIAL_DATA_PORT, 2
.set SERIAL_DATA_RX_QUEUE, (2 * SERIAL_DATA_PORT + 2)
.set SERIAL_DATA_TX_QUEUE, (2 * SERIAL_DATA_PORT + 3)
# What the host sends lands in these buffers, offered to the device in
# advance, and moves into a ring the program reads from; the ring holds
# as much as the buffers do, and what arrives beyond it waits with the
# device.
.set DATA_BUFFER_BYTES, 256
.set DATA_RING_BYTES, (VIRTQ_SIZE * DATA_BUFFER_BYTES)
.endif

.ifdef SERIAL_WANTED
# A control message the device sends fits in one of these, a port's name
# included.
.set SERIAL_CONTROL_BYTES, 64

.section .text

# serial_open: find the virtio-serial device and bring it up: the
# control queues and the wanted ports' queues, the control receive
# queue stocked, the device told the kernel is ready, each wanted port
# answered for as the device names it, then opened. Returns 0; 1 with
# no virtio-serial device on the machine; 2 when the device refuses the
# kernel. Asked again it answers as before at once.
.global serial_open
serial_open:
    la t0, serial_state
    ld t1, 0(t0)
    beqz t1, 1f
    addi a0, t1, -1
    ret
1:
    addi sp, sp, -16
    sd ra, 8(sp)
    li a0, VIRTIO_ID_CONSOLE
    call virtio_find
    beqz a0, 5f
    la t0, serial_base
    sd a0, 0(t0)
    li a1, VIRTIO_CONSOLE_F_MULTIPORT_BIT
    call virtio_init_with
    bnez a0, 6f
    la t0, serial_base
    ld a0, 0(t0)
    li a1, VIRTIO_CONSOLE_CONTROL_RX_QUEUE
    la a2, serial_control_rx_queue
    call virtio_queue_setup
    bnez a0, 6f
    la t0, serial_base
    ld a0, 0(t0)
    li a1, VIRTIO_CONSOLE_CONTROL_TX_QUEUE
    la a2, serial_control_tx_queue
    call virtio_queue_setup
    bnez a0, 6f
.ifdef DEBUG
    la t0, serial_base
    ld a0, 0(t0)
    li a1, SERIAL_DEBUG_TX_QUEUE
    la a2, serial_debug_tx_queue
    call virtio_queue_setup
    bnez a0, 6f
.endif
.ifdef DATA
    la t0, serial_base
    ld a0, 0(t0)
    li a1, SERIAL_DATA_RX_QUEUE
    la a2, serial_data_rx_queue
    call virtio_queue_setup
    bnez a0, 6f
    la t0, serial_base
    ld a0, 0(t0)
    li a1, SERIAL_DATA_TX_QUEUE
    la a2, serial_data_tx_queue
    call virtio_queue_setup
    bnez a0, 6f
    la a0, serial_data_rx_queue
    la a1, serial_data_buffers
    li a2, DATA_BUFFER_BYTES
    call serial_stock
.endif
    # every descriptor of the control receive queue a buffer the device
    # may write, all offered at once
    la a0, serial_control_rx_queue
    la a1, serial_control_buffers
    li a2, SERIAL_CONTROL_BYTES
    call serial_stock
    la t0, serial_base
    ld a0, 0(t0)
    call virtio_driver_ok
    la t0, serial_base
    ld a0, 0(t0)
    call virtio_irq_enable
    la t0, serial_base
    ld t0, 0(t0)
    li t1, VIRTIO_CONSOLE_CONTROL_RX_QUEUE
    sw t1, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
.ifdef DATA
    la t0, serial_base
    ld t0, 0(t0)
    li t1, SERIAL_DATA_RX_QUEUE
    sw t1, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
.endif
    # the kernel is ready; the device then names its ports, and each
    # wanted one is answered for as it is named
    li a0, VIRTIO_CONSOLE_DEVICE_READY
    li a1, 0
    li a2, 1
    call serial_control_send
    call serial_control_drain
.ifdef DEBUG
    li a0, VIRTIO_CONSOLE_PORT_OPEN
    li a1, SERIAL_DEBUG_PORT
    li a2, 1
    call serial_control_send
    call serial_control_drain
.endif
.ifdef DATA
    li a0, VIRTIO_CONSOLE_PORT_OPEN
    li a1, SERIAL_DATA_PORT
    li a2, 1
    call serial_control_send
    call serial_control_drain
.endif
    la t0, serial_state
    li t1, 1
    sd t1, 0(t0)
    li a0, 0
    j 8f
5:
    la t0, serial_state
    li t1, 2
    sd t1, 0(t0)
    li a0, 1
    j 8f
6:
    la t0, serial_state
    li t1, 3
    sd t1, 0(t0)
    li a0, 2
8:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# serial_stock: make every descriptor of the receive queue whose record
# is at a0 a buffer the device may write, the buffers a2 bytes each
# from a1, all offered at once; the caller notifies once the device is
# driven.
serial_stock:
    li t2, 0
1:
    slli t3, t2, 4
    add t3, t3, a0
    sd a1, (VQ_DESC + VIRTQ_DESC_ADDR)(t3)
    sw a2, (VQ_DESC + VIRTQ_DESC_LEN)(t3)
    li t4, VIRTQ_DESC_F_WRITE
    sh t4, (VQ_DESC + VIRTQ_DESC_FLAGS)(t3)
    sh zero, (VQ_DESC + VIRTQ_DESC_NEXT)(t3)
    slli t3, t2, 1
    add t3, t3, a0
    sh t2, (VQ_AVAIL + VIRTQ_AVAIL_RING)(t3)
    add a1, a1, a2
    addi t2, t2, 1
    li t3, VIRTQ_SIZE
    bltu t2, t3, 1b
    fence w, w
    sh t2, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(a0)
    fence rw, rw
    ret

# serial_control_send: send the device a control message: event a0 for
# port a1 with value a2. Returns once the device has taken it.
serial_control_send:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, serial_control_message
    sw a1, VIRTIO_CONSOLE_CONTROL_ID(t0)
    sh a0, VIRTIO_CONSOLE_CONTROL_EVENT(t0)
    sh a2, VIRTIO_CONSOLE_CONTROL_VALUE(t0)
    la a0, serial_control_tx_queue
    li a1, VIRTIO_CONSOLE_CONTROL_TX_QUEUE
    mv a2, t0
    li a3, VIRTIO_CONSOLE_CONTROL_SIZE
    call serial_send
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# serial_control_drain: take every control message the device has
# delivered, hand its buffer back, and answer for a wanted port the
# device names as added, which makes the device say more, taken in the
# same pass. What else the device says, a port's name or that its host
# side is open, changes nothing here, since the ports are fixed by
# number.
serial_control_drain:
    addi sp, sp, -32
    sd ra, 24(sp)
1:
    la t0, serial_control_rx_queue
    ld t1, VQ_LAST_USED(t0)
    fence rw, rw
    lhu t2, (VQ_USED + VIRTQ_USED_IDX)(t0)
    beq t2, t1, 9f
    # the used element, its descriptor id, that descriptor's buffer
    andi t2, t1, VIRTQ_SIZE - 1
    slli t2, t2, 3
    add t2, t2, t0
    lwu t3, (VQ_USED + VIRTQ_USED_RING + VIRTQ_USED_ELEM_ID)(t2)
    li t4, SERIAL_CONTROL_BYTES
    mul t4, t4, t3
    la t5, serial_control_buffers
    add t4, t4, t5
    lwu t5, VIRTIO_CONSOLE_CONTROL_ID(t4)
    lhu t6, VIRTIO_CONSOLE_CONTROL_EVENT(t4)
    sd t5, 0(sp)                # the port the message is about
    sd t6, 8(sp)                # the event
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
    fence rw, rw
    la t0, serial_base
    ld t0, 0(t0)
    li t1, VIRTIO_CONSOLE_CONTROL_RX_QUEUE
    sw t1, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
    # a port added: answer for it when it is one the kernel wants
    ld t6, 8(sp)
    li t0, VIRTIO_CONSOLE_PORT_ADD
    bne t6, t0, 1b
    ld t5, 0(sp)
.ifdef DEBUG
    li t0, SERIAL_DEBUG_PORT
    bne t5, t0, 2f
    li a0, VIRTIO_CONSOLE_PORT_READY
    mv a1, t5
    li a2, 1
    call serial_control_send
    j 1b
2:
.endif
.ifdef DATA
    li t0, SERIAL_DATA_PORT
    bne t5, t0, 3f
    li a0, VIRTIO_CONSOLE_PORT_READY
    mv a1, t5
    li a2, 1
    call serial_control_send
    j 1b
3:
.endif
    j 1b
9:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

.ifdef DATA
# The data channel: the program's bytes to the host go straight from its
# buffer through the port's transmit queue; the host's bytes to the
# program arrive in the offered buffers and move into a ring, which
# jab.data.read empties and jab.await watches.

# sys_data_write (jab.data.write): a0 is the buffer, a1 how many bytes.
# a0 becomes 0 once the device has taken them, or 1 when no data port
# came up.
.global sys_data_write
sys_data_write:
    la t0, serial_state
    ld t0, 0(t0)
    li t1, 1
    bne t0, t1, 8f
    ld a0, 80(sp)
    ld a1, 88(sp)
    call buffer_bounds
    ld a3, 88(sp)
    beqz a3, 7f
    ld a2, 80(sp)
    la a0, serial_data_tx_queue
    li a1, SERIAL_DATA_TX_QUEUE
    call serial_send
7:
    sd zero, 80(sp)
    j trap_return
8:
    li a0, 1
    sd a0, 80(sp)
    j trap_return

# sys_data_read (jab.data.read): a0 is the buffer, a1 how many bytes it
# holds. a0 becomes the bytes written, the oldest first, and a1 how many
# still wait after them, in the ring and with the device. Never waits.
.global sys_data_read
sys_data_read:
    ld a0, 80(sp)
    ld a1, 88(sp)
    call buffer_bounds
    call data_drain
    # copy out of the ring, at most the capacity
    la t0, data_head
    ld t0, 0(t0)
    la t1, data_tail
    ld t1, 0(t1)
    sub t2, t0, t1              # bytes in the ring
    ld t3, 88(sp)
    bleu t2, t3, 1f
    mv t2, t3
1:
    ld a0, 80(sp)               # the program's buffer
    sd t2, 80(sp)               # the bytes written
    beqz t2, 3f
    la t4, data_ring
    li t5, DATA_RING_BYTES - 1
2:
    and t6, t1, t5
    add t6, t6, t4
    lbu a1, 0(t6)
    sb a1, 0(a0)
    addi a0, a0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    bnez t2, 2b
    la t0, data_tail
    sd t1, 0(t0)
3:
    call data_drain
    call data_waiting
    sd a0, 88(sp)
    j trap_return

# data_drain: move every buffer the device has filled into the ring,
# whole buffers only and only while the ring has room for one, and hand
# each back to the device.
data_drain:
    la t0, serial_data_rx_queue
    ld t1, VQ_LAST_USED(t0)
    li t6, 0
1:
    fence rw, rw
    lhu t2, (VQ_USED + VIRTQ_USED_IDX)(t0)
    beq t2, t1, 6f
    # the used element: its descriptor id and how many bytes it holds
    andi t2, t1, VIRTQ_SIZE - 1
    slli t2, t2, 3
    add t2, t2, t0
    lwu t3, (VQ_USED + VIRTQ_USED_RING + VIRTQ_USED_ELEM_ID)(t2)
    lwu t4, (VQ_USED + VIRTQ_USED_RING + VIRTQ_USED_ELEM_LEN)(t2)
    # room for the whole of it, or leave it with the device
    la t2, data_head
    ld t2, 0(t2)
    la t5, data_tail
    ld t5, 0(t5)
    sub t5, t2, t5
    li a0, DATA_RING_BYTES
    sub t5, a0, t5              # room
    bltu t5, t4, 6f
    li t5, DATA_BUFFER_BYTES
    mul t5, t5, t3
    la a0, serial_data_buffers
    add t5, t5, a0              # the buffer
    la a0, data_ring
    li a1, DATA_RING_BYTES - 1
2:
    beqz t4, 3f
    lbu a2, 0(t5)
    and a3, t2, a1
    add a3, a3, a0
    sb a2, 0(a3)
    addi t5, t5, 1
    addi t2, t2, 1
    addi t4, t4, -1
    j 2b
3:
    la a0, data_head
    sd t2, 0(a0)
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
    la t0, serial_base
    ld t0, 0(t0)
    li t1, SERIAL_DATA_RX_QUEUE
    sw t1, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
7:
    ret

# data_waiting: a0 becomes how many bytes wait for the program: in the
# ring, and in buffers the device has filled that the ring had no room
# for.
data_waiting:
    la t0, data_head
    ld a0, 0(t0)
    la t0, data_tail
    ld t0, 0(t0)
    sub a0, a0, t0
    la t0, serial_data_rx_queue
    ld t1, VQ_LAST_USED(t0)
    fence rw, rw
    lhu t2, (VQ_USED + VIRTQ_USED_IDX)(t0)
1:
    beq t2, t1, 2f
    andi t3, t1, VIRTQ_SIZE - 1
    slli t3, t3, 3
    add t3, t3, t0
    lwu t4, (VQ_USED + VIRTQ_USED_RING + VIRTQ_USED_ELEM_LEN)(t3)
    add a0, a0, t4
    addi t1, t1, 1
    li t3, 0xffff
    and t1, t1, t3
    j 1b
2:
    ret

# data_pending: a0 becomes 1 when bytes wait for the program, else 0;
# what jab.await tests for its JAB_AWAIT_DATA bit.
.global data_pending
data_pending:
    la t0, serial_state
    ld t0, 0(t0)
    li t1, 1
    bne t0, t1, 1f
    la t0, data_head
    ld t0, 0(t0)
    la t1, data_tail
    ld t1, 0(t1)
    bne t0, t1, 2f
    la t0, serial_data_rx_queue
    fence rw, rw
    lhu t1, (VQ_USED + VIRTQ_USED_IDX)(t0)
    ld t2, VQ_LAST_USED(t0)
    bne t1, t2, 2f
1:
    li a0, 0
    ret
2:
    li a0, 1
    ret
.endif

# serial_send: give the device a3 bytes at a2 through queue a1, whose
# record is at a0: one descriptor the device reads, offered and
# notified, the hart halted until the device has taken it.
.global serial_send
serial_send:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a2, (VQ_DESC + VIRTQ_DESC_ADDR)(a0)
    sw a3, (VQ_DESC + VIRTQ_DESC_LEN)(a0)
    sh zero, (VQ_DESC + VIRTQ_DESC_FLAGS)(a0)
    sh zero, (VQ_DESC + VIRTQ_DESC_NEXT)(a0)
    lhu t0, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(a0)
    andi t1, t0, VIRTQ_SIZE - 1
    slli t1, t1, 1
    add t1, t1, a0
    sh zero, (VQ_AVAIL + VIRTQ_AVAIL_RING)(t1)
    fence w, w
    addi t0, t0, 1
    sh t0, (VQ_AVAIL + VIRTQ_AVAIL_IDX)(a0)
    fence rw, rw
    la t0, serial_base
    ld t0, 0(t0)
    sw a1, VIRTIO_MMIO_QUEUE_NOTIFY(t0)
    call virtio_wait_used
    ld t2, VQ_LAST_USED(a0)
    addi t2, t2, 1
    li t0, 0xffff
    and t2, t2, t0
    sd t2, VQ_LAST_USED(a0)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

.ifdef DEBUG
# The debug channel's output, the shape of the UART's: a byte, a string,
# a value in hex, a value in decimal. Bytes gather into a line and the
# line goes out whole at its newline, or when it is full.

# debug_putc: a0 is the byte.
.global debug_putc
debug_putc:
    la t0, debug_length
    ld t1, 0(t0)
    la t2, debug_line
    add t2, t2, t1
    sb a0, 0(t2)
    addi t1, t1, 1
    sd t1, 0(t0)
    li t2, '\n'
    beq a0, t2, debug_flush
    li t2, DEBUG_LINE_BYTES
    beq t1, t2, debug_flush
    ret

# debug_flush: send the line gathered so far to the debug port, or to
# the UART when the machine carries no virtio-serial device, so a debug
# kernel on a bare line still reports.
.global debug_flush
debug_flush:
    la t0, debug_length
    ld a3, 0(t0)
    beqz a3, 9f
    sd zero, 0(t0)
    la t0, serial_state
    ld t0, 0(t0)
    li t1, 1
    bne t0, t1, 5f
    addi sp, sp, -16
    sd ra, 8(sp)
    la a0, serial_debug_tx_queue
    li a1, SERIAL_DEBUG_TX_QUEUE
    la a2, debug_line
    call serial_send
    ld ra, 8(sp)
    addi sp, sp, 16
    ret
5:
    addi sp, sp, -32
    sd ra, 24(sp)
    la t2, debug_line
    sd t2, 0(sp)
    sd a3, 8(sp)
6:
    ld t2, 0(sp)
    lbu a0, 0(t2)
    call uart_putc
    ld t2, 0(sp)
    addi t2, t2, 1
    sd t2, 0(sp)
    ld t3, 8(sp)
    addi t3, t3, -1
    sd t3, 8(sp)
    bnez t3, 6b
    ld ra, 24(sp)
    addi sp, sp, 32
9:
    ret

# debug_puts: a0 is a NUL-terminated string.
.global debug_puts
debug_puts:
    addi sp, sp, -16
    sd ra, 8(sp)
    sd a0, 0(sp)
1:
    ld t0, 0(sp)
    lbu a0, 0(t0)
    beqz a0, 2f
    addi t0, t0, 1
    sd t0, 0(sp)
    call debug_putc
    j 1b
2:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# debug_put_hex: a0 is a value, written as 0x and sixteen hex digits.
.global debug_put_hex
debug_put_hex:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)                # the value
    li t0, 60
    sd t0, 8(sp)                # the shift of the digit being written
    li a0, '0'
    call debug_putc
    li a0, 'x'
    call debug_putc
1:
    ld t0, 0(sp)
    ld t1, 8(sp)
    srl t0, t0, t1
    andi t0, t0, 0xf
    li t1, 10
    blt t0, t1, 2f
    addi t0, t0, 'a' - 10
    j 3f
2:
    addi t0, t0, '0'
3:
    mv a0, t0
    call debug_putc
    ld t1, 8(sp)
    addi t1, t1, -4
    sd t1, 8(sp)
    bgez t1, 1b
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# debug_put_dec: a0 is an unsigned value, written in decimal.
.global debug_put_dec
debug_put_dec:
    addi sp, sp, -48
    sd ra, 40(sp)
    addi t2, sp, 31             # the digits, built backwards from here
    sb zero, 0(t2)
    li t3, 10
1:
    remu t4, a0, t3
    divu a0, a0, t3
    addi t4, t4, '0'
    addi t2, t2, -1
    sb t4, 0(t2)
    bnez a0, 1b
    sd t2, 32(sp)
2:
    ld t2, 32(sp)
    lbu a0, 0(t2)
    beqz a0, 3f
    addi t2, t2, 1
    sd t2, 32(sp)
    call debug_putc
    j 2b
3:
    ld ra, 40(sp)
    addi sp, sp, 48
    ret
.endif

.section .bss
.balign 16
serial_control_rx_queue:
    .skip VQ_BYTES
.balign 16
serial_control_tx_queue:
    .skip VQ_BYTES
.ifdef DEBUG
.balign 16
serial_debug_tx_queue:
    .skip VQ_BYTES
.balign 8
debug_line:
    .skip DEBUG_LINE_BYTES
debug_length:
    .skip 8
.endif
.ifdef DATA
.balign 16
serial_data_rx_queue:
    .skip VQ_BYTES
.balign 16
serial_data_tx_queue:
    .skip VQ_BYTES
.balign 8
serial_data_buffers:
    .skip VIRTQ_SIZE * DATA_BUFFER_BYTES
data_ring:
    .skip DATA_RING_BYTES
data_head:
    .skip 8
data_tail:
    .skip 8
.endif
.balign 8
serial_control_buffers:
    .skip VIRTQ_SIZE * SERIAL_CONTROL_BYTES
serial_control_message:
    .skip VIRTIO_CONSOLE_CONTROL_SIZE
serial_base:
    .skip 8
serial_state:
    .skip 8
.endif
