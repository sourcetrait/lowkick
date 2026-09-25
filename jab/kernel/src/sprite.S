.include "riscv.inc"
.include "jab.inc"

# Sprites: frames of native pixels the program owns, blended onto the
# framebuffer (jab.inc for the record). A draw walks the drawn
# rectangle, clipped to the screen, and for each of its pixels samples
# the nearest source pixel of the frame at the scale asked, so scaling
# up repeats pixels and scaling down skips them; a step from one drawn
# pixel to the next source one is fixed per draw in 16.16 fixed point,
# and at JAB_SPRITE_SCALE_ONE it is exactly one, so an unscaled draw is
# a plain copy of the frame. Per pixel the alpha decides: 0 is skipped,
# 255 copied, and anything between blended, each channel becoming
# (s * a + d * (255 - a)) / 255, rounded; the tint multiplies each of the
# sprite's channels by its own, over 255, first. Division by 255 is the
# exact shift form (x + 128 + ((x + 128) >> 8)) >> 8. The record and
# its pixels are read a byte at a time, so a sprite may sit anywhere.

# sprite_round255 reg, tmp: reg, a product of two bytes, becomes that
# product divided by 255 and rounded.
.macro sprite_round255 reg, tmp
    addi \reg, \reg, 128
    srli \tmp, \reg, 8
    add \reg, \reg, \tmp
    srli \reg, \reg, 8
.endm

.section .text

# sys_sprite_draw (jab.sprite.draw): a0 is the sprite record, a1 the
# frame, a2 x, a3 y (signed), a4 the tint, a5 the scale. a0 becomes 0;
# 1 when the frame is not in the sprite; 2 when the scale is past
# JAB_SPRITE_SCALE_MAX.
.global sys_sprite_draw
sys_sprite_draw:
    ld a0, 80(sp)
    li a1, JAB_SPRITE_PIXELS
    call buffer_bounds
    ld s0, 80(sp)
    addi a0, s0, JAB_SPRITE_WIDTH
    call sprite_le32
    mv s1, a0                   # the frame's width
    addi a0, s0, JAB_SPRITE_HEIGHT
    call sprite_le32
    mv s2, a0                   # the height
    addi a0, s0, JAB_SPRITE_FRAMES
    call sprite_le32
    mv s3, a0                   # the frames
    mul s4, s1, s3              # the sheet's width
    mul a1, s4, s2
    slli a1, a1, 2
    addi a0, s0, JAB_SPRITE_PIXELS
    call buffer_bounds
    ld t0, 88(sp)
    li a0, 1
    bgeu t0, s3, 9f
    mul t1, t0, s1
    slli t1, t1, 2
    addi s5, s0, JAB_SPRITE_PIXELS
    add s5, s5, t1              # the frame's top left pixel
    ld s6, 120(sp)
    li a0, 2
    li t0, JAB_SPRITE_SCALE_MAX
    bgtu s6, t0, 9f
    # the drawn size, and the step from a drawn pixel to its source
    mul s7, s1, s6
    srli s7, s7, 8              # the drawn width
    mul s8, s2, s6
    srli s8, s8, 8              # the drawn height
    li a0, 0
    beqz s7, 9f
    beqz s8, 9f
    slli t0, s1, 16
    divu s9, t0, s7             # a drawn column to a source one, 16.16
    slli t0, s2, 16
    divu s10, t0, s8            # a drawn row to a source one
    # the drawn rectangle, clipped to the screen
    ld s0, 96(sp)               # x
    ld s1, 104(sp)              # y
    mv s2, s0
    bgez s2, 1f
    li s2, 0
1:
    add s3, s0, s7
    li t0, JAB_DISPLAY_WIDTH
    ble s3, t0, 2f
    mv s3, t0
2:
    bge s2, s3, 9f              # nothing of it is on the screen
    mv s7, s1
    bgez s7, 3f
    li s7, 0
3:
    add s6, s1, s8
    li t0, JAB_DISPLAY_HEIGHT
    ble s6, t0, 4f
    mv s6, t0
