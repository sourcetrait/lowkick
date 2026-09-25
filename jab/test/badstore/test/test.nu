# badstore's integration test: a store into kernel memory is a program
# fault, reported with the store page fault cause and the address, the
# run ends with status 1, and the program never runs past the store.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set)
    assert equal $run.status 1 "exit status"
    assert ($run.serial | str contains "jab: program fault: cause=0x000000000000000f") "a store page fault reported"
    assert ($run.serial | str contains "tval=0x0000000080000000") "the kernel address reported"
    assert (not ($run.serial | str contains "the store went through")) "the program stopped at the store"
    print "badstore: ok"
}
