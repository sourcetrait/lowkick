# wasd: a sphere you drive and a sphere that bounces, Jab's input
# example with simple physics. W, A, S, and D push your sphere, harder
# the longer a key is held, up to three times the bouncing sphere's
# speed; with no key held it slows to a stop; the space bar stops it
# at once; the walls bounce it back at the speed it hit them, and so
# does the other sphere. The other sphere starts somewhere and bounces
# off the walls as in bounce, and off your sphere too. The two never
# overlap. Positions and speeds carry FIX fractional bits.
.include "jab.inc"

.set RADIUS, 90
.set BACKGROUND, 0x00101018
.set PLAYER, 0x00ff5533
# LowKick's own colour, the logo's
.set BALL, 0x008f00ff
# Where a centre may go, keeping the whole sphere on the screen
.set LEFT, RADIUS
.set RIGHT, (JAB_DISPLAY_WIDTH - 1 - RADIUS)
.set TOP, RADIUS
.set BOTTOM, (JAB_DISPLAY_HEIGHT - 1 - RADIUS)
.set FIX, 8
.set ONE, (1 << FIX)
# The bouncing sphere's speed, bounce's; the driven sphere's top speed
# three times that on each axis, how much a held key adds a frame, and
# how much a free axis loses a frame
.set BALL_VX, (7 * ONE)
.set BALL_VY, (5 * ONE)
.set TOP_SPEED, (26 * ONE)
.set ACCEL, (ONE * 4 / 5)
.set DECEL, (ONE / 2)
# The spheres have met when their centres are this close in pixels,
# squared, and are then set this far apart: two more than touching, so
# the drawn discs, at whole pixels, never share one
.set TOUCH_SQ, ((2 * RADIUS + 2) * (2 * RADIUS + 2))
.set APART, ((2 * RADIUS + 3) * ONE)

.section .text
.global _start
_start:
    jab.display.open
    bnez a0, no_display
    # the background over the whole framebuffer, two pixels a store,
    # shown whole once
    li t0, JAB_DISPLAY_BASE
    li t1, JAB_DISPLAY_BASE + JAB_DISPLAY_SIZE
    li t2, BACKGROUND
    slli t3, t2, 32
    or t2, t2, t3
1:
    sd t2, 0(t0)
    addi t0, t0, 8
    bltu t0, t1, 1b
    jab.display.flip
    # your sphere at the centre, still
    li t0, (JAB_DISPLAY_WIDTH / 2) * ONE
    la t1, player_x
    sd t0, 0(t1)
    li t0, (JAB_DISPLAY_HEIGHT / 2) * ONE
    la t1, player_y
    sd t0, 0(t1)
    # the other somewhere, from the clock
    rdtime t0
    li t1, JAB_DISPLAY_WIDTH - 2 * RADIUS
    remu t2, t0, t1
    addi t2, t2, RADIUS
    slli t2, t2, FIX
    la t1, ball_x
    sd t2, 0(t1)
    li t1, 7919
    divu t0, t0, t1
    li t1, JAB_DISPLAY_HEIGHT - 2 * RADIUS
    remu t2, t0, t1
    addi t2, t2, RADIUS
    slli t2, t2, FIX
    la t1, ball_y
    sd t2, 0(t1)
    li t0, BALL_VX
    la t1, ball_vx
    sd t0, 0(t1)
    li t0, BALL_VY
    la t1, ball_vy
    sd t0, 0(t1)
    call collide
    call remember
frame:
    jab.await
    mv s0, a0
    call read_keys
    andi t0, s0, JAB_AWAIT_DISPLAY
    beqz t0, frame
    call move_player
    call move_ball
    call collide
    call render
    j frame

no_display:
    jab.uart.print msg_no_display
    jab.exit 1

# read_keys: take every key event waiting. W, A, S, D set and clear
# their held flags; the space bar, pressed, stops your sphere.
read_keys:
    addi sp, sp, -16
    sd ra, 8(sp)
1:
    jab.keyboard.input
    beqz a0, 9f
    li t0, JAB_KEY_SPACE
    bne a0, t0, 2f
    li t0, JAB_KEY_PRESSED
    bne a1, t0, 1b
    la t0, player_vx
    sd zero, 0(t0)
    la t0, player_vy
    sd zero, 0(t0)
    j 1b
