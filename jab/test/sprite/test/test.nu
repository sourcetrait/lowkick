# sprite's integration test: every way the program drew its two sprites
# is worked out here from the same rules the SDK states - the nearest
# source pixel at the scale, the flips, the turn about the centre in
# 16.16 with the same sine table, the tint multiply, the alpha blend
# over what is there, each rounded the same way - and every pixel of
# every drawn rectangle is held against the screen, the untouched
# pixels around each included. The codes the refusals gave are checked
# on the UART.
use ../../../sdk/nu/jab.nu
use std/assert

const background = [0x20 0x30 0x40]
const plain = 0xffffff
const one = 256
const flip_h = 0x10000
const flip_v = 0x20000
const width = 1920
const height = 1080

# blend, one frame of four by three as 0xAARRGGBB words; sheet, two
# frames of two by two, the same words as the program's
const blend = [
    [
        [0xffff0000 0x8000ff00 0x000000ff 0xffffffff]
        [0x40ff8000 0xc0ffffff 0xff102030 0x01ffffff]
        [0x7f7f7f7f 0xfe000000 0x00ffffff 0x80404040]
    ]
]
const sheet = [
    [[0xff111111 0xff222222] [0xff333333 0xff444444]]
    [[0xffaa0000 0xff00aa00] [0xff0000aa 0x80ffffff]]
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

# The kernel's sine table: 0 to 90 degrees in 16.16, rounded
def sine-table []: nothing -> list<int> {
    let pi = 3.141592653589793
    0..90 | each {|d| (($d | into float) * $pi / 180.0 | math sin) * 65536.0 | math round | into int }
}

# sin and cos of an angle in degrees, signed 16.16, from the table
def trig [angle: int, table: list<int>]: nothing -> list<int> {
    let q = ($angle // 90)
    let r = ($angle mod 90)
    let tr = ($table | get $r)
    let tc = ($table | get (90 - $r))
    match $q {
        0 => [$tr $tc],
        1 => [$tc (0 - $tr)],
        2 => [(0 - $tr) (0 - $tc)],
        _ => [(0 - $tc) $tr],
    }
}

# What one draw call leaves on the screen: every pixel of the drawn
# rectangle, or of the turned rectangle's bounding box, that is on the
# screen, as {x, y, rgb}, plus a ring of the background around it.
def drawn [sprite: list, frame: int, x: int, y: int, tint: int, scale: int, pose: int]: nothing -> table<x: int, y: int, rgb: list<int>> {
    let rows = ($sprite | get $frame)
    let fw = ($rows | first | length)
    let fh = ($rows | length)
    let mirror_h = (($pose bit-and $flip_h) != 0)
    let mirror_v = (($pose bit-and $flip_v) != 0)
    let angle = (($pose bit-and 0xffff) mod 360)
    let dw = (($fw * $scale) bit-shr 8)
    let dh = (($fh * $scale) bit-shr 8)
    let step_x = (($fw bit-shl 16) // $dw)
    let step_y = (($fh bit-shl 16) // $dh)
    let sample = {|sx: int, sy: int|
        let col = (if $mirror_h { $fw - 1 - $sx } else { $sx })
        let row = (if $mirror_v { $fh - 1 - $sy } else { $sy })
        $rows | get $row | get $col
    }
    let box = (if $angle == 0 {
        { x0: $x, x1: ($x + $dw), y0: $y, y1: ($y + $dh) }
    } else {
        let hw = ($dw bit-shl 15)
        let hh = ($dh bit-shl 15)
        let cx = (($x * 65536) + $hw)
        let cy = (($y * 65536) + $hh)
        let sc = (trig $angle (sine-table))
        let rx = (((($hw * $sc.1) | math abs) // 65536) + ((($hh * $sc.0) | math abs) // 65536))
        let ry = (((($hw * $sc.0) | math abs) // 65536) + ((($hh * $sc.1) | math abs) // 65536))
        { x0: (($cx - $rx) // 65536), x1: ((($cx + $rx) // 65536) + 1), y0: (($cy - $ry) // 65536), y1: ((($cy + $ry) // 65536) + 1) }
    })
    let inside = ($box.y0..<$box.y1 | each {|py|
        $box.x0..<$box.x1 | each {|px|
            let hit = (if $angle == 0 {
                { sx: ((($px - $x) * $step_x) bit-shr 16), sy: ((($py - $y) * $step_y) bit-shr 16) }
            } else {
                let hw = ($dw bit-shl 15)
                let hh = ($dh bit-shl 15)
                let cx = (($x * 65536) + $hw)
                let cy = (($y * 65536) + $hh)
                let sc = (trig $angle (sine-table))
                let u = (($px * 65536) + 32768 - $cx)
                let v = (($py * 65536) + 32768 - $cy)
                let up = (($u * $sc.1 + $v * $sc.0) // 65536)
                let vp = (($v * $sc.1 - $u * $sc.0) // 65536)
                let sxf = ($up + $hw)
                let syf = ($vp + $hh)
                if $sxf < 0 or $sxf >= ($dw * 65536) or $syf < 0 or $syf >= ($dh * 65536) { null } else {
                    let sx = (($sxf * $step_x) // 4294967296)
                    let sy = (($syf * $step_y) // 4294967296)
                    if $sx >= $fw or $sy >= $fh { null } else { { sx: $sx, sy: $sy } }
                }
            })
            let rgb = (if $hit == null { $background } else { composite (do $sample $hit.sx $hit.sy) $background $tint })
            { x: $px, y: $py, rgb: $rgb }
        }
    } | flatten)
    let ring = (($box.x0 - 1)..$box.x1 | each {|px|
        [($box.y0 - 1) $box.y1] | each {|py| { x: $px, y: $py, rgb: $background } }
    } | flatten) ++ ($box.y0..<$box.y1 | each {|py|
        [($box.x0 - 1) $box.x1] | each {|px| { x: $px, y: $py, rgb: $background } }
    } | flatten)
    ($inside ++ $ring) | where {|p| $p.x >= 0 and $p.x < $width and $p.y >= 0 and $p.y < $height }
}

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --capture 2sec)
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    let codes = ((1..13 | each {|_| "draw 0\n" } | str join "") + "draw 1\ndraw 2\ndraw 0\n")
    assert equal $run.serial $codes $"the codes: ($run.serial)"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)

    let draws = [
        (drawn $blend 0 10 10 $plain $one 0)
        (drawn $blend 0 -2 -1 $plain $one 0)
        (drawn $blend 0 1918 1079 $plain $one 0)
        (drawn $blend 0 100 100 0xff8040 $one 0)
        (drawn $blend 0 200 200 $plain (2 * $one) 0)
        (drawn $blend 0 300 300 $plain ($one // 2) 0)
        (drawn $sheet 1 400 400 $plain $one 0)
        (drawn $blend 0 700 100 $plain $one $flip_h)
        (drawn $blend 0 700 200 $plain $one $flip_v)
        (drawn $blend 0 700 300 $plain (2 * $one) ($flip_h bit-or $flip_v))
        (drawn $blend 0 800 100 $plain (4 * $one) 90)
        (drawn $blend 0 800 300 $plain (4 * $one) 45)
        (drawn $blend 0 800 500 $plain (3 * $one) ($flip_h bit-or 30))
    ]
    mut checked = 0
    for d in ($draws | enumerate) {
        for p in $d.item {
            let want = ($p.rgb | each {|c| $c | format number | get lowerhex | str substring 2.. | fill -a right -c "0" -w 2 } | str join "")
            assert equal (jab pixel $screen $p.x $p.y) $want $"draw ($d.index): the pixel at ($p.x), ($p.y)"
            $checked += 1
        }
    }
    print $"sprite: ($checked) pixels of ($draws | length) draws held against the rules; QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    print "sprite: ok"
}
