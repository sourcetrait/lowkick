# jab.inc: the Jab SDK header. `.include "jab.inc"` and call the kernel
# with the jab.* macros, assembler style: `jab.print message`.
.include "jab_keys.inc"
.include "jab_pad.inc"

# Where a program lives. The machine has 4 GiB of RAM from 0x80000000;
# the kernel keeps the first 2 MiB and the framebuffer the 8 MiB after
# it, and everything from there to the end of RAM is the program's:
# QEMU's loader device places the .jab file at JAB_PROGRAM_BASE, the
# program owns JAB_PROGRAM_SIZE bytes from there, and starts with sp at
# JAB_STACK_TOP, the end of RAM.
.set JAB_PROGRAM_BASE, 0x80a00000
.set JAB_PROGRAM_SIZE, 0xff600000
.set JAB_STACK_TOP, (JAB_PROGRAM_BASE + JAB_PROGRAM_SIZE)

# The display: a framebuffer between the kernel and the window,
# JAB_DISPLAY_WIDTH by JAB_DISPLAY_HEIGHT pixels of four bytes each,
# blue, green, red, and one unused, so a pixel stored as a little-endian
# word reads 0x00RRGGBB and a row is JAB_DISPLAY_PITCH bytes. The
# program draws into it and jab.display.flip shows it; RAM starts zero,
# so it starts black. Flips are capped at JAB_DISPLAY_FPS_CAP a second,
# and JAB_DISPLAY_FPS_TARGET is the rate a program is built to hold.
.set JAB_DISPLAY_BASE, 0x80200000
.set JAB_DISPLAY_WIDTH, 1920
.set JAB_DISPLAY_HEIGHT, 1080
.set JAB_DISPLAY_PITCH, (JAB_DISPLAY_WIDTH * 4)
.set JAB_DISPLAY_SIZE, (JAB_DISPLAY_PITCH * JAB_DISPLAY_HEIGHT)
.set JAB_DISPLAY_FPS_TARGET, 30
.set JAB_DISPLAY_FPS_CAP, 32

# The time counter: `rdtime` reads it, JAB_TIME_HZ ticks a second.
.set JAB_TIME_HZ, 10000000

# What jab.await waits for: a mask of these, or 0 for all of them; a
# source the machine lacks drops out of the mask
.set JAB_AWAIT_ALL, 0
.set JAB_AWAIT_DISPLAY, 1
.set JAB_AWAIT_KEYBOARD, 2
.set JAB_AWAIT_API, 4
.set JAB_AWAIT_PAD, 8

# System call numbers (doc/syscalls.nuon)
.set JAB_SYS_EXIT, 1
.set JAB_SYS_PRINT, 2
.set JAB_SYS_UART_PRINT, 3
.set JAB_SYS_DISPLAY_OPEN, 4
.set JAB_SYS_DISPLAY_READY, 5
.set JAB_SYS_DISPLAY_FLIP, 6
.set JAB_SYS_DISPLAY_PRINT, 7
.set JAB_SYS_AWAIT, 8
.set JAB_SYS_DISPLAY_FLIP_RECT, 9
.set JAB_SYS_KEYBOARD_INPUT, 10
.set JAB_SYS_BLOCK_LIST, 11
.set JAB_SYS_BLOCK_FIND, 12
.set JAB_SYS_BLOCK_READ, 13
.set JAB_SYS_BLOCK_WRITE, 14
.set JAB_SYS_ROMFS_LIST, 15
.set JAB_SYS_ROMFS_FIND, 16
.set JAB_SYS_ROMFS_READ, 17
.set JAB_SYS_TAR_LIST, 18
.set JAB_SYS_TAR_FIND, 19
.set JAB_SYS_GZ_SIZE, 20
.set JAB_SYS_GZ_READ, 21
.set JAB_SYS_CHECKSUM, 22
.set JAB_SYS_HASH, 23
.set JAB_SYS_API_WRITE, 24
.set JAB_SYS_API_READ, 25
.set JAB_SYS_PNG_SIZE, 26
.set JAB_SYS_SPRITE_PNG, 27
.set JAB_SYS_SPRITE_DRAW, 28
.set JAB_SYS_SPRITE_LOAD, 29
.set JAB_SYS_DISPLAY_FLIP_RECTS, 30
.set JAB_SYS_KERNEL_FLAGS, 31
.set JAB_SYS_PAD_READ, 32
.set JAB_SYS_PAD_INPUT, 33
.set JAB_SYS_PAD_AXIS, 34
.set JAB_SYS_DISPLAY_TEXT, 35

# Text drawn where a program says, with the console's font: a cell is
# JAB_TEXT_WIDTH by JAB_TEXT_HEIGHT pixels; JAB_TEXT_PLAIN is the
# console's white, and JAB_TEXT_BOLD in the style strikes each glyph
# twice a pixel apart.
.set JAB_TEXT_WIDTH, 12
.set JAB_TEXT_HEIGHT, 24
.set JAB_TEXT_PLAIN, 0x00ffffff
.set JAB_TEXT_BOLD, 1

