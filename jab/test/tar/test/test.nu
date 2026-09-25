# tar's integration test. It builds a small tree, tars it, ships the
# tar inside a romfs image, and holds the kernel's account of the
# archive against its own. The program reads the tar out of romfs into
# its own memory first, which is how a shipped .tar.gz will be read once
# the decompressor lands.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path] {
    let stage = ($out | path join "stage")
    let img = ($out | path join "tar.romfs")
    let fixture = (build-fixture $stage $img)
    let run = (jab launch --kernel $kernel --image $image --out $out --disk $img --serial "tar")
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial)"
    assert equal (open --raw $run.qemu_log | into binary | bytes length) 0 "QEMU has no complaint about the guest"
    let lines = ($run.serial | lines)
    assert equal ($lines | where {|l| $l starts-with "archive " }) [$"archive ($fixture.tar_bytes)"] "the whole archive reached the program"

    # every entry, in the archive's own order, with tar's type byte and
    # the data where it already sits
    let got = ($lines | where {|l| $l starts-with "t " } | each {|l| $l | str substring 2.. })
    assert equal $got $fixture.entries "every entry, by type, size, data offset and name"

    let found = ($lines | where {|l| $l starts-with "f " })
    assert equal $found [$"f 0 ($fixture.note_bytes) foo/note.txt" "f 1"] "one name that is there and one that is not"
    print $"tar: ($fixture.tar_bytes) bytes of archive, ($fixture.entries | length) entries, read out of romfs and walked in memory"
    print "tar: ok"
}

# A tree, tarred, inside a romfs image; and what the kernel should say
# about it, worked out here from the archive itself.
def build-fixture [stage: path, img: path]: nothing -> record {
    if ($stage | path exists) { rm -rf $stage }
    mkdir ($stage | path join "tree" "foo" "img")
    let note = "hello from a tar\n"
    $note | save -f ($stage | path join "tree" "foo" "note.txt")
    ("" | fill -a right -c "p" -w 700) | save -f ($stage | path join "tree" "foo" "img" "sprite.raw")
    let tar = ($stage | path join "ship" "foo.tar")
    mkdir ($stage | path join "ship")
    ^tar -cf $tar -C ($stage | path join "tree") "foo"
    ^genromfs -d ($stage | path join "ship") -f $img -V tar
    {
        tar_bytes: (ls -D $tar | get 0.size | into int),
        note_bytes: ($note | str length),
        entries: (tar-entries $tar),
    }
}

# The archive read here the way the kernel reads it: a 512-byte header,
# the name and the octal size, the data one block on, the next header
# after the data padded to a block.
def tar-entries [tar: path]: nothing -> list<string> {
    let b = (open --raw $tar | into binary)
    let total = ($b | bytes length)
    mut at = 0
    mut rows = []
    while ($at + 512) <= $total {
        let name_field = ($b | bytes at $at..<($at + 100))
        let end = ($name_field | bytes index-of 0x[00])
        if $end == 0 { break }
        let name = (if $end < 0 { $name_field | decode } else { $name_field | bytes at 0..<$end | decode })
        let size_field = ($b | bytes at ($at + 124)..<($at + 136) | decode | str trim --char (char nul) | str trim)
        let size = ($size_field | into int --radix 8)
        let type = ($b | bytes at ($at + 156)..<($at + 157) | decode)
        let data = ($at + 512)
        $rows = ($rows | append $"($type) ($size) ($data) ($name)")
        $at = ($data + (((($size + 511) // 512)) * 512))
    }
    $rows
}
