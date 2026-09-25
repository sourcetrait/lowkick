# logo: a PNG straight from GIMP 3, drawn in the middle of the screen.
# The repository's logo directory ships as this program's romfs; the
# program finds the PNG on it by name, reads it into memory, decodes it
# into a sprite of one frame, opens the display, draws the sprite
# centred, flips, and idles until the window closes.
.include "jab.inc"

.set DISK, 1
# the file: 480 by 640, so the sprite is that at four bytes a pixel and
# four bytes a row past the header, the rule for one frame, and the PNG
# itself is under 32 KiB
.set WIDTH, 480
.set HEIGHT, 640
.set SPRITE_BYTES, (JAB_SPRITE_PIXELS + HEIGHT * (WIDTH * 4 + 4))
.set PNG_BYTES, 32768
.set X, ((JAB_DISPLAY_WIDTH - WIDTH) / 2)
.set Y, ((JAB_DISPLAY_HEIGHT - HEIGHT) / 2)

.section .text
.global _start
_start:
    # the PNG, out of the romfs and into memory
    la t0, rec
    li t1, DISK
    li t2, JAB_ROMFS_ROOT
    jab.romfs.find t0, t1, t2, path
    bnez a0, no_file
    la t0, rec
    lwu s0, JAB_ROMFS_OFFSET(t0)
    li s1, 0                    # where in the file
    li s2, 0                    # how much is here
1:
    la t0, png
    add t0, t0, s2
    li t1, DISK
    mv t2, s0
    mv t3, s1
    li t4, PNG_BYTES
    sub t4, t4, s2
    jab.romfs.read t0, t1, t2, t3, t4
    beqz a0, 2f
    add s2, s2, a0
    mv s1, a1
    bnez s1, 1b
2:
    # the sprite, decoded in place
    la t0, sprite
    la t1, png
    mv t2, s2
    jab.sprite.png t0, t1, t2, SPRITE_BYTES
    bnez a0, bad_png
    jab.display.open
    bnez a0, no_display
    la t0, sprite
    li t1, X
    li t2, Y
    jab.sprite.draw t0, zero, t1, t2
    jab.display.flip
3:
    jab.await
    j 3b

no_file:
    jab.uart.print msg_no_file
    jab.exit 1
bad_png:
    jab.uart.print msg_bad_png
    jab.exit 1
no_display:
    jab.uart.print msg_no_display
    jab.exit 1

.section .rodata
path:
    .asciz "/lowkick.480x640.png"
msg_no_file:
    .asciz "logo: the png is not on the romfs\n"
msg_bad_png:
    .asciz "logo: the png would not decode\n"
msg_no_display:
    .asciz "logo: no display\n"

.section .bss
.balign 8
rec:
    .skip JAB_ROMFS_ENTRY
png:
    .skip PNG_BYTES
sprite:
    .skip SPRITE_BYTES
