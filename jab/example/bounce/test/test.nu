# bounce's integration test: after three seconds the screen holds the
# ball, a disc of radius 90 in its colour on the background, moved from
# where it started, and the hart has been halting between frames.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let run = (jab launch --kernel $kernel --image $image --out $out --capture 3sec)
    assert equal $run.serial "" "the UART stays silent"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)
    assert equal [$screen.width $screen.height] [1920 1080] "a 1080p frame"
    let ball = (jab ink $screen "8f00ff")
    assert ($ball.count > 24900 and $ball.count < 26000) $"a disc of radius 90 has about 25447 pixels, not ($ball.count)"
    assert equal ($ball.right - $ball.left + 1) 181 "the ball's width"
    assert equal ($ball.bottom - $ball.top + 1) 181 "the ball's height"
    assert ($ball.left > 300) $"the ball has moved from where it started: left edge ($ball.left)"
    assert equal (jab pixel $screen 0 0) "101018" "the background at the top left"
    assert equal (jab pixel $screen 1919 1079) "101018" "the background at the bottom right"
    print $"bounce: ball at ($ball.left),($ball.top); QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts between frames"
    print "bounce: ok"
}
