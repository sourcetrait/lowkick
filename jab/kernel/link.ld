/* The Jab kernel at the start of QEMU virt's RAM. .text.boot holds
   _start and goes first so the entry sits at 0x80000000 whatever the
   object order. Sections are page aligned; bss is zeroed by kmain. */
ENTRY(_start)

SECTIONS
{
    . = 0x80000000;

    .text : {
        KEEP(*(.text.boot))
        *(.text .text.*)
    }

    . = ALIGN(4096);
    .rodata : { *(.rodata .rodata.*) }

    . = ALIGN(4096);
    .data : { *(.data .data.*) }

    . = ALIGN(4096);
    .bss : {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4096);
        _bss_end = .;
    }

    _kernel_end = .;
}
