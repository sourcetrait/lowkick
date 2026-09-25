# walk: a large busy sidewalk. The walker sprite, sixteen frames of a
# walk cycle, loads off the romfs straight from its directory; then
# eight horizontal lanes carry walkers, each entering from a random
# side of the screen, in a random colour, at a random size from five
# feet to seven if the frame is six, walking to the other side and
# leaving. A lane holds up to a few walkers at once: when the side
# chosen for a new one is clear, no walker in the lane within a stride
# of that edge, one enters, at once for an empty lane and otherwise
# after a random wait, so the crowd staggers. A walker entering from
# the right is the same frames mirrored. The screen stays black, as
# the framebuffer starts. Each frame tick: every walker is erased,
# moved, and its animation stepped, then every one is drawn top lane
# to bottom so nearer walkers cover farther ones, and the screen is
# flipped whole. Over the API, when a run has it, a record per walker
# that enters and per walker that leaves, for the test.
.include "jab.inc"

.set DISK, 1
.set FRAME_W, 480
.set FRAME_H, 640
.set FRAMES, 16
.set SPRITE_BYTES, (JAB_SPRITE_PIXELS + FRAMES * (FRAME_W * FRAME_H * 4 + FRAME_H))
.set LANES, 8
.set LANE_H, (JAB_DISPLAY_HEIGHT / LANES)
.set PER_LANE, 3
# a six-foot walker at a quarter of the frame is 160 pixels; five feet
# to seven, in 256ths
.set SCALE_MIN, 53
.set SCALE_MAX, 75
# astra's stride: pixels of travel a cycle at the frame's own size
.set STRIDE, 312
# a new walker needs this much clear at its edge, and another one after
# the first waits a random number of ticks up to this
.set ENTRY_GAP, 240
.set ENTRY_WAIT, 128
# the animation steps every so many display ticks, about sixteen a
# second
.set TICKS_PER_FRAME, 2
.set BACKGROUND, 0x00000000
# a walker's record
.set W_X, 0                     # the left edge, in 256ths of a pixel
.set W_DIR, 8                   # 1 walking right, -1 walking left
.set W_SCALE, 16
.set W_TINT, 24
.set W_FRAME, 32
.set W_TICK, 40
.set W_DW, 48                   # the drawn size
.set W_DH, 56
.set W_Y, 64                    # the top, the feet on the lane's floor
.set W_ACTIVE, 72
.set W_SPEED, 80                # 256ths of a pixel a tick
.set W_SIZE, 88
# a lane: its walkers, and the ticks until it may take another
.set LANE_WAIT, (PER_LANE * W_SIZE)
.set LANE_SIZE, (LANE_WAIT + 8)
# the API's records: entered (1) and left (2)
.set R_KIND, 0
.set R_LANE, 1
.set R_SIDE, 2
.set R_SCALE, 3
.set R_TINT, 4
.set R_SIZE, 8

.section .text
.global _start
_start:
    la t0, sprite
    li t1, DISK
    jab.sprite.load t0, t1, path_walker, SPRITE_BYTES
    bnez a0, bad_sprite
    jab.display.open
    bnez a0, no_display
    # the seed, never zero
    rdtime t0
    ori t0, t0, 1
    la t1, seed
    sd t0, 0(t1)
frame:
    jab.display.await
    # every lane: its walkers moved along, and one in when there is room
    li s0, 0
2:
    li t0, LANE_SIZE
    mul t0, t0, s0
    la s2, lanes
    add s2, s2, t0              # the lane
    li s3, 0
3:
    li t0, W_SIZE
    mul t0, t0, s3
    add s1, s2, t0              # the walker
    ld t0, W_ACTIVE(s1)
    beqz t0, 5f
    # erase where it was
    ld a0, W_X(s1)
    srai a0, a0, 8
    ld a1, W_Y(s1)
    ld a2, W_DW(s1)
    ld a3, W_DH(s1)
    li a4, BACKGROUND
    call fill_rect
    # move, and step the animation
    ld t0, W_X(s1)
    ld t1, W_SPEED(s1)
    ld t2, W_DIR(s1)
    mul t1, t1, t2
    add t0, t0, t1
    sd t0, W_X(s1)
    ld t1, W_TICK(s1)
    addi t1, t1, 1
    li t2, TICKS_PER_FRAME
    bltu t1, t2, 4f
    li t1, 0
    ld t3, W_FRAME(s1)
    addi t3, t3, 1
    li t4, FRAMES
    bltu t3, t4, 31f
    li t3, 0
31:
    sd t3, W_FRAME(s1)
4:
    sd t1, W_TICK(s1)
    # off the far side: the place is free
    srai t0, t0, 8
    ld t2, W_DIR(s1)
    bltz t2, 41f
    li t3, JAB_DISPLAY_WIDTH
    blt t0, t3, 5f
    j 42f
41:
    ld t3, W_DW(s1)
    add t0, t0, t3
    bgtz t0, 5f
