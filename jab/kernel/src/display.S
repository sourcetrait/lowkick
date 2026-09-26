.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"
.include "jab.inc"

# The display: QEMU's virtio-gpu in 2D over mmio. One resource, the
# framebuffer at JAB_DISPLAY_BASE, is the program's to draw into; the
# kernel attaches it as the resource's backing, sets it as scanout 0,
# and on a flip transfers the whole of it, or the rectangles the
# program names, to the host and flushes them. The screen console draws
# text into the same framebuffer with the font in font.S and transfers
# only the rows it touched. Commands go through the control queue in
# batches, a chain of two descriptors each, one notify and one wait for
# the whole batch with the hart halted until the device has answered
# every one, since each wait costs a halt and a wake of every hart and
# a rectangle list is dozens of commands; a single command is a batch of
# one. The queue is the wide one of virtio.inc, so a batch holds up to
# GPUQ_CHAINS commands. Each response's type says whether the device
# took the command. A rectangle list is transferred rectangle by
# rectangle, only the changed pixels crossing, and flushed once as the
# one rectangle holding them all, so the host's window draws one
# upload a tick whatever the list: a flush costs the host's window a
# fixed price and a wait each, and a window drawn on a timer draws
# late by as long as the flushes take.
.set DISPLAY_RESOURCE, 1
.set GPU_CMD_BYTES, 64
.set GPU_RESP_BYTES, 24
# a transfer is one command, and the last batch carries the flush
.set GPU_TRANSFERS_PER_BATCH, (GPUQ_CHAINS - 1)

# The console: cells of FONT_WIDTH by FONT_HEIGHT, each glyph a 16-bit
# row per pixel row with the glyph in the high FONT_WIDTH bits, white
# on black. A newline ends the line; the bottom scrolls.
.set FONT_WIDTH, 12
.set FONT_HEIGHT, 24
.set FONT_ROW_BYTES, 2
.set FONT_GLYPH_BYTES, (FONT_HEIGHT * FONT_ROW_BYTES)
.set FONT_FIRST, 32
.set FONT_LAST, 126
.set CONSOLE_COLUMNS, (JAB_DISPLAY_WIDTH / FONT_WIDTH)
.set CONSOLE_ROWS, (JAB_DISPLAY_HEIGHT / FONT_HEIGHT)
.set CONSOLE_LINE_BYTES, (FONT_HEIGHT * JAB_DISPLAY_PITCH)
.set CONSOLE_FG, 0x00ffffff
.set CONSOLE_BG, 0x00000000

.section .text

# sys_display_open (jab.display.open): a0 becomes display_open's code.
.global sys_display_open
sys_display_open:
    call display_open
    sd a0, 80(sp)
    j trap_return

# sys_display_ready (jab.display.ready): a0 becomes 1 when a flip would
# go through now, else 0.
.global sys_display_ready
sys_display_ready:
    call frame_ready
    sd a0, 80(sp)
    j trap_return

# sys_display_flip (jab.display.flip): show the framebuffer. a0 becomes
# 0; 1 when the frame is early, which the cap refuses without a
# transfer; 2 when the display is not open; 3 when the device refused a
# command.
.global sys_display_flip
sys_display_flip:
    la t0, display_state
    ld t0, 0(t0)
    li a0, 2
    beqz t0, 1f
    call frame_ready
    beqz a0, 2f
    li a0, 0
    li a1, 0
    li a2, JAB_DISPLAY_WIDTH
    li a3, JAB_DISPLAY_HEIGHT
    call display_present_rect
    li a1, 3
    bnez a0, 3f
    call frame_flipped
    li a0, 0
    j 1f
2:
    li a0, 1
    j 1f
3:
    mv a0, a1
1:
    sd a0, 80(sp)
    j trap_return

# sys_display_flip_rect (jab.display.flip.rect): show the rectangle at
# a0, a1 of a2 by a3 pixels. a0 becomes 0; 1 when the frame is early,
# nothing transferred; 2 when the display is not open; 3 when the
# device refused a command; 4 when the rectangle is empty or reaches
# outside the screen.
.global sys_display_flip_rect
sys_display_flip_rect:
    la t0, display_state
    ld t0, 0(t0)
    li a0, 2
    beqz t0, 9f
    ld t1, 80(sp)
    ld t2, 88(sp)
    ld t3, 96(sp)
    ld t4, 104(sp)
    li a0, 4
    beqz t3, 9f
    beqz t4, 9f
    li t6, JAB_DISPLAY_WIDTH
    bgtu t3, t6, 9f
    add t5, t1, t3
    bgtu t5, t6, 9f
    li t6, JAB_DISPLAY_HEIGHT
    bgtu t4, t6, 9f
    add t5, t2, t4
    bgtu t5, t6, 9f
    call frame_ready
    beqz a0, 8f
    ld a0, 80(sp)
    ld a1, 88(sp)
    ld a2, 96(sp)
    ld a3, 104(sp)
    call display_present_rect
    li a1, 3
    bnez a0, 7f
    call frame_flipped
    li a0, 0
    j 9f
