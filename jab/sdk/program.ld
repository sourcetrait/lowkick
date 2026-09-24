/* A Jab program: a flat binary at JAB_PROGRAM_BASE (jab.inc), text first,
   then read-only data, data, and bss, contiguous so objcopy emits one
   image. bss is not in the image; RAM is zero when QEMU starts. */
ENTRY(_start)

SECTIONS
{
    . = 0x80800000;

    .text : { *(.text .text.*) }
    .rodata : { *(.rodata .rodata.*) }
    .data : { *(.data .data.*) }
    .bss : { *(.bss .bss.*) *(COMMON) }
}
