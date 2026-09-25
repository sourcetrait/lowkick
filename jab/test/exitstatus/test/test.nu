# exitstatus's integration test: a nonzero jab.exit status comes back
# as QEMU's exit code.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let run = (jab launch --kernel $kernel --image $image --out $out)
    assert equal $run.status 3 "exit status"
    assert equal $run.serial "exiting with 3\n" "the program's line and nothing else"
    print "exitstatus: ok"
}
