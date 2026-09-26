.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# The supervisor trap vector. A trap from the program lands here: its
# registers go into a 256-byte frame on the kernel stack, the cause picks
# a handler, and sret returns with the frame restored. sscratch holds the
# kernel stack top while the program runs and the program's sp while the
# kernel runs, swapped on entry and exit. Frame slot n holds register n;
# slot 2 holds the program's sp. A system call is dispatched through
# syscall_table by its number in a7; a handler finds its arguments in
# slots 80 on (a0 to a5), leaves its results in slots 80 on (a0, and a1
# to a3 where a call has more), and jumps to trap_return.
.set SYSCALL_LAST, JAB_SYS_DISPLAY_TEXT

.section .text
.balign 4
.global trap_vector
trap_vector:
    csrrw sp, sscratch, sp
    addi sp, sp, -256
    sd x1, 8(sp)
    sd x3, 24(sp)
    sd x4, 32(sp)
    sd x5, 40(sp)
    sd x6, 48(sp)
    sd x7, 56(sp)
    sd x8, 64(sp)
    sd x9, 72(sp)
    sd x10, 80(sp)
    sd x11, 88(sp)
    sd x12, 96(sp)
    sd x13, 104(sp)
    sd x14, 112(sp)
    sd x15, 120(sp)
    sd x16, 128(sp)
    sd x17, 136(sp)
    sd x18, 144(sp)
    sd x19, 152(sp)
    sd x20, 160(sp)
    sd x21, 168(sp)
    sd x22, 176(sp)
    sd x23, 184(sp)
    sd x24, 192(sp)
    sd x25, 200(sp)
    sd x26, 208(sp)
    sd x27, 216(sp)
    sd x28, 224(sp)
    sd x29, 232(sp)
    sd x30, 240(sp)
    sd x31, 248(sp)
    csrr t0, sscratch
    sd t0, 16(sp)
    csrr t0, sstatus
    andi t0, t0, SSTATUS_SPP
    bnez t0, kernel_fault
    csrr t0, scause
    li t1, SCAUSE_ECALL_U
    bne t0, t1, program_fault
    # A system call: the number in a7, the argument in a0.
    ld a7, 136(sp)
    ld a0, 80(sp)
    beqz a7, bad_syscall
    li t0, SYSCALL_LAST
    bgtu a7, t0, bad_syscall
    la t0, syscall_table
    slli t1, a7, 3
    add t0, t0, t1
    ld t0, 0(t0)
    jr t0

bad_syscall:
    la a0, msg_bad_syscall
    call uart_puts
    ld a0, 136(sp)
    call uart_put_dec
    li a0, '\n'
    call uart_putc
    li a0, 1
    j qemu_exit

# message_bounds: a0 is a message address from the program. Returns a0
# unchanged and a1 as the window's end, or ends the run when the address
# lies outside the window.
.global message_bounds
message_bounds:
    li t0, JAB_PROGRAM_BASE
    bltu a0, t0, bad_address
    li a1, JAB_STACK_TOP
    bgeu a0, a1, bad_address
    ret

# sys_uart_print (jab.uart.print): a0 is the message, which must lie
# inside the program's window; the write stops at the terminator or the
# window's end. a0 becomes 0.
.global sys_uart_print
sys_uart_print:
    call message_bounds
    mv s0, a0
    mv s1, a1
1:
    bgeu s0, s1, 2f
    lbu a0, 0(s0)
    beqz a0, 2f
    call uart_putc
    addi s0, s0, 1
    j 1b
2:
    sd zero, 80(sp)
    j trap_return

# buffer_bounds: a0 is an address from the program and a1 a count of
# bytes. Returns with both kept when the whole range lies inside the
# program's window, and ends the run otherwise, so a call that fills a
# buffer can write it without checking again.
.global buffer_bounds
buffer_bounds:
    li t0, JAB_PROGRAM_BASE
    bltu a0, t0, bad_address
    li t1, JAB_STACK_TOP
    bgeu a0, t1, bad_address
    add t2, a0, a1
    bltu t2, a0, bad_address    # a count that wraps is nobody's buffer
    bgtu t2, t1, bad_address
    ret

# copy_bytes: a2 bytes from a1 to a0. Program memory is reached through
# SUM, so either end may be the program's.
.global copy_bytes
copy_bytes:
    beqz a2, 2f
1:
    lbu t0, 0(a1)
    sb t0, 0(a0)
    addi a0, a0, 1
    addi a1, a1, 1
    addi a2, a2, -1
    bnez a2, 1b
2:
    ret

# zero_bytes: a1 bytes at a0 become zero.
.global zero_bytes
zero_bytes:
    beqz a1, 2f
