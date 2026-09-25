.include "riscv.inc"
.include "jab.inc"

# Sprites: frames of native pixels the program owns, blended onto the
# framebuffer (jab.inc for the record). A draw walks the drawn
# rectangle, clipped to the screen, and for each of its pixels samples
# the nearest source pixel of the frame at the scale asked, so scaling
# up repeats pixels and scaling down skips them; a step from one drawn
# pixel to the next source one is fixed per draw in 16.16 fixed point,
# and at JAB_SPRITE_SCALE_ONE it is exactly one, so an unscaled draw is
# a plain copy of the frame. A spanned record, one the kernel decoded,
# carries each row's first and last opaque column, and the unturned
# draw walks only the drawn columns those map to, so a thin figure in
# a wide frame costs its own pixels rather than the frame's. The pose
# mirrors and turns: a flip reads the frame's columns or rows from the
# far end, and an angle turns the scaled frame about its centre, the
# draw then walking the turned rectangle's bounding box and mapping
# each pixel of it back through the inverse turn, in 16.16 with a sine
# table, to the source pixel under it or to nothing. Per pixel the
# alpha decides: 0 is skipped, 255 copied, and anything between
# blended, each channel becoming (s * a + d * (255 - a)) / 255,
# rounded; the tint multiplies each of the sprite's channels by its
# own, over 255, first, and a white pixel takes the tint outright,
# which is the same number. Division by 255 is the exact shift form
# (x + 128 + ((x + 128) >> 8)) >> 8. A solid draw writes the tint over
# every pixel the frame covers, a row's span or the whole row, reading
# no source pixel at all, which is how a program clears the shape it
# drew a frame ago. The record and its pixels are read a byte at a
# time, so a sprite may sit anywhere.

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
# frame, a2 x, a3 y (signed), a4 the tint, a5 the scale, a6 the pose.
# a0 becomes 0; 1 when the frame is not in the sprite; 2 when the scale
# is past JAB_SPRITE_SCALE_MAX.
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
    addi a0, s0, JAB_SPRITE_FLAGS
    call sprite_le32
    la t0, sprite_flags
    sd a0, 0(t0)
    mul s4, s1, s2
    slli s4, s4, 2              # a frame's bytes
    mul a1, s4, s3
    addi a0, s0, JAB_SPRITE_PIXELS
    call buffer_bounds
    ld t0, 88(sp)
    li a0, 1
    bgeu t0, s3, 9f
    mul t1, t0, s4
    addi s5, s0, JAB_SPRITE_PIXELS
    add s5, s5, t1              # the frame's first pixel
    # the span table, after every frame's pixels, and this frame's rows
    # of it
    la t1, sprite_flags
    ld t1, 0(t1)
    andi t1, t1, JAB_SPRITE_SPANNED
    beqz t1, 1f
    mul t1, s4, s3
    addi t1, t1, JAB_SPRITE_PIXELS
    add a0, s0, t1
    mul a1, s2, s3
    slli a1, a1, 2
    call buffer_bounds
    ld t0, 88(sp)
    mul t0, t0, s2
    slli t0, t0, 2
    add a0, a0, t0
    la t1, sprite_spans_row
    sd a0, 0(t1)
1:
    ld s6, 120(sp)              # the scale
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
    la t0, sprite_stepabs
    sd s9, 0(t0)
    # what a flip reads from: the frame's last column and row
    addi t0, s1, -1
    la t1, sprite_last_col
    sd t0, 0(t1)
    addi t0, s2, -1
    la t1, sprite_last_row
    sd t0, 0(t1)
    # the pose: the flips, whether the draw is solid, and the angle
    # brought into a turn
    ld t0, 128(sp)
    srli t1, t0, 16
    andi t2, t1, 3
    la t3, sprite_flips
    sd t2, 0(t3)
    andi t2, t1, 4
    la t3, sprite_solid
    sd t2, 0(t3)
    li t1, 0xffff
    and t0, t0, t1
    li t1, 360
    remu t0, t0, t1
    la t2, sprite_angle
    sd t0, 0(t2)
    # the tint's channels, or a mark that there is no tinting; the tint
    # whole is what a solid draw writes
    ld s11, 112(sp)
    li t0, 0xffffff
    and t1, s11, t0
    la t2, sprite_solid_word
    sd t1, 0(t2)
    xor t1, t1, t0              # 0 when the tint is white
    la t2, sprite_tinted
    sd t1, 0(t2)
    beqz t1, 2f
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
2:
    slli s4, s1, 2              # a source row's bytes
    la t0, sprite_angle
    ld t0, 0(t0)
    bnez t0, sprite_turned
    # unturned: the drawn rectangle, clipped to the screen
    ld s0, 96(sp)               # x
    ld s1, 104(sp)              # y
    la t0, sprite_x
    sd s0, 0(t0)
    mv s2, s0
    bgez s2, 3f
    li s2, 0
