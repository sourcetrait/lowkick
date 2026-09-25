# sprite's integration test: every way the program drew its two sprites
# is worked out here from the same rules the SDK states - the nearest
# source pixel at the scale, the tint multiply, the alpha blend over
# what is there, each rounded the same way - and every pixel of every
# drawn rectangle is held against the screen, the untouched pixels
# around each included. The codes the refusals gave are checked on the
# UART.
use ../../../sdk/nu/jab.nu
use std/assert

const background = [0x20 0x30 0x40]
const plain = 0xffffff
const one = 256

# blend, as 0xAARRGGBB words, four by three; sheet, two frames of two
# by two, the same words as the program's
const blend = [
    [0xffff0000 0x8000ff00 0x000000ff 0xffffffff]
    [0x40ff8000 0xc0ffffff 0xff102030 0x01ffffff]
    [0x7f7f7f7f 0xfe000000 0x00ffffff 0x80404040]
]
const sheet = [
    [0xff111111 0xff222222 0xffaa0000 0xff00aa00]
    [0xff333333 0xff444444 0xff0000aa 0x80ffffff]
]

# x / 255, rounded, the way the kernel does it
def round255 [x: int]: nothing -> int {
    let t = ($x + 128)
    ($t + ($t bit-shr 8)) bit-shr 8
}

# The channels of a word: red, green, blue, alpha
def channels [word: int]: nothing -> list<int> {
    [(($word bit-shr 16) bit-and 0xff) (($word bit-shr 8) bit-and 0xff) ($word bit-and 0xff) (($word bit-shr 24) bit-and 0xff)]
}

# One drawn pixel over a screen pixel, both as [r g b]
def composite [source: int, under: list<int>, tint: int]: nothing -> list<int> {
    let c = (channels $source)
    let a = $c.3
    if $a == 0 { return $under }
    let t = (channels ($tint bit-or 0xff000000))
    let s = (if $tint == $plain { [$c.0 $c.1 $c.2] } else {
        [(round255 ($c.0 * $t.0)) (round255 ($c.1 * $t.1)) (round255 ($c.2 * $t.2))]
    })
    if $a == 255 { return $s }
    0..2 | each {|i| round255 (($s | get $i) * $a + ($under | get $i) * (255 - $a)) }
}

# What one draw call leaves on the screen: every pixel of the drawn
# rectangle that is on the screen, as {x, y, rgb}, plus a ring of the
# background around it where the ring is on the screen.
def drawn [sprite: list<list<int>>, frame: int, x: int, y: int, tint: int, scale: int]: nothing -> table<x: int, y: int, rgb: list<int>> {
    let fw = (($sprite | first | length) // (if ($sprite | first | length) == 4 and ($sprite | length) == 2 { 2 } else { 1 }))
    let frames = (($sprite | first | length) // $fw)
    let h = ($sprite | length)
    let dw = (($fw * $scale) bit-shr 8)
    let dh = (($h * $scale) bit-shr 8)
    let step_x = (($fw bit-shl 16) // $dw)
    let step_y = (($h bit-shl 16) // $dh)
    let inside = (0..<$dh | each {|dy|
        0..<$dw | each {|dx|
            let sx = (($dx * $step_x) bit-shr 16) + $frame * $fw
            let sy = (($dy * $step_y) bit-shr 16)
            { x: ($x + $dx), y: ($y + $dy), rgb: (composite ($sprite | get $sy | get $sx) $background $tint) }
        }
    } | flatten)
    let ring = ((-1)..$dw | each {|dx|
        [-1 $dh] | each {|dy| { x: ($x + $dx), y: ($y + $dy), rgb: $background } }
    } | flatten) ++ (0..<$dh | each {|dy|
        [-1 $dw] | each {|dx| { x: ($x + $dx), y: ($y + $dy), rgb: $background } }
    } | flatten)
    ($inside ++ $ring) | where {|p| $p.x >= 0 and $p.x < 1920 and $p.y >= 0 and $p.y < 1080 }
}

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --capture 2sec)
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert equal $run.serial "draw 0\ndraw 0\ndraw 0\ndraw 0\ndraw 0\ndraw 0\ndraw 0\ndraw 1\ndraw 2\ndraw 0\n" $"the codes: ($run.serial)"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)

    let draws = [
        (drawn $blend 0 10 10 $plain $one)
        (drawn $blend 0 -2 -1 $plain $one)
        (drawn $blend 0 1918 1079 $plain $one)
        (drawn $blend 0 100 100 0xff8040 $one)
        (drawn $blend 0 200 200 $plain (2 * $one))
        (drawn $blend 0 300 300 $plain ($one // 2))
        (drawn $sheet 1 400 400 $plain $one)
    ]
    mut checked = 0
    for d in ($draws | enumerate) {
        for p in $d.item {
            let want = ($p.rgb | each {|c| $c | format number | get lowerhex | str substring 2.. | fill -a right -c "0" -w 2 } | str join "")
            assert equal (jab pixel $screen $p.x $p.y) $want $"draw ($d.index): the pixel at ($p.x), ($p.y)"
            $checked += 1
        }
    }
    assert equal (jab pixel $screen 5000 0) "203040" "nothing landed where the off-screen draw was aimed"
    print $"sprite: ($checked) pixels of ($draws | length) draws held against the rules; QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    print "sprite: ok"
}