1:
    sb zero, 0(a0)
    addi a0, a0, 1
    addi a1, a1, -1
    bnez a1, 1b
2:
    ret

bad_address:
    la a0, msg_bad_address
    call uart_puts
    li a0, 1
    j qemu_exit

# sys_exit (jab.exit): a0 is the status. QEMU ends with it, since no
# launcher exists yet to return to; with DEBUG the status is also
# reported on the debug channel.
sys_exit:
.ifdef DEBUG
    mv s0, a0
    la a0, msg_exit
    call debug_puts
    mv a0, s0
    call debug_put_dec
    li a0, '\n'
    call debug_putc
    mv a0, s0
.pushsection .rodata
msg_exit:
    .asciz "jab: exit "
.popsection
.endif
    j qemu_exit

program_fault:
    la a0, msg_program_fault
    call uart_puts
    csrr a0, scause
    call uart_put_hex
    la a0, msg_epc
    call uart_puts
    csrr a0, sepc
    call uart_put_hex
    la a0, msg_tval
    call uart_puts
    csrr a0, stval
    call uart_put_hex
    li a0, '\n'
    call uart_putc
    li a0, 1
    j qemu_exit

kernel_fault:
    la a0, msg_kernel_fault
    call uart_puts
    csrr a0, scause
    call uart_put_hex
    la a0, msg_epc
    call uart_puts
    csrr a0, sepc
    call uart_put_hex
    li a0, '\n'
    call uart_putc
    j halt

.global trap_return
trap_return:
    csrr t0, sepc
    addi t0, t0, 4
    csrw sepc, t0
    ld x1, 8(sp)
    ld x3, 24(sp)
    ld x4, 32(sp)
    ld x5, 40(sp)
    ld x6, 48(sp)
    ld x7, 56(sp)
    ld x8, 64(sp)
    ld x9, 72(sp)
    ld x10, 80(sp)
    ld x11, 88(sp)
    ld x12, 96(sp)
    ld x13, 104(sp)
    ld x14, 112(sp)
    ld x15, 120(sp)
    ld x16, 128(sp)
    ld x17, 136(sp)
    ld x18, 144(sp)
    ld x19, 152(sp)
    ld x20, 160(sp)
    ld x21, 168(sp)
    ld x22, 176(sp)
    ld x23, 184(sp)
    ld x24, 192(sp)
    ld x25, 200(sp)
    ld x26, 208(sp)
    ld x27, 216(sp)
    ld x28, 224(sp)
    ld x29, 232(sp)
    ld x30, 240(sp)
    ld x31, 248(sp)
    addi sp, sp, 256
    csrrw sp, sscratch, sp
    sret

# End QEMU through the virt test device: a0 of 0 passes, anything else
# fails with a0 as the exit code. Halts if the write does not end it.
.global qemu_exit
qemu_exit:
    li t0, QEMU_VIRT_TEST
    beqz a0, 1f
    slli a0, a0, 16
    li t1, QEMU_TEST_FAIL
    or a0, a0, t1
    sw a0, 0(t0)
    j halt
1:
    li a0, QEMU_TEST_PASS
    sw a0, 0(t0)
.global halt
halt:
    wfi
    j halt

.section .rodata
.balign 8
syscall_table:
    .quad bad_syscall
    .quad sys_exit
    .quad sys_print
    .quad sys_uart_print
    .quad sys_display_open
    .quad sys_display_ready
    .quad sys_display_flip
    .quad sys_display_print
    .quad sys_await
    .quad sys_display_flip_rect
    .quad sys_keyboard_input
    .quad sys_block_list
    .quad sys_block_find
    .quad sys_block_read
    .quad sys_block_write
    .quad sys_romfs_list
    .quad sys_romfs_find
    .quad sys_romfs_read
    .quad sys_tar_list
    .quad sys_tar_find
    .quad sys_gz_size
    .quad sys_gz_read
    .quad sys_checksum
    .quad sys_hash
    .quad sys_api_write
    .quad sys_api_read
    .quad sys_png_size
    .quad sys_sprite_png
    .quad sys_sprite_draw
    .quad sys_sprite_load
    .quad sys_display_flip_rects
    .quad sys_kernel_flags
    .quad sys_pad_read
    .quad sys_pad_input
    .quad sys_pad_axis
    .quad sys_display_text
msg_bad_syscall:
    .asciz "jab: unknown system call "
msg_bad_address:
    .asciz "jab: address outside the program\n"
msg_program_fault:
    .asciz "jab: program fault: cause="
msg_kernel_fault:
    .asciz "jab: kernel fault: cause="
msg_epc:
    .asciz " epc="
msg_tval:
    .asciz " tval="
