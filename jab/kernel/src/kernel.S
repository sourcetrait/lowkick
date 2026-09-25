.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# Supervisor-mode entry. Zeroes bss, turns on paging, installs the trap
# vector, and enters the program at JAB_PROGRAM_BASE in user mode with
# its stack at JAB_STACK_TOP and every other register cleared. The UART
# carries only the program's output unless JAB_DEBUG is defined at
# assembly (as --defsym JAB_DEBUG=1), which adds the kernel's own lines.
.section .text
.global kmain
kmain:
    la t0, _bss_start
    la t1, _bss_end
1:
    bgeu t0, t1, 2f
    sd zero, 0(t0)
    addi t0, t0, 8
    j 1b
2:
    call page_init
    la t0, trap_vector
    csrw stvec, t0
    # The kernel reads program memory (a message to print), so SUM.
    li t0, SSTATUS_SUM
    csrs sstatus, t0
    csrw sie, zero
.ifdef JAB_DEBUG
    la a0, msg_banner
    call uart_puts
.endif
    # sscratch holds the kernel stack top while the program runs.
    la t0, kernel_stack_top
    csrw sscratch, t0
    li t0, JAB_PROGRAM_BASE
    csrw sepc, t0
    li t0, SSTATUS_SPP | SSTATUS_SPIE
    csrc sstatus, t0
    li sp, JAB_STACK_TOP
    li ra, 0
    li gp, 0
    li tp, 0
    li t0, 0
    li t1, 0
    li t2, 0
    li s0, 0
    li s1, 0
    li a0, 0
    li a1, 0
    li a2, 0
    li a3, 0
    li a4, 0
    li a5, 0
    li a6, 0
    li a7, 0
    li s2, 0
    li s3, 0
    li s4, 0
    li s5, 0
    li s6, 0
    li s7, 0
    li s8, 0
    li s9, 0
    li s10, 0
    li s11, 0
    li t3, 0
    li t4, 0
    li t5, 0
    li t6, 0
    sret

.section .bss
.balign 16
kernel_stack:
    .skip 16384
.global kernel_stack_top
kernel_stack_top:

.section .rodata
msg_banner:
    .asciz "jab: kernel up on qemu virt\n"
