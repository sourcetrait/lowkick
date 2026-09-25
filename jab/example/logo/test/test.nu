# logo's integration test: the SDK built the repository's logo directory
# into this program's romfs, and after a few seconds the screen holds
# the logo PNG, decoded by the kernel and blended over black, in the
# centre. The same file is decoded here on the host, with python's zlib
# and the five filters, and composited over black the way the kernel
# blends, so the drawn rectangle is held against it pixel for pixel:
# the kernel's decode and its blend get an exact oracle on the real
# GIMP file.
use ../../../sdk/nu/jab.nu
use std/assert

const width = 480
const height = 640
const x = 720
const y = 220

def main [--kernel: path, --image: path, --out: path, --assets: path, --set: string = ""] {
    assert ($assets | path exists) "the sdk built the assets image"
    let repo = ($env.FILE_PWD | path join ".." ".." ".." ".." | path expand)
    let png = ($repo | path join "asset" "img" "logo" "lowkick.480x640.png")
    let expected_path = ($out | path join "expected.rgb")
    let said = (^python3 ($env.FILE_PWD | path join "decode.py") $png $expected_path | str trim)
    assert equal $said $"($width) ($height)" "the file is the logo's size"
    let expected = (open --raw $expected_path | into binary)

    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --disk $assets --serial "logo" --capture 4sec)
    assert equal $run.serial "" $"the UART stays silent: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)
    assert equal [$screen.width $screen.height] [1920 1080] "a 1080p frame"
    assert equal (jab pixel $screen 0 0) "000000" "black at the top left"
    assert equal (jab pixel $screen 1919 1079) "000000" "black at the bottom right"
    assert equal (jab pixel $screen ($x - 1) ($y + 100)) "000000" "black just left of the logo"
    assert equal (jab pixel $screen ($x + $width) ($y + 100)) "000000" "black just right of it"

    # the drawn rectangle, row by row, against the oracle
    let row_bytes = ($screen.width * 3)
    let rows = (0..<$height | each {|r|
        let at = ((($y + $r) * $row_bytes) + ($x * 3))
        $screen.pixels | bytes at $at..<($at + $width * 3)
    })
    let got = ($rows | bytes collect)
    assert equal ($got | bytes length) ($expected | bytes length) "the whole rectangle was read"
    if $got != $expected {
        let bad = (0..<$height | where {|r|
            ($rows | get $r) != ($expected | bytes at ($r * $width * 3)..<(($r + 1) * $width * 3))
        })
        let r = ($bad | first)
        let want_row = ($expected | bytes at ($r * $width * 3)..<(($r + 1) * $width * 3))
        let col = (0..<$width | where {|c|
            (($rows | get $r) | bytes at ($c * 3)..<($c * 3 + 3)) != ($want_row | bytes at ($c * 3)..<($c * 3 + 3))
        } | first)
        assert equal (jab pixel $screen ($x + $col) ($y + $r)) ($want_row | bytes at ($col * 3)..<($col * 3 + 3) | encode hex | str lowercase) $"($bad | length) of ($height) rows differ; the first differing pixel is at ($col), ($r) of the logo"
    }
    print $"logo: ($width * $height) pixels of the GIMP file held against the host's decode; QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    print "logo: ok"
}
