# jab.inc: the Jab SDK header. `.include "jab.inc"` and call the kernel
# with the jab.* macros, assembler style: `jab.print message`.
.include "jab_keys.inc"

# Where a program lives. QEMU's loader device places the .jab file at
# JAB_PROGRAM_BASE; the program owns JAB_PROGRAM_SIZE bytes from there,
# and starts with sp at JAB_STACK_TOP.
.set JAB_PROGRAM_BASE, 0x80800000
.set JAB_PROGRAM_SIZE, 0x200000
.set JAB_STACK_TOP, (JAB_PROGRAM_BASE + JAB_PROGRAM_SIZE)

# The display: a framebuffer right after the window, JAB_DISPLAY_WIDTH
# by JAB_DISPLAY_HEIGHT pixels of four bytes each, blue, green, red, and
# one unused, so a pixel stored as a little-endian word reads 0x00RRGGBB
# and a row is JAB_DISPLAY_PITCH bytes. The program draws into it and
# jab.display.flip shows it; RAM starts zero, so it starts black. Flips
# are capped at JAB_DISPLAY_FPS_CAP a second, and JAB_DISPLAY_FPS_TARGET
# is the rate a program is built to hold.
.set JAB_DISPLAY_BASE, 0x80a00000
.set JAB_DISPLAY_WIDTH, 1920
.set JAB_DISPLAY_HEIGHT, 1080
.set JAB_DISPLAY_PITCH, (JAB_DISPLAY_WIDTH * 4)
.set JAB_DISPLAY_SIZE, (JAB_DISPLAY_PITCH * JAB_DISPLAY_HEIGHT)
.set JAB_DISPLAY_FPS_TARGET, 30
.set JAB_DISPLAY_FPS_CAP, 32

# The time counter: `rdtime` reads it, JAB_TIME_HZ ticks a second.
.set JAB_TIME_HZ, 10000000

# What jab.await waits for: a mask of these, or 0 for all of them
.set JAB_AWAIT_ALL, 0
.set JAB_AWAIT_DISPLAY, 1
.set JAB_AWAIT_KEYBOARD, 2

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

# jab.display.print message: write a NUL-terminated string to the screen
# console, opening the display first if the program has not. A newline
# ends the line, and the console scrolls at the bottom. a0 becomes 0, or
# jab.display.open's code.
.macro jab.display.print message
    la a0, \message
    li a7, JAB_SYS_DISPLAY_PRINT
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
# (JAB_AWAIT_KEYBOARD), or either (JAB_AWAIT_ALL). The one call that
# waits, and how a program idles between frames instead of spinning. a0
# becomes the events that fired.
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
