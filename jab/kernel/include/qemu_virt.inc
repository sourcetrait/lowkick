# qemu_virt.inc: QEMU's virt machine, the only machine Jab runs on. The
# map is fixed, so it is written down here rather than read from a
# device tree.

# 16550 UART, byte registers: transmit at 0, line status at 5
.set QEMU_VIRT_UART0, 0x10000000

# The test device: a 32-bit write ends QEMU with an exit code
.set QEMU_VIRT_TEST, 0x100000
.set QEMU_TEST_PASS, 0x5555
.set QEMU_TEST_FAIL, 0x3333

# RAM begins here; -kernel loads the kernel at its start
.set QEMU_VIRT_DRAM, 0x80000000
