.include "riscv.inc"
.include "qemu_virt.inc"

# Machine-mode entry. QEMU starts every hart here, at the start of RAM,
# with -bios none -kernel. Hart 0 opens memory, delegates traps, hands
# the timer to supervisor mode, and drops to supervisor mode in kmain;
# every other hart parks.
.section .text.boot
.global _start
_start:
    csrr t0, mhartid
    bnez t0, park
    la sp, kernel_stack_top
    # Physical memory protection: one entry over everything.
    li t0, -1
    csrw pmpaddr0, t0
    li t0, PMP_NAPOT_RWX
    csrw pmpcfg0, t0
    # Traps go to supervisor mode; what still lands here stops.
    la t0, mtrap
    csrw mtvec, t0
    li t0, MEDELEG_ALL
    csrw medeleg, t0
    li t0, MIDELEG_S_ALL
    csrw mideleg, t0
    csrw mie, zero
    # The supervisor timer: stimecmp (Sstc), with time readable there.
    li t0, MENVCFG_STCE
    csrs menvcfg, t0
    li t0, MCOUNTEREN_CY_TM_IR
    csrw mcounteren, t0
    # mret into kmain as supervisor.
    csrr t0, mstatus
    li t1, MSTATUS_MPP_MASK
    not t1, t1
    and t0, t0, t1
    li t1, MSTATUS_MPP_S
    or t0, t0, t1
    csrw mstatus, t0
    la t0, kmain
    csrw mepc, t0
    mret

park:
    wfi
    j park

.balign 4
mtrap:
    j mtrap
