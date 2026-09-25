# riscv.inc: the RISC-V privileged bits the kernel touches.

# mstatus
.set MSTATUS_MPP_MASK, (3 << 11)
.set MSTATUS_MPP_S, (1 << 11)

# sstatus
.set SSTATUS_SPIE, (1 << 5)
.set SSTATUS_SPP, (1 << 8)
.set SSTATUS_SUM, (1 << 18)

# sie: the supervisor timer interrupt
.set SIE_STIE, (1 << 5)

# menvcfg: stimecmp (Sstc) usable in supervisor mode
.set MENVCFG_STCE, (1 << 63)

# mcounteren: cycle, time, and instret readable below machine mode
.set MCOUNTEREN_CY_TM_IR, 0x7

# One PMP entry, NAPOT, read, write, execute
.set PMP_NAPOT_RWX, 0x1f

# Delegation: every exception; the three supervisor interrupts
.set MEDELEG_ALL, 0xffff
.set MIDELEG_S_ALL, 0x222

# scause values
.set SCAUSE_ECALL_U, 8

# Sv39
.set SATP_MODE_SV39, (8 << 60)
.set PTE_V, 0x01
.set PTE_R, 0x02
.set PTE_W, 0x04
.set PTE_X, 0x08
.set PTE_U, 0x10
.set PTE_A, 0x40
.set PTE_D, 0x80
.set PTE_TABLE, PTE_V
.set PTE_KERNEL_RW, (PTE_V | PTE_R | PTE_W | PTE_A | PTE_D)
.set PTE_KERNEL_RWX, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)
.set PTE_USER_RW, (PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)
.set PTE_USER_RWX, (PTE_V | PTE_R | PTE_W | PTE_X | PTE_U | PTE_A | PTE_D)