7:
    mv a0, a1
    j 9f
8:
    li a0, 1
9:
    sd a0, 80(sp)
    j trap_return

# sys_display_flip_rects (jab.display.flip.rects): show the a1
# rectangles at a0, JAB_RECT_SIZE bytes each, as one flip. Every
# rectangle is checked before any is shown. a0 becomes 0; 1 when the
# frame is early, nothing transferred; 2 when the display is not open;
# 3 when the device refused a command; 4 when the count is 0 or a
# rectangle is empty or reaches outside the screen.
.global sys_display_flip_rects
sys_display_flip_rects:
    la t0, display_state
    ld t0, 0(t0)
    li a0, 2
    beqz t0, 9f
    ld s0, 80(sp)               # the rectangles
    ld s1, 88(sp)               # how many
    li a0, 4
    beqz s1, 9f
    mv a0, s0
    slli a1, s1, 4
    call buffer_bounds
    mv s2, s0
    mv s3, s1
1:
    lwu t1, JAB_RECT_X(s2)
    lwu t2, JAB_RECT_Y(s2)
    lwu t3, JAB_RECT_WIDTH(s2)
    lwu t4, JAB_RECT_HEIGHT(s2)
    li a0, 4
    beqz t3, 9f
    beqz t4, 9f
    li t6, JAB_DISPLAY_WIDTH
    bgtu t3, t6, 9f
    add t5, t1, t3
    bgtu t5, t6, 9f
    li t6, JAB_DISPLAY_HEIGHT
    bgtu t4, t6, 9f
    add t5, t2, t4
    bgtu t5, t6, 9f
    addi s2, s2, JAB_RECT_SIZE
    addi s3, s3, -1
    bnez s3, 1b
    call frame_ready
    beqz a0, 8f
    mv a0, s0
    mv a1, s1
    call display_present_rects
    bnez a0, 7f
    call frame_flipped
    li a0, 0
    j 9f
7:
    li a0, 3
    j 9f
8:
    li a0, 1
9:
    sd a0, 80(sp)
    j trap_return

# display_present_rects: transfer the a1 rectangles at a0, JAB_RECT_SIZE
# bytes each, to the host, in batches of GPU_TRANSFERS_PER_BATCH with
# one wait each, and flush the one rectangle holding them all once,
# riding the last batch, so a list up to GPU_TRANSFERS_PER_BATCH is one
# wait. Returns 0, or 1 when a command fails.
.global display_present_rects
display_present_rects:
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
    mv s0, a0                   # the next rectangle
    mv s1, a1                   # how many are left
    beqz s1, 8f
    # the rectangle holding them all, from the list
    li s4, JAB_DISPLAY_WIDTH    # its left
    li s5, JAB_DISPLAY_HEIGHT   # its top
    li s6, 0                    # its right
    li s7, 0                    # its bottom
    mv t0, s0
    mv t1, s1
1:
    beqz t1, 2f
    lwu t2, JAB_RECT_X(t0)
    lwu t3, JAB_RECT_Y(t0)
    lwu t4, JAB_RECT_WIDTH(t0)
    lwu t5, JAB_RECT_HEIGHT(t0)
    add t4, t4, t2
    add t5, t5, t3
    bgeu t2, s4, 11f
    mv s4, t2
11:
    bgeu t3, s5, 12f
    mv s5, t3
12:
    bleu t4, s6, 13f
    mv s6, t4
13:
    bleu t5, s7, 14f
    mv s7, t5
14:
    addi t0, t0, JAB_RECT_SIZE
    addi t1, t1, -1
    j 1b
    # then the transfers, the last batch carrying the flush
2:
    li s2, GPU_TRANSFERS_PER_BATCH
    bgeu s1, s2, 3f
    mv s2, s1                   # this batch
3:
    la t0, gpu_queue
    sd zero, GPUQ_PENDING(t0)
    li s3, 0                    # the rectangle in the batch
4:
    bgeu s3, s2, 15f
    slli t0, s3, 4
    add t0, t0, s0
    lwu a0, JAB_RECT_X(t0)
    lwu a1, JAB_RECT_Y(t0)
    lwu a2, JAB_RECT_WIDTH(t0)
    lwu a3, JAB_RECT_HEIGHT(t0)
    call gpu_transfer_command
    addi s3, s3, 1
    j 4b
