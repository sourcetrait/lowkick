# png: the decoder. Reads a set of PNG files out of the romfs disk and,
# for each row of its table, asks jab.png.size and reports `s <code>
# <width> <height>`, then decodes the file into a sprite of that many
# frames with that much buffer and reports `p <code> <frame width>
# <height> <frames>`, or `p <code>` when the decode failed; a decoded
# sprite's pixels follow as hex, 64 bytes to a line as `x <hex>`, then
# its span table as `y <hex>` and its flags as `f <n>`, for the test to
# hold against what it put in. Then, for each row of a
# second table, loads a sprite from a directory of frames straight off
# the disk and reports `l <code> <frame width> <height> <frames>` the
# same way. The frames and the capacity come from the tables at run
# time, so the plain ecall is used where the macro would want constants.
.include "jab.inc"

.set DISK, 1
.set PNGBUF, 65536
.set SPRITEBUF, 65536
.set COLUMNS, 64

.section .text
.global _start
_start:
    la s0, table
1:
    ld s1, 0(s0)                # the path, 0 at the end
    beqz s1, 8f
    ld s10, 8(s0)               # the frames
    ld s11, 16(s0)              # the capacity
    # the file, out of romfs and into memory
    mv a3, s1
    la a0, rec
    li a1, DISK
    li a2, JAB_ROMFS_ROOT
    li a7, JAB_SYS_ROMFS_FIND
    ecall
    bnez a0, 9f
    la t0, rec
    lwu s2, JAB_ROMFS_OFFSET(t0)
    li s3, 0                    # where in the file
    li s4, 0                    # how much is here
2:
    la t0, pngbuf
    add t0, t0, s4
    li t1, DISK
    mv t2, s2
    mv t3, s3
    li t4, PNGBUF
    sub t4, t4, s4
    jab.romfs.read t0, t1, t2, t3, t4
    beqz a0, 3f
    add s4, s4, a0
    mv s3, a1
    bnez s3, 2b
3:
    # what the header says
    la t0, pngbuf
    mv t1, s4
    jab.png.size t0, t1
    mv s5, a0
    mv s6, a1
    mv s7, a2
    call line_reset
    la a0, word_s
    call line_str
    mv a0, s7
    call line_dec
    li a0, ' '
    call line_char
    mv a0, s5
    call line_dec
    li a0, ' '
    call line_char
    mv a0, s6
    call line_dec
    call line_nl
    jab.uart.print line
    # the decode, with the table's frames and capacity
    la a0, sprite
    la a1, pngbuf
    mv a2, s4
    mv a3, s11
    mv a4, s10
    li a7, JAB_SYS_SPRITE_PNG
    ecall
    la a1, word_p
    call report
    addi s0, s0, 24
    j 1b
8:
    # the directories, straight off the disk
    la s0, loads
4:
    ld s1, 0(s0)
    beqz s1, 5f
    ld s11, 8(s0)
    la a0, sprite
    li a1, DISK
    mv a2, s1
    mv a3, s11
    li a7, JAB_SYS_SPRITE_LOAD
    ecall
    la a1, word_l
    call report
    addi s0, s0, 16
    j 4b
5:
    jab.uart.print msg_done
    jab.exit 0
9:
    jab.uart.print msg_missing
    jab.exit 1

# report: a0 is a sprite call's code and a1 the word that opens the
# line. The line, and on success the sprite's pixels as hex.
report:
    addi sp, sp, -16
    sd ra, 8(sp)
    mv s8, a0
    mv s9, a1
    call line_reset
    mv a0, s9
    call line_str
    mv a0, s8
    call line_dec
    bnez s8, 1f
    li a0, ' '
    call line_char
    la t0, sprite
    lwu a0, JAB_SPRITE_WIDTH(t0)
    call line_dec
    li a0, ' '
    call line_char
    la t0, sprite
    lwu a0, JAB_SPRITE_HEIGHT(t0)
    call line_dec
    li a0, ' '
    call line_char
    la t0, sprite
    lwu a0, JAB_SPRITE_FRAMES(t0)
    call line_dec
