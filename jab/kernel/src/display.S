.include "riscv.inc"
.include "qemu_virt.inc"
.include "virtio.inc"
.include "jab.inc"

# The display: QEMU's virtio-gpu in 2D over mmio. One resource, the
# framebuffer at JAB_DISPLAY_BASE, is the program's to draw into; the
# kernel attaches it as the resource's backing, sets it as scanout 0,
# and on a flip transfers the whole of it, or the rectangle the program
# names, to the host and flushes it. The screen console draws text into
# the same framebuffer with the font in font.S and transfers only the
# rows it touched. Commands run one at
# a time through the control queue, the hart halted until the device
# answers; the response's type says whether the device took the
# command.
.set DISPLAY_RESOURCE, 1

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
    la t0, gpu_base
    ld a0, 0(t0)
    li a1, 0
    la a2, gpu_queue
    call virtio_queue_setup
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

# gpu_submit: run the request of a0 bytes and expect a response of type
# a1. Returns 0 when the device answered with it, else 1. With DEBUG
# every command and its answer is reported on the debug channel.
gpu_submit:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a1, 16(sp)
    mv a3, a0
    la t0, gpu_base
    ld a0, 0(t0)
    li a1, 0
    la a2, gpu_queue
    la a4, gpu_cmd
    la a5, gpu_resp
    li a6, VIRTIO_GPU_DISPLAY_INFO_SIZE
    call virtio_request
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
    .skip VQ_BYTES
.balign 16
gpu_cmd:
    .skip 64
gpu_resp:
    .skip 416
gpu_base:
    .skip 8
display_state:
    .skip 8
console_col:
    .skip 8
console_row:
    .skip 8
