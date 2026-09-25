# sprite: the draw call. Two sprites written straight into the program
# as native pixels, no PNG at all, drawn onto a painted background in
# every way jab.sprite.draw can: plain, hanging off the top left and the
# bottom right corners, tinted, at twice and at half its size, a frame
# of a two-frame sprite, mirrored each way and both, turned a quarter,
# an eighth, and a twelfth, and the refusals, a frame past the sprite
# and a scale past the most; each call's code goes to the UART as `draw
# <code>`. Then one flip, and idle for the test to take the screen.
.include "jab.inc"

.set BACKGROUND, 0x00203040
.set TINT, 0x00ff8040

.section .text
.global _start
_start:
    jab.display.open
    bnez a0, no_display
    li t0, JAB_DISPLAY_BASE
    li t1, JAB_DISPLAY_BASE + JAB_DISPLAY_SIZE
    li t2, BACKGROUND
    slli t3, t2, 32
    or t2, t2, t3
1:
    sd t2, 0(t0)
    addi t0, t0, 8
    bltu t0, t1, 1b
    la s0, blend
    la s1, sheet
    # plain, whole, over the background
    li t1, 10
    li t2, 10
    jab.sprite.draw s0, zero, t1, t2
    call report
    # hanging off the top left: two columns and a row lost
    li t1, -2
    li t2, -1
    jab.sprite.draw s0, zero, t1, t2
    call report
    # hanging off the bottom right: two columns and a row kept
    li t1, JAB_DISPLAY_WIDTH - 2
    li t2, JAB_DISPLAY_HEIGHT - 1
    jab.sprite.draw s0, zero, t1, t2
    call report
    # tinted, the tint in a register
    li t1, 100
    li t2, 100
    li t3, TINT
    jab.sprite.draw s0, zero, t1, t2, t3
    call report
    # twice the size, plain
    li t1, 200
    li t2, 200
    li t3, JAB_SPRITE_PLAIN
    li t4, 2 * JAB_SPRITE_SCALE_ONE
    jab.sprite.draw s0, zero, t1, t2, t3, t4
    call report
    # half the size, which keeps every other source pixel
    li t1, 300
    li t2, 300
    li t3, JAB_SPRITE_PLAIN
    li t4, JAB_SPRITE_SCALE_ONE / 2
    jab.sprite.draw s0, zero, t1, t2, t3, t4
    call report
    # the second frame of the sheet
    li t0, 1
    li t1, 400
    li t2, 400
    jab.sprite.draw s1, t0, t1, t2
    call report
    # mirrored left to right
    li t1, 700
    li t2, 100
    li t3, JAB_SPRITE_PLAIN
    li t4, JAB_SPRITE_SCALE_ONE
    li t5, JAB_SPRITE_FLIP_H
    jab.sprite.draw s0, zero, t1, t2, t3, t4, t5
    call report
    # mirrored top to bottom
    li t1, 700
    li t2, 200
    li t5, JAB_SPRITE_FLIP_V
    jab.sprite.draw s0, zero, t1, t2, t3, t4, t5
    call report
    # both, at twice the size
    li t1, 700
    li t2, 300
    li t4, 2 * JAB_SPRITE_SCALE_ONE
    li t5, JAB_SPRITE_FLIP_H | JAB_SPRITE_FLIP_V
    jab.sprite.draw s0, zero, t1, t2, t3, t4, t5
    call report
    # a quarter turn at four times
    li t1, 800
    li t2, 100
    li t4, 4 * JAB_SPRITE_SCALE_ONE
    li t5, 90
    jab.sprite.draw s0, zero, t1, t2, t3, t4, t5
    call report
    # an eighth turn at four times
    li t1, 800
    li t2, 300
    li t5, 45
    jab.sprite.draw s0, zero, t1, t2, t3, t4, t5
    call report
    # mirrored and turned a twelfth, at three times
    li t1, 800
    li t2, 500
    li t4, 3 * JAB_SPRITE_SCALE_ONE
    li t5, JAB_SPRITE_FLIP_H | 30
    jab.sprite.draw s0, zero, t1, t2, t3, t4, t5
    call report
    # a frame the sheet does not have
    li t0, 2
    li t1, 500
    li t2, 500
    jab.sprite.draw s1, t0, t1, t2
    call report
    # a scale past the most
    li t1, 600
    li t2, 600
    li t3, JAB_SPRITE_PLAIN
    li t4, JAB_SPRITE_SCALE_MAX + 1
    jab.sprite.draw s0, zero, t1, t2, t3, t4
    call report
    # wholly off the screen: nothing drawn, and no complaint
    li t1, 5000
    li t2, 5000
    jab.sprite.draw s0, zero, t1, t2
    call report
    jab.display.flip
2:
    jab.await
    j 2b

no_display:
    jab.uart.print msg_no_display
    jab.exit 1

# report: a0 is a call's code; `draw <code>` on the UART.
report:
    la t0, line
    li t1, 'd'
    sb t1, 0(t0)
    li t1, 'r'
    sb t1, 1(t0)
    li t1, 'a'
    sb t1, 2(t0)
    li t1, 'w'
    sb t1, 3(t0)
    li t1, ' '
    sb t1, 4(t0)
    addi t1, a0, '0'
    sb t1, 5(t0)
    li t1, '\n'
    sb t1, 6(t0)
    sb zero, 7(t0)
    jab.uart.print line
    ret

.section .rodata
.balign 4
# blend: one frame of 4 by 3, every kind of alpha, as 0xAARRGGBB words
blend:
    .word 4, 3, 1
    .word 0xffff0000, 0x8000ff00, 0x000000ff, 0xffffffff
    .word 0x40ff8000, 0xc0ffffff, 0xff102030, 0x01ffffff
    .word 0x7f7f7f7f, 0xfe000000, 0x00ffffff, 0x80404040
# sheet: two frames of 2 by 2, one after the other
sheet:
    .word 2, 2, 2
    .word 0xff111111, 0xff222222
    .word 0xff333333, 0xff444444
    .word 0xffaa0000, 0xff00aa00
    .word 0xff0000aa, 0x80ffffff
msg_no_display:
    .asciz "sprite: no display\n"

.section .bss
line:
    .skip 16
