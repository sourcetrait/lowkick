.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# The frame clock: a tick every 1/JAB_DISPLAY_FPS_CAP of a second, kept
# as the time of the next tick. jab.display.flip moves it, jab.display.ready
# reads it, and jab.await halts the hart until it through the supervisor
# timer, stimecmp, with the timer interrupt enabled only while waiting
# and taken by wfi rather than by the trap vector.
.set TICK, (QEMU_VIRT_TIMEBASE / JAB_DISPLAY_FPS_CAP)

.section .text

# frame_clock_init: the first tick is now.
.global frame_clock_init
frame_clock_init:
    rdtime t0
    la t1, frame_tick
    sd t0, 0(t1)
    ret

# frame_ready: a0 becomes 1 when the next tick has come, else 0.
.global frame_ready
frame_ready:
    rdtime t0
    la t1, frame_tick
    ld t1, 0(t1)
    sltu a0, t0, t1
    xori a0, a0, 1
    ret

# frame_flipped: a flip went through now. The next tick is one period
# after the current one, or one period from now when a whole period has
# already gone by, so a punctual program keeps an exact cadence and a
# slow one is never refused.
.global frame_flipped
frame_flipped:
    rdtime t0
    la t2, frame_tick
    ld t1, 0(t2)
    li t3, TICK
    add t1, t1, t3
    bltu t0, t1, 1f
    add t1, t0, t3
1:
    sd t1, 0(t2)
    ret

# frame_await: halt until the next tick. A tick already past is moved
# forward, period by period, so the wait is always for a tick to come.
.global frame_await
frame_await:
    la t2, frame_tick
    ld t1, 0(t2)
    li t3, TICK
    rdtime t0
1:
    bltu t0, t1, 2f
    add t1, t1, t3
    j 1b
2:
    sd t1, 0(t2)
    csrw stimecmp, t1
    li t4, SIE_STIE
    csrs sie, t4
3:
    rdtime t0
    bgeu t0, t1, 4f
    wfi
    j 3b
4:
    csrc sie, t4
    li t0, -1
    csrw stimecmp, t0
    ret

# sys_await (jab.await): a0 is the mask of events to wait for, 0 for all
# of them. The display's tick is the only event so far, so every mask
# waits for it; a0 becomes the events that ended the wait.
.global sys_await
sys_await:
    call frame_await
    li a0, JAB_AWAIT_DISPLAY
    sd a0, 80(sp)
    j trap_return

.section .bss
.balign 8
frame_tick:
    .skip 8
