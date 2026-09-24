.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# Sv39 with 2 MiB pages, one table per level, built once and never
# changed: the first 2 MiB (QEMU's test device) and the 2 MiB at the
# UART for the kernel, the kernel's own 2 MiB at the start of RAM, and
# the program's 2 MiB window for user mode. Everything is mapped at its
# physical address.

# For each address: the PTE (without flags) of the 2 MiB page holding
# it, the page's aligned base as a PPN shifted into place, and the byte
# offset of that page's slot in a level 1 table.
.set TEST_PTE, ((((QEMU_VIRT_TEST >> 21) << 21) >> 12) << 10)
.set TEST_SLOT, (((QEMU_VIRT_TEST >> 21) & 0x1ff) * 8)
.set UART_PTE, ((((QEMU_VIRT_UART0 >> 21) << 21) >> 12) << 10)
.set UART_SLOT, (((QEMU_VIRT_UART0 >> 21) & 0x1ff) * 8)
.set KERNEL_PTE, ((((QEMU_VIRT_DRAM >> 21) << 21) >> 12) << 10)
.set KERNEL_SLOT, (((QEMU_VIRT_DRAM >> 21) & 0x1ff) * 8)
.set PROGRAM_PTE, ((((JAB_PROGRAM_BASE >> 21) << 21) >> 12) << 10)
.set PROGRAM_SLOT, (((JAB_PROGRAM_BASE >> 21) & 0x1ff) * 8)

.section .text
.global page_init
page_init:
    # root: index 0 for the first GiB (the devices), index 2 for RAM
    la t0, page_root
    la t1, page_l1_devices
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, PTE_TABLE
    sd t1, (((QEMU_VIRT_TEST >> 30) & 0x1ff) * 8)(t0)
    la t1, page_l1_ram
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, PTE_TABLE
    sd t1, (((QEMU_VIRT_DRAM >> 30) & 0x1ff) * 8)(t0)
    # devices: the test device's 2 MiB and the UART's 2 MiB, supervisor only
    la t0, page_l1_devices
    li t1, TEST_PTE | PTE_KERNEL_RW
    sd t1, TEST_SLOT(t0)
    li t1, UART_PTE | PTE_KERNEL_RW
    sd t1, UART_SLOT(t0)
    # ram: the kernel's 2 MiB, supervisor only; the program's 2 MiB, user
    la t0, page_l1_ram
    li t1, KERNEL_PTE | PTE_KERNEL_RWX
    sd t1, KERNEL_SLOT(t0)
    li t1, PROGRAM_PTE | PTE_USER_RWX
    sd t1, PROGRAM_SLOT(t0)
    # satp: Sv39 with the root table
    la t0, page_root
    srli t0, t0, 12
    li t1, SATP_MODE_SV39
    or t0, t0, t1
    csrw satp, t0
    sfence.vma
    ret

.section .bss
.balign 4096
page_root:
    .skip 4096
page_l1_devices:
    .skip 4096
page_l1_ram:
    .skip 4096