15:
    slli t0, s2, 4
    add s0, s0, t0
    sub s1, s1, s2
    bnez s1, 16f
    mv a0, s4
    mv a1, s5
    sub a2, s6, s4
    sub a3, s7, s5
    call gpu_flush_command
16:
    call gpu_batch_run
    bnez a0, 7f
    bnez s1, 2b
    j 8f
7:
    li a0, 1
    j 9f
8:
    li a0, 0
9:
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

# gpu_transfer_command: add the transfer to the host of the rectangle
# at a0, a1 of a2 by a3 to the pending batch, one chain.
gpu_transfer_command:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 32(sp)
    sd a1, 24(sp)
    sd a2, 16(sp)
    sd a3, 8(sp)
    li a0, VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D
    call gpu_batch_command
    ld t1, 32(sp)
    ld t2, 24(sp)
    ld t3, 16(sp)
    ld t4, 8(sp)
    sw t1, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_X)(a0)
    sw t2, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_Y)(a0)
    sw t3, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_WIDTH)(a0)
    sw t4, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_HEIGHT)(a0)
    li t5, JAB_DISPLAY_PITCH
    mul t5, t5, t2
    slli t6, t1, 2
    add t5, t5, t6
    sd t5, VIRTIO_GPU_TRANSFER_OFFSET(a0)
    li t5, DISPLAY_RESOURCE
    sw t5, VIRTIO_GPU_TRANSFER_RESOURCE_ID(a0)
    li a1, VIRTIO_GPU_TRANSFER_SIZE
    call gpu_batch_add
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# gpu_flush_command: add the flush of the rectangle at a0, a1 of a2 by
# a3 to the pending batch, one chain.
gpu_flush_command:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 32(sp)
    sd a1, 24(sp)
    sd a2, 16(sp)
    sd a3, 8(sp)
    li a0, VIRTIO_GPU_CMD_RESOURCE_FLUSH
    call gpu_batch_command
    ld t1, 32(sp)
    ld t2, 24(sp)
    ld t3, 16(sp)
    ld t4, 8(sp)
    sw t1, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_X)(a0)
    sw t2, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_Y)(a0)
    sw t3, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_WIDTH)(a0)
    sw t4, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_HEIGHT)(a0)
    li t5, DISPLAY_RESOURCE
    sw t5, VIRTIO_GPU_FLUSH_RESOURCE_ID(a0)
    li a1, VIRTIO_GPU_FLUSH_SIZE
    call gpu_batch_add
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# gpu_batch_command: a0 becomes the pending chain's command buffer,
# zeroed, with its type set to a0 as given.
gpu_batch_command:
    la t0, gpu_queue
    ld t1, GPUQ_PENDING(t0)
    li t2, GPU_CMD_BYTES
    mul t1, t1, t2
    la t0, gpu_batch_cmds
    add t0, t0, t1
    sd zero, 0(t0)
    sd zero, 8(t0)
    sd zero, 16(t0)
    sd zero, 24(t0)
    sd zero, 32(t0)
    sd zero, 40(t0)
    sd zero, 48(t0)
    sd zero, 56(t0)
    sw a0, VIRTIO_GPU_HDR_TYPE(t0)
    mv a0, t0
    ret