3:
    add s3, s0, s7
    li t0, JAB_DISPLAY_WIDTH
    ble s3, t0, 4f
    mv s3, t0
4:
    bge s2, s3, 9f              # nothing of it is on the screen
    mv s7, s1
    bgez s7, 5f
    li s7, 0
5:
    add s6, s1, s8
    li t0, JAB_DISPLAY_HEIGHT
    ble s6, t0, 6f
    mv s6, t0
6:
    bge s7, s6, 9f
    # The source position runs along with the drawn one as a 16.16
    # accumulator, a step a pixel; a flip runs it backwards from the
    # frame's far edge, since (last + 1) * 65536 - 1 - n * step, shifted
    # down, is last - (n * step shifted down) for every n.
    sub t0, s2, s0
    mul s0, t0, s9              # the first drawn column's source column
    la t0, sprite_flips
    ld t0, 0(t0)
    andi t1, t0, 1
    beqz t1, 61f
    la t1, sprite_last_col
    ld t1, 0(t1)
    addi t1, t1, 1
    slli t1, t1, 16
    addi t1, t1, -1
    sub s0, t1, s0
    neg s9, s9
61:
    sub t1, s7, s1
    mul s1, t1, s10             # the first drawn row's source row
    andi t1, t0, 2
    beqz t1, 62f
    la t1, sprite_last_row
    ld t1, 0(t1)
    addi t1, t1, 1
    slli t1, t1, 16
    addi t1, t1, -1
    sub s1, t1, s1
    neg s10, s10
62:
    sub s3, s3, s2              # the drawn columns
    sub s6, s6, s7              # and rows
    li t0, JAB_DISPLAY_PITCH
    mul t0, t0, s7
    slli t1, s2, 2
    add t0, t0, t1
    li t1, JAB_DISPLAY_BASE
    mv s7, s2                   # the first drawn column
    add s2, t0, t1              # the row's first screen pixel
    # the rows: s6 left, s2 the screen row, s1 the source row's
    # position, s11 the source row, s7 the first drawn column and s3
    # how many; the pixels: s8 left, a2 the screen pixel, a3 the source
    # column's position, a1 the source pixel
7:
    srli t0, s1, 16
    mul t1, t0, s4
    add s11, s5, t1
    la t1, sprite_flags
    ld t1, 0(t1)
    andi t1, t1, JAB_SPRITE_SPANNED
    beqz t1, 75f
    # the row's span: its first and last opaque columns, mirrored for a
    # flip, then the drawn columns whose source columns fall inside it,
    # the first at or past the span's first and the end past its last,
    # clipped to what is on the screen
    la t1, sprite_spans_row
    ld t1, 0(t1)
    slli t2, t0, 2
    add t1, t1, t2
    lbu t2, 0(t1)
    lbu t3, 1(t1)
    slli t3, t3, 8
    or t2, t2, t3               # the first
    lbu t3, 2(t1)
    lbu t4, 3(t1)
    slli t4, t4, 8
    or t3, t3, t4               # the last
    bgtu t2, t3, 8f             # a row with nothing in it
    la t4, sprite_flips
    ld t4, 0(t4)
    andi t4, t4, 1
    beqz t4, 71f
    la t4, sprite_last_col
    ld t4, 0(t4)
    sub t5, t4, t3
    sub t3, t4, t2
    mv t2, t5
71:
    la t4, sprite_stepabs
    ld t4, 0(t4)
    slli t2, t2, 16
    add t2, t2, t4
    addi t2, t2, -1
    divu t2, t2, t4             # the first drawn column, from x
    addi t3, t3, 1
    slli t3, t3, 16
    add t3, t3, t4
    addi t3, t3, -1
    divu t3, t3, t4             # the end, from x
    la t4, sprite_x
    ld t4, 0(t4)
    add t2, t2, t4
    add t3, t3, t4
    bge t2, s7, 72f
    mv t2, s7
72:
    add t4, s7, s3
    ble t3, t4, 73f
    mv t3, t4