# The pad: a gamepad the host passed through as a virtio-input device.
# jab.pad.read fills a state record of JAB_PAD_ENTRY bytes, on a 4-byte
# boundary: JAB_PAD_KEYS, a 32-bit mask of the gamepad's keys, bit n
# for the code JAB_BTN_GAMEPAD + n (jab_pad.inc), then JAB_PAD_AXES,
# JAB_PAD_AXIS_COUNT signed 16-bit values indexed by the axis's own
# code, JAB_ABS_X and the rest, each normalised to -JAB_PAD_FULL through
# JAB_PAD_FULL from the axis's own range: a centred axis reads 0 across
# its flat band about the middle of its range and rescales to full
# scale at either end; ABS_GAS and ABS_BRAKE, one-sided, read 0 to
# JAB_PAD_FULL; a hat reads -JAB_PAD_FULL, 0, or JAB_PAD_FULL; an axis
# the pad lacks, or one that has not moved since the program started,
# reads 0. The pad's own range for an axis is JAB_PAD_AXIS_ENTRY bytes
# from jab.pad.axis, five signed 32-bit fields as virtio reports them.
.set JAB_PAD_ENTRY, 132
.set JAB_PAD_KEYS, 0
.set JAB_PAD_AXES, 4
.set JAB_PAD_AXIS_COUNT, 64
.set JAB_PAD_FULL, 32767
.set JAB_PAD_AXIS_ENTRY, 20
.set JAB_PAD_AXIS_MIN, 0
.set JAB_PAD_AXIS_MAX, 4
.set JAB_PAD_AXIS_FUZZ, 8
.set JAB_PAD_AXIS_FLAT, 12
.set JAB_PAD_AXIS_RES, 16

# What the kernel was built with, as jab.kernel.flags reports it: a
# mask of these. JAB_KERNEL_DEBUG: DEBUG was set, so the kernel's own
# lines go to its debug channel. A program can .ifdef the same symbols
# at build, since every symbol reaches it too; the call is for the
# same fact at run time.
.set JAB_KERNEL_DEBUG, 1

# A sprite: frames of pixels in the framebuffer's own format, which the
# program owns and jab.sprite.draw blends onto the screen. The record is
# a header of four 32-bit fields - the width of one frame, the height,
# the frame count, and flags - and then the pixels at JAB_SPRITE_PIXELS,
# frame after frame, each frame its rows top to bottom, so frame k is
# one contiguous block. A pixel is a little-endian word 0xAARRGGBB: the
# framebuffer's blue, green, red, and the unused byte carrying alpha, 0
# clear through 255 solid. A sprite of one frame is a plain image.
#
# With JAB_SPRITE_SPANNED in the flags, a table follows the pixels: for
# every row of every frame, in order, two 16-bit columns, the first and
# the last that carry any alpha, the first past the last in a row with
# none; the draw then walks only those columns, which is what makes a
# thin figure in a wide frame cheap. jab.sprite.png and jab.sprite.load
# write the table and set the flag; a sprite written by hand may leave
# the flags 0 and is drawn whole.
#
# jab.sprite.png fills a sprite from a PNG the program holds, a sheet of
# frames stacked top to bottom, and jab.sprite.load from a directory of
# PNGs on a romfs disk, one frame each; both decode in place and add the
# table, so the buffer holding the record needs JAB_SPRITE_PIXELS plus
# four bytes a pixel and four bytes a row of every frame: for N frames
# of W by H, JAB_SPRITE_PIXELS + N * H * (W * 4 + 4). A program that
# knows its asset writes that down with .set; one that does not asks
# jab.png.size first. Declare the record on a 4-byte boundary, as its
# fields want.
.set JAB_SPRITE_WIDTH, 0
.set JAB_SPRITE_HEIGHT, 4
.set JAB_SPRITE_FRAMES, 8
.set JAB_SPRITE_FLAGS, 12
.set JAB_SPRITE_PIXELS, 16
.set JAB_SPRITE_SPANNED, 1

# A rectangle of the screen, as jab.display.flip.rects takes them: x,
# y, width, height, each 32 bits, JAB_RECT_SIZE bytes in all.
.set JAB_RECT_X, 0
.set JAB_RECT_Y, 4
.set JAB_RECT_WIDTH, 8
.set JAB_RECT_HEIGHT, 12
.set JAB_RECT_SIZE, 16

