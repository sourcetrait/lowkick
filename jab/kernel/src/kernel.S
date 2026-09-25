.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# Supervisor-mode entry. Zeroes bss, turns on paging, starts the frame
# clock, installs the trap vector, and enters the program at
# JAB_PROGRAM_BASE in user mode with its stack at JAB_STACK_TOP and
# every other register cleared. The display comes up when the program
# asks for it. The UART carries only the program's output and the fault
# lines; with DEBUG set at assembly (`--set debug`) the kernel's own
# lines go to its debug channel, a virtio-serial port brought up first
# (serial.S).
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
    call frame_clock_init
    la t0, trap_vector
    csrw stvec, t0
    # The kernel reads and writes program memory (a message to print,
    # the framebuffer), so SUM.
    li t0, SSTATUS_SUM
    csrs sstatus, t0
    # The machine is RVA23, so the program has floating point and
    # vectors; their state starts Initial, since Off makes the first
    # such instruction an illegal instruction.
    li t0, SSTATUS_FS_INITIAL | SSTATUS_VS_INITIAL
    csrs sstatus, t0
    csrw sie, zero
    # The program may read the time counter.
    li t0, SCOUNTEREN_TM
    csrw scounteren, t0
.ifdef DEBUG
    # the debug channel first, so the banner and everything after it go
    # there
    call serial_open
    la a0, msg_banner
    call debug_puts
.pushsection .rodata
msg_banner:
    .asciz "jab: kernel up on qemu virt\n"
.popsection
.endif
.ifdef DATA
    # the data channel, up before the program starts; open already
    # when DEBUG brought the device up
    call serial_open
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
