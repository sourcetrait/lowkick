# helloworld: the first Jab program. Prints a line and exits.
.include "jab.inc"

.section .text
.global _start
_start:
    jab.print message
    jab.exit 0

.section .rodata
message:
    .asciz "Hello, World!\n"