# jab.sprite.draw's tint is a colour, 0x00RRGGBB, that each channel of a
# sprite's pixel is multiplied by, over 255, before it is blended, so
# JAB_SPRITE_PLAIN, white, draws the sprite as it is and black draws its
# silhouette. A sprite meant to be recoloured is drawn white with its
# shape in alpha. The scale is in 256ths: JAB_SPRITE_SCALE_ONE draws the
# frame at its own size, half that at half, twice at twice, sampling the
# nearest source pixel; at most JAB_SPRITE_SCALE_MAX. The pose turns
# and mirrors the frame: its low sixteen bits are an angle in degrees,
# clockwise, and JAB_SPRITE_FLIP_H and JAB_SPRITE_FLIP_V mirror it left
# to right and top to bottom, applied to the frame before the turn; the
# turn is about the scaled frame's centre. JAB_SPRITE_SOLID in the pose
# writes the tint over every pixel the frame covers, no alpha and no
# blend: each row's span for a spanned sprite, the whole frame
# otherwise; drawing the frame a program drew last time, at the same
# place, scale, and pose, solid in the background's colour is how it
# clears that frame at the cost of its shape rather than its box, and
# a solid draw in any colour is a silhouette.
.set JAB_SPRITE_PLAIN, 0x00ffffff
.set JAB_SPRITE_SCALE_ONE, 256
.set JAB_SPRITE_SCALE_MAX, 65536
.set JAB_SPRITE_FLIP_H, 0x10000
.set JAB_SPRITE_FLIP_V, 0x20000
.set JAB_SPRITE_SOLID, 0x40000

# PNG, as GIMP 3 exports it by default from any image mode: colour types
# 0 (grey), 2 (RGB), 3 (indexed, with its palette and its transparency),
# 4 (grey with alpha) and 6 (RGBA); 8 bits a sample, and 1, 2, or 4 for
# grey and indexed, which GIMP writes for a small palette; not
# interlaced. Every ancillary chunk is skipped. What GIMP writes only
# when asked - 16 bits a sample, Adam7 interlace - is JAB_PNG_UNSUPPORTED.
# Every chunk's CRC-32 and the stream's Adler-32 are checked. The codes
# from JAB_PNG_INPUT on come from the DEFLATE stream inside the file
# rather than the PNG around it, in the order jab.gz.read reports them.
.set JAB_PNG_OK, 0
.set JAB_PNG_NOT_PNG, 1
.set JAB_PNG_UNSUPPORTED, 2
.set JAB_PNG_TRUNCATED, 3
.set JAB_PNG_CRC, 4
.set JAB_PNG_ZLIB, 5
.set JAB_PNG_LENGTH, 6
.set JAB_PNG_FILTER, 7
.set JAB_PNG_PALETTE, 8
.set JAB_PNG_FRAMES, 9
.set JAB_PNG_SIZE, 10
.set JAB_PNG_NOT_FOUND, 11
.set JAB_PNG_INPUT, 12
.set JAB_PNG_OUTPUT, 13
.set JAB_PNG_BLOCK, 14
.set JAB_PNG_STORED, 15
.set JAB_PNG_CODES, 16
.set JAB_PNG_SYMBOL, 17
.set JAB_PNG_DISTANCE, 18

# gzip, which is DEFLATE with a jacket: ten bytes of header, optionally
# an extra field, a name and a comment, then the compressed bytes, then
# a CRC-32 of the contents and their length. That length is why the
# read is one shot: a program asks jab.gz.size first, sizes its buffer,
# and gets everything in a single call. DEFLATE cannot be entered in the
# middle, so a cursor would mean the kernel holding decoder state
# between calls, which nothing else here does. What can go wrong is one
# of these; the ones from JAB_GZ_INPUT on come from the DEFLATE stream
# itself rather than the jacket.
.set JAB_GZ_OK, 0
.set JAB_GZ_NOT_GZIP, 1
.set JAB_GZ_TRUNCATED, 2
.set JAB_GZ_CRC, 3
.set JAB_GZ_LENGTH, 4
.set JAB_GZ_INPUT, 5
.set JAB_GZ_OUTPUT, 6
.set JAB_GZ_BLOCK, 7
.set JAB_GZ_STORED, 8
.set JAB_GZ_CODES, 9
.set JAB_GZ_SYMBOL, 10
.set JAB_GZ_DISTANCE, 11

# A tar archive, read where the program already holds it: unlike romfs,
# which lives on a disk, a tar is bytes in the program's own memory,
# usually a .tar.gz read out of romfs and inflated. Everything a tar
# call names is therefore an offset into that block of bytes, and an
# entry's data needs no reading call at all: JAB_TAR_DATA is where it
# already sits. A header is 512 bytes and so is every block after it, so
# an offset is always a multiple of 512. The type is tar's own byte,
# stored as a digit character. A ustar path is a 155-byte prefix, a
# separator, and a 100-byte name, so 256 characters at most, and the
# record holds all of them.
.set JAB_TAR_ENTRY, 296
.set JAB_TAR_PAGE, 16
.set JAB_TAR_LIST_SIZE, (JAB_TAR_PAGE * JAB_TAR_ENTRY)
.set JAB_TAR_BLOCK, 512
.set JAB_TAR_OFFSET, 0
.set JAB_TAR_DATA, 8
.set JAB_TAR_SIZE, 16
.set JAB_TAR_TYPE, 24
.set JAB_TAR_NAME, 32
.set JAB_TAR_NAME_BYTES, 264
.set JAB_TAR_REGULAR, '0'
.set JAB_TAR_HARDLINK, '1'
.set JAB_TAR_SYMLINK, '2'
.set JAB_TAR_CHAR, '3'
.set JAB_TAR_BLOCKDEV, '4'
.set JAB_TAR_DIRECTORY, '5'
.set JAB_TAR_FIFO, '6'

