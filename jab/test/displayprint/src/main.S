# displayprint: the print calls by device. jab.print goes to the UART
# until the display is open and to the screen console after; the named
# calls go where they say. The program then idles so the screen can be
# read.
.include "jab.inc"

.section .text
.global _start
_start:
    jab.print uart_first
    jab.display.open
    bnez a0, no_display
    jab.print on_screen
    jab.uart.print uart_again
    jab.display.print line_two
idle:
    jab.await
    j idle

no_display:
    jab.uart.print msg_no_display
    jab.exit 1

.section .rodata
uart_first:
    .asciz "uart first\n"
on_screen:
    .asciz "on screen\n"
uart_again:
    .asciz "uart again\n"
line_two:
    .asciz "line two\n"
msg_no_display:
    .asciz "displayprint: no display\n"
