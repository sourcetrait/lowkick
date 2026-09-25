# jab.nu: the Jab SDK's nushell tooling.
#
# As a module (`use jab.nu`) it gives a program's integration test
# `jab launch`, which runs a program headless and can take its screen,
# and the helpers that read a screen: `jab screen`, `jab ink`,
# `jab pixel`, `jab thumbnail`. As a script (`nu jab.nu <command> ...`)
# it builds, runs, and tests the kernel and the programs for the
# justfiles, doing every lookup the workspace defines: the workspace
# directory (the nearest parent holding workspace.jab.toml), the
# toolchain (RISCV_TOOLCHAIN, else extern/riscv beside the kernel or
# program, else the workspace's, else the tools on PATH, under the
# official triple or a distribution's name), the target (.target in the
# workspace, else beside the kernel or program), and the manifests.
#
# A build is described by its symbols: `--set debug,data` names them,
# comma separated, in any case, and each reaches the assembler as
# `--defsym NAME=1` for `.ifdef NAME` to read, in the kernel and the
# programs alike. DEBUG picks the debug tree, .target/debug, and every
# other build lands in .target/release, so the two coexist. `test`
# always sets DEBUG, so a program's own debug reporting is there for its
# test; `run` and `build` are release unless asked otherwise. A program
# whose manifest says `data = true` gets DATA on top, and the kernel it
# runs on is built with the same symbols. A build is skipped when its
# output is newer than every input and the flags, symbols included,
# match the last build.

# The riscv64 binutils prefixes: the official toolchain's triple first,
# then the names distributions package the tools under.
const triples = [
    "riscv64-unknown-linux-gnu-" "riscv64-linux-gnu-"
    "riscv64-unknown-elf-" "riscv64-elf-"
]
const program_base = "0x80800000"
# RVA23 is the profile Jab pins, so everything it mandates is on whether
# or not Jab itself uses it; the supervisor profile is the one carrying
# an MMU mode and the supervisor timer the frame clock needs. RVA23 says
# nothing about machine mode, so QEMU's model of it has no physical
# memory protection at all, and the kernel enters in machine mode and
# opens PMP before it has a trap vector: without `pmp=true` that write
# is an illegal instruction which traps to address zero and spins there
# forever.
const machine = [
    "-machine" "virt" "-cpu" "rva23s64,pmp=true" "-accel" "tcg" "-smp" "4"
    "-global" "virtio-mmio.force-legacy=false"
]
# The process is named, and so are its threads (CPU 0/TCG and the
# rest), so a per-thread listing reads.
const name = ["-name" "jab,debug-threads=on"]
const display_device = ["-device" "virtio-gpu-device,xres=1920,yres=1080"]
const input_devices = [
    "-device" "virtio-keyboard-device"
    "-device" "virtio-tablet-device"
]
const devices = [
    "-device" "virtio-net-device,netdev=net0" "-netdev" "user,id=net0"
    "-device" "virtio-sound-device,audiodev=snd0" "-audiodev" "none,id=snd0"
    "-device" "virtio-rng-device"
]