# The disks: QEMU's virtio-blk devices, one id each, 1 to JAB_BLOCK_MAX
# in the order their transports sit on the machine. A sector is
# JAB_BLOCK_SECTOR bytes, virtio's unit for every capacity and every
# request. jab.block.list fills a program buffer with records of
# JAB_BLOCK_ENTRY bytes, so a buffer of JAB_BLOCK_LIST_SIZE holds every
# disk the machine can carry. A record's fields are each the width
# virtio gives them: the id and the kind a byte, the capacity eight,
# the serial the device ID string's twenty. The kind is what the kernel
# found on the disk, not what anyone meant to put there; a record of
# zeroes reads as JAB_BLOCK_KIND_NONE, and so does a disk that would
# not come up.
.set JAB_BLOCK_MAX, 8
.set JAB_BLOCK_SECTOR, 512
.set JAB_BLOCK_ENTRY, 40
.set JAB_BLOCK_LIST_SIZE, (JAB_BLOCK_MAX * JAB_BLOCK_ENTRY)
.set JAB_BLOCK_ID, 0
.set JAB_BLOCK_KIND, 1
.set JAB_BLOCK_SECTORS, 8
.set JAB_BLOCK_SERIAL, 16
.set JAB_BLOCK_SERIAL_BYTES, 20
.set JAB_BLOCK_KIND_NONE, 0
.set JAB_BLOCK_KIND_RAW, 1
.set JAB_BLOCK_KIND_ROMFS, 2

# RomFS on a disk: read-only, every structure on a 16-byte boundary,
# every value big-endian on the image and little-endian in a record.
# Everything romfs names is a header's offset in the image, which is
# what jab.romfs.find gives back and what jab.romfs.list and
# jab.romfs.read take; JAB_ROMFS_ROOT names the volume's first header.
# A record is JAB_ROMFS_ENTRY bytes, a page of JAB_ROMFS_PAGE of them
# JAB_ROMFS_LIST_SIZE. JAB_ROMFS_NEXT carries the next header's offset
# with the mode in its low four bits, as the image stores it:
# JAB_ROMFS_TYPE masks the type and JAB_ROMFS_EXEC the executable bit,
# and clearing both low nibbles leaves the offset. A name is at most
# 127 characters, the most a Linux mount of the same image can read.
.set JAB_ROMFS_ENTRY, 144
.set JAB_ROMFS_PAGE, 16
.set JAB_ROMFS_LIST_SIZE, (JAB_ROMFS_PAGE * JAB_ROMFS_ENTRY)
.set JAB_ROMFS_OFFSET, 0
.set JAB_ROMFS_NEXT, 4
.set JAB_ROMFS_SPEC, 8
.set JAB_ROMFS_SIZE, 12
.set JAB_ROMFS_NAME, 16
.set JAB_ROMFS_NAME_BYTES, 128
.set JAB_ROMFS_ROOT, 0
.set JAB_ROMFS_TYPE, 7
.set JAB_ROMFS_EXEC, 8
.set JAB_ROMFS_HARDLINK, 0
.set JAB_ROMFS_DIRECTORY, 1
.set JAB_ROMFS_REGULAR, 2
.set JAB_ROMFS_SYMLINK, 3
.set JAB_ROMFS_BLOCK, 4
.set JAB_ROMFS_CHAR, 5
.set JAB_ROMFS_SOCKET, 6
.set JAB_ROMFS_FIFO, 7

# jab.exit status: end the program. status is an immediate, 0 by default.
.macro jab.exit status=0
    li a0, \status
    li a7, JAB_SYS_EXIT
    ecall
.endm

# jab.print message: write a NUL-terminated string to the screen console
# once the display is open, and to the UART until then. message is a
# label inside the program. a0 becomes 0.
.macro jab.print message
    la a0, \message
    li a7, JAB_SYS_PRINT
    ecall
.endm

# jab.uart.print message: write a NUL-terminated string to the UART.
# a0 becomes 0.
.macro jab.uart.print message
    la a0, \message
    li a7, JAB_SYS_UART_PRINT
    ecall
.endm

