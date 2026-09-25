# displayprint's integration test: the UART carries the two lines sent
# to it and nothing else, and the screen carries exactly the glyphs of
# the two lines sent to it, white on black in the first two console
# rows, as the console font defines them.
use ../../../sdk/nu/jab.nu
use std/assert

# How many pixels each printable character lights, from the font table.
def glyph-ink []: nothing -> record {
    let font = ($env.FILE_PWD | path join ".." ".." ".." "kernel" "src" "font.S" | path expand)
    let text = (open --raw $font | decode)
    $text | split row "\n# " | where {|b| $b =~ '^\d+ ' } | reduce --fold {} {|block, acc|
        let lines = ($block | lines)
        let code = ($lines.0 | split row " " | get 0 | into int)
        let words = ($lines | skip 1 | where {|l| $l | str contains ".2byte" } | each {|l| $l | str replace ".2byte" "" | split row "," | each {|w| $w | str trim | into int } } | flatten)
        let ink = ($words | each {|w| 0..15 | each {|b| ($w bit-shr $b) bit-and 1 } | math sum } | math sum)
        $acc | insert ($code | into string) $ink
    }
}

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set --capture 2sec)
    assert equal $run.serial "uart first\nuart again\n" "the UART's two lines and nothing else"
    assert equal (open --raw $run.qemu_log) "" "QEMU has no complaint about the guest"
    assert ($run.screen != "") "a screen was taken"
    let screen = (jab screen $run.screen)
    let ink = (glyph-ink)
    let expected = ("on screenline two" | split chars | each {|c| $ink | get ($c | into binary | first | into string) } | math sum)
    let white = (jab ink $screen "ffffff")
    assert equal $white.count $expected "the screen's white pixels are the two lines' glyphs"
    assert ($white.top < 24) $"the text starts in the first console row: top ($white.top)"
    assert ($white.bottom < 48) $"the text stays in the first two console rows: bottom ($white.bottom)"
    assert ($white.right < 108) $"the text stays in the first nine cells: right ($white.right)"
    print "displayprint: ok"
}