1:
    call line_nl
    jab.uart.print line
    bnez s8, 4f
    # the pixels, byte by byte
    la t0, sprite
    lwu t1, JAB_SPRITE_WIDTH(t0)
    lwu t2, JAB_SPRITE_HEIGHT(t0)
    lwu t3, JAB_SPRITE_FRAMES(t0)
    mul s7, t1, t3
    mul s7, s7, t2
    slli s7, s7, 2              # the bytes
    li s9, 0
2:
    bgeu s9, s7, 4f
    call line_reset
    la a0, word_x
    call line_str
    li s6, 0
3:
    bgeu s9, s7, 31f
    li t0, COLUMNS
    bgeu s6, t0, 31f
    la t0, sprite
    addi t0, t0, JAB_SPRITE_PIXELS
    add t0, t0, s9
    lbu a0, 0(t0)
    call line_hex
    addi s9, s9, 1
    addi s6, s6, 1
    j 3b
31:
    call line_nl
    jab.uart.print line
    j 2b
4:
    bnez s8, 6f
    # the span table after the pixels, four bytes a row of every frame,
    # as `y <hex>` lines, and the flags as `f <n>`
    la t0, sprite
    lwu t1, JAB_SPRITE_HEIGHT(t0)
    lwu t3, JAB_SPRITE_FRAMES(t0)
    mul s10, t1, t3
    slli s10, s10, 2            # the table's bytes
    add s7, s7, s10             # where it ends, from the pixels
    sub s9, s7, s10             # where it starts
5:
    bgeu s9, s7, 51f
    call line_reset
    la a0, word_y
    call line_str
    li s6, 0
52:
    bgeu s9, s7, 53f
    li t0, COLUMNS
    bgeu s6, t0, 53f
    la t0, sprite
    addi t0, t0, JAB_SPRITE_PIXELS
    add t0, t0, s9
    lbu a0, 0(t0)
    call line_hex
    addi s9, s9, 1
    addi s6, s6, 1
    j 52b
53:
    call line_nl
    jab.uart.print line
    j 5b
51:
    call line_reset
    la a0, word_f
    call line_str
    la t0, sprite
    lwu a0, JAB_SPRITE_FLAGS(t0)
    call line_dec
    call line_nl
    jab.uart.print line
6:
    ld ra, 8(sp)
    addi sp, sp, 16
    ret

line_reset:
    la t0, line
    la t1, lineptr
    sd t0, 0(t1)
    ret

line_char:
    la t1, lineptr
    ld t0, 0(t1)
    sb a0, 0(t0)
    addi t0, t0, 1
    sd t0, 0(t1)
    ret

# line_nl: end the line and terminate it where it ends.
line_nl:
    la t1, lineptr
    ld t0, 0(t1)
    li t2, '\n'
    sb t2, 0(t0)
    addi t0, t0, 1
    sb zero, 0(t0)
    sd t0, 0(t1)
    ret

line_str:
    mv t2, a0
    la t1, lineptr
    ld t0, 0(t1)
1:
    lbu t3, 0(t2)
    beqz t3, 2f
    sb t3, 0(t0)
    addi t0, t0, 1
    addi t2, t2, 1
    j 1b
2:
    sd t0, 0(t1)
    ret

line_dec:
    mv t2, a0
    la t1, lineptr
    ld t0, 0(t1)
    la t4, digits
    addi t4, t4, 31
    sb zero, 0(t4)
    li t5, 10
1:
    remu t6, t2, t5
    divu t2, t2, t5
    addi t6, t6, '0'
    addi t4, t4, -1
    sb t6, 0(t4)
    bnez t2, 1b
2:
    lbu t6, 0(t4)
    beqz t6, 3f
    sb t6, 0(t0)
    addi t0, t0, 1
    addi t4, t4, 1
    j 2b
3:
    sd t0, 0(t1)
    ret

line_hex:
    mv t2, a0
    la t1, lineptr
    ld t0, 0(t1)
    li t5, 10
    srli t3, t2, 4
    andi t3, t3, 15
    blt t3, t5, 1f
    addi t3, t3, 'a' - 10
    j 2f
1:
    addi t3, t3, '0'
2:
    sb t3, 0(t0)
    addi t0, t0, 1
    andi t3, t2, 15
    blt t3, t5, 3f
    addi t3, t3, 'a' - 10
    j 4f
