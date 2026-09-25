.include "riscv.inc"
.include "qemu_virt.inc"
.include "jab.inc"

# The frame clock and the wait: a tick every 1/JAB_DISPLAY_FPS_CAP of a
# second, kept as the time of the next tick. jab.display.flip moves it,
# jab.display.ready reads it, and jab.await halts the hart until it,
# or until a key arrives, through the supervisor timer (stimecmp) and
# the PLIC, with the interrupts enabled only while waiting and taken by
# wfi rather than by the trap vector.
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

# sys_await (jab.await): a0 is the mask of events to wait for, 0 for
# all of them: the display's next tick (JAB_AWAIT_DISPLAY), a key event
# (JAB_AWAIT_KEYBOARD), which brings the keyboard up and is dropped from
# the mask when there is none, and bytes from the host
# (JAB_AWAIT_DATA), dropped when the build or the machine has no data
# port. a0 becomes the events that ended the wait, 0 when nothing in
# the mask can happen.
.global sys_await
sys_await:
    mv s0, a0
    bnez s0, 1f
    li s0, JAB_AWAIT_DISPLAY | JAB_AWAIT_KEYBOARD | JAB_AWAIT_DATA
1:
    andi t0, s0, JAB_AWAIT_KEYBOARD
    beqz t0, 2f
    call keyboard_open
    beqz a0, 2f
    andi s0, s0, ~JAB_AWAIT_KEYBOARD
2:
.ifdef DATA
    andi t0, s0, JAB_AWAIT_DATA
    beqz t0, 20f
    call serial_open
    beqz a0, 20f
    andi s0, s0, ~JAB_AWAIT_DATA
20:
.else
    andi s0, s0, ~JAB_AWAIT_DATA
.endif
    li a0, 0
    beqz s0, 9f
    # the display's tick: a tick already past moves forward, period by
    # period, so the wait is always for a tick to come; then the timer
    # is armed
    andi t0, s0, JAB_AWAIT_DISPLAY
    beqz t0, 3f
    la t2, frame_tick
    ld t1, 0(t2)
    li t3, TICK
    rdtime t0
21:
    bltu t0, t1, 22f
    add t1, t1, t3
    j 21b
22:
    sd t1, 0(t2)
    csrw stimecmp, t1
    li t4, SIE_STIE
    csrs sie, t4
3:
    andi t0, s0, JAB_AWAIT_KEYBOARD | JAB_AWAIT_DATA
    beqz t0, 4f
    li t4, SIE_SEIE
    csrs sie, t4
4:
    # wait: what in the mask has happened, else halt
    li s1, 0
    andi t0, s0, JAB_AWAIT_DISPLAY
    beqz t0, 5f
    rdtime t0
    la t1, frame_tick
    ld t1, 0(t1)
    bltu t0, t1, 5f
    ori s1, s1, JAB_AWAIT_DISPLAY
5:
    andi t0, s0, JAB_AWAIT_KEYBOARD
    beqz t0, 6f
    call keyboard_pending
    beqz a0, 6f
    ori s1, s1, JAB_AWAIT_KEYBOARD
6:
.ifdef DATA
    andi t0, s0, JAB_AWAIT_DATA
    beqz t0, 60f
    call data_pending
    beqz a0, 60f
    ori s1, s1, JAB_AWAIT_DATA
60:
.endif
    bnez s1, 7f
    wfi
    call plic_service
    j 4b
7:
    li t4, SIE_STIE | SIE_SEIE
    csrc sie, t4
    li t0, -1
    csrw stimecmp, t0
    mv a0, s1
9:
    sd a0, 80(sp)
    j trap_return

.section .bss
.balign 8
frame_tick:
    .skip 8