2:
    snez t1, a1
    li t0, JAB_KEY_W
    bne a0, t0, 3f
    la t2, held_w
    sb t1, 0(t2)
    j 1b
3:
    li t0, JAB_KEY_A
    bne a0, t0, 4f
    la t2, held_a
    sb t1, 0(t2)
    j 1b
4:
    li t0, JAB_KEY_S
    bne a0, t0, 5f
    la t2, held_s
    sb t1, 0(t2)
    j 1b
5:
    li t0, JAB_KEY_D
    bne a0, t0, 1b
    la t2, held_d
    sb t1, 0(t2)
    j 1b
9:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# drive: a0 is a speed, a1 whether the key that adds to it is held, a2
# whether the key that takes from it is; a0 becomes the speed a frame
# later: pushed, or slowed toward a stop, and held under TOP_SPEED.
drive:
    li t0, ACCEL
    beqz a1, 1f
    add a0, a0, t0
1:
    beqz a2, 2f
    sub a0, a0, t0
2:
    or t1, a1, a2
    bnez t1, 5f
    li t0, DECEL
    bgez a0, 3f
    add a0, a0, t0
    bgtz a0, 4f
    j 5f
3:
    sub a0, a0, t0
    bgez a0, 5f
4:
    li a0, 0
5:
    li t0, TOP_SPEED
    ble a0, t0, 6f
    mv a0, t0
6:
    li t0, -TOP_SPEED
    bge a0, t0, 7f
    mv a0, t0
7:
    ret

# wall: a0 is a position, a1 its speed, a2 the least centre, a3 the
# greatest, in pixels; a0 and a1 become the position a frame later and
# the speed, reversed when a wall was hit.
wall:
    add a0, a0, a1
    srai t0, a0, FIX
    bge t0, a2, 1f
    slli a0, a2, FIX
    neg a1, a1
    ret
1:
    ble t0, a3, 2f
    slli a0, a3, FIX
    neg a1, a1
2:
    ret

# clamp: a0 is a position, a1 the least centre and a2 the greatest in
# pixels; a0 becomes the position kept between them.
clamp:
    srai t0, a0, FIX
    bge t0, a1, 1f
    slli a0, a1, FIX
    ret
1:
    ble t0, a2, 2f
    slli a0, a2, FIX
2:
    ret

# isqrt: a0 becomes the whole square root of a0, rounded down.
isqrt:
    beqz a0, 3f
    mv t0, a0
1:
    divu t1, a0, t0
    add t1, t1, t0
    srli t1, t1, 1
    bgeu t1, t0, 2f
    mv t0, t1
    j 1b
2:
    mv a0, t0
3:
    ret

# move_player: your sphere's speed from the keys, then its position.
move_player:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, player_vx
    ld a0, 0(t0)
    la t0, held_d
    lbu a1, 0(t0)
    la t0, held_a
    lbu a2, 0(t0)
    call drive
    mv a1, a0
    la t0, player_x
    ld a0, 0(t0)
    li a2, LEFT
    li a3, RIGHT
    call wall
    la t0, player_x
    sd a0, 0(t0)
    la t0, player_vx
    sd a1, 0(t0)
    la t0, player_vy
    ld a0, 0(t0)
    la t0, held_s
    lbu a1, 0(t0)
    la t0, held_w
    lbu a2, 0(t0)
    call drive
    mv a1, a0
    la t0, player_y
    ld a0, 0(t0)
    li a2, TOP
    li a3, BOTTOM
    call wall
    la t0, player_y
    sd a0, 0(t0)
    la t0, player_vy
    sd a1, 0(t0)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# move_ball: the other sphere on, and off the walls.