# gpu_batch_add: the pending chain's command, a1 bytes of it, and its
# response buffer become descriptors 2p and 2p + 1, offered in the
# available ring's next slot; the chain is then pending.
gpu_batch_add:
    la t0, gpu_queue
    ld t1, GPUQ_PENDING(t0)
    slli t2, t1, 1              # the descriptor pair
    slli t3, t2, 4
    add t3, t3, t0              # descriptor 2p
    li t4, GPU_CMD_BYTES
    mul t4, t4, t1
    la t5, gpu_batch_cmds
    add t5, t5, t4
    sd t5, (GPUQ_DESC + VIRTQ_DESC_ADDR)(t3)
    sw a1, (GPUQ_DESC + VIRTQ_DESC_LEN)(t3)
    li t4, VIRTQ_DESC_F_NEXT
    sh t4, (GPUQ_DESC + VIRTQ_DESC_FLAGS)(t3)
    addi t4, t2, 1
    sh t4, (GPUQ_DESC + VIRTQ_DESC_NEXT)(t3)
    addi t3, t3, VIRTQ_DESC_SIZE
    li t4, GPU_RESP_BYTES
    mul t4, t4, t1
    la t5, gpu_batch_resps
    add t5, t5, t4
    sd t5, (GPUQ_DESC + VIRTQ_DESC_ADDR)(t3)
    li t4, GPU_RESP_BYTES
    sw t4, (GPUQ_DESC + VIRTQ_DESC_LEN)(t3)
    li t4, VIRTQ_DESC_F_WRITE
    sh t4, (GPUQ_DESC + VIRTQ_DESC_FLAGS)(t3)
    sh zero, (GPUQ_DESC + VIRTQ_DESC_NEXT)(t3)
    # the available ring's slot for it: the index plus the pending count
    lhu t3, (GPUQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    add t3, t3, t1
    andi t3, t3, GPUQ_SIZE - 1
    slli t3, t3, 1
    add t3, t3, t0
    sh t2, (GPUQ_AVAIL + VIRTQ_AVAIL_RING)(t3)
    addi t1, t1, 1
    sd t1, GPUQ_PENDING(t0)
    ret

# gpu_batch_run: publish the pending chains, notify the device, halt
# until it has used every one, and read their responses. a0 becomes 0
# when each answered VIRTIO_GPU_RESP_OK_NODATA, else 1.
gpu_batch_run:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, gpu_queue
    ld t1, GPUQ_PENDING(t0)
    beqz t1, 8f
    fence w, w
    lhu t2, (GPUQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    add t2, t2, t1
    sh t2, (GPUQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    fence rw, rw
    la t2, gpu_base
    ld t2, 0(t2)
    sw zero, VIRTIO_MMIO_QUEUE_NOTIFY(t2)
    call gpu_wait_batch
    la t0, gpu_queue
    ld t1, GPUQ_PENDING(t0)
    ld t2, GPUQ_LAST_USED(t0)
    add t2, t2, t1
    li t3, 0xffff
    and t2, t2, t3
    sd t2, GPUQ_LAST_USED(t0)
    sd zero, GPUQ_PENDING(t0)
    # every response
    la t2, gpu_batch_resps
    li t3, VIRTIO_GPU_RESP_OK_NODATA
1:
    beqz t1, 8f
    lwu t4, VIRTIO_GPU_HDR_TYPE(t2)
    bne t4, t3, 7f
    addi t2, t2, GPU_RESP_BYTES
    addi t1, t1, -1
    j 1b
7:
    li a0, 1
    j 9f
8:
    li a0, 0
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# gpu_wait_batch: halt until the GPU queue's used index has moved past
# what the kernel last saw by the pending count, waking on the
# transport's line, which is serviced before returning.
gpu_wait_batch:
    addi sp, sp, -16
    sd ra, 8(sp)
    li t4, SIE_SEIE
    csrs sie, t4
1:
    la t0, gpu_queue
    fence rw, rw
    lhu t1, (GPUQ_USED + VIRTQ_USED_IDX)(t0)
    ld t2, GPUQ_LAST_USED(t0)
    ld t3, GPUQ_PENDING(t0)
    add t2, t2, t3
    li t3, 0xffff
    and t2, t2, t3
    beq t1, t2, 2f
    wfi
    call plic_service
    j 1b
2:
    call plic_service
    li t4, SIE_SEIE
    csrc sie, t4
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# gpu_queue_setup: give the device's control queue the wide record's
# rings, GPUQ_SIZE entries. Returns 0, or 1 when the device offers
# fewer.
gpu_queue_setup:
    la t2, gpu_base
    ld a0, 0(t2)
    la a2, gpu_queue
    sw zero, VIRTIO_MMIO_QUEUE_SEL(a0)
    lwu t0, VIRTIO_MMIO_QUEUE_NUM_MAX(a0)
    li t1, GPUQ_SIZE
    bltu t0, t1, 1f
    sw t1, VIRTIO_MMIO_QUEUE_NUM(a0)
    addi t0, a2, GPUQ_DESC
    srli t1, t0, 32
    sw t0, VIRTIO_MMIO_QUEUE_DESC_LOW(a0)
    sw t1, VIRTIO_MMIO_QUEUE_DESC_HIGH(a0)
    addi t0, a2, GPUQ_AVAIL
    srli t1, t0, 32
    sw t0, VIRTIO_MMIO_QUEUE_DRIVER_LOW(a0)
    sw t1, VIRTIO_MMIO_QUEUE_DRIVER_HIGH(a0)
    addi t0, a2, GPUQ_USED
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

# sys_display_print (jab.display.print): write the string at a0 to the
# screen console, opening the display if the program has not. a0 becomes
# 0, or display_open's code.
.global sys_display_print
sys_display_print:
    call message_bounds
    mv s0, a0
    mv s1, a1
    la t0, display_state
    ld t0, 0(t0)
    bnez t0, 1f
    call display_open
    bnez a0, 2f
1:
    mv a0, s0
    mv a1, s1
    call console_write
    li a0, 0
2:
    sd a0, 80(sp)
    j trap_return

# sys_print (jab.print): the screen console once the display is open,
# else the UART.
.global sys_print
sys_print:
    la t0, display_state
    ld t0, 0(t0)
    bnez t0, sys_display_print
    j sys_uart_print

# display_open: bring the GPU up and show the framebuffer. Returns 0; 1
# when no virtio-gpu is on the machine; 2 when the device refuses the
# features or has no control queue of VIRTQ_SIZE; 3 when a command
# fails. Open already, it returns 0 at once.
.global display_open
display_open:
    la t0, display_state
    ld t0, 0(t0)
    beqz t0, 1f
    li a0, 0
    ret
1:
    addi sp, sp, -16
    sd ra, 8(sp)
    li a0, VIRTIO_ID_GPU
    call virtio_find
    beqz a0, 5f
    la t0, gpu_base
    sd a0, 0(t0)
.ifdef DEBUG
    la a0, msg_gpu_at
    call debug_puts
    la t0, gpu_base
    ld a0, 0(t0)
    call debug_put_hex
    li a0, '\n'
    call debug_putc
    la t0, gpu_base
    ld a0, 0(t0)
.pushsection .rodata
msg_gpu_at:
    .asciz "jab: gpu at "
.popsection
.endif
    call virtio_init
    bnez a0, 6f
    call gpu_queue_setup
    bnez a0, 6f
    la t0, gpu_base
    ld a0, 0(t0)
    call virtio_driver_ok
    la t0, gpu_base
    ld a0, 0(t0)
    call virtio_irq_enable
    # what the display is, then the resource, its backing, the scanout,
    # and the first frame
    call gpu_get_display_info
    bnez a0, 7f
    call gpu_create_resource
    bnez a0, 7f
    call gpu_attach_backing
    bnez a0, 7f
    call gpu_set_scanout
    bnez a0, 7f
    li a0, 0
    li a1, 0
    li a2, JAB_DISPLAY_WIDTH
    li a3, JAB_DISPLAY_HEIGHT
    call display_present_rect
    bnez a0, 7f
    la t0, display_state
    li t1, 1
    sd t1, 0(t0)
    li a0, 0
    j 8f
5:
    li a0, 1
    j 8f
6:
    li a0, 2
    j 8f
7:
    li a0, 3
8:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# display_present_rect: transfer the rectangle at a0, a1 of a2 by a3
# pixels of the framebuffer to the host and flush it to the screen.
# Returns 0, or 1 when a command fails.
.global display_present_rect
display_present_rect:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 32(sp)
    sd a1, 24(sp)
    sd a2, 16(sp)
    sd a3, 8(sp)
    li a0, VIRTIO_GPU_CMD_TRANSFER_TO_HOST_2D
    call gpu_command
    la t0, gpu_cmd
    ld t1, 32(sp)
    ld t2, 24(sp)
    ld t3, 16(sp)
    ld t4, 8(sp)
    sw t1, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_X)(t0)
    sw t2, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_Y)(t0)
    sw t3, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_WIDTH)(t0)
    sw t4, (VIRTIO_GPU_TRANSFER_RECT + VIRTIO_GPU_RECT_HEIGHT)(t0)
    # the byte offset of the rectangle's top left in the framebuffer
    li t5, JAB_DISPLAY_PITCH
    mul t5, t5, t2
    slli t6, t1, 2
    add t5, t5, t6
    sd t5, VIRTIO_GPU_TRANSFER_OFFSET(t0)
    li t5, DISPLAY_RESOURCE
    sw t5, VIRTIO_GPU_TRANSFER_RESOURCE_ID(t0)
    li a0, VIRTIO_GPU_TRANSFER_SIZE
    li a1, VIRTIO_GPU_RESP_OK_NODATA
    call gpu_submit
    bnez a0, 1f
    li a0, VIRTIO_GPU_CMD_RESOURCE_FLUSH
    call gpu_command
    la t0, gpu_cmd
    ld t1, 32(sp)
    ld t2, 24(sp)
    ld t3, 16(sp)
    ld t4, 8(sp)
    sw t1, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_X)(t0)
    sw t2, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_Y)(t0)
    sw t3, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_WIDTH)(t0)
    sw t4, (VIRTIO_GPU_FLUSH_RECT + VIRTIO_GPU_RECT_HEIGHT)(t0)
    li t5, DISPLAY_RESOURCE
    sw t5, VIRTIO_GPU_FLUSH_RESOURCE_ID(t0)
    li a0, VIRTIO_GPU_FLUSH_SIZE
    li a1, VIRTIO_GPU_RESP_OK_NODATA
    call gpu_submit
