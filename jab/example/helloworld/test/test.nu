# helloworld's integration test: the program runs on the kernel, prints
# the greeting, and exits 0.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let run = (jab launch --kernel $kernel --image $image --out $out)
    assert equal $run.status 0 "exit status"
    assert ($run.serial | str contains "Hello, World!") "the greeting printed"
    assert ($run.serial | str contains "jab: exit 0") "the exit reported"
    print "helloworld: ok"
}
