# romfs's integration test. It builds a fixture image with genromfs,
# holding files taken from the repository at their own paths, one entry
# of every mode romfs knows, and two names at and past the 127
# characters a record carries; then it holds the kernel's account of
# that image against its own. The binary file is compared byte for byte:
# the program reads it in pages of 4000, which line up with no sector,
# and writes every byte back as hex.
use ../../../sdk/nu/jab.nu
use std/assert

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let repo = ($env.FILE_PWD | path join ".." ".." ".." ".." | path expand)
    let img = ($out | path join "fixture.romfs")
    let fixture = (build-fixture $repo ($out | path join "fixture") $img)
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --disk $img --serial "fixture" --seconds 30)
    assert equal $run.status 0 $"exit status, with the first of the UART: ($run.serial | str substring 0..400)"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    let lines = ($run.serial | lines)

    # what it found, in the order the program asked
    let found = ($lines | where {|l| $l starts-with "f " })
    let want = [
        $"f 0 2 ($fixture.readme_bytes) README.md"
        "f 0 2 0 EMPTY"
        $"f 0 2 ($fixture.png_bytes) lowkick.480x640.png"
        $"f 0 2 ($fixture.font_bytes) font.S"
        $"f 0 3 ($fixture.symlink_bytes) points"
        "f 0 2 15 plain"
        "f 0 7 0 pipe"
        "f 0 4 0 loop"
        "f 0 5 0 zero"
        "f 0 6 0 sock"
        "f 0 1 0 folder"
        $"f 0 2 ($fixture.max_bytes) ($fixture.max_name)"
        "f 1"
    ]
    assert equal $found $want "every path, by its code, kind, size, and name"

    # the binary file, byte for byte
    let hex = ($lines | where {|l| $l starts-with "x " } | each {|l| $l | str substring 2.. } | str join "")
    let got = ($hex | decode hex)
    let real = (open --raw ($repo | path join "asset" "img" "logo" "lowkick.480x640.png"))
    assert equal ($got | bytes length) ($real | bytes length) "the whole file came back"
    assert equal $got $real "every byte of the file is the file's"
    assert equal ($lines | where {|l| $l starts-with "png bytes " }) [$"png bytes ($fixture.png_bytes)"] "the bytes it counted"
    assert equal ($lines | where {|l| $l starts-with "empty " }) ["empty 0 0"] "an empty file reads nothing and ends"

    # the directory holding a name past what a record carries: the entry
    # is there and its name is cut where the record ends, which is what
    # a linux mount of the same image shows
    let over = ($lines | where {|l| $l starts-with "over " })
    let cut = ($fixture.over_name | str substring 0..<127)
    assert equal ($over | where {|l| $l starts-with "over 2 " }) [$"over 2 ($cut)"] "the long name, cut to 127"
    assert ($over | any {|l| $l == "over 0 ." }) "the directory's own link is listed"
    assert ($over | any {|l| $l == "over 0 .." }) "and its parent's"

    print $"romfs: ($fixture.png_bytes) bytes of png read in pages of 4000 and compared byte for byte"
    print $"romfs: every mode found, a 127-character name matched, a ($fixture.over_name | str length)-character one cut to 127"
    print "romfs: ok"
}

# The fixture: repository files at their own paths, one entry of every
# mode, and the two names. Returns what the test needs to judge by.
def build-fixture [repo: path, stage: path, img: path]: nothing -> record {
    if ($stage | path exists) { rm -rf $stage }
    mkdir $stage

    # the repository's own files, at the paths they have there
    cp ($repo | path join "README.md") ($stage | path join "README.md")
    "" | save -f ($stage | path join "EMPTY")
    mkdir ($stage | path join "asset" "img" "logo")
    let png = ($repo | path join "asset" "img" "logo" "lowkick.480x640.png")
    cp $png ($stage | path join "asset" "img" "logo" "lowkick.480x640.png")
    # the console font, the one source file the program names by path
    let font_path = (["jab" "kernel" "src" "font.S"] | path join)
    let font = { path: $font_path, bytes: (ls -D ($repo | path join $font_path) | get 0.size | into int), full: ($repo | path join $font_path) }
    mkdir ($stage | path join $font.path | path dirname)
    cp $font.full ($stage | path join $font.path)

    # one entry of every mode, under mode/<mode>/<name>. A device node
    # needs no privilege here: genromfs makes one from an empty file
    # named @<name>,<b or c>,<major>,<minor>.
    for m in [regular directory symlink hardlink fifo block char socket] {
        mkdir ($stage | path join "mode" $m)
    }
    "a regular file\n" | save -f ($stage | path join "mode" "regular" "plain")
    mkdir ($stage | path join "mode" "directory" "folder")
    let symlink_target = ([".." "regular" "plain"] | path join)
    ^ln -s $symlink_target ($stage | path join "mode" "symlink" "points")
    ^ln ($stage | path join "mode" "regular" "plain") ($stage | path join "mode" "hardlink" "same")
    ^mkfifo ($stage | path join "mode" "fifo" "pipe")
    "" | save -f ($stage | path join "mode" "block" "@loop,b,7,0")
    "" | save -f ($stage | path join "mode" "char" "@zero,c,1,5")
    ^python3 -c "import socket,sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])" ($stage | path join "mode" "socket" "sock")

    # a name of exactly 127 characters, and one well past it
    let max_dir = ($stage | path join "name" "max" "one" "two" "three" "four" "five")
    mkdir $max_dir
    let max_name = (("" | fill -a right -c "m" -w 118) + ".max.name")
    let max_body = "the longest name a linux mount can read\n"
    $max_body | save -f ($max_dir | path join $max_name)
    let over_dir = ($stage | path join "name" "overflow" "one" "two" "three")
    mkdir $over_dir
    let over_name = (("" | fill -a right -c "o" -w 151) + ".overflow.name")
    let over_body = "a name past what a linux mount can read\n"
    $over_body | save -f ($over_dir | path join $over_name)

    ^genromfs -d $stage -f $img -V fixture
    {
        readme_bytes: (ls -D ($repo | path join "README.md") | get 0.size | into int),
        png_bytes: (ls -D $png | get 0.size | into int),
        font_bytes: $font.bytes,
        font_path: $font.path,
        symlink_bytes: ($symlink_target | str length),
        max_name: $max_name,
        max_bytes: ($max_body | str length),
        over_name: $over_name,
        over_bytes: ($over_body | str length),
    }
}