1:
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# gpu_get_display_info: ask what the display is; with DEBUG the first
# mode is reported.
gpu_get_display_info:
    addi sp, sp, -16
    sd ra, 8(sp)
    li a0, VIRTIO_GPU_CMD_GET_DISPLAY_INFO
    call gpu_command
    li a0, VIRTIO_GPU_HDR_SIZE
    li a1, VIRTIO_GPU_RESP_OK_DISPLAY_INFO
    call gpu_submit
.ifdef DEBUG
    bnez a0, 1f
    la a0, msg_display
    call debug_puts
    la t0, gpu_resp
    lwu a0, (VIRTIO_GPU_DISPLAY_INFO_MODES + VIRTIO_GPU_RECT_WIDTH)(t0)
    call debug_put_dec
    li a0, 'x'
    call debug_putc
    la t0, gpu_resp
    lwu a0, (VIRTIO_GPU_DISPLAY_INFO_MODES + VIRTIO_GPU_RECT_HEIGHT)(t0)
    call debug_put_dec
    la a0, msg_enabled
    call debug_puts
    la t0, gpu_resp
    lwu a0, (VIRTIO_GPU_DISPLAY_INFO_MODES + VIRTIO_GPU_DISPLAY_ONE_ENABLED)(t0)
    call debug_put_dec
    li a0, '\n'
    call debug_putc
    li a0, 0
