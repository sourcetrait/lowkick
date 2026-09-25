# wasd's integration test: your sphere starts at the centre and, after
# D is held for most of a second, has moved right and not up or down;
# the other sphere is on the screen; the hart halts between frames.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let run = (jab launch --kernel $kernel --image $image --out $out --keys [[at, key, hold]; [1sec, "d", 800]] --capture 3500ms)
    assert equal $run.serial "" "the UART stays silent"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)
    let player = (jab ink $screen "ff5533")
    assert ($player.count > 24900 and $player.count < 26000) $"your sphere, a disc of radius 90, has about 25447 pixels, not ($player.count)"
    let centre_x = (($player.left + $player.right) // 2)
    let centre_y = (($player.top + $player.bottom) // 2)
    assert ($centre_x > 1160) $"your sphere has moved right from the centre: ($centre_x)"
    assert ($centre_y >= 538 and $centre_y <= 542) $"and not up or down: ($centre_y)"
    let ball = (jab ink $screen "8f00ff")
    assert ($ball.count > 1000) $"the other sphere is on the screen, though yours may cover part of it: ($ball.count) pixels"
    assert (($ball.right - $ball.left + 1) <= 181 and ($ball.bottom - $ball.top + 1) <= 181) "and no bigger than a sphere"
    print $"wasd: yours at ($centre_x),($centre_y), the other at ($ball.left),($ball.top); QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts between frames"
    print "wasd: ok"
}
