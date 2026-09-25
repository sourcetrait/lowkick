# png's integration test. It generates the fixtures on the host with
# python's zlib, shaped as GIMP 3 shapes a file, ships them in a romfs
# image, and holds the kernel's account of each against what went in:
# the size from the header, the code the decode gave, and every pixel
# of every decoded image in the kernel's own format; then the sprites
# loaded from directories of frames straight off the disk, the same
# way. The rows of the program's two tables are mirrored here, refusals
# and all.
use ../../../sdk/nu/jab.nu
use std/assert

const JAB_PNG_OK = 0

# The program's first table: the file, the frames it asks for, and the
# codes expected from jab.png.size and jab.sprite.png.
const table = [
    [name, frames, size_code, png_code];
    ["rgba8.png", 1, 0, 0]
    ["rgb8.png", 1, 0, 0]
    ["grey8.png", 1, 0, 0]
    ["grey4.png", 1, 0, 0]
    ["grey2.png", 1, 0, 0]
    ["grey1.png", 1, 0, 0]
    ["ga8.png", 1, 0, 0]
    ["idx8.png", 1, 0, 0]
    ["idx4.png", 1, 0, 0]
    ["idx2.png", 1, 0, 0]
    ["idx1.png", 1, 0, 0]
    ["sheet.png", 2, 0, 0]
    ["split.png", 1, 0, 0]
    ["big.png", 1, 0, 0]
    ["extras.png", 1, 0, 0]
    ["depth16.png", 1, 2, 2]
    ["interlaced.png", 1, 2, 2]
    ["badcrc.png", 1, 0, 4]
    ["badadler.png", 1, 0, 5]
    ["badfilter.png", 1, 0, 7]
    ["short.png", 1, 0, 6]
    ["truncated.png", 1, 0, 3]
    ["notpng.png", 1, 1, 1]
    ["rgba8.png", 3, 0, 9]
    ["rgba8.png", 1, 0, 10]
]

# The second: the directory and the code expected from jab.sprite.load.
const loads = [
    [name, code];
    ["walker", 0]
    ["mixed", 9]
    ["nozero", 11]
    ["missing", 11]
    ["rgba8.png", 11]
    ["walker", 10]
]

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let stage = ($out | path join "fixtures")
    if ($stage | path exists) { rm -rf $stage }
    mkdir $stage
    let made = (^python3 ($env.FILE_PWD | path join "encode.py") $stage | from json)
    let img = ($out | path join "png.romfs")
    ^genromfs -d $stage -f $img -V png
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --disk $img --serial "png" --seconds 60)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial | str substring 0..600)"
    assert equal (open --raw $run.qemu_log | into binary | bytes length) 0 "QEMU has no complaint about the guest"
    let lines = ($run.serial | lines)
    assert equal ($lines | last) "done" "the program reached the end of its tables"

    # the program's answers, row by row: an s line and a p line, or an l
    # line, then the pixels of a decoded sprite
    mut answers = []
    mut current: any = null
    for l in ($lines | drop 1) {
        if ($l | str starts-with "s ") or ($l | str starts-with "l ") {
            if $current != null { $answers = ($answers | append $current) }
            $current = { s: $l, p: "", hex: "", spans: "", flags: "" }
        } else if ($l | str starts-with "p ") {
            $current.p = $l
        } else if ($l | str starts-with "x ") {
            $current.hex = ($current.hex + ($l | str substring 2..))
        } else if ($l | str starts-with "y ") {
            $current.spans = ($current.spans + ($l | str substring 2..))
        } else if ($l | str starts-with "f ") {
            $current.flags = ($l | str substring 2..)
        }
    }
    if $current != null { $answers = ($answers | append $current) }
    assert equal ($answers | length) (($table | length) + ($loads | length)) "one answer per row of the tables"

    mut decoded = 0
    mut pixels = 0
    for row in ($table | enumerate) {
        let want = $row.item
        let got = ($answers | get $row.index)
        let fixture = ($made.fixtures | where name == $want.name | first)
        let size_line = (if $want.size_code == $JAB_PNG_OK {
            $"s 0 ($fixture.width) ($fixture.height)"
        } else { $"s ($want.size_code) 0 0" })
        assert equal $got.s $size_line $"($want.name): jab.png.size"
        if $want.png_code == $JAB_PNG_OK {
            let fh = ($fixture.height // $want.frames)
            assert equal $got.p $"p 0 ($fixture.width) ($fh) ($want.frames)" $"($want.name): jab.sprite.png with ($want.frames) frames"
            compare-pixels $want.name $got.hex $fixture.native $fixture.width
            assert equal $got.spans $fixture.spans $"($want.name): the span table, first and last opaque column per row"
            assert equal $got.flags "1" $"($want.name): the record is flagged spanned"
            $decoded += 1
            $pixels += ($fixture.width * $fixture.height)
        } else {
            assert equal $got.p $"p ($want.png_code)" $"($want.name): jab.sprite.png refuses with ($want.png_code)"
        }
    }

    mut loaded = 0
    for row in ($loads | enumerate) {
        let want = $row.item
        let got = ($answers | get (($table | length) + $row.index))
        if $want.code == $JAB_PNG_OK {
            let dir = ($made.dirs | where name == $want.name | first)
            assert equal $got.s $"l 0 ($dir.width) ($dir.height) ($dir.frames)" $"($want.name): jab.sprite.load"
            compare-pixels $want.name $got.hex $dir.native $dir.width
            assert equal $got.spans $dir.spans $"($want.name): the span table of every frame"
            assert equal $got.flags "1" $"($want.name): the record is flagged spanned"
            $loaded += 1
            $pixels += ($dir.width * $dir.height * $dir.frames)
        } else {
            assert equal $got.s $"l ($want.code)" $"($want.name): jab.sprite.load refuses with ($want.code)"
        }
    }

    print $"png: ($decoded) images decoded and ($loaded) sprite loaded off the disk, ($pixels) pixels compared byte for byte; (($table | length) + ($loads | length) - $decoded - $loaded) refusals by their codes"
    print "png: ok"
}

# Every byte of a sprite's pixels against the fixture's, naming the
# first pixel that differs.
def compare-pixels [name: string, got: string, want: string, width: int]: nothing -> nothing {
    assert equal ($got | str length) ($want | str length) $"($name): every pixel came back"
    if $got != $want {
        let first = (0..<($want | str length) | where {|i| ($got | str substring $i..$i) != ($want | str substring $i..$i) } | first)
        let px = ($first // 8)
        assert equal ($got | str substring ($px * 8)..<($px * 8 + 8)) ($want | str substring ($px * 8)..<($px * 8 + 8)) $"($name): pixel ($px) \(x ($px mod $width), y ($px // $width)\) as blue, green, red, alpha"
    }
}
