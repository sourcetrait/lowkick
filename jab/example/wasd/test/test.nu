# wasd's integration test: your sphere starts at the centre and, after
# D is held for most of a second, has moved right; the other sphere is
# whole too, never overlapped; the hart halts between frames. The
# program is a debug build here, and reports each meeting of the spheres
# on the UART: with no meeting your sphere is still level, since only D
# was pressed, and after one its height is the meeting's to decide.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --keys [[at, key, hold]; [1sec, "d", 800]] --capture 3500ms)
    let lines = ($run.serial | lines)
    let meetings = ($lines | where {|l| $l == "wasd: meeting" } | length)
    assert equal ($lines | where {|l| $l != "wasd: meeting" }) [] $"the UART carries nothing but meeting reports: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)
    let player = (jab ink $screen "ff5533")
    assert ($player.count > 24900 and $player.count < 26000) $"your sphere, a disc of radius 90, has about 25447 pixels, not ($player.count)"
    let centre_x = (($player.left + $player.right) // 2)
    let centre_y = (($player.top + $player.bottom) // 2)
    assert ($centre_x > 1160) $"your sphere has moved right from the centre: ($centre_x)"
    if $meetings == 0 {
        # D drives it right and nothing drives it up or down
        assert ($centre_y >= 538 and $centre_y <= 542) $"with no meeting, your sphere stays level: ($centre_y)"
    } else {
        # the other sphere hit yours somewhere, so the height is its
        # doing; what holds is that the disc is whole
        assert ($centre_y > 90 and $centre_y < 990) $"after a meeting, your sphere is still whole on the screen: ($centre_y)"
    }
    let ball = (jab ink $screen "8f00ff")
    assert ($ball.count > 24900 and $ball.count < 26000) $"the other sphere is whole on the screen, since the two never overlap: ($ball.count) pixels"
    assert equal ($ball.right - $ball.left + 1) 181 "the other sphere's width"
    assert equal ($ball.bottom - $ball.top + 1) 181 "the other sphere's height"
    print $"wasd: yours at ($centre_x),($centre_y), the other at ($ball.left),($ball.top), ($meetings) meetings; QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts between frames"
    print "wasd: ok"
}
