# jab.inc: the Jab SDK header. `.include "jab.inc"` and call the kernel
# with the jab.* macros, assembler style: `jab.print message`.

# Where a program lives. QEMU's loader device places the .jab file at
# JAB_PROGRAM_BASE; the program owns JAB_PROGRAM_SIZE bytes from there,
# and starts with sp at JAB_STACK_TOP.
.set JAB_PROGRAM_BASE, 0x80800000
.set JAB_PROGRAM_SIZE, 0x200000
.set JAB_STACK_TOP, (JAB_PROGRAM_BASE + JAB_PROGRAM_SIZE)

# System call numbers (doc/syscalls.nuon)
.set JAB_SYS_EXIT, 1
.set JAB_SYS_PRINT, 2

# jab.exit status: end the program. status is an immediate, 0 by default.
.macro jab.exit status=0
    li a0, \status
    li a7, JAB_SYS_EXIT
    ecall
.endm

# jab.print message: write a NUL-terminated string. message is a label
# inside the program.
.macro jab.print message
    la a0, \message
    li a7, JAB_SYS_PRINT
    ecall
.endm