# Run a program on the kernel under QEMU with no window, the UART to
# serial.log in `out`, for at most `seconds`. The status is what jab.exit
# gave, 1 on a program fault, 124 when the bound ended the run. With
# `capture`, the screen is taken into screen.ppm that long after the
# start and the run is then ended (status 0); with `keys`, each key is
# pressed through the monitor that long after the start; with `data`,
# each entry's bytes are written into the data port that long after the
# start. `set` names the symbols the kernel was built with: DEBUG puts
# the kernel's debug channel on the machine, whose text comes back as
# `debug`, and DATA the program's data channel, whose every byte to the
# host, landed in data.out, comes back as `data`. QEMU's own complaints about the guest go to
# qemu.log; cpu_seconds is the QEMU process's CPU time over the run and
# wall_seconds the run's length.
export def launch [
    --kernel: path             # the kernel ELF
    --image: path              # the program's .jab
    --out: path                # where serial.log and the rest go
    --seconds: int = 10        # the bound
    --capture: duration = 0sec # when to take the screen and end the run; 0 never
    --keys: table<at: duration, key: string, hold: int> = [] # keys to press that long after the start, QEMU's names, held for hold ms
    --data: table<at: duration, bytes: binary> = [] # bytes to write into the data port that long after the start
    --disk: path = ""          # a raw image to put on the machine as the one virtio-blk disk
    --serial: string = "disk0" # the disk's serial, which the guest reads back as its own; 19 characters at most
    --set: string = ""         # the symbols the kernel was built with, comma separated
]: nothing -> record<status: int, serial: string, debug: string, data: binary, screen: string, qemu_log: string, cpu_seconds: float, wall_seconds: float> {
    let out = ($out | path expand)
    mkdir $out
    let log = ($out | path join "serial.log")
    let qemu_log = ($out | path join "qemu.log")
    let screen = ($out | path join "screen.ppm")
    let pidfile = ($out | path join "qemu.pid")
    let monitor = ($out | path join "monitor")
    for f in [$log $qemu_log $screen $pidfile ($monitor + ".in") ($monitor + ".out")] {
        if ($f | path exists) { rm $f }
    }
    ^mkfifo ($monitor + ".in") ($monitor + ".out")
    let ports = (ports (symbols $set) $out)
    let args = ([
        "--signal=TERM" $"($seconds)" "qemu-system-riscv64"
    ] ++ $machine ++ $name ++ ["-m" "128M"] ++ $display_device ++ $input_devices ++ $ports.args ++ [
        "-bios" "none" "-kernel" ($kernel | path expand)
        "-device" $"loader,file=($image | path expand),addr=($program_base),force-raw=on"
        "-display" "none" "-monitor" $"pipe:($monitor)" "-serial" $"file:($log)"
        "-pidfile" $pidfile "-d" "guest_errors" "-D" $qemu_log
    ])
    let disked = ($args ++ (disk-args $disk $serial))
    let data_out = (if $ports.data_pipe == "" { "" } else { $ports.data_pipe + ".out" })
    let data_in = (if $ports.data_pipe == "" { "" } else { $ports.data_pipe + ".in" })
    let started = (date now)
    job spawn { ^timeout ...$disked | complete | job send 0 }
    mut result: any = null
    mut cpu = 0.0
    mut captured = ($capture == 0sec)
    mut sent = 0
    mut sent_data = 0
    while $result == null {
        $result = (try { job recv --timeout 100ms } catch { null })
        let pid = (if ($pidfile | path exists) { open --raw $pidfile | str trim } else { "" })
        let sample = (if $pid == "" { null } else { cpu-seconds $pid })
        if $sample != null { $cpu = $sample }
        let elapsed = ((date now) - $started)
        while $sent < ($keys | length) and ($keys | get $sent | get at) <= $elapsed {
            let k = ($keys | get $sent)
            if $result == null and $sample != null { monitor-send $monitor $"sendkey ($k.key) ($k.hold)" }
            $sent += 1
        }
        while $sent_data < ($data | length) and ($data | get $sent_data | get at) <= $elapsed {
            let d = ($data | get $sent_data)
            if $result == null and $sample != null and $data_in != "" { $d.bytes | save --raw --append $data_in }
            $sent_data += 1
        }
        if (not $captured) and ($elapsed >= $capture) {
            $captured = true
            if $result == null and $sample != null {
                monitor-send $monitor $"screendump ($screen)"
                wait-for-file $screen
                monitor-send $monitor "quit"
            }
        }
    }
    {
        status: $result.exit_code,
        serial: (if ($log | path exists) { open --raw $log | decode } else { "" }),
        debug: (if $ports.debug_log != "" and ($ports.debug_log | path exists) { open --raw $ports.debug_log | decode } else { "" }),
        data: (if $data_out != "" and ($data_out | path exists) { open --raw $data_out | into binary } else { 0x[] }),
        screen: (if ($screen | path exists) { $screen } else { "" }),
        qemu_log: $qemu_log,
        cpu_seconds: $cpu,
        wall_seconds: (((date now) - $started) / 1sec),
    }
}

