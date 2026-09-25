# exitstatus's integration test: a nonzero jab.exit status comes back
# as QEMU's exit code.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let run = (jab launch --kernel $kernel --image $image --out $out)
    assert equal $run.status 3 "exit status"
    assert ($run.serial | str contains "jab: exit 3") "the exit reported"
    print "exitstatus: ok"
}
