# png's integration test. It generates the fixtures on the host with
# python's zlib, shaped as GIMP 3 shapes a file, ships them in a romfs
# image, and holds the kernel's account of each against what went in:
# the size from the header, the code the decode gave, and every pixel
# of every decoded image in the kernel's own format. The rows of the
# program's table are mirrored here, refusals and all.
use ../../../sdk/nu/jab.nu
use std/assert

const JAB_PNG_OK = 0
const JAB_PNG_NOT_PNG = 1
const JAB_PNG_UNSUPPORTED = 2
const JAB_PNG_TRUNCATED = 3
const JAB_PNG_CRC = 4
const JAB_PNG_ZLIB = 5
const JAB_PNG_LENGTH = 6
const JAB_PNG_FILTER = 7
const JAB_PNG_FRAMES = 9
const JAB_PNG_SIZE = 10

# The program's table: the file, the frames it asks for, and the codes
# expected from jab.png.size and jab.sprite.png.
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

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let stage = ($out | path join "fixtures")
    if ($stage | path exists) { rm -rf $stage }
    mkdir $stage
    let made = (^python3 ($env.FILE_PWD | path join "encode.py") $stage | from json | get fixtures)
    let img = ($out | path join "png.romfs")
    ^genromfs -d $stage -f $img -V png
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --disk $img --serial "png" --seconds 60)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial | str substring 0..600)"
    assert equal (open --raw $run.qemu_log | into binary | bytes length) 0 "QEMU has no complaint about the guest"
    let lines = ($run.serial | lines)
    assert equal ($lines | last) "done" "the program reached the end of its table"

    # the program's answers, row by row: an s line, a p line, then the
    # pixels of a decoded image
    mut answers = []
    mut current: any = null
    for l in ($lines | drop 1) {
        if ($l | str starts-with "s ") {
            if $current != null { $answers = ($answers | append $current) }
            $current = { s: $l, p: "", hex: "" }
        } else if ($l | str starts-with "p ") {
            $current.p = $l
        } else if ($l | str starts-with "x ") {
            $current.hex = ($current.hex + ($l | str substring 2..))
        }
    }
    if $current != null { $answers = ($answers | append $current) }
    assert equal ($answers | length) ($table | length) "one answer per row of the table"

    mut decoded = 0
    mut pixels = 0
    for row in ($table | enumerate) {
        let want = $row.item
        let got = ($answers | get $row.index)
        let fixture = ($made | where name == $want.name | first)
        let size_line = (if $want.size_code == $JAB_PNG_OK {
            $"s 0 ($fixture.width) ($fixture.height)"
        } else { $"s ($want.size_code) 0 0" })
        assert equal $got.s $size_line $"($want.name): jab.png.size"
        if $want.png_code == $JAB_PNG_OK {
            let fw = ($fixture.width // $want.frames)
            assert equal $got.p $"p 0 ($fw) ($fixture.height) ($want.frames)" $"($want.name): jab.sprite.png with ($want.frames) frames"
            assert equal ($got.hex | str length) ($fixture.native | str length) $"($want.name): every pixel came back"
            if $got.hex != $fixture.native {
                let first = (0..<($fixture.native | str length) | where {|i| ($got.hex | str substring $i..$i) != ($fixture.native | str substring $i..$i) } | first)
                let px = ($first // 8)
                assert equal ($got.hex | str substring ($px * 8)..<($px * 8 + 8)) ($fixture.native | str substring ($px * 8)..<($px * 8 + 8)) $"($want.name): pixel ($px) \(x ($px mod $fixture.width), y ($px // $fixture.width)\) as blue, green, red, alpha"
            }
            $decoded += 1
            $pixels += ($fixture.width * $fixture.height)
        } else {
            assert equal $got.p $"p ($want.png_code)" $"($want.name): jab.sprite.png refuses with ($want.png_code)"
        }
    }

    print $"png: ($decoded) images decoded, ($pixels) pixels compared byte for byte; (($table | length) - $decoded) refusals by their codes"
    print "png: ok"
}