4:
    bge s7, s6, 9f
    slli s4, s4, 2              # a source row, in bytes
    ld s11, 112(sp)             # the tint
    li t0, 0xffffff
    and t1, s11, t0
    xor s8, t1, t0              # 0 when the tint is white: nothing to do
    beqz s8, 5f
    srli t0, s11, 16
    andi t0, t0, 0xff
    la t1, sprite_tint_r
    sd t0, 0(t1)
    srli t0, s11, 8
    andi t0, t0, 0xff
    la t1, sprite_tint_g
    sd t0, 0(t1)
    andi t0, s11, 0xff
    la t1, sprite_tint_b
    sd t0, 0(t1)
5:
    # the rows: s7 the drawn row, s6 its end; s2 the first drawn column
    # and s3 the end; s0 and s1 where the frame's top left is; s5 the
    # frame's pixels, s4 a source row's bytes, s9 and s10 the steps, s8
    # whether to tint
    sub t0, s7, s1
    mul t0, t0, s10
    srli t0, t0, 16
    mul t0, t0, s4
    add a1, s5, t0              # the source row
    li t0, JAB_DISPLAY_PITCH
    mul t0, t0, s7
    slli t1, s2, 2
    add t0, t0, t1
    li t1, JAB_DISPLAY_BASE
    add a2, t0, t1              # the screen pixel
    mv a3, s2                   # the drawn column
6:
    sub t0, a3, s0
    mul t0, t0, s9
    srli t0, t0, 16
    slli t0, t0, 2
    add t0, a1, t0              # the source pixel
    lbu a7, 3(t0)               # alpha
    beqz a7, 8f
    lbu a4, 0(t0)               # blue
    lbu a5, 1(t0)               # green
    lbu a6, 2(t0)               # red
    beqz s8, 7f
    la t1, sprite_tint_b
    ld t1, 0(t1)
    mul a4, a4, t1
    sprite_round255 a4, t2
    la t1, sprite_tint_g
    ld t1, 0(t1)
    mul a5, a5, t1
    sprite_round255 a5, t2
    la t1, sprite_tint_r
    ld t1, 0(t1)
    mul a6, a6, t1
    sprite_round255 a6, t2
7:
    li t1, 255
    beq a7, t1, 71f
    # blended over what is there
    sub t1, t1, a7              # what the screen keeps
    lwu t2, 0(a2)
    andi t3, t2, 0xff           # its blue
    mul t3, t3, t1
    mul a4, a4, a7
    add a4, a4, t3
    sprite_round255 a4, t4
    srli t3, t2, 8
    andi t3, t3, 0xff           # green
    mul t3, t3, t1
    mul a5, a5, a7
    add a5, a5, t3
    sprite_round255 a5, t4
    srli t3, t2, 16
    andi t3, t3, 0xff           # red
    mul t3, t3, t1
    mul a6, a6, a7
    add a6, a6, t3
    sprite_round255 a6, t4
71:
    slli a6, a6, 16
    slli a5, a5, 8
    or a4, a4, a5
    or a4, a4, a6
    sw a4, 0(a2)
8:
    addi a2, a2, 4
    addi a3, a3, 1
    blt a3, s3, 6b
    addi s7, s7, 1
    blt s7, s6, 5b
    li a0, 0
9:
    sd a0, 80(sp)
    j trap_return

# sprite_le32: a0 is an address; a0 becomes the little-endian longword
# there, read a byte at a time.
sprite_le32:
    lbu t0, 0(a0)
    lbu t1, 1(a0)
    lbu t2, 2(a0)
    lbu t3, 3(a0)
    slli t1, t1, 8
    slli t2, t2, 16
    slli t3, t3, 24
    or t0, t0, t1
    or t0, t0, t2
    or a0, t0, t3
    ret

.section .bss
.balign 8
sprite_tint_r:
    .skip 8
sprite_tint_g:
    .skip 8
sprite_tint_b:
    .skip 8