42:
    sd zero, W_ACTIVE(s1)
    mv a0, s0
    call leave
5:
    addi s3, s3, 1
    li t0, PER_LANE
    bltu s3, t0, 3b
    mv a0, s2
    mv a1, s0
    call admit
    addi s0, s0, 1
    li t0, LANES
    bltu s0, t0, 2b
    # every walker, top lane first
    li s0, 0
6:
    li t0, LANE_SIZE
    mul t0, t0, s0
    la s2, lanes
    add s2, s2, t0
    li s3, 0
7:
    li t0, W_SIZE
    mul t0, t0, s3
    add s1, s2, t0
    ld t0, W_ACTIVE(s1)
    beqz t0, 8f
    ld t1, W_FRAME(s1)
    ld t2, W_X(s1)
    srai t2, t2, 8
    ld t3, W_Y(s1)
    ld t4, W_TINT(s1)
    ld t5, W_SCALE(s1)
    ld t6, W_DIR(s1)
    bgez t6, 71f
    li t6, JAB_SPRITE_FLIP_H
    j 72f
71:
    li t6, 0
72:
    la t0, sprite
    jab.sprite.draw t0, t1, t2, t3, t4, t5, t6
8:
    addi s3, s3, 1
    li t0, PER_LANE
    bltu s3, t0, 7b
    addi s0, s0, 1
    li t0, LANES
    bltu s0, t0, 6b
    jab.display.flip
    j frame

bad_sprite:
    # the code, one or two digits, after the message
    la t0, msg_bad_sprite_code
    li t1, 10
    divu t2, a0, t1
    remu t3, a0, t1
    beqz t2, 1f
    addi t2, t2, '0'
    sb t2, 0(t0)
    addi t0, t0, 1
1:
    addi t3, t3, '0'
    sb t3, 0(t0)
    li t3, '\n'
    sb t3, 1(t0)
    sb zero, 2(t0)
    jab.uart.print msg_bad_sprite
    jab.exit 1
no_display:
    jab.uart.print msg_no_display
    jab.exit 1

# admit: a0 is a lane and a1 its number. A new walker enters when the
# lane has a free place, its wait is over, and the side chosen is
# clear; an empty lane takes one at once, and after each entry the lane
# waits a random number of ticks before the next.
admit:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    # a free place, and whether the lane is empty
    li t1, 0                    # the place
    li t2, -1                   # the free one
    li t3, 0                    # how many are walking
1:
    li t0, W_SIZE
    mul t0, t0, t1
    add t0, t0, a0
    ld t4, W_ACTIVE(t0)
    beqz t4, 11f
    addi t3, t3, 1
    j 12f
11:
    bgez t2, 12f
    mv t2, t1
12:
    addi t1, t1, 1
    li t0, PER_LANE
    bltu t1, t0, 1b
    bltz t2, 9f                 # every place taken
    sd t2, 16(sp)
    beqz t3, 2f                 # an empty lane waits for nothing
    ld t0, LANE_WAIT(a0)
    beqz t0, 2f
    addi t0, t0, -1
    sd t0, LANE_WAIT(a0)
    j 9f
2:
    call random
    andi t5, a0, 1
    sd t5, 24(sp)               # the side, 0 the left
    # clear at that edge: no walker within the gap of it
    ld a0, 0(sp)
    li t1, 0
3:
    li t0, W_SIZE
    mul t0, t0, t1
    add t0, t0, a0
    ld t4, W_ACTIVE(t0)
    beqz t4, 4f
    ld t4, W_X(t0)
    srai t4, t4, 8
    ld t5, 24(sp)
    bnez t5, 31f
    li t6, ENTRY_GAP
    blt t4, t6, 9f              # too near the left edge
    j 4f
31:
    ld t6, W_DW(t0)
    add t4, t4, t6
    li t6, JAB_DISPLAY_WIDTH - ENTRY_GAP
    bgt t4, t6, 9f              # too near the right edge
4:
    addi t1, t1, 1
    li t0, PER_LANE
    bltu t1, t0, 3b
    # in it comes
    ld t2, 16(sp)
    li t0, W_SIZE
    mul t0, t0, t2
    ld a0, 0(sp)
    add a0, a0, t0
    ld a1, 8(sp)
    ld a2, 24(sp)
    call enter
    call random
    li t1, ENTRY_WAIT
    remu t0, a0, t1
    ld a0, 0(sp)
    sd t0, LANE_WAIT(a0)
