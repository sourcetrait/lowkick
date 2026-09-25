# walk's integration test: the SDK built the repository's image
# directory into this program's romfs, the walker's sixteen frames
# among it, and after a few seconds every lane has walkers on the
# screen. The program's records over the API say which: one per walker
# that entered, with its lane, its side, its size, and its colour, and
# one per walker that left. Every lane entered a walker; every size is
# from five feet to seven; every colour is bright enough; and on the
# screen each lane shows at least one of its walkers by its colour,
# with its pixels inside its lane and its feet on the lane's floor.
use ../../../sdk/nu/jab.nu
use std/assert

const lanes = 8
const lane_h = 135
const frame_h = 640
const scale_min = 53
const scale_max = 75

def main [--kernel: path, --image: path, --out: path, --assets: path, --set: string = ""] {
    assert ($assets | path exists) "the sdk built the assets image"
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --disk $assets --serial "walk" --api --capture 8sec --seconds 30)
    assert equal $run.serial "" $"the UART stays silent: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)

    # the records: kind, lane, side, scale, then the tint as a word
    let bytes = $run.api
    let count = (($bytes | bytes length) // 8)
    assert ($count >= $lanes) $"at least one walker per lane entered: ($count) records"
    let records = (0..<$count | each {|i|
        let r = ($bytes | bytes at ($i * 8)..<($i * 8 + 8))
        {
            kind: ($r | bytes at 0..<1 | into int),
            lane: ($r | bytes at 1..<2 | into int),
            side: ($r | bytes at 2..<3 | into int),
            scale: ($r | bytes at 3..<4 | into int),
            tint: ($r | bytes at 4..<8 | into int --endian little),
        }
    })
    let entered = ($records | where kind == 1)
    assert equal ($entered | get lane | uniq | sort) (0..<$lanes | each {|l| $l }) "every lane took a walker"
    for r in $entered {
        assert ($r.side == 0 or $r.side == 1) $"a side is left or right: ($r)"
        assert ($r.scale >= $scale_min and $r.scale <= $scale_max) $"a size from five feet to seven: ($r)"
        for c in [16 8 0] {
            assert ((($r.tint bit-shr $c) bit-and 0xff) >= 64) $"a colour bright enough to see: ($r)"
        }
    }

    # the walkers on the screen: in every lane at least one of those
    # that entered is found by its colour, inside its lane, its feet on
    # the floor; a walker that entered just before the screen was taken
    # may still be off the edge
    mut seen = 0
    for lane in 0..<$lanes {
        let floor = (($lane + 1) * $lane_h)
        let found = ($entered | where lane == $lane | each {|walker|
            let hex = ($walker.tint | format number | get lowerhex | str substring 2.. | fill -a right -c "0" -w 6)
            let ink = (jab ink $screen $hex)
            let dh = (($frame_h * $walker.scale) bit-shr 8)
            if $ink.count > 100 {
                assert ($ink.bottom < $floor) $"lane ($lane)'s walker ($hex) stands on its floor at ($floor): bottom ($ink.bottom)"
                assert ($ink.top >= ($floor - $dh)) $"lane ($lane)'s walker ($hex) is no taller than its size ($dh): top ($ink.top)"
                1
            } else { 0 }
        } | math sum)
        assert ($found > 0) $"lane ($lane) shows a walker"
        $seen += $found
    }
    print $"walk: ($entered | length) walkers entered over ($run.wall_seconds | math round -p 2) seconds, ($seen) on the screen in their lanes; QEMU used ($run.cpu_seconds) CPU seconds"
    print "walk: ok"
}