# Read a screen `jab launch` took: its size and its pixels, three bytes
# each, red, green, blue, row by row from the top left.
export def screen [path: path]: nothing -> record<width: int, height: int, pixels: binary> {
    let bytes = (open --raw ($path | path expand))
    # P6, a line of width and height, the maximum, then the pixels
    let newlines = ($bytes | bytes index-of --all 0x[0a] | take 3)
    let header = ($bytes | bytes at 0..<($newlines.2) | decode | lines)
    let size = ($header.1 | split row " ")
    { width: ($size.0 | into int), height: ($size.1 | into int), pixels: ($bytes | bytes at ($newlines.2 + 1)..) }
}

# Where a color is on a screen: how many pixels have it and their
# bounding box (-1 all round when none do). `color` is six hex digits,
# RRGGBB.
export def ink [screen: record<width: int, height: int, pixels: binary>, color: string]: nothing -> record<count: int, left: int, top: int, right: int, bottom: int> {
    let pattern = ($color | decode hex)
    let hits = ($screen.pixels | bytes index-of --all $pattern | where {|i| $i mod 3 == 0 })
    if ($hits | is-empty) { return { count: 0, left: -1, top: -1, right: -1, bottom: -1 } }
    let xs = ($hits | each {|i| ($i // 3) mod $screen.width })
    let ys = ($hits | each {|i| ($i // 3) // $screen.width })
    { count: ($hits | length), left: ($xs | math min), top: ($ys | math min), right: ($xs | math max), bottom: ($ys | math max) }
}

# The color of the pixel at x, y as six hex digits, RRGGBB.
export def pixel [screen: record<width: int, height: int, pixels: binary>, x: int, y: int]: nothing -> string {
    let i = (($y * $screen.width + $x) * 3)
    $screen.pixels | bytes at $i..<($i + 3) | encode hex | str lowercase
}

# A rough look at a screen as text, one character per block from the
# pixel at the block's centre: space for black, then . o # by
# brightness.
export def thumbnail [screen: record<width: int, height: int, pixels: binary>, --columns: int = 96, --rows: int = 27]: nothing -> string {
    let block_w = ($screen.width // $columns)
    let block_h = ($screen.height // $rows)
    let row_bytes = ($screen.width * 3)
    0..<$rows | each {|r|
        let y = ($r * $block_h + ($block_h // 2))
        let row = ($screen.pixels | bytes at ($y * $row_bytes)..<(($y + 1) * $row_bytes))
        0..<$columns | each {|c|
            let x = ($c * $block_w + ($block_w // 2))
            let p = ($row | bytes at ($x * 3)..<($x * 3 + 3))
            let brightness = (($p | bytes at 0..<1 | into int) + ($p | bytes at 1..<2 | into int) + ($p | bytes at 2..<3 | into int))
            if $brightness < 48 { " " } else if $brightness < 256 { "." } else if $brightness < 512 { "o" } else { "#" }
        } | str join ""
    } | str join "\n"
}

# The strings in a binary that start with `prefix`, each read to its
# terminator: how a test asks a kernel image what text it carries.
export def strings [path: path, prefix: string]: nothing -> list<string> {
    let bytes = (open --raw ($path | path expand) | into binary)
    let total = ($bytes | bytes length)
    $bytes | bytes index-of --all ($prefix | into binary) | each {|at|
        let tail = ($bytes | bytes at $at..<([($at + 256) $total] | math min))
        let end = ($tail | bytes index-of 0x[00])
        (if $end < 0 { $tail } else { $tail | bytes at 0..<$end }) | decode
    }
}

# The QEMU arguments that put a raw image on the machine as its one
# virtio-blk disk, or nothing at all when there is no image. The serial
# is what the guest reads back with jab.block.list, so it is how a
# program tells one disk from another.
def disk-args [disk: path, serial: string]: nothing -> list<string> {
    if ($disk | is-empty) { return [] }
    [
        "-drive" $"if=none,id=disk0,file=($disk | path expand),format=raw"
        "-device" $"virtio-blk-device,drive=disk0,serial=($serial)"
    ]
}

# The channels a build symbol turns on, each a port of one
# virtio-serial-device: DEBUG puts the kernel's debug channel on port 1
# with the host's end a file, debug.log in `out`, and DATA the program's
# data channel on port 2 with the host's end QEMU's pipe chardev over
# data.in, a named pipe the host writes into, and data.out, a plain
# file the guest's bytes land in as they are sent, both made here. A
# file rather than a second pipe, so nothing has to hold a pipe open
# for the run and a program is never held by a host that stopped
# reading. Nothing at all for a build with neither, so its machine
# carries no serial device. The console keeps the UART in every build,
# since a fault line has to reach the host when a port has not come up.
def ports [names: list<string>, out: path]: nothing -> record<args: list<string>, debug_log: string, data_pipe: string> {
    mkdir $out
    let debug = (if "DEBUG" in $names {
        let log = ($out | path join "debug.log")
        if ($log | path exists) { rm $log }
        { args: ["-chardev" $"file,id=jabdebug,path=($log)" "-device" "virtserialport,chardev=jabdebug,nr=1,name=jab.debug"], log: $log }
    } else { { args: [], log: "" } })
    let data = (if "DATA" in $names {
        let pipe = ($out | path join "data")
        let inward = ($pipe + ".in")
        if (($inward | path type) != "pipe") {
            if ($inward | path exists) { rm $inward }
            ^mkfifo $inward
        }
        let outward = ($pipe + ".out")
        if ($outward | path exists) { rm $outward }
        "" | save -f $outward
        { args: ["-chardev" $"pipe,id=jabdata,path=($pipe)" "-device" "virtserialport,chardev=jabdata,nr=2,name=jab.data"], pipe: $pipe }
    } else { { args: [], pipe: "" } })
    let device = (if ($debug.args | is-empty) and ($data.args | is-empty) { [] } else { ["-device" "virtio-serial-device"] })
    { args: ($device ++ $debug.args ++ $data.args), debug_log: $debug.log, data_pipe: $data.pipe }
}

# The build symbols named by `--set`: comma separated, in any case,
# each made screaming snake case (debug, Debug and some-thing become
# DEBUG and SOME_THING), sorted so order cannot matter, and refused when
# the assembler would not take the name, which it would only say much
# later.
def symbols [set: string]: nothing -> list<string> {
    let names = ($set | split row "," | each {|s| $s | str trim } | where {|s| $s != "" } | each {|s| $s | str screaming-snake-case } | uniq | sort)
    for n in $names {
        if not ($n =~ '^[A-Z_][A-Z0-9_]*$') {
            error make {msg: $"--set ($n): not a symbol the assembler takes; a name starts with a letter"}
        }
    }
    $names
}

# A test build's symbols: whatever was asked, and DEBUG.
def with-debug [names: list<string>]: nothing -> list<string> { $names | append "DEBUG" | uniq | sort }

# A program's own symbols: whatever was asked, and DATA when its
# manifest says `data = true`, so the data port is there for a program
# that declared it and absent for one that did not.
def program-symbols [dir: path, names: list<string>]: nothing -> list<string> {
    let manifest = (open (($dir | path expand) | path join "program.jab.toml"))
    if ($manifest | get -o data | default false) { $names | append "DATA" | uniq | sort } else { $names }
}

# Which tree a build lands in: debug with DEBUG set, else release.
def profile [names: list<string>]: nothing -> string { if "DEBUG" in $names { "debug" } else { "release" } }

# The symbols as the assembler takes them.
def defsyms [names: list<string>]: nothing -> list<string> { $names | each {|n| ["--defsym" $"($n)=1"] } | flatten }

# A program's assets as a romfs image, built when the directory it names
# has moved on: `assets` in its manifest, relative to the manifest, with
# the program's own name as the volume's. The image is what `just run`
# puts on the machine, and the program reads it with jab.romfs.*.
def assets-image [c: record]: nothing -> string {
    let declared = ($c.manifest | get -o assets | default "")
    if $declared == "" { return "" }
    let dir = ($c.here | path join $declared | path expand)
    if not ($dir | path exists) {
        error make {msg: $"($c.manifest.name): assets = '($declared)' names no directory at ($dir)"}
    }
    assets-names $dir
    let image = ($c.out | path join $"($c.manifest.name).romfs")
    let stamp = ($c.out | path join "assets.flags")
    let inputs = (files-under [$dir])
    if ($image | path exists) and (not (stale $image ($inputs ++ [$dir]) $c.manifest.name $stamp)) { return $image }
    mkdir $c.out
    ^genromfs -d $dir -f $image -V (volume-name $c.manifest.name)
    $c.manifest.name | save -f $stamp
    $image
}

# A romfs name is at most 127 characters, which is what a Linux mount of
# the same image can read: its driver lists through a 128-byte buffer
# and works out where a file's data begins from a length that stops
# there, so a longer name makes it read the wrong bytes. The kernel
# reports such a name cut rather than wrong, but an image Jab builds
# never has one.
def assets-names [dir: path]: nothing -> nothing {
    let long = (glob ($dir | path join "**" "*") | each {|p| $p | path basename } | where {|n| ($n | str length) > 127 })
    if not ($long | is-empty) {
        error make {msg: $"romfs names are 127 characters at most, which is what a linux mount can read; too long: ($long | first)"}
    }
}

# A volume's name is bound the same way, and a disk's serial by virtio's
# 20-byte ID string, which carries a terminator only when it fits.
def volume-name [name: string]: nothing -> string { $name | str substring 0..<127 }
def disk-serial [name: string]: nothing -> string { $name | str substring 0..<19 }

# The CPU seconds a process has used, user plus system, or null once it
# is gone.
def cpu-seconds [pid: string]: nothing -> oneof<float, nothing> {
    let stat = (try { open --raw ("/proc" | path join $pid "stat") | decode } catch { "" })
    if $stat == "" { return null }
    # after the command's closing parenthesis: state, ppid, pgrp,
    # session, tty, tpgid, flags, minflt, cminflt, majflt, cmajflt,
    # utime, stime, in clock ticks of a hundredth
    let fields = ($stat | split row ") " | last | split row " ")
    (($fields | get 11 | into int) + ($fields | get 12 | into int)) / 100.0
}

# Give the QEMU monitor a command through its pipe.
def monitor-send [monitor: path, command: string]: nothing -> nothing {
    $"($command)\n" | save --raw --append ($monitor + ".in")
}

# Wait for a file QEMU writes whole to appear and stop growing.
def wait-for-file [path: path]: nothing -> nothing {
    mut last = -1
    for _ in 0..100 {
        sleep 50ms
        if ($path | path exists) {
            let size = (ls -D $path | get 0.size | into int)
            if $size > 0 and $size == $last { return }
            $last = $size
        }
    }
}

# The nearest parent of `dir` holding workspace.jab.toml, or null.
def workspace-dir [dir: path]: nothing -> oneof<string, nothing> {
    mut d = ($dir | path expand)
    loop {
        if ($d | path join "workspace.jab.toml" | path exists) { return $d }
        let parent = ($d | path dirname)
        if $parent == $d { return null }
        $d = $parent
    }
}

# The toolchain's install directory, or null for the tools on PATH.
def toolchain [here: path, workspace: oneof<string, nothing>]: nothing -> oneof<string, nothing> {
    let from_env = ($env.RISCV_TOOLCHAIN? | default "")
    if $from_env != "" { return $from_env }
    let local = ($here | path join "extern" "riscv")
    if ($local | path exists) { return $local }
    if $workspace != null {
        let shared = ($workspace | path join "extern" "riscv")
        if ($shared | path exists) { return $shared }
    }
    null
}

# The tools' command prefix: under a toolchain directory, `bin/<triple>`
# for the first triple whose `as` is there; on PATH, the first triple
# whose `as` `which` finds. Untyped because it ends in an error.
def tool-prefix [toolchain: oneof<string, nothing>] {
    let looked = ($triples | each {|t| $t + "as" } | str join ", ")
    if $toolchain != null {
        let bin = ($toolchain | path join "bin")
        for t in $triples {
            let prefix = ($bin | path join $t)
            if (($prefix + "as") | path exists) { return $prefix }
        }
        error make {msg: $"no riscv64 binutils under ($bin): looked for ($looked)"}
    }
    for t in $triples {
        if not (which ($t + "as") | is-empty) { return $t }
    }
    error make {msg: $"no riscv64 binutils on PATH: looked for ($looked); set RISCV_TOOLCHAIN or link extern/riscv to a toolchain"}
}

# Every file under the directories, for the staleness check.
def files-under [dirs: list<string>]: nothing -> list<string> {
    $dirs | each {|d| glob ($d | path join "**" "*") } | flatten | where {|p| ($p | path type) == "file" }
}

# Whether `output` needs building: missing, older than an input, or
# built with other flags than `stamp` records.
def stale [output: path, inputs: list<string>, flags: string, stamp: path]: nothing -> bool {
    if not ($output | path exists) { return true }
    if not ($stamp | path exists) { return true }
    if (open --raw $stamp) != $flags { return true }
    let newest = ($inputs | each {|p| ls -D $p | get 0.modified } | sort | last)
    (ls -D $output | get 0.modified) <= $newest
}

# The kernel's or a program's context for a build with `names` set:
# manifest, workspace, toolchain, symbols, the target tree (.target's
# debug or release), and the output directory (the workspace-relative
# path under the tree, or the name when standalone).
def context [dir: path, kind: string, names: list<string>]: nothing -> record {
    let here = ($dir | path expand)
    let manifest_path = ($here | path join $"($kind).jab.toml")
    let manifest = (open $manifest_path)
    let workspace = (workspace-dir $here)
    let tree = (profile $names)
    let target = (if $workspace == null { $here | path join ".target" $tree } else { $workspace | path join ".target" $tree })
    let relative = (if $workspace == null { $manifest.name } else { $here | path relative-to $workspace })
    let tc = (toolchain $here $workspace)
    {
        here: $here,
        manifest: $manifest,
        manifest_path: $manifest_path,
        workspace: $workspace,
        toolchain: $tc,
        prefix: (tool-prefix $tc),
        symbols: $names,
        profile: $tree,
        target: $target,
        out: ($target | path join $relative),
    }
}

# The kernel ELF a program runs on: the workspace's, in the same tree,
# or JAB_KERNEL. Left untyped because it ends in an error, which the
# output check rejects.
def kernel-elf [c: record] {
    if $c.workspace != null {
        let ws = (open ($c.workspace | path join "workspace.jab.toml"))
        return ($c.target | path join $ws.kernel "jab.elf")
    }
    let from_env = ($env.JAB_KERNEL? | default "")
    if $from_env != "" { return $from_env }
    error make {msg: "no workspace above this program and no JAB_KERNEL: where is the kernel?"}
}

# The window for a run: JAB_DISPLAY, else the manifest's display, else
# the best QEMU window the host has: gtk with OpenGL on Linux, SDL with
# OpenGL on Windows, cocoa on macOS (its only window, and it has no
# OpenGL). A Linux machine with no display server is nobody's console;
# there the display goes out over VNC for development.
def display [manifest: record]: nothing -> string {
    let forced = ($env.JAB_DISPLAY? | default "")
    if $forced != "" { return $forced }
    let declared = ($manifest | get -o display | default "")
    if $declared != "" { return $declared }
    match $nu.os-info.name {
        "macos" => "cocoa",
        "windows" => "sdl,gl=on",
        _ => {
            let server = (($env.DISPLAY? | default "") != "") or (($env.WAYLAND_DISPLAY? | default "") != "")
            if $server { "gtk,gl=on" } else { "vnc=127.0.0.1:30" }
        },
    }
}

def build-kernel [dir: path, names: list<string>]: nothing -> nothing {
    let c = (context $dir "kernel" $names)
    let m = $c.manifest
    let includes = ($m | get -o includes | default [])
    let include_flags = ($includes | each {|i| ["-I" $i] } | flatten)
    let set_flags = (defsyms $names)
    let flags = (($include_flags ++ $set_flags ++ [$c.prefix]) | str join " ")
    let elf = ($c.out | path join "jab.elf")
    let stamp = ($c.out | path join "flags")
    cd $c.here
    let inputs = ((files-under (["src"] ++ $includes)) ++ [$c.manifest_path $m.link])
    if not (stale $elf $inputs $flags $stamp) { return }
    mkdir $c.out
    let asm = ($c.prefix + "as")
    let ld = ($c.prefix + "ld")
    let objdump = ($c.prefix + "objdump")
    for f in (glob src/*.S) {
        let obj = ($c.out | path join (($f | path parse | get stem) + ".o"))
        ^$asm ...$include_flags ...$set_flags $f -o $obj
    }
    ^$ld -T $m.link -nostdlib ...(glob ($c.out | path join "*.o")) -o $elf
    ^$objdump -d $elf | save -f ($c.out | path join "jab.disas")
    $flags | save -f $stamp
}

def build-program [dir: path, names: list<string>]: nothing -> nothing {
    let c = (context $dir "program" $names)
    let m = $c.manifest
    let includes = ($m | get -o includes | default [])
    let include_flags = ($includes | each {|i| ["-I" $i] } | flatten)
    let set_flags = (defsyms $names)
    let flags = (($include_flags ++ $set_flags ++ [$c.prefix]) | str join " ")
    let image = ($c.out | path join $"($m.name).jab")
    let stamp = ($c.out | path join "flags")
    cd $c.here
    let inputs = ((files-under (["src"] ++ $includes)) ++ [$c.manifest_path $m.link])
    if not (stale $image $inputs $flags $stamp) { return }
    mkdir $c.out
    let asm = ($c.prefix + "as")
    let ld = ($c.prefix + "ld")
    let objcopy = ($c.prefix + "objcopy")
    let obj = ($c.out | path join $"($m.name).o")
    let elf = ($c.out | path join $"($m.name).elf")
    ^$asm ...$include_flags ...$set_flags src/main.S -o $obj
    ^$ld -T $m.link -nostdlib $obj -o $elf
    ^$objcopy -O binary $elf $image
    $flags | save -f $stamp
}

# What a program's test or run needs, after building it with `names`
# set, and DATA when its manifest asks: the kernel built with the same
# symbols in the same tree, so a debug program runs on a debug kernel
# and a data program on a kernel carrying the port; standalone, with no
# workspace, JAB_KERNEL is taken as it is.
def prepared [dir: path, names: list<string>]: nothing -> record {
    let names = (program-symbols $dir $names)
    build-program $dir $names
    let c = (context $dir "program" $names)
    if $c.workspace != null {
        let ws = (open ($c.workspace | path join "workspace.jab.toml"))
        build-kernel ($c.workspace | path join $ws.kernel) $names
    }
    let kernel = (kernel-elf $c)
    if not ($kernel | path exists) { error make {msg: $"no kernel at ($kernel); build the kernel first, with the same --set"} }
    { context: $c, kernel: $kernel, image: ($c.out | path join $"($c.manifest.name).jab") }
}

# Build the kernel and every program of the workspace at `ws` with
# `names` set, each program with its own manifest's DATA on top.
def workspace-build [ws: path, names: list<string>]: nothing -> nothing {
    let m = (open ($ws | path join "workspace.jab.toml"))
    build-kernel ($ws | path join $m.kernel) $names
    for p in $m.programs {
        let dir = ($ws | path join $p)
        build-program $dir (program-symbols $dir $names)
    }
}

# The arguments that run a program's test/test.nu on the kernel: the
# kernel, the image, the output directory, the assets image when the
# program has one, and the symbols the build was made with.
def test-args [ready: record]: nothing -> list<string> {
    let script = ($ready.context.here | path join "test" "test.nu")
    if not ($script | path exists) { error make {msg: $"($ready.context.manifest.name) has no test/test.nu"} }
    let assets = (assets-image $ready.context)
    let set = ($ready.context.symbols | str join ",")
    let common = [$script "--kernel" $ready.kernel "--image" $ready.image "--out" $ready.context.out "--set" $set]
    if $assets == "" { $common } else { $common ++ ["--assets" $assets] }
}

# Run a program with the console window and the full virtio device set,
# the UART on stdio, the debug channel to a file when DEBUG is set, and
# the data channel on a pair of pipes when the program asks for it;
# QEMU's exit code is the program's exit status.
def run-program [dir: path, names: list<string>]: nothing -> nothing {
    let ready = (prepared $dir $names)
    let c = $ready.context
    # a program's own assets when it has them, else the blank image that
    # has always been there, so the machine always carries one disk
    let assets = (assets-image $c)
    let disk = (if $assets == "" {
        let blank = ($c.target | path join "disk.img")
        if not ($blank | path exists) { ^truncate -s 64M $blank }
        $blank
    } else { $assets })
    let serial = (if $assets == "" { "disk0" } else { disk-serial $c.manifest.name })
    let window = (display $c.manifest)
    if ($window | str starts-with "vnc=") {
        print "no display server here, so this is a development run: the display is served over VNC on 127.0.0.1:5930; tunnel it with `ssh -N -L 5930:127.0.0.1:5930 <this host>` and view it with `vncviewer 127.0.0.1:5930`"
    }
    let ports = (ports $c.symbols $c.out)
    if $ports.debug_log != "" { print $"the kernel's debug channel goes to ($ports.debug_log)" }
    if $ports.data_pipe != "" { print $"the program's data channel: write into the pipe ($ports.data_pipe).in; what it sends lands in ($ports.data_pipe).out" }
    let args = ($machine ++ $name ++ ["-m" "4G"] ++ $display_device ++ $input_devices ++ $devices ++ (disk-args $disk $serial) ++ $ports.args ++ [
        "-bios" "none" "-kernel" $ready.kernel
        "-device" $"loader,file=($ready.image),addr=($program_base),force-raw=on"
        "-display" $window "-serial" "stdio" "-monitor" "none"
    ])
    ^qemu-system-riscv64 ...$args
}

# Build the kernel and every program of the workspace at `ws`; release
# unless --set says otherwise.
def "main workspace build" [ws: path, --set: string = ""] {
    workspace-build $ws (symbols $set)
}

# Test every program, a category, or one program, on a build with DEBUG
# set beside whatever --set names; prints each test's output and a
# summary, exits 1 if any fails.
def "main workspace test" [ws: path, category: string = "", name: string = "", --set: string = ""] {
    let names = (with-debug (symbols $set))
    workspace-build $ws $names
    let m = (open ($ws | path join "workspace.jab.toml"))
    let selected = ($m.programs | where {|p| ($category == "" or ($p | str starts-with $"($category)/")) and ($name == "" or ($p | path basename) == $name) })
    if ($selected | is-empty) { error make {msg: $"no program matches ($category) ($name)"} }
    let results = ($selected | each {|p|
        let ready = (prepared ($ws | path join $p) $names)
        let r = (^nu ...(test-args $ready) | complete)
        print $"--- ($p)"
        print -n $r.stdout
        if $r.exit_code != 0 { print -n $r.stderr }
        { program: $p, passed: ($r.exit_code == 0) }
    })
    print ($results | table)
    if not ($results | all {|r| $r.passed }) { exit 1 }
}

# Build everything, then run one program with the console window;
# release unless --set says otherwise.
def "main workspace run" [ws: path, category: string, name: string, --set: string = ""] {
    let names = (symbols $set)
    workspace-build $ws $names
    run-program ($ws | path join $category $name) $names
}

# Build the kernel at `dir` (--kernel) or the program at `dir`; release
# unless --set says otherwise.
def "main build" [dir: path, --kernel, --set: string = ""] {
    let names = (symbols $set)
    if $kernel { build-kernel $dir $names } else { build-program $dir $names }
}

# Build the program at `dir` with DEBUG set beside whatever --set names
# and run its test/test.nu on the debug kernel.
def "main test" [dir: path, --set: string = ""] {
    ^nu ...(test-args (prepared $dir (with-debug (symbols $set))))
}

# Build the program at `dir` and run it with the console window; release
# unless --set says otherwise.
def "main run" [dir: path, --set: string = ""] {
    run-program $dir (symbols $set)
}

# Remove the kernel's (--kernel) or the program's build output from both
# trees.
def "main clean" [dir: path, --kernel] {
    for names in [[] ["DEBUG"]] {
        let c = (context $dir (if $kernel { "kernel" } else { "program" }) $names)
        if ($c.out | path exists) { rm -r $c.out }
    }
}

def main [] {
    print "nu jab.nu <build|test|run|clean> <dir> [--kernel] [--set names]; nu jab.nu workspace <build|test|run> <ws> [category [name]] [--set names]"
}