# jab.display.open: bring the display up and show the framebuffer. a0
# becomes 0; 1 with no virtio-gpu on the machine; 2 when the device
# refuses the kernel; 3 when a command fails. Open already: 0.
.macro jab.display.open
    li a7, JAB_SYS_DISPLAY_OPEN
    ecall
.endm

# jab.display.ready: a0 becomes 1 when a flip would go through now, and
# 0 while the cap holds it back.
.macro jab.display.ready
    li a7, JAB_SYS_DISPLAY_READY
    ecall
.endm

# jab.display.flip: show the framebuffer. Never waits: a0 becomes 0 when
# the frame went to the host; 1 when it came before the cap allows,
# nothing shown (await, or ask ready, first); 2 when the display is not
# open; 3 when the device refused it.
.macro jab.display.flip
    li a7, JAB_SYS_DISPLAY_FLIP
    ecall
.endm

# jab.display.flip.rect: show the rectangle the program has in a0 to
# a3, x, y, width, height in pixels, and nothing else. What
# jab.display.flip is, with the same codes, plus 4 when the rectangle
# is empty or reaches outside the screen. One flip a frame, so several
# changed areas go as the one rectangle holding them. The host copies
# and paints only the rectangle, which is what keeps a moving object
# cheap.
.macro jab.display.flip.rect
    li a7, JAB_SYS_DISPLAY_FLIP_RECT
    ecall
.endm

# jab.display.flip.rects buffer, count: show that many rectangles of
# the framebuffer, JAB_RECT_SIZE bytes each from the buffer, as one
# flip: what jab.display.flip.rect is for several changed areas at
# once. The host copies only the rectangles listed and paints once,
# the rectangle holding them all, so a busy screen costs the host one
# draw a tick whatever the list. The same codes, 4 when the count is 0
# or any rectangle is empty or reaches outside the screen, in which
# case nothing is shown.
.macro jab.display.flip.rects buffer, count
    mv a1, \count
    mv a0, \buffer
    li a7, JAB_SYS_DISPLAY_FLIP_RECTS
    ecall
.endm

# jab.kernel.flags: a0 becomes the mask of what the kernel was built
# with, JAB_KERNEL_DEBUG.
.macro jab.kernel.flags
    li a7, JAB_SYS_KERNEL_FLAGS
    ecall
.endm

# jab.display.print message: write a NUL-terminated string to the screen
# console, opening the display first if the program has not. A newline
# ends the line, and the console scrolls at the bottom. a0 becomes 0, or
# jab.display.open's code.
.macro jab.display.print message
    la a0, \message
    li a7, JAB_SYS_DISPLAY_PRINT
    ecall
.endm

# jab.display.text message, x, y, color, style: draw a NUL-terminated
# string, a label inside the program, into the framebuffer with the
# console's font, its top left at x, y, which may be negative or past
# the screen with what falls off clipped, in the colour, 0x00RRGGBB,
# JAB_TEXT_PLAIN when left out; the style JAB_TEXT_BOLD strikes each
# glyph twice a pixel apart, 0 when left out. Only the glyphs' own
# pixels are drawn, so what is under the text stays; a program clears
# the strip first when it wants a clean line. Nothing is presented:
# the program flips the rectangle, whole or with the rest. x, y,
# color, and style are registers. a0 becomes the width drawn in pixels
# and a1 the height, JAB_TEXT_HEIGHT.
.macro jab.display.text message, x, y, color, style
    .ifb \style
    li a4, 0
    .else
    mv a4, \style
    .endif
    .ifb \color
    li a3, JAB_TEXT_PLAIN
    .else
    mv a3, \color
    .endif
    mv a2, \y
    mv a1, \x
    la a0, \message
    li a7, JAB_SYS_DISPLAY_TEXT
    ecall
.endm

# jab.keyboard.input: the next key event. a0 becomes the key's code, a
# JAB_KEY_* (jab_keys.inc), or 0 when no event is waiting; a1 its
# value: JAB_KEY_PRESSED, JAB_KEY_RELEASED, or JAB_KEY_HELD. The
# keyboard comes up on the first call; a machine with no keyboard never
# has an event. Call it until a0 is 0 to take everything that arrived.
.macro jab.keyboard.input
    li a7, JAB_SYS_KEYBOARD_INPUT
    ecall
.endm

# jab.await mask=JAB_AWAIT_ALL: halt until an event in the mask: the
# display's next frame tick (JAB_AWAIT_DISPLAY), a key event waiting
# (JAB_AWAIT_KEYBOARD), bytes from the host waiting on the API
# (JAB_AWAIT_API), a pad event waiting (JAB_AWAIT_PAD), or any of them
# (JAB_AWAIT_ALL). How a program idles between frames instead of
# spinning. a0 becomes the events that fired.
.macro jab.await mask=JAB_AWAIT_ALL
    li a0, \mask
    li a7, JAB_SYS_AWAIT
    ecall