.pushsection .rodata
msg_display:
    .asciz "jab: display "
msg_enabled:
    .asciz " enabled="
.popsection
1:
.endif
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# gpu_create_resource: the one 2D resource, the framebuffer's size and
# format.
gpu_create_resource:
    addi sp, sp, -16
    sd ra, 8(sp)
    li a0, VIRTIO_GPU_CMD_RESOURCE_CREATE_2D
    call gpu_command
    la t0, gpu_cmd
    li t1, DISPLAY_RESOURCE
    sw t1, VIRTIO_GPU_CREATE_2D_RESOURCE_ID(t0)
    li t1, VIRTIO_GPU_FORMAT_B8G8R8X8_UNORM
    sw t1, VIRTIO_GPU_CREATE_2D_FORMAT(t0)
    li t1, JAB_DISPLAY_WIDTH
    sw t1, VIRTIO_GPU_CREATE_2D_WIDTH(t0)
    li t1, JAB_DISPLAY_HEIGHT
    sw t1, VIRTIO_GPU_CREATE_2D_HEIGHT(t0)
    li a0, VIRTIO_GPU_CREATE_2D_SIZE
    li a1, VIRTIO_GPU_RESP_OK_NODATA
    call gpu_submit
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# gpu_attach_backing: the framebuffer, one contiguous entry, backs the
# resource.
gpu_attach_backing:
    addi sp, sp, -16
    sd ra, 8(sp)
    li a0, VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING
    call gpu_command
    la t0, gpu_cmd
    li t1, DISPLAY_RESOURCE
    sw t1, VIRTIO_GPU_ATTACH_RESOURCE_ID(t0)
    li t1, 1
    sw t1, VIRTIO_GPU_ATTACH_NR_ENTRIES(t0)
    li t1, JAB_DISPLAY_BASE
    sd t1, VIRTIO_GPU_ATTACH_ENTRY_ADDR(t0)
    li t1, JAB_DISPLAY_SIZE
    sw t1, VIRTIO_GPU_ATTACH_ENTRY_LENGTH(t0)
    li a0, VIRTIO_GPU_ATTACH_SIZE
    li a1, VIRTIO_GPU_RESP_OK_NODATA
    call gpu_submit
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# gpu_set_scanout: scanout 0 shows the whole resource.
gpu_set_scanout:
    addi sp, sp, -16
    sd ra, 8(sp)
    li a0, VIRTIO_GPU_CMD_SET_SCANOUT
    call gpu_command
    la t0, gpu_cmd
    li t1, JAB_DISPLAY_WIDTH
    sw t1, (VIRTIO_GPU_SCANOUT_RECT + VIRTIO_GPU_RECT_WIDTH)(t0)
    li t1, JAB_DISPLAY_HEIGHT
    sw t1, (VIRTIO_GPU_SCANOUT_RECT + VIRTIO_GPU_RECT_HEIGHT)(t0)
    li t1, DISPLAY_RESOURCE
    sw t1, VIRTIO_GPU_SCANOUT_RESOURCE_ID(t0)
    li a0, VIRTIO_GPU_SCANOUT_SIZE
    li a1, VIRTIO_GPU_RESP_OK_NODATA
    call gpu_submit
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# gpu_command: zero the request buffer and set its type to a0.
gpu_command:
    la t0, gpu_cmd
    sd zero, 0(t0)
    sd zero, 8(t0)
    sd zero, 16(t0)
    sd zero, 24(t0)
    sd zero, 32(t0)
    sd zero, 40(t0)
    sd zero, 48(t0)
    sd zero, 56(t0)
    sw a0, VIRTIO_GPU_HDR_TYPE(t0)
    ret

