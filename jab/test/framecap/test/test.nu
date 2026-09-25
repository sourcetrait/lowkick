# framecap's integration test: a burst of flips is refused past the
# first, sixty-four awaited frames, whole and rectangular, take two
# seconds at the cap of thirty-two a second, a rectangle past the edge
# is refused with 4, and the hart halts while it waits, so QEMU's CPU
# time stays well under the run's length.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let run = (jab launch --kernel $kernel --image $image --out $out)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    let report = ($run.serial | parse "refused={refused}\nbadrect={badrect}\npaced\n" | get -o 0 | default { refused: "", badrect: "" })
    let refused = ($report.refused | into int)
    assert ($refused >= 60) $"the burst is refused past the first flip: ($refused) of 63"
    assert equal ($report.badrect | into int) 4 "a rectangle past the edge is refused with 4"
    assert ($run.wall_seconds >= 2.0) $"sixty-four frames at thirty-two a second take two seconds: ($run.wall_seconds)"
    assert ($run.wall_seconds < 6.0) $"and not much more: ($run.wall_seconds)"
    print $"framecap: ($refused) refused; QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts while it waits"
    print "framecap: ok"
}
