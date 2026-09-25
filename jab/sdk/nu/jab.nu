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
# A build is described by its symbols: `--set debug,stats` names them,
# comma separated, in any case, and each reaches the assembler as
# `--defsym NAME=1` for `.ifdef NAME` to read, in the kernel and the
# programs alike. DEBUG picks the debug tree, .target/debug, and every
# other build lands in .target/release, so the two coexist. `test`
# always sets DEBUG, so a program's own debug reporting is there for its
# test; `run` and `build` are release unless asked otherwise. The API,
# a port between the program and the host, is not a build symbol: every
# kernel carries it, and `--api` on a run (or `jab launch --api`) puts
# the port on the machine, off by default, so one build runs either
# way. A build is skipped when its output is newer than every input and
# the flags, symbols included, match the last build.

# The riscv64 binutils prefixes: the official toolchain's triple first,
# then the names distributions package the tools under.
const triples = [
    "riscv64-unknown-linux-gnu-" "riscv64-linux-gnu-"
    "riscv64-unknown-elf-" "riscv64-elf-"
]
# The window's base (jab.inc): the kernel's 2 MiB and the framebuffer's
# 8 MiB come first, and the program has the rest of the machine's 4 GiB.
const program_base = "0x80a00000"
const memory = ["-m" "4G"]
# RVA23 is the profile Jab pins, so everything it mandates is on whether
# or not Jab itself uses it; the supervisor profile is the one carrying
# an MMU mode and the supervisor timer the frame clock needs. RVA23 says
# nothing about machine mode, so QEMU's model of it has no physical
# memory protection at all, and the kernel enters in machine mode and
# opens PMP before it has a trap vector: without `pmp=true` that write
# is an illegal instruction which traps to address zero and spins there
# forever. QEMU carries the profile from 9.2; an older QEMU gets the
# generic rv64, which has what the kernel needs (Sv39, Sstc, PMP, F and
# D) and lacks only what the profile would add for a program. RVA22's
# model is not the fallback: it starts bare with the profile's mandatory
# set, and Sstc is optional there, so the frame clock would fault.
const cpu_profile = "rva23s64,pmp=true"
const cpu_generic = "rv64,pmp=true"
const machine_rest = [
    "-accel" "tcg" "-smp" "4"
    "-global" "virtio-mmio.force-legacy=false"
]

# The CPU model for this host's QEMU: JAB_CPU as given, else the RVA23
# profile when `-cpu help` lists it, else the generic rv64.
def cpu-model []: nothing -> string {
    let forced = ($env.JAB_CPU? | default "")
    if $forced != "" { return $forced }
    let listed = (^qemu-system-riscv64 -cpu help | complete | get stdout | lines | any {|l| ($l | str trim) == "rva23s64" })
    if $listed { $cpu_profile } else { $cpu_generic }
}