73:
    bge t2, t3, 8f
    sub s8, t3, t2              # the pixels
    sub t4, t2, s7              # how far in the row starts
    mul a3, t4, s9
    add a3, a3, s0
    slli t4, t4, 2
    add a2, s2, t4
    j 76f
75:
    mv a2, s2
    mv a3, s0
    mv s8, s3
76:
    la t0, sprite_solid
    ld t0, 0(t0)
    bnez t0, 78f
761:
    srli t0, a3, 16
    slli t0, t0, 2
    add a1, s11, t0
    lbu a7, 3(a1)
    beqz a7, 77f
    call sprite_blend
77:
    add a3, a3, s9
    addi a2, a2, 4
    addi s8, s8, -1
    bnez s8, 761b
    j 8f
78:
    # solid: the tint over every pixel of the row's stretch, no source
    # read at all
    la t0, sprite_solid_word
    ld t0, 0(t0)
79:
    sw t0, 0(a2)
    addi a2, a2, 4
    addi s8, s8, -1
    bnez s8, 79b
8:
    add s1, s1, s10
    li t0, JAB_DISPLAY_PITCH
    add s2, s2, t0
    addi s6, s6, -1
    bnez s6, 7b
    li a0, 0
9:
    sd a0, 80(sp)
    j trap_return

# The turned draw: the scaled frame's centre in 16.16, the sine and
# cosine of the angle, the half sizes and the size of the drawn
# rectangle, then its bounding box on the screen; each pixel of the box
# is taken back through the inverse turn to where it sits on the
# unturned frame, and sampled when that is inside it.
sprite_turned:
    ld s0, 96(sp)               # x
    ld s1, 104(sp)              # y
    slli t0, s7, 15
    la t1, sprite_hw
    sd t0, 0(t1)                # half the drawn width, 16.16
    slli t1, s0, 16
    add t1, t1, t0
    mv s0, t1                   # the centre's x, 16.16
    slli t0, s7, 16
    la t1, sprite_dw16
    sd t0, 0(t1)
    slli t0, s8, 15
    la t1, sprite_hh
    sd t0, 0(t1)
    slli t1, s1, 16
    add t1, t1, t0
    mv s1, t1                   # the centre's y
    slli t0, s8, 16
    la t1, sprite_dh16
    sd t0, 0(t1)
    la t0, sprite_angle
    ld a0, 0(t0)
    call sprite_trig
    la t0, sprite_sin
    sd a0, 0(t0)
    la t0, sprite_cos
    sd a1, 0(t0)
    # how far the turned corners reach from the centre
    la t0, sprite_hw
    ld t0, 0(t0)
    la t1, sprite_hh
    ld t1, 0(t1)
    mul t2, t0, a1              # hw cos
    bgez t2, 1f
    neg t2, t2
1:
    srai t2, t2, 16
    mul t3, t1, a0              # hh sin
    bgez t3, 2f
    neg t3, t3
2:
    srai t3, t3, 16
    add t2, t2, t3              # the reach in x
    mul t3, t0, a0              # hw sin
    bgez t3, 3f
    neg t3, t3
3:
    srai t3, t3, 16
    mul t4, t1, a1              # hh cos
    bgez t4, 4f
    neg t4, t4
4:
    srai t4, t4, 16
    add t3, t3, t4              # the reach in y
    # the bounding box, clipped to the screen
    sub s2, s0, t2
    srai s2, s2, 16
    add s3, s0, t2
    srai s3, s3, 16
    addi s3, s3, 1
    bgez s2, 5f
    li s2, 0
5:
    li t0, JAB_DISPLAY_WIDTH
    ble s3, t0, 6f
    mv s3, t0
6:
    li a0, 0
    bge s2, s3, 19f
    sub s7, s1, t3
    srai s7, s7, 16
    add s6, s1, t3
    srai s6, s6, 16
    addi s6, s6, 1
    bgez s7, 7f
    li s7, 0
7:
    li t0, JAB_DISPLAY_HEIGHT
    ble s6, t0, 8f
    mv s6, t0
8:
    bge s7, s6, 19f
    # the rows: s7 the drawn row, s6 its end, s2 and s3 the columns; s0
    # and s1 the centre; s11 the row's offset from the centre, 16.16
9:
    slli s11, s7, 16
    li t0, 0x8000
    add s11, s11, t0
    sub s11, s11, s1
    mv s8, s2
