# purity's integration test: a release kernel carries none of the
# kernel's debug text, and a debug kernel carries all of it, so the scan
# is proved on the build it must find things in before it is trusted on
# the build it must find nothing in. Every `jab: ` string a release
# kernel does carry is a fault line, which stays in every build. The
# workspace's test build is a debug build, so the release kernel is
# built here through the tool, into its own tree. The program itself is
# run once as well, and its own debug line is the same proof for a
# program.
use ../../../sdk/nu/jab.nu
use std/assert

# What only a debug kernel says
const debug_text = [
    "jab: kernel up on qemu virt"
    "jab: exit "
    "jab: keyboard at "
    "jab: no keyboard"
    "jab: gpu at "
    "jab: gpu cmd="
    "jab: display "
]

# What every kernel says, because a fault has to be reported whatever
# the build
const fault_text = [
    "jab: unknown system call "
    "jab: address outside the program"
    "jab: program fault: cause="
    "jab: kernel fault: cause="
    "jab: romfs: no disk "
    "jab: romfs: no romfs on disk "
    "jab: romfs: bad header at "
    "jab: romfs: wrong kind at "
    "jab: romfs: disk error"
]

def main [--kernel: path, --image: path, --out: path, --set: string = ""] {
    let ws = ($env.FILE_PWD | path join ".." ".." ".." | path expand)
    let kernel_dir = ($ws | path join (open ($ws | path join "workspace.jab.toml") | get kernel))
    let tool = ($ws | path join "sdk" "nu" "jab.nu")
    ^nu $tool build --kernel $kernel_dir
    let release = ($ws | path join ".target" "release" "kernel" "jab.elf")
    assert ($release | path exists) $"the release kernel was built at ($release)"

    # the scan finds every debug line in the debug kernel
    let debug_found = (jab strings $kernel "jab: ")
    for text in $debug_text {
        assert ($debug_found | any {|s| $s | str starts-with $text }) $"the debug kernel carries '($text)'"
    }
    for text in $fault_text {
        assert ($debug_found | any {|s| $s | str starts-with $text }) $"the debug kernel carries the fault line '($text)'"
    }

    # and none of them in the release kernel, where every jab: line is a
    # fault line
    let release_found = (jab strings $release "jab: ")
    assert (($release_found | length) > 0) "the release kernel's fault lines are found, so the scan works there too"
    for text in $debug_text {
        assert (not ($release_found | any {|s| $s | str starts-with $text })) $"the release kernel carries no '($text)'"
    }
    for text in $fault_text {
        assert ($release_found | any {|s| $s | str starts-with $text }) $"the release kernel keeps the fault line '($text)'"
    }
    let strays = ($release_found | where {|s| not ($fault_text | any {|f| $s | str starts-with $f }) })
    assert equal $strays [] $"every jab: line in the release kernel is a fault line; not these: ($strays)"

    # the program: its debug line is there in this debug build, and it
    # runs on the debug kernel with the kernel's own lines on the debug
    # channel rather than the UART
    let run = (jab launch --kernel $kernel --image $image --out $out --set $set)
    assert equal $run.status 0 $"exit status, with the UART: ($run.serial)"
    assert equal $run.serial "purity: debug build\npurity: done\n" "the program's debug line and its last line, and nothing of the kernel's"
    assert ($run.debug | str contains "jab: kernel up on qemu virt") $"the kernel's banner is on the debug channel: ($run.debug)"
    assert ($run.debug | str contains "jab: exit 0") $"and so is its exit line: ($run.debug)"
    print $"purity: ($debug_text | length) debug lines absent from the release kernel and present in the debug one; ($fault_text | length) fault lines in both"
    print "purity: ok"
}
