# gz's integration test. It ships six gzip files inside a romfs image,
# picked to reach every kind of DEFLATE block: repetitive text and real
# source for dynamic Huffman with long matches, random bytes which gzip
# cannot compress and so stores as they are, a five-byte file, an empty
# one, and a PNG which is already compressed.
#
# The kernel checks each file's CRC-32 and length itself, so a code of
# JAB_GZ_OK back from the call already means the bytes that came out are
# the bytes that went in. The first file is also compared here byte for
# byte, so that the checking inside the kernel is itself checked once
# against something outside it.
use ../../../sdk/nu/jab.nu
use std/assert

const JAB_GZ_OK = 0

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let repo = ($env.FILE_PWD | path join ".." ".." ".." ".." | path expand)
    let img = ($out | path join "gz.romfs")
    let files = (build-fixture $repo ($out | path join "stage") $img)
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --disk $img --serial "gz" --seconds 60)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial | str substring 0..600)"
    assert equal (open --raw $run.qemu_log | into binary | bytes length) 0 "QEMU has no complaint about the guest"
    let lines = ($run.serial | lines)

    # every file: the code, what came out, what the trailer promised
    let got = ($lines | where {|l| $l starts-with "g " })
    let want = ($files | each {|f| $"g ($JAB_GZ_OK) ($f.bytes) ($f.bytes) ($JAB_GZ_OK)" })
    assert equal $got $want "every file inflated, its length and its CRC-32 agreeing"

    # and the first of them, byte for byte, against the original
    let hex = ($lines | where {|l| $l starts-with "x " } | each {|l| $l | str substring 2.. } | str join "")
    let inflated = ($hex | decode hex)
    let original = (open --raw ($files | first | get source) | into binary)
    assert equal ($inflated | bytes length) ($original | bytes length) "the whole of the first file came back"
    assert equal $inflated $original "every byte of it is the file's"

    print $"gz: ($files | length) files inflated, ($files | get bytes | math sum) bytes, each checked by its own crc-32"
    print $"gz: the first, ($original | bytes length) bytes, compared byte for byte outside the kernel"
    print "gz: ok"
}

# Six gzip files in a romfs image, and what each should inflate to.
def build-fixture [repo: path, stage: path, img: path]: nothing -> table<name: string, bytes: int, source: string> {
    if ($stage | path exists) { rm -rf $stage }
    mkdir ($stage | path join "src")
    mkdir ($stage | path join "ship")
    let src = ($stage | path join "src")

    # repetitive text, which gzip matches heavily
    let text = (1..200 | each {|i| $"line ($i): the quick brown fox jumps over the lazy dog\n" } | str join "")
    $text | save -f ($src | path join "text.txt")
    # bytes with no pattern, which gzip stores as they are
    random binary 4096 | save -f ($src | path join "random.bin")
    "hello" | save -f ($src | path join "tiny.txt")
    "" | save -f ($src | path join "empty")
    cp ($repo | path join "asset" "img" "logo" "lowkick.480x640.png") ($src | path join "logo.png")
    let font = (glob ($repo | path join "**" "*.S")
        | where {|p| ($p | path type) == "file" }
        | each {|p| { path: $p, bytes: (ls -D $p | get 0.size | into int) } }
        | sort-by bytes
        | last)
    cp $font.path ($src | path join "font.S")

    let names = ["text.txt" "random.bin" "tiny.txt" "empty" "logo.png" "font.S"]
    let rows = ($names | enumerate | each {|row|
        let plain = ($src | path join $row.item)
        # the levels vary so the blocks do too
        let level = (if ($row.index mod 2) == 0 { "-9" } else { "-1" })
        let gz = ($stage | path join "ship" $"($row.item).gz")
        ^gzip $level -c $plain | save -f $gz
        { name: $row.item, bytes: (ls -D $plain | get 0.size | into int), source: $plain }
    })
    ^genromfs -d ($stage | path join "ship") -f $img -V gz
    $rows
}
