# keys' integration test: two keys pressed through QEMU's monitor
# arrive as press and release events with Linux's codes, W as 17 and
# the space bar as 57, in order, and the program exits on the space
# bar's release.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let run = (jab launch --kernel $kernel --image $image --out $out --keys [[at, key, hold]; [1sec, "w", 100], [2sec, "spc", 100]])
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert equal $run.serial "keys: ready\nkey 017 1\nkey 017 0\nkey 057 1\nkey 057 0\n" "W then the space bar, pressed and released"
    print $"keys: QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts while it waits for a key"
    print "keys: ok"
}
