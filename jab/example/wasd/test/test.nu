# wasd's integration test: your sphere starts at the centre and, after
# D is held for most of a second, has moved right and is whole on the
# screen; the other sphere is whole too, never overlapped; the hart
# halts between frames.
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
    # D drives it right and nothing drives it up or down, but the other
    # sphere starts somewhere random and bounces off yours, which does,
    # so a level path is not something this example promises. Over six
    # runs of the same build, three ended level and three ended between
    # 605 and 810. What holds every time is that it went right and that
    # both discs are whole, since the two never overlap.
    assert ($centre_y > 90 and $centre_y < 990) $"your sphere is whole on the screen: ($centre_y)"
    let ball = (jab ink $screen "8f00ff")
    assert ($ball.count > 24900 and $ball.count < 26000) $"the other sphere is whole on the screen, since the two never overlap: ($ball.count) pixels"
    assert equal ($ball.right - $ball.left + 1) 181 "the other sphere's width"
    assert equal ($ball.bottom - $ball.top + 1) 181 "the other sphere's height"
    print $"wasd: yours at ($centre_x),($centre_y), the other at ($ball.left),($ball.top); QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts between frames"
    print "wasd: ok"
}
