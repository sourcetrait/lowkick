# wasd's integration test, through its data channel: the host holds D
# for most of a second by sending key events into the port, and reads
# back wasd's records. The drive vector is reported when D goes down and
# when it comes up, your sphere's velocity grows while it is held and
# shrinks after, the ball's first velocity is bounce's, every wall hit's
# contact point lies on a screen edge, a meeting is reported for both
# spheres at one point, and the screen agrees: your sphere has moved
# right and, with no meeting, is still level. The hart halts between
# frames and the UART stays silent.
use ../../../sdk/nu/jab.nu
use std/assert

# The API's records, as example/wasd/src/main.S lays them out
const CMD_SIZE = 4
const REPORT_SIZE = 12
const REPORT_VELOCITY = 1
const REPORT_ACCELERATION = 2
const REPORT_HIT = 3
const SPHERE_PLAYER = 1
const SPHERE_BALL = 2
const AGAINST_WALL = 0
# The program's numbers: 8 fractional bits, ACCEL = ONE * 4 / 5, bounce's speed
const ONE = 256
const ACCEL = 204
const TOP_SPEED = 6656
const BALL_VX = 1792
const BALL_VY = 1280
# Where a contact point lies on a wall: a centre at LEFT or TOP less a
# radius is 0, at RIGHT or BOTTOM plus a radius the last pixel
const WALL_LEFT = 0
const WALL_RIGHT = 491264
const WALL_TOP = 0
const WALL_BOTTOM = 276224
# Linux's codes, as sdk/jab_keys.inc
const KEY_D = 32
const PRESSED = 1
const RELEASED = 0

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let hold = (key-event $KEY_D $PRESSED)
    let free = (key-event $KEY_D $RELEASED)
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --data [[at, bytes]; [1sec, $hold], [1800ms, $free]] --capture 3500ms)
    print $"wasd: status ($run.status) after ($run.wall_seconds | math round -p 2) seconds, ($run.data | bytes length) bytes of records, ($run.debug | lines | length) kernel debug lines"
    assert equal $run.serial "" $"the UART stays silent: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.screen != "") "a screen was taken"
    let reports = (records $run.data)
    assert (($reports | length) > 0) "wasd reported through the data channel"
    assert equal (($run.data | bytes length) mod $REPORT_SIZE) 0 "whole records only"

    # the drive vector: D down, then D up
    let drive = ($reports | where kind == $REPORT_ACCELERATION and sphere == $SPHERE_PLAYER)
    assert equal ($drive | select x y) [{x: $ACCEL, y: 0}, {x: 0, y: 0}] $"the drive vector as D goes down and comes up: ($drive)"

    # your velocity: grows while D is held, never past the top speed,
    # and is smaller at the end than at its peak
    let mine = ($reports | where kind == $REPORT_VELOCITY and sphere == $SPHERE_PLAYER)
    assert (($mine | length) > 10) $"your velocity was reported frame by frame: ($mine | length)"
    let peak = ($mine | get x | math max)
    assert ($peak > $ACCEL * 10 and $peak <= $TOP_SPEED) $"a peak speed from most of a second of D: ($peak)"
    assert (($mine | last | get x) < $peak) $"and slowing once D is up: ($mine | last | get x)"

    # the ball: bounce's speed first, and every wall hit on an edge
    let ball = ($reports | where kind == $REPORT_VELOCITY and sphere == $SPHERE_BALL)
    assert equal ($ball | first | select x y) {x: $BALL_VX, y: $BALL_VY} "the ball starts at bounce's speed"
    let wall_hits = ($reports | where kind == $REPORT_HIT and against == $AGAINST_WALL)
    for h in $wall_hits {
        assert ($h.x == $WALL_LEFT or $h.x == $WALL_RIGHT or $h.y == $WALL_TOP or $h.y == $WALL_BOTTOM) $"a wall hit's contact point lies on an edge: ($h)"
    }

    # a meeting is one point reported for both spheres
    let meetings = ($reports | where kind == $REPORT_HIT and against != $AGAINST_WALL)
    let yours = ($meetings | where sphere == $SPHERE_PLAYER)
    let theirs = ($meetings | where sphere == $SPHERE_BALL)
    assert equal ($yours | select x y) ($theirs | select x y) "each meeting is reported for both spheres at the same point"

    # the screen agrees
    let screen = (jab screen $run.screen)
    let player = (jab ink $screen "ff5533")
    assert ($player.count > 24900 and $player.count < 26000) $"your sphere, a disc of radius 90, has about 25447 pixels, not ($player.count)"
    let centre_x = (($player.left + $player.right) // 2)
    let centre_y = (($player.top + $player.bottom) // 2)
    assert ($centre_x > 1160) $"your sphere has moved right from the centre: ($centre_x)"
    if ($yours | is-empty) {
        assert ($centre_y >= 538 and $centre_y <= 542) $"with no meeting, your sphere stays level: ($centre_y)"
    } else {
        assert ($centre_y > 90 and $centre_y < 990) $"after a meeting, your sphere is still whole on the screen: ($centre_y)"
    }
    let disc = (jab ink $screen "8f00ff")
    assert ($disc.count > 24900 and $disc.count < 26000) $"the other sphere is whole on the screen, since the two never overlap: ($disc.count) pixels"
    assert equal ($disc.right - $disc.left + 1) 181 "the other sphere's width"
    assert equal ($disc.bottom - $disc.top + 1) 181 "the other sphere's height"
    print $"wasd: ($reports | length) records, yours at ($centre_x),($centre_y) peaking at ($peak), ($wall_hits | length) wall hits, ($yours | length) meetings; QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts between frames"
    print "wasd: ok"
}

# A key event as the port takes it: the code and the value, 16 bits
# each, little-endian.
def key-event [code: int, value: int]: nothing -> binary {
    ($code | into binary --endian little | bytes at 0..<2) ++ ($value | into binary --endian little | bytes at 0..<2)
}

# wasd's reports, one record each.
def records [data: binary]: nothing -> table<kind: int, sphere: int, against: int, x: int, y: int> {
    let count = (($data | bytes length) // $REPORT_SIZE)
    0..<$count | each {|i|
        let r = ($data | bytes at ($i * $REPORT_SIZE)..<(($i + 1) * $REPORT_SIZE))
        {
            kind: ($r | bytes at 0..<1 | into int),
            sphere: ($r | bytes at 1..<2 | into int),
            against: ($r | bytes at 2..<3 | into int),
            x: ($r | bytes at 4..<8 | into int --endian little --signed),
            y: ($r | bytes at 8..<12 | into int --endian little --signed),
        }
    }
}