move_ball:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, ball_x
    ld a0, 0(t0)
    la t0, ball_vx
    ld a1, 0(t0)
    li a2, LEFT
    li a3, RIGHT
    call wall
    la t0, ball_x
    sd a0, 0(t0)
    la t0, ball_vx
    sd a1, 0(t0)
    la t0, ball_y
    ld a0, 0(t0)
    la t0, ball_vy
    ld a1, 0(t0)
    li a2, TOP
    li a3, BOTTOM
    call wall
    la t0, ball_y
    sd a0, 0(t0)
    la t0, ball_vy
    sd a1, 0(t0)
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# collide: when the spheres have met, each one closing on the other
# has its speed reflected about the line between the centres, as off a
# wall, and the two are set apart along that line so they never
# overlap, kept on the screen.
collide:
    addi sp, sp, -64
    sd ra, 56(sp)
    sd s2, 48(sp)
    sd s3, 40(sp)
    sd s4, 32(sp)
    sd s5, 24(sp)
    sd s6, 16(sp)
    sd s7, 8(sp)
    la t0, player_x
    ld s2, 0(t0)
    la t0, player_y
    ld s3, 0(t0)
    la t0, ball_x
    ld s4, 0(t0)
    la t0, ball_y
    ld s5, 0(t0)
    # from your centre to the other: dx, dy, and the distance squared
    sub s6, s4, s2
    sub s7, s5, s3
    mul a5, s6, s6
    mul t0, s7, s7
    add a5, a5, t0
    li t0, TOUCH_SQ
    slli t0, t0, 2 * FIX
    bgt a5, t0, 9f
.ifdef DEBUG
    # a meeting, reported for the test to read: its outcome depends on
    # where the other sphere started, so a run that had one is judged
    # differently from one that did not
    jab.uart.print msg_meeting
.pushsection .rodata
msg_meeting:
    .asciz "wasd: meeting\n"
.popsection
.endif
    beqz a5, 3f
    # the other sphere, if closing: its speed's part along the line,
    # taken away twice
    la t0, ball_vx
    ld t5, 0(t0)
    la t0, ball_vy
    ld t6, 0(t0)
    mul a0, t5, s6
    mul a1, t6, s7
    add a0, a0, a1
    bgez a0, 1f
    slli a0, a0, 1
    mul a1, a0, s6
    div a1, a1, a5
    sub t5, t5, a1
    mul a1, a0, s7
    div a1, a1, a5
    sub t6, t6, a1
    la t0, ball_vx
    sd t5, 0(t0)
    la t0, ball_vy
    sd t6, 0(t0)
1:
    # yours, if closing, the same way
    la t0, player_vx
    ld t5, 0(t0)
    la t0, player_vy
    ld t6, 0(t0)
    mul a0, t5, s6
    mul a1, t6, s7
    add a0, a0, a1
    blez a0, 2f
    slli a0, a0, 1
    mul a1, a0, s6
    div a1, a1, a5
    sub t5, t5, a1
    mul a1, a0, s7
    div a1, a1, a5
    sub t6, t6, a1
    la t0, player_vx
    sd t5, 0(t0)
    la t0, player_vy
    sd t6, 0(t0)
2:
    # apart: half the shortfall each, along the line
    mv a0, a5
    call isqrt
    mv a4, a0
    j 4f
3:
    # centres together: apart along x
    li s6, ONE
    li s7, 0
    li a4, ONE
4:
    li t0, APART
    sub t0, t0, a4
    blez t0, 9f
    srai t0, t0, 1
    mul t1, s6, t0
    div t1, t1, a4
    mul t2, s7, t0
    div t2, t2, a4
    sub s2, s2, t1
    sub s3, s3, t2
    add s4, s4, t1
    add s5, s5, t2
    mv a0, s2
    li a1, LEFT
    li a2, RIGHT
    call clamp
    la t0, player_x
    sd a0, 0(t0)
    mv a0, s3
    li a1, TOP
    li a2, BOTTOM
    call clamp
    la t0, player_y
    sd a0, 0(t0)
    mv a0, s4
    li a1, LEFT
    li a2, RIGHT
    call clamp
    la t0, ball_x
    sd a0, 0(t0)
    mv a0, s5
    li a1, TOP
    li a2, BOTTOM
    call clamp
    la t0, ball_y
    sd a0, 0(t0)
9:
    ld ra, 56(sp)
    ld s2, 48(sp)
    ld s3, 40(sp)
    ld s4, 32(sp)
    ld s5, 24(sp)
    ld s6, 16(sp)
    ld s7, 8(sp)
    addi sp, sp, 64
    ret