10:
    slli t0, s8, 16
    li t1, 0x8000
    add t0, t0, t1
    sub t0, t0, s0              # the column's offset from the centre
    la t1, sprite_cos
    ld t1, 0(t1)
    la t2, sprite_sin
    ld t2, 0(t2)
    mul t3, t0, t1              # u cos
    mul t4, s11, t2             # v sin
    add t3, t3, t4
    srai t3, t3, 16             # where it sits across the unturned frame
    mul t4, s11, t1             # v cos
    mul t5, t0, t2              # u sin
    sub t4, t4, t5
    srai t4, t4, 16             # and down it
    la t0, sprite_hw
    ld t0, 0(t0)
    add t3, t3, t0
    bltz t3, 18f
    la t0, sprite_dw16
    ld t0, 0(t0)
    bge t3, t0, 18f
    la t0, sprite_hh
    ld t0, 0(t0)
    add t4, t4, t0
    bltz t4, 18f
    la t0, sprite_dh16
    ld t0, 0(t0)
    bge t4, t0, 18f
    # the source pixel under it
    mul t3, t3, s9
    srli t3, t3, 32
    la t0, sprite_last_col
    ld t0, 0(t0)
    bgtu t3, t0, 18f
    mul t4, t4, s10
    srli t4, t4, 32
    la t1, sprite_last_row
    ld t1, 0(t1)
    bgtu t4, t1, 18f
    la t2, sprite_flips
    ld t2, 0(t2)
    andi t5, t2, 1
    beqz t5, 11f
    sub t3, t0, t3
11:
    andi t5, t2, 2
    beqz t5, 12f
    sub t4, t1, t4
12:
    mul t4, t4, s4
    slli t3, t3, 2
    add a1, s5, t4
    add a1, a1, t3
    li t0, JAB_DISPLAY_PITCH
    mul t0, t0, s7
    slli t1, s8, 2
    add t0, t0, t1
    li t1, JAB_DISPLAY_BASE
    add a2, t0, t1
    la t0, sprite_solid
    ld t0, 0(t0)
    beqz t0, 13f
    la t0, sprite_solid_word
    ld t0, 0(t0)
    sw t0, 0(a2)
    j 18f
13:
    lbu a7, 3(a1)
    call sprite_blend
18:
    addi s8, s8, 1
    blt s8, s3, 10b
    addi s7, s7, 1
    blt s7, s6, 9b
    li a0, 0
19:
    sd a0, 80(sp)
    j trap_return

# sprite_blend: a1 is a source pixel with its alpha already in a7, and
# a2 the screen word under it. The alpha decides, the tint multiplies,
# the blend rounds; a leaf that keeps the s registers, a1, a2, and a3.
sprite_blend:
    beqz a7, 9f
    lbu a4, 0(a1)               # blue
    lbu a5, 1(a1)               # green
    lbu a6, 2(a1)               # red
    la t1, sprite_tinted
    ld t1, 0(t1)
    beqz t1, 1f
    # a white pixel under a tint is the tint, exactly what the
    # multiplies would give, and the recolour rule makes every pixel of
    # such a sprite white, so the multiplies are skipped for it
    and t2, a4, a5
    and t2, t2, a6
    li t3, 255
    bne t2, t3, 11f
    la t1, sprite_tint_b
    ld a4, 0(t1)
    la t1, sprite_tint_g
    ld a5, 0(t1)
    la t1, sprite_tint_r
    ld a6, 0(t1)
    j 1f
11:
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
1:
    li t1, 255
    beq a7, t1, 2f
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
2:
    slli a6, a6, 16
    slli a5, a5, 8
    or a4, a4, a5
    or a4, a4, a6
    sw a4, 0(a2)
9:
    ret

# sprite_spans: a0 is a sprite record whose header and pixels are in
# place. Writes the span table after the pixels, two 16-bit columns per
# row of every frame, the first and the last with any alpha, the first
# past the last for a row with none, and sets JAB_SPRITE_SPANNED in
# the flags. What png.S calls once a decode is done.
.global sprite_spans
sprite_spans:
    addi sp, sp, -48
    sd ra, 40(sp)
    sd a0, 0(sp)
    addi a0, a0, JAB_SPRITE_WIDTH
    call sprite_le32
    sd a0, 8(sp)                # the width
    ld a0, 0(sp)
    addi a0, a0, JAB_SPRITE_HEIGHT
    call sprite_le32
    sd a0, 16(sp)               # the height
    ld a0, 0(sp)
    addi a0, a0, JAB_SPRITE_FRAMES
    call sprite_le32
    ld t1, 16(sp)
    mul t1, t1, a0              # the rows, all frames
    ld t2, 8(sp)
    ld t0, 0(sp)
    addi t0, t0, JAB_SPRITE_PIXELS
    slli t3, t2, 2              # a row's bytes
    mul t4, t3, t1
    add t4, t4, t0              # the table, after the pixels
