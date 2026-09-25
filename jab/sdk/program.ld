/* A Jab program: a flat binary at JAB_PROGRAM_BASE (jab.inc), text first,
   then read-only data, data, and bss, contiguous so objcopy emits one
   image. bss is not in the image; RAM is zero when QEMU starts. Two
   segments, code with its read-only data and then writable data, so
   the linker sees no segment that is read, write, and execute at once,
   though the whole window is. */
ENTRY(_start)

PHDRS
{
    code PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = 0x80800000;

    .text : { *(.text .text.*) } :code
    .rodata : { *(.rodata .rodata.*) } :code
    .data : { *(.data .data.*) } :data
    .bss : { *(.bss .bss.*) *(COMMON) } :data
}
