# pad's integration test: a gamepad shaped like the reference pad,
# attached through the evdev shim and played from table.nuon, is found
# by the kernel and read as the program expects: the ranges it reports
# for three axes and none for a fourth, every event in evdev's terms
# and, after each, the state normalised, the keys as a mask, the left
# stick full scale at its ends, part way in between, 0 inside its flat
# band and at centre, the hat at full scale, the trigger one-sided, a
# scan code dropped, and the run ending on South's release.
use ../../../sdk/nu/jab.nu
use std/assert

const expected = [
    "pad: ready"
    "axis 0 0 255 0 15 0"
    "axis 9 0 255 0 15 0"
    "axis 16 -1 1 0 0 0"
    "axis 3 none"
    "pad 3 0 255"
    "state 0 32767 0 0 0"
    "pad 3 1 0"
    "state 0 32767 -32767 0 0"
    "pad 3 0 200"
    "state 0 16818 -32767 0 0"
    "pad 3 0 135"
    "state 0 0 -32767 0 0"
    "pad 3 1 127"
    "state 0 0 0 0 0"
    "pad 3 16 -1"
    "state 0 0 0 -32767 0"
    "pad 3 16 0"
    "state 0 0 0 0 0"
    "pad 3 9 255"
    "state 0 0 0 0 32767"
    "pad 3 9 0"
    "state 0 0 0 0 0"
    "pad 1 304 1"
    "state 1 0 0 0 0"
    "pad 1 304 0"
    "state 0 0 0 0 0"
]

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let table = ($env.FILE_PWD | path join "table.nuon")
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --pad $table --seconds 8)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.debug | str contains "jab: pad at ") $"the kernel found the pad: ($run.debug)"
    assert equal ($run.serial | lines) $expected $"the ranges, every event, and the state after each: ($run.serial)"
    print $"pad: ($expected | length) lines as expected; QEMU used ($run.cpu_seconds) CPU seconds over ($run.wall_seconds | math round -p 2) seconds"
    assert ($run.cpu_seconds < ($run.wall_seconds * 0.5)) "the hart halts while it waits for the pad"
    print "pad: ok"
}
