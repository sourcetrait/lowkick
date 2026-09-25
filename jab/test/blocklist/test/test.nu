# blocklist's integration test: the SDK built this program's own assets
# directory into a romfs image, and the machine carries it as its one
# disk. The kernel must find it, name it by the serial QEMU was given,
# read its capacity from the device, and know a romfs when it sees one.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path, --assets: path] {
    assert (($assets | path exists)) "the sdk built the assets image"
    let bytes = (ls -D $assets | get 0.size | into int)
    let sectors = ($bytes // 512)
    let run = (jab launch --kernel $kernel --image $image --out $out --disk $assets --serial "blocklist")
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    let lines = ($run.serial | lines)
    assert equal ($lines | length) 2 $"one disk and the count: ($run.serial)"
    assert equal $lines.0 $"disk 1 kind 2 sectors ($sectors) serial blocklist" "the disk as the kernel sees it"
    assert equal $lines.1 "count 1 next 0" "one record written and no page after it"
    print $"blocklist: one romfs disk of ($sectors) sectors, serial blocklist"
    print "blocklist: ok"
}