.endm

# jab.display.await: jab.await for the display's frame tick.
.macro jab.display.await
    jab.await JAB_AWAIT_DISPLAY
.endm

# jab.keyboard.await: jab.await for a key event.
.macro jab.keyboard.await
    jab.await JAB_AWAIT_KEYBOARD
.endm

# jab.api.await: jab.await for bytes from the host over the API.
.macro jab.api.await
    jab.await JAB_AWAIT_API
.endm

# jab.pad.await: jab.await for a pad event.
.macro jab.pad.await
    jab.await JAB_AWAIT_PAD
.endm

# jab.pad.read record: the pad's state now, written into the record,
# JAB_PAD_ENTRY bytes on a 4-byte boundary: the keys held and every
# axis normalised, as jab.inc describes above. The pad comes up on the
# first pad call. a0 becomes 0 with the record written, or 1 when the
# machine carries no pad.
.macro jab.pad.read record
    mv a0, \record
    li a7, JAB_SYS_PAD_READ
    ecall
.endm

# jab.pad.input: the next pad event, in evdev's own terms. a0 becomes
# the event's type, JAB_EV_KEY or JAB_EV_ABS, or 0 when no event is
# waiting; a1 its code, a JAB_BTN_* or JAB_ABS_*; a2 its value, signed:
# for a key JAB_KEY_PRESSED, JAB_KEY_RELEASED, or JAB_KEY_HELD, for an
# axis the raw reading the pad sent. Call it until a0 is 0 to take
# everything that arrived. A machine with no pad never has an event.
.macro jab.pad.input
    li a7, JAB_SYS_PAD_INPUT
    ecall
.endm

# jab.pad.axis buffer, code: the pad's own range for that axis, a
# JAB_ABS_* constant, written into the buffer as JAB_PAD_AXIS_ENTRY
# bytes: min, max, fuzz, flat, and resolution, each a signed 32-bit
# field as the pad reports them, on a 4-byte boundary. a0 becomes 0
# with the record written; 1 when the machine carries no pad; 2 when
# the pad has no such axis.
.macro jab.pad.axis buffer, code
    li a1, \code
    mv a0, \buffer
    li a7, JAB_SYS_PAD_AXIS
    ecall
.endm

# The API: bytes both ways between the program and the host over a port
# of the machine, there when the run put it there (`--api`) and absent
# otherwise, which the calls report; one build runs either way. A byte
# stream, so any record shape is the program's own.

# jab.api.write buffer, length: send that many bytes of the buffer to
# the host. a0 becomes 0, or 1 when the machine has no API port. It
# returns once the device has taken the bytes, so a host that stops
# reading holds the program here once what is between them is full:
# with jab.await the one call that can wait.
.macro jab.api.write buffer, length
    mv a1, \length
    mv a0, \buffer
    li a7, JAB_SYS_API_WRITE
    ecall
.endm

# jab.api.read buffer, capacity: the bytes the host has sent, oldest
# first, into the buffer, at most capacity of them. a0 becomes the
# bytes written, 0 when none wait, and a1 how many still wait after
# them; both 0 with no API port. Never waits; to sleep until bytes
# arrive, jab.api.await.
.macro jab.api.read buffer, capacity
    li a1, \capacity
    mv a0, \buffer
    li a7, JAB_SYS_API_READ
    ecall
.endm

# The disk and file calls take the program's buffer first, the way a
# RISC-V load names its destination first, then what they act on, then
# where in it, then how much the buffer holds. Each macro loads the
# argument registers from the highest down, so a value already sitting
# in a low argument register can be passed as a later argument: that is
# what lets a paging loop hand a1 straight back as the next cursor.
# Unless a macro's comment says otherwise its arguments are registers;
# a capacity is a constant and a name or a path is a label.

# jab.block.list buffer, at=zero, capacity=JAB_BLOCK_MAX: write a record
# per disk into the buffer, starting at the disk whose id is `at`, zero
# for the first. a0 becomes the records written, a1 the id to pass as
# `at` next time, or 0 once the last disk is in the buffer.
.macro jab.block.list buffer, at=zero, capacity=JAB_BLOCK_MAX
    li a2, \capacity
    mv a1, \at
    mv a0, \buffer
    li a7, JAB_SYS_BLOCK_LIST
    ecall
.endm

# jab.block.find serial: the id of the first disk whose serial is that
# NUL-terminated string, a label inside the program, or 0 when no disk
# carries it.
.macro jab.block.find serial
    la a0, \serial
    li a7, JAB_SYS_BLOCK_FIND
    ecall
.endm

