# jab.inc: the Jab SDK header. `.include "jab.inc"` and call the kernel
# with the jab.* macros, assembler style: `jab.print message`.

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

# What jab.await waits for: a mask of these, or 0 for all of them
.set JAB_AWAIT_ALL, 0
.set JAB_AWAIT_DISPLAY, 1

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

# jab.await mask=JAB_AWAIT_ALL: halt until an event in the mask, which is
# the display's next frame tick (JAB_AWAIT_DISPLAY), every event there
# is so far. The one call that waits, and how a program idles between
# frames instead of spinning. a0 becomes the events that fired.
.macro jab.await mask=JAB_AWAIT_ALL
    li a0, \mask
    li a7, JAB_SYS_AWAIT
    ecall
.endm

# jab.display.await: jab.await for the display's frame tick.
.macro jab.display.await
    jab.await JAB_AWAIT_DISPLAY
.endm