# gpu_submit: run the request of a0 bytes in gpu_cmd and expect a
# response of type a1 in gpu_resp: a batch of one chain, descriptors 0
# and 1. Returns 0 when the device answered with it, else 1. With DEBUG
# every command and its answer is reported on the debug channel.
gpu_submit:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a1, 16(sp)
    la t0, gpu_queue
    sd zero, GPUQ_PENDING(t0)
    la t1, gpu_cmd
    sd t1, (GPUQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_ADDR)(t0)
    sw a0, (GPUQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_LEN)(t0)
    li t1, VIRTQ_DESC_F_NEXT
    sh t1, (GPUQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_FLAGS)(t0)
    li t1, 1
    sh t1, (GPUQ_DESC + 0 * VIRTQ_DESC_SIZE + VIRTQ_DESC_NEXT)(t0)
    la t1, gpu_resp
    sd t1, (GPUQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_ADDR)(t0)
    li t1, VIRTIO_GPU_DISPLAY_INFO_SIZE
    sw t1, (GPUQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_LEN)(t0)
    li t1, VIRTQ_DESC_F_WRITE
    sh t1, (GPUQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_FLAGS)(t0)
    sh zero, (GPUQ_DESC + 1 * VIRTQ_DESC_SIZE + VIRTQ_DESC_NEXT)(t0)
    lhu t1, (GPUQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    andi t1, t1, GPUQ_SIZE - 1
    slli t1, t1, 1
    add t1, t1, t0
    sh zero, (GPUQ_AVAIL + VIRTQ_AVAIL_RING)(t1)
    li t1, 1
    sd t1, GPUQ_PENDING(t0)
    fence w, w
    lhu t1, (GPUQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    addi t1, t1, 1
    sh t1, (GPUQ_AVAIL + VIRTQ_AVAIL_IDX)(t0)
    fence rw, rw
    la t1, gpu_base
    ld t1, 0(t1)
    sw zero, VIRTIO_MMIO_QUEUE_NOTIFY(t1)
    call gpu_wait_batch
    la t0, gpu_queue
    ld t1, GPUQ_LAST_USED(t0)
    addi t1, t1, 1
    li t2, 0xffff
    and t1, t1, t2
    sd t1, GPUQ_LAST_USED(t0)
    sd zero, GPUQ_PENDING(t0)
.ifdef DEBUG
    la a0, msg_gpu_cmd
    call debug_puts
    la t0, gpu_cmd
    lwu a0, VIRTIO_GPU_HDR_TYPE(t0)
    call debug_put_hex
    la a0, msg_gpu_resp
    call debug_puts
    la t0, gpu_resp
    lwu a0, VIRTIO_GPU_HDR_TYPE(t0)
    call debug_put_hex
    li a0, '\n'
    call debug_putc
.pushsection .rodata
msg_gpu_cmd:
    .asciz "jab: gpu cmd="
msg_gpu_resp:
    .asciz " resp="
.popsection
.endif
    la t0, gpu_resp
    lwu t1, VIRTIO_GPU_HDR_TYPE(t0)
    ld t2, 16(sp)
    li a0, 0
    beq t1, t2, 1f
    li a0, 1
1:
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# console_write: draw the bytes from a0 up to the terminator or a1 at
# the cursor, then show the rows touched. A newline moves to the next
# line; a line past the last scrolls the screen up; other control bytes
# are skipped, and bytes past ASCII draw as a space.
.global console_write
console_write:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd s0, 32(sp)
    sd s1, 24(sp)
    sd s2, 16(sp)
    sd s3, 8(sp)
    mv s0, a0
    mv s1, a1
    li s2, JAB_DISPLAY_HEIGHT
    li s3, 0
1:
    bgeu s0, s1, 9f
    lbu a0, 0(s0)
    beqz a0, 9f
    addi s0, s0, 1
    li t0, '\n'
    bne a0, t0, 2f
    la t0, console_col
    sd zero, 0(t0)
    la t0, console_row
    ld t1, 0(t0)
    addi t1, t1, 1
    sd t1, 0(t0)
    j 1b
2:
    li t0, FONT_FIRST
    bltu a0, t0, 1b
    li t0, FONT_LAST
    bleu a0, t0, 3f
    li a0, ' '
3:
    la t0, console_col
    ld t1, 0(t0)
    li t2, CONSOLE_COLUMNS
    bltu t1, t2, 4f
    sd zero, 0(t0)
    la t0, console_row
    ld t1, 0(t0)
    addi t1, t1, 1
    sd t1, 0(t0)
4:
    la t0, console_row
    ld t1, 0(t0)
    li t2, CONSOLE_ROWS
    bltu t1, t2, 5f
    sd a0, 0(sp)
    call console_scroll
    ld a0, 0(sp)
    la t0, console_row
    li t1, CONSOLE_ROWS - 1
    sd t1, 0(t0)
    li s2, 0
    li s3, JAB_DISPLAY_HEIGHT
5:
    # the dirty band takes in this line's pixel rows
    la t0, console_row
    ld a2, 0(t0)
    li t2, FONT_HEIGHT
    mul t3, a2, t2
    bgeu t3, s2, 6f
    mv s2, t3
6:
    add t4, t3, t2
    bleu t4, s3, 7f
    mv s3, t4
7:
    la t0, console_col
    ld a1, 0(t0)
    call console_glyph
    la t0, console_col
    ld t1, 0(t0)
    addi t1, t1, 1
    sd t1, 0(t0)
    j 1b
9:
    bgeu s2, s3, 10f
    li a0, 0
    mv a1, s2
    li a2, JAB_DISPLAY_WIDTH
    sub a3, s3, s2
    call display_present_rect
10:
    ld ra, 40(sp)
    ld s0, 32(sp)
    ld s1, 24(sp)
    ld s2, 16(sp)
    ld s3, 8(sp)
    addi sp, sp, 48
    ret

# console_glyph: draw the glyph of a0 in the cell at column a1, row a2.
console_glyph:
    addi t0, a0, -FONT_FIRST
    li t1, FONT_GLYPH_BYTES
    mul t0, t0, t1
    la t1, font_glyphs
    add t0, t0, t1
    li t1, CONSOLE_LINE_BYTES
    mul t1, t1, a2
    li t2, FONT_WIDTH * 4
    mul t2, t2, a1
    add t1, t1, t2
    li t2, JAB_DISPLAY_BASE
    add t1, t1, t2
    li t2, FONT_HEIGHT
    li t5, CONSOLE_FG
    li t6, CONSOLE_BG
1:
    lhu t3, 0(t0)
    mv t4, t1
    li a3, FONT_WIDTH
2:
    srli a4, t3, 15
    andi a4, a4, 1
    beqz a4, 3f
    sw t5, 0(t4)
    j 4f
3:
    sw t6, 0(t4)
4:
    slli t3, t3, 1
    addi t4, t4, 4
    addi a3, a3, -1
    bnez a3, 2b
    addi t0, t0, FONT_ROW_BYTES
    li a4, JAB_DISPLAY_PITCH
    add t1, t1, a4
    addi t2, t2, -1
    bnez t2, 1b
    ret

# console_scroll: move every line up by one and clear the last.
console_scroll:
    li t0, JAB_DISPLAY_BASE
    li t1, JAB_DISPLAY_BASE + CONSOLE_LINE_BYTES
    li t2, JAB_DISPLAY_BASE + JAB_DISPLAY_SIZE
1:
    ld t3, 0(t1)
    sd t3, 0(t0)
    addi t0, t0, 8
    addi t1, t1, 8
    bltu t1, t2, 1b
2:
    sd zero, 0(t0)
    addi t0, t0, 8
    bltu t0, t2, 2b
    ret

.section .bss
.balign 16
gpu_queue:
    .skip GPUQ_BYTES
.balign 16
gpu_cmd:
    .skip GPU_CMD_BYTES
gpu_resp:
    .skip VIRTIO_GPU_DISPLAY_INFO_SIZE
.balign 16
gpu_batch_cmds:
    .skip GPUQ_CHAINS * GPU_CMD_BYTES
gpu_batch_resps:
    .skip GPUQ_CHAINS * GPU_RESP_BYTES
gpu_base:
    .skip 8
display_state:
    .skip 8
console_col:
    .skip 8
console_row:
    .skip 8