# render: erase both spheres where they were, draw them where they are,
# and flip the one rectangle holding all four squares.
render:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, old_player_x
    ld a0, 0(t0)
    la t0, old_player_y
    ld a1, 0(t0)
    li a2, BACKGROUND
    call fill_square
    la t0, old_ball_x
    ld a0, 0(t0)
    la t0, old_ball_y
    ld a1, 0(t0)
    li a2, BACKGROUND
    call fill_square
    la t0, ball_x
    ld a0, 0(t0)
    srai a0, a0, FIX
    la t0, ball_y
    ld a1, 0(t0)
    srai a1, a1, FIX
    li a2, BALL
    call draw_disc
    la t0, player_x
    ld a0, 0(t0)
    srai a0, a0, FIX
    la t0, player_y
    ld a1, 0(t0)
    srai a1, a1, FIX
    li a2, PLAYER
    call draw_disc
    # the rectangle: the least and greatest centres, less and plus the
    # radius
    la t0, old_player_x
    ld a0, 0(t0)
    la t0, old_ball_x
    ld t1, 0(t0)
    la t0, player_x
    ld t2, 0(t0)
    srai t2, t2, FIX
    la t0, ball_x
    ld t3, 0(t0)
    srai t3, t3, FIX
    mv a2, a0
    call least_greatest
    addi a0, a0, -RADIUS
    addi a2, a2, RADIUS + 1
    sub a2, a2, a0
    mv s2, a0
    mv s3, a2
    la t0, old_player_y
    ld a0, 0(t0)
    la t0, old_ball_y
    ld t1, 0(t0)
    la t0, player_y
    ld t2, 0(t0)
    srai t2, t2, FIX
    la t0, ball_y
    ld t3, 0(t0)
    srai t3, t3, FIX
    mv a2, a0
    call least_greatest
    addi a1, a0, -RADIUS
    addi a3, a2, RADIUS + 1
    sub a3, a3, a1
    mv a0, s2
    mv a2, s3
    jab.display.flip.rect
    call remember
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# least_greatest: a0 becomes the least of a0, t1, t2, t3 and a2 the
# greatest of a2, t1, t2, t3.
least_greatest:
    bge t1, a0, 1f
    mv a0, t1
1:
    bge t2, a0, 2f
    mv a0, t2
2:
    bge t3, a0, 3f
    mv a0, t3
3:
    ble t1, a2, 4f
    mv a2, t1
4:
    ble t2, a2, 5f
    mv a2, t2
5:
    ble t3, a2, 6f
    mv a2, t3
6:
    ret

# remember: where the spheres are now, in pixels, to erase next frame.
remember:
    la t0, player_x
    ld t1, 0(t0)
    srai t1, t1, FIX
    la t0, old_player_x
    sd t1, 0(t0)
    la t0, player_y
    ld t1, 0(t0)
    srai t1, t1, FIX
    la t0, old_player_y
    sd t1, 0(t0)
    la t0, ball_x
    ld t1, 0(t0)
    srai t1, t1, FIX
    la t0, old_ball_x
    sd t1, 0(t0)
    la t0, ball_y
    ld t1, 0(t0)
    srai t1, t1, FIX
    la t0, old_ball_y
    sd t1, 0(t0)
    ret

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

# draw_disc: the disc of RADIUS around (a0, a1) in the colour a2.
draw_disc:
    li t0, -RADIUS
    li t6, RADIUS
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
    sw a2, 0(a4)
3:
    addi t2, t2, 1
    ble t2, t6, 2b
    addi t0, t0, 1
    ble t0, t6, 1b
    ret

.section .bss
.balign 8
player_x:
    .skip 8
player_y:
    .skip 8
player_vx:
    .skip 8
player_vy:
    .skip 8
ball_x:
    .skip 8
ball_y:
    .skip 8
ball_vx:
    .skip 8
ball_vy:
    .skip 8
old_player_x:
    .skip 8
old_player_y:
    .skip 8
old_ball_x:
    .skip 8
old_ball_y:
    .skip 8
held_w:
    .skip 1
held_a:
    .skip 1
held_s:
    .skip 1
held_d:
    .skip 1

.section .rodata
msg_no_display:
    .asciz "wasd: no display\n"
