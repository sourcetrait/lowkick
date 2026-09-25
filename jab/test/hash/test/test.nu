# hash's integration test. XXH3-64 is four algorithms behind one name,
# chosen by length, so the lengths here sit on both sides of every
# boundary: 16, 128 and 240. Neither nushell nor this box's python
# carries XXH3, so the reference implementation is built here as a
# throwaway Rust binary and asked the same question, over bytes it
# generates by the same rule rather than by reading a file.
use ../../../sdk/nu/jab.nu
use std/assert

const MODULUS = 251

def main [--kernel: path, --image: path, --out: path] {
    let oracle = (build-oracle ($out | path join "xxoracle"))
    let run = (jab launch --kernel $kernel --image $image --out $out --seconds 60)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial | str substring 0..400)"
    assert equal (open --raw $run.qemu_log | into binary | bytes length) 0 "QEMU has no complaint about the guest"
    let got = ($run.serial | lines | where {|l| $l starts-with "h " } | each {|l|
        let parts = ($l | str substring 2.. | split row " ")
        { length: ($parts.0 | into int), hash: $parts.1 }
    })
    assert (($got | length) > 20) $"a hash for every length, not ($got | length)"
    let checked = ($got | each {|row|
        let want = (^$oracle ($row.length | into string) ($MODULUS | into string) | str trim)
        { length: $row.length, got: $row.hash, want: $want }
    })
    let wrong = ($checked | where {|r| $r.got != $r.want })
    assert equal $wrong [] $"every length against the reference; wrong: ($wrong | first 4)"
    print $"hash: ($checked | length) lengths, 0 to ($checked | last | get length), every one matching the reference implementation"
    print "hash: ok"
}

# The reference, built once into the test's own output directory. The
# crate is already in the local registry, so this needs no network.
def build-oracle [dir: path]: nothing -> string {
    let bin = ($dir | path join "target" "release" "xxoracle")
    if ($bin | path exists) { return $bin }
    mkdir ($dir | path join "src")
    '[package]
name = "xxoracle"
version = "0.0.0"
edition = "2021"

[dependencies]
xxhash-rust = { version = "0.8", features = ["xxh3"] }

[[bin]]
name = "xxoracle"
path = "src/main.rs"
' | save -f ($dir | path join "Cargo.toml")
    'fn main() {
    let mut args = std::env::args().skip(1);
    let n: usize = args.next().expect("a length").parse().unwrap();
    let m: u64 = args.next().expect("a modulus").parse().unwrap();
    let data: Vec<u8> = (0..n).map(|i| (i as u64 % m) as u8).collect();
    println!("{:016x}", xxhash_rust::xxh3::xxh3_64(&data));
}
' | save -f ($dir | path join "src" "main.rs")
    cd $dir
    ^cargo build --release --offline | complete | ignore
    $bin
}