9:
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# enter: a0 is a walker's record, a1 the lane, a2 the side, 0 the
# left. Its colour with every channel bright enough to see, its size,
# and the frame it starts on are random; its speed follows its size.
enter:
    addi sp, sp, -32
    sd ra, 24(sp)
    sd a0, 0(sp)
    sd a1, 8(sp)
    sd a2, 16(sp)
    call random
    li t1, SCALE_MAX - SCALE_MIN + 1
    remu t0, a0, t1
    addi t0, t0, SCALE_MIN
    ld a1, 0(sp)
    sd t0, W_SCALE(a1)
    call random
    li t1, 192
    remu t2, a0, t1
    addi t2, t2, 64
    slli t2, t2, 16
    srli a0, a0, 8
    remu t3, a0, t1
    addi t3, t3, 64
    slli t3, t3, 8
    or t2, t2, t3
    srli a0, a0, 8
    remu t3, a0, t1
    addi t3, t3, 64
    or t2, t2, t3
    ld a1, 0(sp)
    sd t2, W_TINT(a1)
    call random
    li t1, FRAMES
    remu t0, a0, t1
    ld a1, 0(sp)
    sd t0, W_FRAME(a1)
    sd zero, W_TICK(a1)
    ld t0, W_SCALE(a1)
    li t1, FRAME_W
    mul t1, t1, t0
    srli t1, t1, 8
    sd t1, W_DW(a1)
    li t2, FRAME_H
    mul t2, t2, t0
    srli t2, t2, 8
    sd t2, W_DH(a1)
    ld t3, 8(sp)
    addi t3, t3, 1
    li t4, LANE_H
    mul t3, t3, t4
    sub t3, t3, t2
    sd t3, W_Y(a1)
    li t3, STRIDE
    mul t3, t3, t0
    srli t3, t3, 5
    sd t3, W_SPEED(a1)
    ld t0, 16(sp)
    bnez t0, 1f
    neg t1, t1
    slli t1, t1, 8
    sd t1, W_X(a1)
    li t2, 1
    sd t2, W_DIR(a1)
    j 2f
1:
    li t1, JAB_DISPLAY_WIDTH
    slli t1, t1, 8
    sd t1, W_X(a1)
    li t2, -1
    sd t2, W_DIR(a1)
2:
    li t0, 1
    sd t0, W_ACTIVE(a1)
    # the record for the host
    la t0, record
    li t1, 1
    sb t1, R_KIND(t0)
    ld t1, 8(sp)
    sb t1, R_LANE(t0)
    ld t1, 16(sp)
    sb t1, R_SIDE(t0)
    ld t1, W_SCALE(a1)
    sb t1, R_SCALE(t0)
    ld t1, W_TINT(a1)
    sw t1, R_TINT(t0)
    la t0, record
    li t1, R_SIZE
    jab.api.write t0, t1
    ld ra, 24(sp)
    addi sp, sp, 32
    ret

# leave: a0 is the lane; a record for the host.
leave:
    addi sp, sp, -16
    sd ra, 8(sp)
    la t0, record
    li t1, 2
    sb t1, R_KIND(t0)
    sb a0, R_LANE(t0)
    sb zero, R_SIDE(t0)
    sb zero, R_SCALE(t0)
    sw zero, R_TINT(t0)
    la t0, record
    li t1, R_SIZE
    jab.api.write t0, t1
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

# random: a0 becomes the next of an xorshift sequence from the seed.
random:
    la t0, seed
    ld t1, 0(t0)
    slli t2, t1, 13
    xor t1, t1, t2
    srli t2, t1, 7
    xor t1, t1, t2
    slli t2, t1, 17
    xor t1, t1, t2
    sd t1, 0(t0)
    mv a0, t1
    ret

# fill_rect: the rectangle at a0, a1 of a2 by a3 pixels in the colour
# a4, whatever of it is on the screen.
fill_rect:
    add t0, a0, a2              # the right edge
    add t1, a1, a3              # the bottom
    bgez a0, 1f
    li a0, 0
1:
    li t2, JAB_DISPLAY_WIDTH
    ble t0, t2, 2f
    mv t0, t2
2:
    bge a0, t0, 9f
    bgez a1, 3f
    li a1, 0
3:
    li t2, JAB_DISPLAY_HEIGHT
    ble t1, t2, 4f
    mv t1, t2
4:
    bge a1, t1, 9f
    sub t2, t0, a0              # the columns
    li t3, JAB_DISPLAY_PITCH
    mul t3, t3, a1
    slli t4, a0, 2
    add t3, t3, t4
    li t4, JAB_DISPLAY_BASE
    add t3, t3, t4              # the first pixel of the first row
5:
    mv t4, t3
    mv t5, t2
6:
    sw a4, 0(t4)
    addi t4, t4, 4
    addi t5, t5, -1
    bnez t5, 6b
    li t4, JAB_DISPLAY_PITCH
    add t3, t3, t4
    addi a1, a1, 1
    blt a1, t1, 5b
9:
    ret

.section .rodata
path_walker:
    .asciz "/walker"
msg_no_display:
    .asciz "walk: no display\n"

.section .data
msg_bad_sprite:
    .ascii "walk: the walker would not load, code "
msg_bad_sprite_code:
    .skip 4

.section .bss
.balign 8
seed:
    .skip 8
record:
    .skip R_SIZE
lanes:
    .skip LANES * LANE_SIZE
sprite:
    .skip SPRITE_BYTES
