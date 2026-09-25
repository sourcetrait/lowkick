# qemu_virt.inc: QEMU's virt machine, the only machine Jab runs on. The
# map is fixed, so it is written down here rather than read from a
# device tree.

# 16550 UART, byte registers: transmit at 0, line status at 5
.set QEMU_VIRT_UART0, 0x10000000

# virtio over mmio: eight transports from QEMU_VIRT_VIRTIO0, one page
# apart, modern with -global virtio-mmio.force-legacy=false; a device is
# found by its id, since -device order is free. Transport n's interrupt
# line at the PLIC is QEMU_VIRT_VIRTIO_IRQ0 + n.
.set QEMU_VIRT_VIRTIO0, 0x10001000
.set QEMU_VIRT_VIRTIO_STRIDE, 0x1000
.set QEMU_VIRT_VIRTIO_COUNT, 8
.set QEMU_VIRT_VIRTIO_IRQ0, 1

# The PLIC, the platform interrupt controller: a priority word per
# line, enable words per context, and a threshold and a claim word per
# context; hart 0's supervisor context is 1.
.set QEMU_VIRT_PLIC, 0x0c000000
.set QEMU_VIRT_PLIC_PRIORITY, 0x0
.set QEMU_VIRT_PLIC_ENABLE, 0x2000
.set QEMU_VIRT_PLIC_ENABLE_STRIDE, 0x80
.set QEMU_VIRT_PLIC_CONTEXT, 0x200000
.set QEMU_VIRT_PLIC_CONTEXT_STRIDE, 0x1000
.set QEMU_VIRT_PLIC_THRESHOLD, 0
.set QEMU_VIRT_PLIC_CLAIM, 4
.set QEMU_VIRT_HART0_S_CONTEXT, 1
.set QEMU_VIRT_PLIC_SIZE, 0x400000

# The test device: a 32-bit write ends QEMU with an exit code
.set QEMU_VIRT_TEST, 0x100000
.set QEMU_TEST_PASS, 0x5555
.set QEMU_TEST_FAIL, 0x3333

# RAM begins here; -kernel loads the kernel at its start
.set QEMU_VIRT_DRAM, 0x80000000

# The timebase: how many times the time counter ticks a second
.set QEMU_VIRT_TIMEBASE, 10000000