# The machine: virt, the CPU this host can give, four harts, every
# transport modern.
def machine-args []: nothing -> list<string> {
    ["-machine" "virt" "-cpu" (cpu-model)] ++ $machine_rest
}
# The guest is named jab and so are the threads (CPU 0/TCG and the
# rest), so a per-thread listing reads; on Linux the process is named
# jab too, so `pgrep -x jab` finds it. `-name jab` alone names only the
# guest, and `process=` is a Linux prctl that QEMU refuses to start
# without elsewhere ("Change of process name not supported by your
# OS"), so the process name is Linux's alone.
def name-args []: nothing -> list<string> {
    let process = (if $nu.os-info.name == "linux" { ",process=jab" } else { "" })
    ["-name" $"jab($process),debug-threads=on"]
}
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
# pressed through the monitor that long after the start. `set` names the
# symbols the kernel was built with: DEBUG puts the kernel's debug
# channel on the machine, whose text comes back as `debug`. With `api`,
# or with anything to `send`, the API's port is on the machine: each
# entry of `send` is written into it that long after the start, and
# every byte the program sent, landed in api.out, comes back as `api`.
# QEMU's own complaints about the guest go to qemu.log; cpu_seconds is
# the QEMU process's CPU time over the run and wall_seconds the run's
# length.
export def launch [
    --kernel: path             # the kernel ELF
    --image: path              # the program's .jab
    --out: path                # where serial.log and the rest go
    --seconds: int = 10        # the bound
    --capture: duration = 0sec # when to take the screen and end the run; 0 never
    --keys: table<at: duration, key: string, hold: int> = [] # keys to press that long after the start, QEMU's names, held for hold ms
    --api                      # put the API's port on the machine
    --send: table<at: duration, bytes: binary> = [] # bytes to write into the API that long after the start; puts the port on the machine
    --disk: path = ""          # a raw image to put on the machine as the one virtio-blk disk
    --serial: string = "disk0" # the disk's serial, which the guest reads back as its own; 19 characters at most
    --set: string = ""         # the symbols the kernel was built with, comma separated
]: nothing -> record<status: int, serial: string, debug: string, api: binary, screen: string, qemu_log: string, cpu_seconds: float, wall_seconds: float> {
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
    let ports = (ports (symbols $set) $out ($api or (not ($send | is-empty))))
    let args = ([
        "--signal=TERM" $"($seconds)" "qemu-system-riscv64"
    ] ++ (machine-args) ++ (name-args) ++ $memory ++ $display_device ++ $input_devices ++ $ports.args ++ [
        "-bios" "none" "-kernel" ($kernel | path expand)
        "-device" $"loader,file=($image | path expand),addr=($program_base),force-raw=on"
        "-display" "none" "-monitor" $"pipe:($monitor)" "-serial" $"file:($log)"
        "-pidfile" $pidfile "-d" "guest_errors" "-D" $qemu_log
    ])
    let disked = ($args ++ (disk-args $disk $serial))
    let api_out = (if $ports.api_pipe == "" { "" } else { $ports.api_pipe + ".out" })
    let api_in = (if $ports.api_pipe == "" { "" } else { $ports.api_pipe + ".in" })
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
        while $sent_data < ($send | length) and ($send | get $sent_data | get at) <= $elapsed {
            let d = ($send | get $sent_data)
            if $result == null and $sample != null and $api_in != "" { $d.bytes | save --raw --append $api_in }
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
        api: (if $api_out != "" and ($api_out | path exists) { open --raw $api_out | into binary } else { 0x[] }),
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

# The ports, each of one virtio-serial-device: DEBUG in the build puts
# the kernel's debug channel on port 1 with the host's end a file,
# debug.log in `out`; `api` puts the API on port 2 with the host's end
# QEMU's pipe chardev over api.in, a named pipe the host writes into,
# and api.out, a plain file the program's bytes land in as they are
# sent, both made here. A file rather than a second pipe, so nothing
# has to hold a pipe open for the run and a program is never held by a
# host that stopped reading. Nothing at all with neither, so the
# machine carries no serial device. The console keeps the UART in
# every build, since a fault line has to reach the host when a port has
# not come up.
def ports [names: list<string>, out: path, api: bool]: nothing -> record<args: list<string>, debug_log: string, api_pipe: string> {
    mkdir $out
    let debug = (if "DEBUG" in $names {
        let log = ($out | path join "debug.log")
        if ($log | path exists) { rm $log }
        { args: ["-chardev" $"file,id=jabdebug,path=($log)" "-device" "virtserialport,chardev=jabdebug,nr=1,name=jab.debug"], log: $log }
    } else { { args: [], log: "" } })
    let port = (if $api {
        let pipe = ($out | path join "api")
        let inward = ($pipe + ".in")
        if (($inward | path type) != "pipe") {
            if ($inward | path exists) { rm $inward }
            ^mkfifo $inward
        }
        let outward = ($pipe + ".out")
        if ($outward | path exists) { rm $outward }
        "" | save -f $outward
        { args: ["-chardev" $"pipe,id=jabapi,path=($pipe)" "-device" "virtserialport,chardev=jabapi,nr=2,name=jab.api"], pipe: $pipe }
    } else { { args: [], pipe: "" } })
    let device = (if ($debug.args | is-empty) and ($port.args | is-empty) { [] } else { ["-device" "virtio-serial-device"] })
    { args: ($device ++ $debug.args ++ $port.args), debug_log: $debug.log, api_pipe: $port.pipe }
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

# The symbol the host adds to every build: DISPLAY_FLUSH_SCALED where
# the window a run would open charges a flush by its area, SDL and GTK,
# and nothing under cocoa, which charges every flush alike. The window
# is JAB_DISPLAY's or the host's own, never a manifest's, so a tree
# holds one class; `JAB_DISPLAY=cocoa` builds the other kernel on any
# host, for measuring.
def with-host [names: list<string>]: nothing -> list<string> {
    if ((display {}) | str starts-with "cocoa") { $names } else { $names | append "DISPLAY_FLUSH_SCALED" | uniq | sort }
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

# The Jab QEMU processes on this host, by their command line, which
# every Jab line marks with `-name jab`.
def jab-pids []: nothing -> list<int> {
    ps -l | where {|p| ($p.command | str contains "qemu-system-riscv64") and ($p.command | str contains "-name jab") } | get pid
}

# Watch the running Jab QEMU per thread, whatever shell this is run
# from: on Linux in the host's own top, where the harts (`CPU 0/TCG`
# and on) and the main loop (under the process name, where the host's
# copy and paint land) show by name, ending when top does; on macOS,
# whose top has no thread view, `ps -M` of the process every second,
# the first row the AppKit thread that draws the window, QEMU's own
# loop and the harts below it unnamed, until the run ends or the watch
# is interrupted.
def "main watch" [] {
    let pids = (jab-pids)
    if ($pids | is-empty) { error make {msg: "no jab is running"} }
    let list = ($pids | each {|p| $p | into string } | str join ",")
    match $nu.os-info.name {
        "linux" => { ^top -H -p $list },
        "macos" => {
            loop {
                let alive = (jab-pids)
                if ($alive | is-empty) { print "jab: the run has ended"; break }
                let threads = ($alive | each {|p| ^ps -M -p ($p | into string) | complete | get stdout } | str join (char nl))
                print $"(ansi cls)(date now | format date '%H:%M:%S')  jab ($alive | each {|p| $p | into string } | str join ', ')(char nl)($threads)"
                sleep 1sec
            }
        },
        _ => { error make {msg: $"no top here for ($nu.os-info.name); the jab processes are ($list)"} },
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
# the best QEMU window the host has: SDL with OpenGL on Linux and
# Windows, cocoa on macOS (its only window, and it has no OpenGL). A
# Linux machine with no display server is nobody's console; there the
# display goes out over VNC for development.
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
            if $server { "sdl,gl=on" } else { "vnc=127.0.0.1:30" }
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
# set: the kernel built with the same symbols in the same tree, so a
# debug program runs on a debug kernel; standalone, with no workspace,
# JAB_KERNEL is taken as it is.
def prepared [dir: path, names: list<string>]: nothing -> record {
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
# `names` set.
def workspace-build [ws: path, names: list<string>]: nothing -> nothing {
    let m = (open ($ws | path join "workspace.jab.toml"))
    build-kernel ($ws | path join $m.kernel) $names
    for p in $m.programs { build-program ($ws | path join $p) $names }
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
# the API's port when `api` asked for it; QEMU's exit code is the
# program's exit status.
def run-program [dir: path, names: list<string>, api: bool]: nothing -> nothing {
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
    # the ports' files sit beside the build output, named in the README;
    # a run says nothing of its own
    let ports = (ports $c.symbols $c.out $api)
    let args = ((machine-args) ++ (name-args) ++ $memory ++ $display_device ++ $input_devices ++ $devices ++ (disk-args $disk $serial) ++ $ports.args ++ [
        "-bios" "none" "-kernel" $ready.kernel
        "-device" $"loader,file=($ready.image),addr=($program_base),force-raw=on"
        "-display" $window "-serial" "stdio" "-monitor" "none"
    ])
    ^qemu-system-riscv64 ...$args
}

# Build the kernel and every program of the workspace at `ws`; release
# unless --set says otherwise.
def "main workspace build" [ws: path, --set: string = ""] {
    workspace-build $ws (with-host (symbols $set))
}

# Test every program, a category, or one program, on a build with DEBUG
# set beside whatever --set names; prints each test's output and a
# summary, exits 1 if any fails. A test that drives the API asks
# `jab launch` for the port itself.
def "main workspace test" [ws: path, category: string = "", name: string = "", --set: string = ""] {
    let names = (with-host (with-debug (symbols $set)))
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
# release unless --set says otherwise, the API's port on the machine
# with --api.
def "main workspace run" [ws: path, category: string, name: string, --set: string = "", --api] {
    let names = (with-host (symbols $set))
    workspace-build $ws $names
    run-program ($ws | path join $category $name) $names $api
}

# Build the kernel at `dir` (--kernel) or the program at `dir`; release
# unless --set says otherwise.
def "main build" [dir: path, --kernel, --set: string = ""] {
    let names = (with-host (symbols $set))
    if $kernel { build-kernel $dir $names } else { build-program $dir $names }
}

# Build the program at `dir` with DEBUG set beside whatever --set names
# and run its test/test.nu on the debug kernel.
def "main test" [dir: path, --set: string = ""] {
    ^nu ...(test-args (prepared $dir (with-host (with-debug (symbols $set)))))
}

# Build the program at `dir` and run it with the console window; release
# unless --set says otherwise, the API's port on the machine with --api.
def "main run" [dir: path, --set: string = "", --api] {
    run-program $dir (with-host (symbols $set)) $api
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
    print "nu jab.nu <build|test|clean> <dir> [--kernel] [--set names]; nu jab.nu run <dir> [--set names] [--api]; nu jab.nu workspace <build|test|run> <ws> [category [name]] [--set names] [--api]; nu jab.nu watch"
}