# jab.block.read buffer, id, sector, count: read count sectors of
# JAB_BLOCK_SECTOR bytes from that disk, starting at that sector,
# straight into the buffer. a0 becomes 0; 1 when no disk carries the id;
# 2 when that disk would not come up; 3 when the device reported an
# error; 4 when those sectors are not on it.
.macro jab.block.read buffer, id, sector, count
    mv a3, \count
    mv a2, \sector
    mv a1, \id
    mv a0, \buffer
    li a7, JAB_SYS_BLOCK_READ
    ecall
.endm

# jab.block.write buffer, id, sector, count: the same, the other way.
.macro jab.block.write buffer, id, sector, count
    mv a3, \count
    mv a2, \sector
    mv a1, \id
    mv a0, \buffer
    li a7, JAB_SYS_BLOCK_WRITE
    ecall
.endm

# jab.romfs.list buffer, id, directory, offset=zero, capacity: write a
# record per entry of that directory into the buffer, starting at
# `offset`, which is zero for its first entry and otherwise the a1 of
# the page before. `directory` is a header's offset, JAB_ROMFS_ROOT for
# the volume's root. a0 becomes the records written and a1 the offset to
# start the next page at, 0 once the directory has ended.
.macro jab.romfs.list buffer, id, directory, offset=zero, capacity=JAB_ROMFS_PAGE
    li a4, \capacity
    mv a3, \offset
    mv a2, \directory
    mv a1, \id
    mv a0, \buffer
    li a7, JAB_SYS_ROMFS_LIST
    ecall
.endm

# jab.romfs.find buffer, id, directory, path: look for that path from
# that directory, a leading / starting at the root instead, and write
# the entry's record into the buffer, which holds one. A hard link is
# followed, so . and .. lead where romfs points them. `path` is a label.
# a0 becomes 0 with the record written, 1 when nothing of that name is
# there, or 2 when a component along the way is not a directory; a1
# becomes the entry's own offset, to list or read it with.
.macro jab.romfs.find buffer, id, directory, path
    la a3, \path
    mv a2, \directory
    mv a1, \id
    mv a0, \buffer
    li a7, JAB_SYS_ROMFS_FIND
    ecall
.endm

# jab.tar.list buffer, archive, length, offset=zero, capacity: write a
# record per entry of a tar archive the program already holds into the
# buffer, starting at that header's offset and 0 for the first. a0
# becomes the records written and a1 the offset to start the next page
# at, 0 once the archive has ended. An entry's data needs no call: the
# record's JAB_TAR_DATA is where it already sits.
.macro jab.tar.list buffer, archive, length, offset=zero, capacity=JAB_TAR_PAGE
    li a4, \capacity
    mv a3, \offset
    mv a2, \length
    mv a1, \archive
    mv a0, \buffer
    li a7, JAB_SYS_TAR_LIST
    ecall
.endm

# jab.tar.find buffer, archive, length, path: look for that path in the
# archive and write its record into the buffer, which holds one. A
# directory's trailing separator is ignored, since tar writes one.
# `path` is a label. a0 becomes 0 with the record written or 1 when the
# archive holds no such name; a1 becomes the entry's own offset.
.macro jab.tar.find buffer, archive, length, path
    la a3, \path
    mv a2, \length
    mv a1, \archive
    mv a0, \buffer
    li a7, JAB_SYS_TAR_FIND
    ecall
.endm

# jab.checksum address, size: the SHA3-256 of those bytes. A digest is
# 32 bytes, which is exactly four registers, so it comes back in a0 to
# a3 and needs no buffer: storing them with four `sd` writes the digest
# in the order anything else computes it.
.macro jab.checksum address, size
    mv a1, \size
    mv a0, \address
    li a7, JAB_SYS_CHECKSUM
    ecall
.endm

# jab.hash address, size: the XXH3-64 of those bytes, which is one
# register wide and comes back in a0. Where jab.checksum answers whether
# bytes are exactly the bytes expected, this answers which bytes they
# are, quickly, for keying and lookups.
.macro jab.hash address, size
    mv a1, \size
    mv a0, \address
    li a7, JAB_SYS_HASH
    ecall
.endm

# jab.gz.size source, length: the length the contents of that gzip will
# be, which its trailer carries, so a program can size its buffer before
# it inflates anything. a0 becomes that length and a1 JAB_GZ_OK or
# JAB_GZ_NOT_GZIP.
.macro jab.gz.size source, length
    mv a1, \length
    mv a0, \source
    li a7, JAB_SYS_GZ_SIZE
    ecall
.endm

# jab.gz.read buffer, source, length, capacity: inflate that gzip into
# the buffer in one call, checking its CRC-32 and its length against
# what came out. Unlike a list's capacity this one is a register, since
# a program works it out from jab.gz.size rather than writing it down.
# a0 becomes the bytes written and a1 one of the JAB_GZ_* codes.
.macro jab.gz.read buffer, source, length, capacity
    mv a3, \capacity
    mv a2, \length
    mv a1, \source
    mv a0, \buffer
    li a7, JAB_SYS_GZ_READ
    ecall
