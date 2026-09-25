# keys: the keyboard. Waits for key events and reports each on the
# UART as `key <code> <value>`, three digits and one, until the space
# bar is released, then exits 0.
.include "jab.inc"

.section .text
.global _start
_start:
    jab.uart.print ready
wait:
    jab.keyboard.await
next:
    jab.keyboard.input
    beqz a0, wait
    mv s0, a0
    mv s1, a1
    # the code, three digits
    la t0, code_digits
    li t1, 100
    divu t2, s0, t1
    remu t3, s0, t1
    addi t2, t2, '0'
    sb t2, 0(t0)
    li t1, 10
    divu t2, t3, t1
    remu t3, t3, t1
    addi t2, t2, '0'
    addi t3, t3, '0'
    sb t2, 1(t0)
    sb t3, 2(t0)
    # the value, one digit
    la t0, value_digit
    addi t1, s1, '0'
    sb t1, 0(t0)
    jab.uart.print report
    li t0, JAB_KEY_SPACE
    bne s0, t0, next
    bnez s1, next
    jab.exit 0

.section .data
report:
    .ascii "key "
code_digits:
    .ascii "000 "
value_digit:
    .asciz "0\n"

.section .rodata
ready:
    .asciz "keys: ready\n"
