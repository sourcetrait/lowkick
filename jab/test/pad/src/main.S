# pad: the kernel's pad driver under test. Prints the pad's own range
# for X, GAS, and HAT0X and for an axis this pad lacks, then reports
# every pad event as `pad <type> <code> <value>` and, after each, the
# state as `state <keys> <x> <y> <hat0x> <gas>`, the keys as a mask and
# the axes normalised, until BTN_SOUTH is released. With no pad on the
# machine it says so and exits.
.include "jab.inc"

.set LINE_BYTES, 96
.set DIGITS_BYTES, 24

.section .text
.global _start
_start:
    jab.uart.print msg_ready
    li s0, JAB_ABS_X
    call print_axis
    li s0, JAB_ABS_GAS
    call print_axis
    li s0, JAB_ABS_HAT0X
    call print_axis
    li s0, JAB_ABS_RX
    call print_axis
frame:
    jab.pad.await
    beqz a0, no_pad
    call read_pad
    la t0, quit
    lbu t0, 0(t0)
    beqz t0, frame
    jab.exit 0

no_pad:
    jab.uart.print msg_no_pad
    jab.exit 2

# print_axis: s0 is an axis code; one line, `axis <code> <min> <max>
# <fuzz> <flat> <res>`, or `axis <code> none`.
print_axis:
    addi sp, sp, -16
    sd ra, 8(sp)
    la a0, axis_record
    mv a1, s0
    li a7, JAB_SYS_PAD_AXIS
    ecall
    mv s1, a0
    call line_begin
    la a0, msg_axis
    call line_str
    mv a0, s0
    call line_int
    bnez s1, 2f
    la s2, axis_record
    li s3, 5
1:
    la a0, msg_space
    call line_str
    lw a0, 0(s2)
    call line_int
    addi s2, s2, 4
    addi s3, s3, -1
    bnez s3, 1b
    j 3f
2:
    la a0, msg_none
    call line_str
3:
    call line_end
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# read_pad: take every pad event waiting, reporting each and the state
# after it; BTN_SOUTH released marks the end.
read_pad:
    addi sp, sp, -16
    sd ra, 8(sp)
1:
    jab.pad.input
    beqz a0, 9f
    mv s1, a0
    mv s2, a1
    mv s3, a2
    call line_begin
    la a0, msg_pad
    call line_str
    mv a0, s1
    call line_int
    la a0, msg_space
    call line_str
    mv a0, s2
    call line_int
    la a0, msg_space
    call line_str
    mv a0, s3
    call line_int
    call line_end
    li t0, JAB_EV_KEY
    bne s1, t0, 2f
    li t0, JAB_BTN_SOUTH
    bne s2, t0, 2f
    bnez s3, 2f
    la t0, quit
    li t1, 1
    sb t1, 0(t0)
2:
    call print_state
    j 1b
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# print_state: `state <keys> <x> <y> <hat0x> <gas>` from a fresh read.
print_state:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, state_record
    jab.pad.read t0
    call line_begin
    la a0, msg_state
    call line_str
    la t0, state_record
    lwu a0, JAB_PAD_KEYS(t0)
    call line_int
    li s1, JAB_ABS_X
    call print_axis_value
    li s1, JAB_ABS_Y
    call print_axis_value
    li s1, JAB_ABS_HAT0X
    call print_axis_value
    li s1, JAB_ABS_GAS
    call print_axis_value
    call line_end
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# print_axis_value: a space and the state record's value for axis s1.
print_axis_value:
    addi sp, sp, -16
    sd ra, 8(sp)
    la a0, msg_space
    call line_str
    la t0, state_record
    slli t1, s1, 1
    add t0, t0, t1
    lh a0, JAB_PAD_AXES(t0)
    call line_int
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# The line: begun empty, strings and signed decimals appended, ended
# with a newline and sent to the UART.
line_begin:
    la t0, line_len
    sd zero, 0(t0)
    ret

# line_str: a0 is a NUL-terminated string.
line_str:
    la t0, line_len
    ld t1, 0(t0)
    la t2, line
1:
    lbu t3, 0(a0)
    beqz t3, 2f
    add t4, t2, t1
    sb t3, 0(t4)
    addi t1, t1, 1
    addi a0, a0, 1
    j 1b
2:
    sd t1, 0(t0)
    ret

# line_int: a0 is a signed value, appended in decimal.
line_int:
    la t0, line_len
    ld t1, 0(t0)
    la t2, line
    bgez a0, 1f
    add t4, t2, t1
    li t3, '-'
    sb t3, 0(t4)
    addi t1, t1, 1
    neg a0, a0
1:
    la t3, digits
    addi t3, t3, DIGITS_BYTES
    li t4, 10
2:
    remu t5, a0, t4
    divu a0, a0, t4
    addi t5, t5, '0'
    addi t3, t3, -1
    sb t5, 0(t3)
    bnez a0, 2b
    la t5, digits
    addi t5, t5, DIGITS_BYTES
3:
    bgeu t3, t5, 4f
    lbu t6, 0(t3)
    add t4, t2, t1
    sb t6, 0(t4)
    addi t1, t1, 1
    addi t3, t3, 1
    j 3b
4:
    sd t1, 0(t0)
    ret

# line_end: the newline and the terminator, then the line to the UART.
line_end:
    la t0, line_len
    ld t1, 0(t0)
    la t2, line
    add t2, t2, t1
    li t3, '\n'
    sb t3, 0(t2)
    sb zero, 1(t2)
    sd zero, 0(t0)
    jab.uart.print line
    ret

.section .bss
.balign 8
line_len:
    .skip 8
line:
    .skip LINE_BYTES
digits:
    .skip DIGITS_BYTES
.balign 4
axis_record:
    .skip JAB_PAD_AXIS_ENTRY
state_record:
    .skip JAB_PAD_ENTRY
quit:
    .skip 1

.section .rodata
msg_ready:
    .asciz "pad: ready\n"
msg_no_pad:
    .asciz "pad: no pad\n"
msg_axis:
    .asciz "axis "
msg_none:
    .asciz " none"
msg_pad:
    .asciz "pad "
msg_state:
    .asciz "state "
msg_space:
    .asciz " "
