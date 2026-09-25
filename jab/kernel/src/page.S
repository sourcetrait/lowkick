.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# Sv39 with 2 MiB pages, one root table and one level 1 table per GiB
# in use, built once and never changed: the first 2 MiB (QEMU's test
# device), the 2 MiB at the UART, and the PLIC's two for the kernel; in
# RAM the kernel's own 2 MiB at its start, supervisor only, then the
# framebuffer's pages, user read-write, then the program's window, user
# read-write-execute, which is every page from there to the end of the
# machine's 4 GiB. Everything is mapped at its physical address; the
# virtio transports sit in the UART's page. The RAM tables sit side by
# side in bss, so a 2 MiB page's slot is its distance from the start of
# RAM, in pages, times eight, whichever GiB it falls in.

# For each address: the PTE (without flags) of the 2 MiB page holding
# it, the page's aligned base as a PPN shifted into place, and the byte
# offset of that page's slot in a level 1 table.
.set TEST_PTE, ((((QEMU_VIRT_TEST >> 21) << 21) >> 12) << 10)
.set TEST_SLOT, (((QEMU_VIRT_TEST >> 21) & 0x1ff) * 8)
.set UART_PTE, ((((QEMU_VIRT_UART0 >> 21) << 21) >> 12) << 10)
.set UART_SLOT, (((QEMU_VIRT_UART0 >> 21) & 0x1ff) * 8)
.set PLIC_PTE, ((((QEMU_VIRT_PLIC >> 21) << 21) >> 12) << 10)
.set PLIC_SLOT, (((QEMU_VIRT_PLIC >> 21) & 0x1ff) * 8)
.set PLIC_PAGES, ((QEMU_VIRT_PLIC_SIZE + 0x1fffff) >> 21)
# In RAM a slot is measured from the start of RAM across the tables.
.set KERNEL_PTE, ((((QEMU_VIRT_DRAM >> 21) << 21) >> 12) << 10)
.set KERNEL_SLOT, (((QEMU_VIRT_DRAM - QEMU_VIRT_DRAM) >> 21) * 8)
.set DISPLAY_PTE, ((((JAB_DISPLAY_BASE >> 21) << 21) >> 12) << 10)
.set DISPLAY_SLOT, (((JAB_DISPLAY_BASE - QEMU_VIRT_DRAM) >> 21) * 8)
.set DISPLAY_PAGES, ((JAB_DISPLAY_SIZE + 0x1fffff) >> 21)
.set PROGRAM_PTE, ((((JAB_PROGRAM_BASE >> 21) << 21) >> 12) << 10)
.set PROGRAM_SLOT, (((JAB_PROGRAM_BASE - QEMU_VIRT_DRAM) >> 21) * 8)
.set PROGRAM_PAGES, (JAB_PROGRAM_SIZE >> 21)
.set RAM_GIBS, (QEMU_VIRT_DRAM_SIZE >> 30)
.set RAM_ROOT_SLOT, (((QEMU_VIRT_DRAM >> 30) & 0x1ff) * 8)
# One page on is this much more PTE.
.set PAGE_PTE_STEP, ((0x200000 >> 12) << 10)

# The window is what the SDK says, and it ends where RAM does.
.if (JAB_PROGRAM_BASE + JAB_PROGRAM_SIZE) != (QEMU_VIRT_DRAM + QEMU_VIRT_DRAM_SIZE)
.error "the program's window does not end at the end of RAM"
.endif
.if (JAB_DISPLAY_BASE + DISPLAY_PAGES * 0x200000) != JAB_PROGRAM_BASE
.error "the program's window does not begin after the framebuffer"
.endif

.section .text
.global page_init
page_init:
    # root: index 0 for the first GiB (the devices), then a table for
    # each GiB of RAM
    la t0, page_root
    la t1, page_l1_devices
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, PTE_TABLE
    sd t1, (((QEMU_VIRT_TEST >> 30) & 0x1ff) * 8)(t0)
    li t1, RAM_ROOT_SLOT
    add t0, t0, t1
    la t1, page_l1_ram
    li t2, RAM_GIBS
    li t4, 4096
1:
    srli t3, t1, 12
    slli t3, t3, 10
    ori t3, t3, PTE_TABLE
    sd t3, 0(t0)
    addi t0, t0, 8
    add t1, t1, t4
    addi t2, t2, -1
    bnez t2, 1b
    # devices: the test device's 2 MiB and the UART's 2 MiB, supervisor only
    la t0, page_l1_devices
    li t1, TEST_PTE | PTE_KERNEL_RW
    sd t1, TEST_SLOT(t0)
    li t1, UART_PTE | PTE_KERNEL_RW
    sd t1, UART_SLOT(t0)
    # the PLIC's pages, supervisor only
    li t1, PLIC_SLOT
    add t0, t0, t1
    li t1, PLIC_PTE | PTE_KERNEL_RW
    li t2, PLIC_PAGES
    li t3, PAGE_PTE_STEP
2:
    sd t1, 0(t0)
    add t1, t1, t3
    addi t0, t0, 8
    addi t2, t2, -1
    bnez t2, 2b
    # ram: the kernel's 2 MiB, supervisor only
    la t0, page_l1_ram
    li t1, KERNEL_PTE | PTE_KERNEL_RWX
    sd t1, KERNEL_SLOT(t0)
    # the framebuffer's pages, user read-write, after the kernel
    li t1, DISPLAY_SLOT
    add t0, t0, t1
    li t1, DISPLAY_PTE | PTE_USER_RW
    li t2, DISPLAY_PAGES
    li t3, PAGE_PTE_STEP
3:
    sd t1, 0(t0)
    add t1, t1, t3
    addi t0, t0, 8
    addi t2, t2, -1
    bnez t2, 3b
    # the program's pages, user read-write-execute, to the end of RAM,
    # running on from one GiB's table into the next
    la t0, page_l1_ram
    li t1, PROGRAM_SLOT
    add t0, t0, t1
    li t1, PROGRAM_PTE | PTE_USER_RWX
    li t2, PROGRAM_PAGES
    li t3, PAGE_PTE_STEP
4:
    sd t1, 0(t0)
    add t1, t1, t3
    addi t0, t0, 8
    addi t2, t2, -1
    bnez t2, 4b
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
    .skip 4096 * RAM_GIBS