.endm

# jab.romfs.read buffer, id, file, offset, length: read at most length
# bytes of that file from that byte of it into the buffer. `file` is a
# header's offset, as JAB_ROMFS_OFFSET of a record carries. a0 becomes
# the bytes written and a1 the offset to read from next, 0 at the file's
# end, so a loop over a file of any size is the same shape as a listing.
.macro jab.romfs.read buffer, id, file, offset, length
    mv a4, \length
    mv a3, \offset
    mv a2, \file
    mv a1, \id
    mv a0, \buffer
    li a7, JAB_SYS_ROMFS_READ
    ecall
.endm

# jab.png.size source, length: what a PNG the program holds is, from its
# header, so a program can size a sprite for it. a0 becomes the width
# and a1 the height in pixels, with a2 JAB_PNG_OK; or both 0 with a2
# JAB_PNG_NOT_PNG, JAB_PNG_TRUNCATED, JAB_PNG_CRC, or JAB_PNG_UNSUPPORTED
# when jab.sprite.png could not decode it.
.macro jab.png.size source, length
    mv a1, \length
    mv a0, \source
    li a7, JAB_SYS_PNG_SIZE
    ecall
.endm

# jab.sprite.png sprite, source, length, capacity, frames=1: decode the
# PNG at `source` into the sprite record at `sprite`, as a sheet of that
# many frames stacked top to bottom, so the PNG's height must divide by
# `frames`. `capacity` is how many bytes the record's buffer holds, a
# constant, and must reach the rule above, which the call checks. The
# decode is in place, so the buffer holds the filtered rows on the way
# to the pixels. a0 becomes a JAB_PNG_* code: JAB_PNG_OK with the record
# filled, JAB_PNG_FRAMES when the height does not divide, JAB_PNG_SIZE
# when the buffer is too small, and the rest for what is wrong with the
# file.
.macro jab.sprite.png sprite, source, length, capacity, frames=1
    li a4, \frames
    li a3, \capacity
    mv a2, \length
    mv a1, \source
    mv a0, \sprite
    li a7, JAB_SYS_SPRITE_PNG
    ecall
.endm

# jab.sprite.load sprite, id, path, capacity: fill the sprite record
# from a directory on disk `id` named by `path`, a label: its frames are
# the files 0.png, 1.png, and on, in order until one is missing, each
# decoded straight off the disk into its own frame, so the program holds
# no buffer for the files; every frame must be one size. `capacity` is
# how many bytes the record's buffer holds, a constant, and must reach
# the rule above for the frames there are. a0 becomes a JAB_PNG_* code:
# JAB_PNG_NOT_FOUND when the directory or its 0.png is not there,
# JAB_PNG_FRAMES when a frame's size differs from the first's,
# JAB_PNG_SIZE when the buffer is too small, else a frame's own code.
.macro jab.sprite.load sprite, id, path, capacity
    li a3, \capacity
    la a2, \path
    mv a1, \id
    mv a0, \sprite
    li a7, JAB_SYS_SPRITE_LOAD
    ecall
.endm

# jab.sprite.draw sprite, frame, x, y, tint, scale, pose: blend frame
# `frame` of the sprite onto the framebuffer with its top left at x, y,
# which may be negative or past the screen; what falls off an edge is
# clipped. `tint` is a colour the pixels are multiplied by,
# JAB_SPRITE_PLAIN when left out; `scale` is in 256ths,
# JAB_SPRITE_SCALE_ONE when left out; `pose` is an angle in degrees with
# JAB_SPRITE_FLIP_H, JAB_SPRITE_FLIP_V, and JAB_SPRITE_SOLID above it, 0
# when left out, the turn about the scaled frame's centre with x, y
# still where the unturned frame's top left would be. All three are
# registers when given, so a program may vary them at run time. Per
# pixel, alpha 0 is skipped, 255 copied, and anything between blended
# over what is there: each channel becomes (s * a + d * (255 - a)) /
# 255, rounded, with s the sprite's tinted channel and d the screen's;
# solid, the tint is written over every pixel the frame covers instead.
# It only draws; the program flips, whole or the rectangles. a0 becomes
# 0; 1 when the frame is not in the sprite; 2 when the scale is past
# JAB_SPRITE_SCALE_MAX.
.macro jab.sprite.draw sprite, frame, x, y, tint, scale, pose
    .ifb \pose
    li a6, 0
    .else
    mv a6, \pose
    .endif
    .ifb \scale
    li a5, JAB_SPRITE_SCALE_ONE
    .else
    mv a5, \scale
    .endif
    .ifb \tint
    li a4, JAB_SPRITE_PLAIN
    .else
    mv a4, \tint
    .endif
    mv a3, \y
    mv a2, \x
    mv a1, \frame
    mv a0, \sprite
    li a7, JAB_SYS_SPRITE_DRAW
    ecall
.endm
