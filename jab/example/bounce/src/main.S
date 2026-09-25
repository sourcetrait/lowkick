# bounce: a ball bouncing around the display, Jab's display example.
# Opens the display, paints the background once, then each frame waits
# for the tick, erases the ball, moves it, draws it, and flips. Runs
# until the window closes.
.include "jab.inc"

.set RADIUS, 90
.set BACKGROUND, 0x00101018
.set BALL, 0x00ff5533
# Where the centre may go, keeping the whole ball on the screen
.set LEFT, RADIUS
.set RIGHT, (JAB_DISPLAY_WIDTH - 1 - RADIUS)
.set TOP, RADIUS
.set BOTTOM, (JAB_DISPLAY_HEIGHT - 1 - RADIUS)

.section .text
.global _start
_start:
    jab.display.open
    bnez a0, no_display
    # the background over the whole framebuffer, two pixels a store
    li t0, JAB_DISPLAY_BASE
    li t1, JAB_DISPLAY_BASE + JAB_DISPLAY_SIZE
    li t2, BACKGROUND
    slli t3, t2, 32
    or t2, t2, t3
1:
    sd t2, 0(t0)
    addi t0, t0, 8
    bltu t0, t1, 1b
    # the ball's centre, and its speed in pixels per frame
    li s0, 200
    li s1, 200
    li s2, 7
    li s3, 5
frame:
    jab.display.await
    mv a0, s0
    mv a1, s1
    li a2, BACKGROUND
    call fill_square
    add s0, s0, s2
    add s1, s1, s3
    li t0, LEFT
    bge s0, t0, 1f
    mv s0, t0
    neg s2, s2
1:
    li t0, RIGHT
    ble s0, t0, 2f
    mv s0, t0
    neg s2, s2
2:
    li t0, TOP
    bge s1, t0, 3f
    mv s1, t0
    neg s3, s3
3:
    li t0, BOTTOM
    ble s1, t0, 4f
    mv s1, t0
    neg s3, s3
4:
    mv a0, s0
    mv a1, s1
    call draw_ball
    jab.display.flip
    j frame

no_display:
    jab.uart.print msg_no_display
    jab.exit 1

# fill_square: the square of side 2 * RADIUS + 1 around (a0, a1) in the
# colour a2.
fill_square:
    li t0, -RADIUS
    li t6, RADIUS
1:
    add t1, a1, t0
    li t2, JAB_DISPLAY_PITCH
    mul t1, t1, t2
    addi t2, a0, -RADIUS
    slli t2, t2, 2
    add t1, t1, t2
    li t2, JAB_DISPLAY_BASE
    add t1, t1, t2
    li t3, 2 * RADIUS + 1
2:
    sw a2, 0(t1)
    addi t1, t1, 4
    addi t3, t3, -1
    bnez t3, 2b
    addi t0, t0, 1
    ble t0, t6, 1b
    ret

# draw_ball: the disc of RADIUS around (a0, a1) in BALL.
draw_ball:
    li t0, -RADIUS
    li t6, RADIUS
    li t5, BALL
    li a3, RADIUS * RADIUS
1:
    add t1, a1, t0
    li t2, JAB_DISPLAY_PITCH
    mul t1, t1, t2
    li t2, JAB_DISPLAY_BASE
    add t1, t1, t2
    slli t2, a0, 2
    add t1, t1, t2
    mul t4, t0, t0
    li t2, -RADIUS
2:
    mul t3, t2, t2
    add t3, t3, t4
    bgt t3, a3, 3f
    slli a4, t2, 2
    add a4, a4, t1
    sw t5, 0(a4)
3:
    addi t2, t2, 1
    ble t2, t6, 2b
    addi t0, t0, 1
    ble t0, t6, 1b
    ret

.section .rodata
msg_no_display:
    .asciz "bounce: no display\n"
