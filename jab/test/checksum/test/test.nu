# checksum's integration test. Two of the four digests are the answers
# the standard publishes for the empty message and for "abc", written
# here as constants so the test needs nothing outside itself to catch a
# wrong permutation. The other two are ramps long enough to run the
# sponge over many blocks, and those are held against what the host
# computes with the same algorithm.
use ../../../sdk/nu/jab.nu
use std/assert

# FIPS 202's own vectors
const SHA3_256_EMPTY = "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a"
const SHA3_256_ABC = "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532"

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --seconds 60)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial)"
    assert equal (open --raw $run.qemu_log | into binary | bytes length) 0 "QEMU has no complaint about the guest"
    let got = ($run.serial | lines | where {|l| $l starts-with "d " } | each {|l| $l | str substring 2.. })
    assert equal ($got | length) 4 $"four digests, not ($got | length)"
    assert equal $got.0 $SHA3_256_EMPTY "the empty message, against the standard's own vector"
    assert equal $got.1 $SHA3_256_ABC "abc, against the standard's own vector"

    # the ramps: the same bytes the program built, built again here
    assert equal $got.2 (host-sha3-ramp 200 256) "a ramp of 200 bytes, which is two blocks"
    assert equal $got.3 (host-sha3-ramp 100000 251) "a ramp of 100000 bytes, which is many"
    print $"checksum: four digests, two against FIPS 202's vectors and two against the host over 200 and 100000 bytes"
    print "checksum: ok"
}

# nushell's `hash` offers md5 and sha256 only, so SHA3 comes from
# python3's hashlib, which is where the host's answer lives. It builds
# the ramp itself rather than taking a file, since the bytes are a rule
# rather than data: the nth is n modulo the given number, which is what
# the program stores.
def host-sha3-ramp [count: int, modulus: int]: nothing -> string {
    ^python3 -c "import hashlib, sys
n, m = int(sys.argv[1]), int(sys.argv[2])
print(hashlib.sha3_256(bytes((i % m) for i in range(n))).hexdigest())" ($count | into string) ($modulus | into string) | str trim
}