3:
    addi t3, t3, '0'
4:
    sb t3, 0(t0)
    addi t0, t0, 1
    sd t0, 0(t1)
    ret

.section .rodata
.balign 8
# the path, the frames, and the capacity of each decode; the last two
# rows ask for frames the height does not divide by and for a buffer
# too small, on a file the rows before decoded
table:
    .quad path_rgba8, 1, SPRITEBUF
    .quad path_rgb8, 1, SPRITEBUF
    .quad path_grey8, 1, SPRITEBUF
    .quad path_grey4, 1, SPRITEBUF
    .quad path_grey2, 1, SPRITEBUF
    .quad path_grey1, 1, SPRITEBUF
    .quad path_ga8, 1, SPRITEBUF
    .quad path_idx8, 1, SPRITEBUF
    .quad path_idx4, 1, SPRITEBUF
    .quad path_idx2, 1, SPRITEBUF
    .quad path_idx1, 1, SPRITEBUF
    .quad path_sheet, 2, SPRITEBUF
    .quad path_split, 1, SPRITEBUF
    .quad path_big, 1, SPRITEBUF
    .quad path_extras, 1, SPRITEBUF
    .quad path_depth16, 1, SPRITEBUF
    .quad path_interlaced, 1, SPRITEBUF
    .quad path_badcrc, 1, SPRITEBUF
    .quad path_badadler, 1, SPRITEBUF
    .quad path_badfilter, 1, SPRITEBUF
    .quad path_short, 1, SPRITEBUF
    .quad path_truncated, 1, SPRITEBUF
    .quad path_notpng, 1, SPRITEBUF
    .quad path_rgba8, 3, SPRITEBUF
    .quad path_rgba8, 1, 100
    .quad 0, 0, 0

# the directory and the capacity of each load: four frames, then a
# directory whose second frame is another size, one with no 0.png, one
# that is not there, a file where a directory should be, and the four
# frames with too small a buffer
loads:
    .quad dir_walker, SPRITEBUF
    .quad dir_mixed, SPRITEBUF
    .quad dir_nozero, SPRITEBUF
    .quad dir_missing, SPRITEBUF
    .quad path_rgba8, SPRITEBUF
    .quad dir_walker, 100
    .quad 0, 0

path_rgba8:
    .asciz "/rgba8.png"
path_rgb8:
    .asciz "/rgb8.png"
path_grey8:
    .asciz "/grey8.png"
path_grey4:
    .asciz "/grey4.png"
path_grey2:
    .asciz "/grey2.png"
path_grey1:
    .asciz "/grey1.png"
path_ga8:
    .asciz "/ga8.png"
path_idx8:
    .asciz "/idx8.png"
path_idx4:
    .asciz "/idx4.png"
path_idx2:
    .asciz "/idx2.png"
path_idx1:
    .asciz "/idx1.png"
path_sheet:
    .asciz "/sheet.png"
path_split:
    .asciz "/split.png"
path_big:
    .asciz "/big.png"
path_extras:
    .asciz "/extras.png"
path_depth16:
    .asciz "/depth16.png"
path_interlaced:
    .asciz "/interlaced.png"
path_badcrc:
    .asciz "/badcrc.png"
path_badadler:
    .asciz "/badadler.png"
path_badfilter:
    .asciz "/badfilter.png"
path_short:
    .asciz "/short.png"
path_truncated:
    .asciz "/truncated.png"
path_notpng:
    .asciz "/notpng.png"
dir_walker:
    .asciz "/walker"
dir_mixed:
    .asciz "/mixed"
dir_nozero:
    .asciz "/nozero"
dir_missing:
    .asciz "/missing"

word_s:
    .asciz "s "
word_p:
    .asciz "p "
word_l:
    .asciz "l "
word_x:
    .asciz "x "
word_y:
    .asciz "y "
word_f:
    .asciz "f "
msg_done:
    .asciz "done\n"
msg_missing:
    .asciz "png: a fixture is missing\n"

.section .bss
.balign 8
rec:
    .skip JAB_ROMFS_ENTRY
pngbuf:
    .skip PNGBUF
sprite:
    .skip SPRITEBUF
line:
    .skip 512
lineptr:
    .skip 8
digits:
    .skip 32
