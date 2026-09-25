# badstore: stores into the kernel's memory. The kernel must report a
# program fault (a store page fault, cause 15) and end the run with
# status 1; the message after the store must never print.
.include "jab.inc"

.section .text
.global _start
_start:
    jab.print before
    li t0, 0x80000000
    sw zero, 0(t0)
    jab.print after
    jab.exit 0

.section .rodata
before:
    .asciz "storing into the kernel\n"
after:
    .asciz "the store went through\n"