1:
    beqz t1, 3f
    mv t5, t2                   # the first, none yet
    li t6, 0                    # the last
    li a1, 0                    # the column
    addi a2, t0, 3              # its alpha
2:
    lbu a3, 0(a2)
    beqz a3, 21f
    mv t6, a1
    bltu a1, t5, 22f
    j 21f
22:
    mv t5, a1
21:
    addi a2, a2, 4
    addi a1, a1, 1
    bltu a1, t2, 2b
    sb t5, 0(t4)
    srli a3, t5, 8
    sb a3, 1(t4)
    sb t6, 2(t4)
    srli a3, t6, 8
    sb a3, 3(t4)
    addi t4, t4, 4
    add t0, t0, t3
    addi t1, t1, -1
    j 1b
3:
    ld t0, 0(sp)
    addi t0, t0, JAB_SPRITE_FLAGS
    li t1, JAB_SPRITE_SPANNED
    sb t1, 0(t0)
    sb zero, 1(t0)
    sb zero, 2(t0)
    sb zero, 3(t0)
    ld ra, 40(sp)
    addi sp, sp, 48
    ret

# sprite_trig: a0 is an angle, 0 to 359 degrees; a0 becomes its sine
# and a1 its cosine, signed 16.16, from the quarter-wave table.
sprite_trig:
    li t0, 90
    divu t1, a0, t0             # the quadrant
    remu t2, a0, t0             # the degrees into it
    sub t3, t0, t2              # and the degrees left of it
    la t4, sprite_sine
    slli t2, t2, 2
    add t2, t2, t4
    lwu t2, 0(t2)               # sin of the degrees in
    slli t3, t3, 2
    add t3, t3, t4
    lwu t3, 0(t3)               # sin of the degrees left, the cosine
    beqz t1, 1f
    li t0, 1
    beq t1, t0, 2f
    li t0, 2
    beq t1, t0, 3f
    # the fourth quadrant
    neg a0, t3
    mv a1, t2
    ret
1:
    mv a0, t2
    mv a1, t3
    ret
2:
    mv a0, t3
    neg a1, t2
    ret
3:
    neg a0, t2
    neg a1, t3
    ret

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

.section .rodata
.balign 4
# The sine of 0 to 90 degrees in 16.16 fixed point, rounded.
sprite_sine:
    .word 0, 1144, 2287, 3430, 4572, 5712, 6850
    .word 7987, 9121, 10252, 11380, 12505, 13626, 14742
    .word 15855, 16962, 18064, 19161, 20252, 21336, 22415
    .word 23486, 24550, 25607, 26656, 27697, 28729, 29753
    .word 30767, 31772, 32768, 33754, 34729, 35693, 36647
    .word 37590, 38521, 39441, 40348, 41243, 42126, 42995
    .word 43852, 44695, 45525, 46341, 47143, 47930, 48703
    .word 49461, 50203, 50931, 51643, 52339, 53020, 53684
    .word 54332, 54963, 55578, 56175, 56756, 57319, 57865
    .word 58393, 58903, 59396, 59870, 60326, 60764, 61183
    .word 61584, 61966, 62328, 62672, 62997, 63303, 63589
    .word 63856, 64104, 64332, 64540, 64729, 64898, 65048
    .word 65177, 65287, 65376, 65446, 65496, 65526, 65536

.section .bss
.balign 8
sprite_tinted:
    .skip 8
sprite_tint_r:
    .skip 8
sprite_tint_g:
    .skip 8
sprite_tint_b:
    .skip 8
sprite_flips:
    .skip 8
sprite_solid:
    .skip 8
sprite_solid_word:
    .skip 8
sprite_flags:
    .skip 8
sprite_spans_row:
    .skip 8
sprite_stepabs:
    .skip 8
sprite_x:
    .skip 8
sprite_angle:
    .skip 8
sprite_last_col:
    .skip 8
sprite_last_row:
    .skip 8
sprite_hw:
    .skip 8
sprite_hh:
    .skip 8
sprite_dw16:
    .skip 8
sprite_dh16:
    .skip 8
sprite_sin:
    .skip 8
sprite_cos:
    .skip 8
