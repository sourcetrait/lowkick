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
# virt's map has this many virtio-mmio transports, a hard ceiling on
# the devices a line can carry.
const transport_limit = 8
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
# No parallel port: QEMU's default is a text console of its own, which
# under SDL is a second, hidden window with its own GL context, drawn
# on every refresh its cursor blinks.
const machine_rest = [
    "-accel" "tcg" "-smp" "4"
    "-global" "virtio-mmio.force-legacy=false"
    "-parallel" "none"
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
# The guest is named for the program, `Jab: <program>`, which is what
# QEMU's window shows after its own prefix (SDL adds the console's
# index, `QEMU (Jab: pad-0)`), and the threads are named (CPU 0/TCG and
# the rest), so a per-thread listing reads; on Linux the process is
# named jab, so `pgrep -x jab` finds it. `-name` alone names only the
# guest, and `process=` is a Linux prctl that QEMU refuses to start
# without elsewhere ("Change of process name not supported by your
# OS"), so the process name is Linux's alone.
def name-args [program: string]: nothing -> list<string> {
    let process = (if $nu.os-info.name == "linux" { ",process=jab" } else { "" })
    ["-name" $"Jab: ($program)($process),debug-threads=on"]
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
    --pad: path = ""           # a NUON file of pad events, [[at, type, code, value]; ...], played into a fifo attached as a gamepad through the evdev shim; Linux
    --kbm                      # the keyboard and the tablet on the machine, which is the default
    --no-kbm                   # neither on the machine
]: nothing -> record<status: int, serial: string, debug: string, api: binary, screen: string, qemu_log: string, cpu_seconds: float, wall_seconds: float> {
    if $kbm and $no_kbm { error make {msg: "--kbm and --no-kbm together: one or the other"} }
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
    let inputs = (if $no_kbm { [] } else { $input_devices })
    let gamepad = (pad-setup $pad $out)
    let args = ([
        "--signal=TERM" $"($seconds)" "qemu-system-riscv64"
    ] ++ (machine-args) ++ (name-args ($image | path parse | get stem)) ++ $memory ++ $display_device ++ $inputs ++ $ports.args ++ $gamepad.args ++ [
        "-bios" "none" "-kernel" ($kernel | path expand)
        "-device" $"loader,file=($image | path expand),addr=($program_base),force-raw=on"
        "-display" "none" "-monitor" $"pipe:($monitor)" "-serial" $"file:($log)"
        "-pidfile" $pidfile "-d" "guest_errors" "-D" $qemu_log
    ])
    let disked = ($args ++ (disk-args $disk $serial))
    let api_out = (if $ports.api_pipe == "" { "" } else { $ports.api_pipe + ".out" })
    let api_in = (if $ports.api_pipe == "" { "" } else { $ports.api_pipe + ".in" })
    let started = (date now)
    job spawn { with-env $gamepad.env { ^timeout ...$disked | complete } | job send 0 }
    mut result: any = null
    mut cpu = 0.0
    mut captured = ($capture == 0sec)
    mut sent = 0
    mut sent_data = 0
    mut sent_pad = 0
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
        while $sent_pad < ($gamepad.groups | length) and ($gamepad.groups | get $sent_pad | get at) <= $elapsed {
            let g = ($gamepad.groups | get $sent_pad)
            if $result == null and $sample != null and $gamepad.fifo != "" { pad-report $g.items | save --raw --append $gamepad.fifo }
            $sent_pad += 1
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

# The gamepad a launch plays: nothing at all without a table; with one,
# the fifo `pad` in `out`, made fresh, which QEMU's host-input device
# opens as the pad with the evdev shim preloaded to answer its ioctls
# as the reference pad; the QEMU arguments and environment for that;
# and the table's rows grouped by their time, each group one report
# the launch loop writes into the fifo at that time. The shim is one
# of the workspace's, so the workspace above `out` must hold it. Linux
# only, since it preloads.
def pad-setup [table: path, out: path]: nothing -> record<args: list<string>, env: record, fifo: string, groups: list<any>> {
    if ($table | is-empty) { return { args: [], env: {}, fifo: "", groups: [] } }
    if $nu.os-info.name != "linux" { error make {msg: "--pad preloads the evdev shim into QEMU, which is Linux only"} }
    let ws = (workspace-dir $out)
    if $ws == null { error make {msg: "--pad needs the workspace above the output directory, which holds shim/crates/evdev"} }
    let shim = (shim-build $ws "jabshim_evdev")
    let rows = (open ($table | path expand))
    let wanted = [at type code value]
    if not ($wanted | all {|c| $c in ($rows | columns) }) {
        error make {msg: $"($table): a pad table has the columns at, type, code, value; this one has ($rows | columns | str join ', ')"}
    }
    let fifo = ($out | path join "pad")
    if (($fifo | path type) != null) { rm $fifo }
    ^mkfifo $fifo
    let groups = ($rows | sort-by at | group-by --to-table {|r| $r.at | into int } | each {|g| { at: ($g.items | first | get at), items: $g.items } })
    {
        args: ["-device" $"virtio-input-host-device,evdev=($fifo)"],
        env: { LD_PRELOAD: $shim, EVDEV_SHIM_FIFO: $fifo },
        fifo: $fifo,
        groups: $groups,
    }
}

# One report of pad events, as the device would send them: each row an
# input_event, then a SYN_REPORT closing the report.
def pad-report [items: table<type: int, code: int, value: int>]: nothing -> binary {
    ($items | each {|e| input-event $e.type $e.code $e.value } | bytes collect) ++ (input-event 0 0 0)
}

# One input_event as an evdev device writes it, 24 bytes: the wall
# clock's seconds and microseconds as two 64-bit fields, then the type
# and the code as 16 bits each and the value as 32, all little-endian.
def input-event [type: int, code: int, value: int]: nothing -> binary {
    let ns = (date now | into int)
    let sec = ($ns // 1_000_000_000)
    let usec = (($ns mod 1_000_000_000) // 1000)
    ($sec | into binary --endian little | bytes at 0..<8) ++ ($usec | into binary --endian little | bytes at 0..<8) ++ ($type | into binary --endian little | bytes at 0..<2) ++ ($code | into binary --endian little | bytes at 0..<2) ++ ($value | into binary --endian little | bytes at 0..<4)
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
# every Jab line marks with `-name Jab:`: the QEMU itself, never the
# `timeout` a test wraps it in, whose command line carries the same
# words.
def jab-pids []: nothing -> list<int> {
    ps -l | where {|p| (($p.command | split row " " | first | path basename) == "qemu-system-riscv64") and ($p.command | str contains "-name Jab:") } | get pid
}

# The threads of a process with their cumulative CPU seconds: on Linux
# from /proc, by thread id and name (the harts `CPU 0/TCG` and on, the
# main loop under the process name); on macOS from `ps -M`, its rows
# in order, the first the AppKit thread that draws the window, the
# rest unnamed, so a thread is identified by its row.
def threads-of [pid: int]: nothing -> table<id: string, name: string, cpu: float> {
    match $nu.os-info.name {
        "linux" => {
            let tasks = (try { ls ("/proc" | path join ($pid | into string) "task") | get name } catch { [] })
            $tasks | each {|t|
                let stat = (try { open --raw ($t | path join "stat") | decode } catch { "" })
                if $stat == "" { null } else {
                    let fields = ($stat | split row ") " | last | split row " ")
                    let name = (try { open --raw ($t | path join "comm") | decode | str trim } catch { "" })
                    { id: ($t | path basename), name: $name, cpu: ((($fields | get 11 | into int) + ($fields | get 12 | into int)) / 100.0) }
                }
            } | compact
        },
        "macos" => {
            let out = (^ps -M -p ($pid | into string) | complete | get stdout)
            $out | lines | skip 1 | enumerate | each {|row|
                let times = ($row.item | parse --regex '(?P<stime>\d+:\d+(?::\d+)?\.\d+)\s+(?P<utime>\d+:\d+(?::\d+)?\.\d+)' | get -o 0)
                if $times == null { null } else {
                    { id: ($row.index | into string), name: (if $row.index == 0 { "main" } else { $"thread ($row.index)" }), cpu: ((clock-seconds $times.stime) + (clock-seconds $times.utime)) }
                }
            } | compact
        },
        _ => { error make {msg: $"no thread reading here for ($nu.os-info.name)"} },
    }
}

# `ps` clock text, M:SS.hh or H:MM:SS.hh, as seconds.
def clock-seconds [text: string]: nothing -> float {
    $text | split row ":" | each {|p| $p | into float } | reduce --fold 0.0 {|it, acc| $acc * 60.0 + $it }
}

# Where `watch` records: watch.nuonl under the workspace's .target.
def watch-file [ws: path]: nothing -> string {
    $ws | path expand | path join ".target" "watch.nuonl"
}

# Record the running Jab QEMU per thread, once a second, to the
# workspace's .target/watch.nuonl, whatever shell this is run from: a
# first line describing the run (host, QEMU, the window, the kernel and
# the symbols it was built with, read from its tree's flags stamp),
# then a line per sample with every thread's cumulative CPU seconds.
# One short line is printed per sample, the rates since the last; the
# file is what `watched` reports on. Ends when the run does, or when
# interrupted.
def "main watch" [ws: path] {
    let pids = (jab-pids)
    if ($pids | is-empty) { error make {msg: "no jab is running"} }
    let pid = ($pids | first)
    let command = (ps -l | where pid == $pid | get -o 0.command | default "")
    let window = ($command | parse --regex '-display (?P<w>\S+)' | get -o 0.w | default "")
    let kernel = ($command | parse --regex '-kernel (?P<k>\S+)' | get -o 0.k | default "")
    let stamp_file = (if $kernel == "" { "" } else { $kernel | path dirname | path join "flags" })
    let stamp = (if $stamp_file != "" and ($stamp_file | path exists) { open --raw $stamp_file | decode | str trim } else { "" })
    let symbols = ($stamp | parse --regex '--defsym (?P<s>[A-Z0-9_]+)=1' | get s)
    let qemu = (^qemu-system-riscv64 --version | complete | get stdout | lines | get -o 0 | default "")
    let file = (watch-file $ws)
    mkdir ($file | path dirname)
    let started = (date now)
    let run = { os: $nu.os-info.name, arch: $nu.os-info.arch, qemu: $qemu, window: $window, kernel: $kernel, symbols: $symbols, pid: $pid, started: ($started | format date "%Y-%m-%dT%H:%M:%S") }
    ({ run: $run } | to nuon) + (char nl) | save --raw -f $file
    print $"jab watch: recording ($pid) to ($file), ($symbols | str join ', ') under ($window)"
    if ($pids | length) > 1 { print $"jab watch: ($pids | length) jab processes; recording the first" }
    mut last: any = null
    loop {
        if (jab-pids | where {|p| $p == $pid } | is-empty) { print "jab watch: the run has ended"; break }
        let at = (((date now) - $started) / 1sec)
        let threads = (threads-of $pid)
        ({ at: $at, threads: $threads } | to nuon) + (char nl) | save --raw --append $file
        let previous = $last
        if $previous != null {
            let seconds = ($at - $previous.at)
            let rates = ($threads | each {|t|
                let before = ($previous.threads | where id == $t.id | get -o 0.cpu | default $t.cpu)
                { name: $t.name, rate: (($t.cpu - $before) / $seconds) }
            } | where rate >= 0.01 | sort-by rate --reverse)
            print $"($at | math round)s  ($rates | each {|r| $'($r.name) ($r.rate | math round -p 2)' } | str join '  ')"
        }
        $last = { at: $at, threads: $threads }
        sleep 1sec
    }
}

# Report on what `watch` recorded, as one NUON record to paste: the run
# as recorded, the stretch reported on (the first `--skip` seconds
# dropped as the load), and per thread the steady CPU seconds a second
# over that stretch and the peak second, with the process total;
# threads under 0.005 a second are left out. On macOS a thread is its
# row, and QEMU's worker threads come and go, so a row can change
# identity between samples: a row whose second-by-second rate is
# impossible for one thread, negative or past one, is reported with
# `stable: false` and no peak, its steady figure a mix.
def "main watched" [ws: path, --skip: float = 5.0] {
    let file = (watch-file $ws)
    if not ($file | path exists) { error make {msg: $"nothing recorded at ($file); run `just watch` during a run first"} }
    let lines = (open --raw $file | decode | lines | where {|l| ($l | str trim) != "" })
    let header = ($lines | first | from nuon)
    let samples = ($lines | skip 1 | each {|l| $l | from nuon } | where at >= $skip)
    if ($samples | length) < 2 { error make {msg: $"only ($samples | length) samples after the first ($skip) seconds; watch longer or lower --skip"} }
    let first = ($samples | first)
    let last = ($samples | last)
    let seconds = ($last.at - $first.at)
    let threads = ($last.threads | get id | each {|id|
        let series = ($samples | each {|s|
            let t = ($s.threads | where id == $id | get -o 0)
            if $t == null { null } else { { at: $s.at, cpu: $t.cpu, name: $t.name } }
        } | compact)
        if ($series | length) < 2 { null } else {
            let steady = ((($series | last).cpu - ($series | first).cpu) / (($series | last).at - ($series | first).at))
            let rates = ($series | window 2 | each {|w| ($w.1.cpu - $w.0.cpu) / ($w.1.at - $w.0.at) })
            let stable = (not ($rates | any {|r| $r < -0.001 or $r > 1.05 }))
            { name: ($series | last).name, id: $id, steady: ($steady | math round -p 3), peak: (if $stable { $rates | math max | math round -p 3 } else { null }), stable: $stable }
        }
    } | compact | where steady >= 0.005 | sort-by steady --reverse)
    let report = {
        run: $header.run,
        skipped: $skip,
        seconds: ($seconds | math round -p 1),
        samples: ($samples | length),
        process: (if ($threads | is-empty) { 0.0 } else { $threads | get steady | math sum | math round -p 3 }),
        threads: $threads,
    }
    print ($report | to nuon --indent 2)
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

# The QEMU line that runs a program, built first: the full virtio device
# set, the program's own disk when it has one else the blank image that
# has always been there, the debug channel to a file when DEBUG is set,
# the API's port when `api` asks, the window given (null for the one a
# run would open), the UART where `serial` says (`stdio` or `none`), and
# no monitor. The ports' files sit beside the build output, named in the
# README.
def run-line [dir: path, names: list<string>, api: bool, window: oneof<string, nothing>, serial: string, kbm: bool, pad: bool]: nothing -> record<args: list<string>, window: string, context: record> {
    let ready = (prepared $dir $names)
    let c = $ready.context
    let assets = (assets-image $c)
    let disk = (if $assets == "" {
        let blank = ($c.target | path join "disk.img")
        if not ($blank | path exists) { ^truncate -s 64M $blank }
        $blank
    } else { $assets })
    let disk_serial = (if $assets == "" { "disk0" } else { disk-serial $c.manifest.name })
    let shown = (if $window == null { display $c.manifest } else { $window })
    let ports = (ports $c.symbols $c.out $api)
    let inputs = (if $kbm { $input_devices } else { [] })
    let gamepad = (if $pad { gamepad-args $c.workspace } else { [] })
    let args = ((machine-args) ++ (name-args $c.manifest.name) ++ $memory ++ $display_device ++ $inputs ++ $gamepad ++ $devices ++ (disk-args $disk $disk_serial) ++ $ports.args ++ [
        "-bios" "none" "-kernel" $ready.kernel
        "-device" $"loader,file=($ready.image),addr=($program_base),force-raw=on"
        "-display" $shown "-serial" $serial "-monitor" "none"
    ])
    let count = (transports $args)
    if $count > $transport_limit {
        error make {msg: $"the machine line carries ($count) virtio transports and virt has ($transport_limit): drop --api or --set debug, which share one, or run with --no-kbm, which frees two"}
    }
    { args: $args, window: $shown, context: $c }
}

# The virtio transports a QEMU line uses: every `-device` of a
# virtio-*-device, which is how a device rides virt's mmio transports;
# a port on the serial device's own bus, and the loader, ride none.
def transports [args: list<string>]: nothing -> int {
    $args | window 2 | where {|w| $w.0 == "-device" and ($w.1 =~ '^virtio-.*-device') } | length
}

# The gamepad on the line, when there is one: JAB_PAD names its evdev
# path outright; else on Linux, with a workspace to build it in,
# jabdisco finds the expected pad and its path, and nothing goes on
# the line when it finds none or the host has no path to give.
def gamepad-args [ws: oneof<string, nothing>]: nothing -> list<string> {
    let forced = ($env.JAB_PAD? | default "")
    let path = (if $forced != "" { $forced } else if $nu.os-info.name != "linux" or $ws == null { "" } else {
        let disco = (disco-build $ws)
        let found = (^$disco | complete)
        if $found.exit_code != 0 { error make {msg: $"jabdisco failed:\n($found.stderr)"} }
        let pad = ($found.stdout | from nuon | get -o gamepad)
        if $pad == null { "" } else { $pad | get -o path | default "" }
    })
    if $path == "" { [] } else { ["-device" $"virtio-input-host-device,evdev=($path)"] }
}

# The jabdisco binary, built with cargo from the disco workspace beside
# the jab workspace into that workspace's own target/ on first use and
# whenever it changes, so a `cargo build --release` there is the same
# build: its path.
def disco-build [ws: path]: nothing -> string {
    let disco = ($ws | path dirname | path join "disco")
    let manifest = ($disco | path join "Cargo.toml")
    if not ($manifest | path exists) { error make {msg: $"no disco workspace beside this one at ($disco); JAB_PAD names a pad's evdev path outright, and --no-pad leaves the pad off"} }
    let built = (^cargo build --release --quiet --manifest-path $manifest -p jabdisco_cli | complete)
    if $built.exit_code != 0 { error make {msg: $"building jabdisco failed:\n($built.stderr)"} }
    $disco | path join "target" "release" "jabdisco"
}

# Run a program with the console window, the UART on stdio; QEMU's exit
# code is the program's exit status. A run says nothing of its own.
def run-program [dir: path, names: list<string>, api: bool, kbm: bool, pad: bool]: nothing -> nothing {
    let line = (run-line $dir $names $api null "stdio" $kbm $pad)
    if ($line.window | str starts-with "vnc=") {
        print "no display server here, so this is a development run: the display is served over VNC on 127.0.0.1:5930; tunnel it with `ssh -N -L 5930:127.0.0.1:5930 <this host>` and view it with `vncviewer 127.0.0.1:5930`"
    }
    ^qemu-system-riscv64 ...$line.args
}

# A shim, one package of the workspace's shim/ workspace, built with
# cargo into .target/shim on first use and whenever it changes: the
# path of its shared library, to preload into QEMU.
def shim-build [ws: path, name: string]: nothing -> string {
    let manifest = ($ws | path join "shim" "Cargo.toml")
    let target = ($ws | path join ".target" "shim")
    let built = (^cargo build --release --quiet --manifest-path $manifest -p $name --target-dir $target | complete)
    if $built.exit_code != 0 { error make {msg: $"building the shim package ($name) failed:\n($built.stderr)"} }
    $target | path join "release" $"lib($name).so"
}

# Probe a program under a window. `sdl`: run it under SDL with OpenGL
# for `seconds` with the shim of probe/sdl_shim preloaded into QEMU,
# then report how its flips reached the window.
def probe [dir: path, kind: string, names: list<string>, seconds: int]: nothing -> nothing {
    match $kind {
        "sdl" => { probe-sdl $dir $names $seconds },
        _ => { error make {msg: $"no probe called ($kind); there is `sdl`"} },
    }
}

# The SDL probe: the shim built with cargo into the workspace's .target,
# the program run under `sdl,gl=on` with the UART off for `seconds`, the
# shim's log read back, and one NUON record printed. Linux only, since
# it preloads a library into QEMU. With no display server SDL runs its
# offscreen driver, which draws nothing but keeps every path the same.
def probe-sdl [dir: path, names: list<string>, seconds: int]: nothing -> nothing {
    if $nu.os-info.name != "linux" { error make {msg: "the sdl probe preloads a library into QEMU, which is Linux only"} }
    let ws = (workspace-dir $dir)
    if $ws == null { error make {msg: "the sdl probe needs the workspace above the program, which holds shim/crates/sdl"} }
    let shim = (shim-build $ws "jabshim_sdl")
    let line = (run-line $dir $names false "sdl,gl=on" "none" true false)
    let out = ($line.context.out | path join "probe")
    mkdir $out
    let log = ($out | path join "sdl.log")
    if ($log | path exists) { rm $log }
    let server = (($env.DISPLAY? | default "") != "") or (($env.WAYLAND_DISPLAY? | default "") != "")
    let driver = (if $server { "" } else { "offscreen" })
    let preload = { LD_PRELOAD: $shim, SDL_SHIM_LOG: $log }
    let extra = (if $driver == "" { $preload } else { $preload | insert SDL_VIDEODRIVER $driver })
    let run = (with-env $extra { ^timeout --signal=TERM ($seconds | into string) qemu-system-riscv64 ...$line.args | complete })
    if not ($log | path exists) { error make {msg: $"QEMU wrote no shim log; its stderr:\n($run.stderr)"} }
    let qemu = (^qemu-system-riscv64 --version | complete | get stdout | lines | get -o 0 | default "")
    let report = (sdl-report $log)
    let record = ({
        run: {
            program: $line.context.manifest.name,
            os: $nu.os-info.name,
            qemu: $qemu,
            window: "sdl,gl=on",
            driver: (if $driver == "" { "the host's" } else { $driver }),
            symbols: $line.context.symbols,
            seconds: $seconds,
            qemu_said: ($run.stderr | lines | where {|l| not ($l | str contains "terminating on signal") } | first 3),
        },
    } | merge $report)
    print ($record | to nuon --indent 2)
}

# The report on a shim log: how the flips reached the window. A
# make_current followed by a window-size call within 2 ms opens a drawn
# frame. Any other is an upload: one per rectangle flushed when it comes
# through the virtio-gpu device, which its callers name, and otherwise
# one of the console's own, which a timer makes now and then and which
# is no flip of the program's. Flush uploads within 5 ms of the previous
# belong to one flip. A drawn frame with a flush upload under 3 ms on
# each side sits inside a flip, which is the half-drawn tick to look
# for.
def sdl-report [log: path]: nothing -> record {
    let events = (open --raw $log | decode | lines | each {|l| $l | parse --regex '^(?P<ts>\d+\.\d+) (?P<name>\S+)(?P<rest>.*)$' | get -o 0 } | compact | each {|e| { ts: ($e.ts | into float), name: $e.name, callers: ($e.rest | str trim) } })
    if ($events | is-empty) { error make {msg: "the shim log is empty; the window made no SDL calls"} }
    let t0 = ($events | first | get ts)
    let kinds = ($events | enumerate | each {|e|
        if $e.item.name != "make_current" { { ts: $e.item.ts, kind: $e.item.name, callers: "" } } else {
            let next = ($events | get -o ($e.index + 1))
            if $next != null and $next.name == "size" and (($next.ts - $e.item.ts) < 0.002) { { ts: $e.item.ts, kind: "render", callers: $e.item.callers } } else if ($e.item.callers | str contains "virtio-gpu") or ($e.item.callers | str contains "virtio_gpu") { { ts: $e.item.ts, kind: "upload", callers: $e.item.callers } } else { { ts: $e.item.ts, kind: "other_upload", callers: $e.item.callers } }
        }
    })
    let uploads = ($kinds | where kind == "upload")
    let others = ($kinds | where kind == "other_upload")
    let renders = ($kinds | where kind == "render" | get ts)
    let polls = ($kinds | where kind == "poll" | get ts)
    mut flips: list<record<start: float, end: float, size: int, gaps: list<float>>> = []
    for u in $uploads {
        if (($flips | length) > 0) and (($u.ts - ($flips | last | get end)) < 0.005) {
            let f = ($flips | last)
            $flips = (($flips | drop 1) ++ [{ start: $f.start, end: $u.ts, size: ($f.size + 1), gaps: ($f.gaps ++ [(($u.ts - $f.end) * 1000.0)]) }])
        } else {
            $flips = ($flips ++ [{ start: $u.ts, end: $u.ts, size: 1, gaps: [] }])
        }
    }
    let done = $flips
    mut last_upload = -1.0
    mut befores: list<float> = []
    for e in $kinds {
        if $e.kind == "upload" { $last_upload = $e.ts } else if $e.kind == "render" { $befores = ($befores ++ [(if $last_upload < 0.0 { 1.0 } else { $e.ts - $last_upload })]) }
    }
    mut next_upload = -1.0
    mut afters: list<float> = []
    for e in ($kinds | reverse) {
        if $e.kind == "upload" { $next_upload = $e.ts } else if $e.kind == "render" { $afters = ($afters ++ [(if $next_upload < 0.0 { 1.0 } else { $next_upload - $e.ts })]) }
    }
    let afters_in_order = ($afters | reverse)
    let befores_in_order = $befores
    let inside = ($renders | enumerate | each {|r|
        let before = (($befores_in_order | get $r.index) * 1000.0)
        let after = (($afters_in_order | get $r.index) * 1000.0)
        if $before < 3.0 and $after < 3.0 { { at: (($r.item - $t0) | math round -p 3), upload_before_ms: ($before | math round -p 2), upload_after_ms: ($after | math round -p 2) } } else { null }
    } | compact)
    let spans = ($done | where size > 1 | each {|f| ($f.end - $f.start) * 1000.0 })
    let gaps = ($done | get gaps | flatten)
    let cadence = ($done | window 2 | each {|w| ($w.1.start - $w.0.start) * 1000.0 })
    let intervals = ($renders | window 2 | each {|w| ($w.1 - $w.0) * 1000.0 })
    let hist = {|values: list<float>| $values | each {|v| $v | math round -p 0 } | uniq --count | sort-by count --reverse | first 6 | each {|c| { ms: $c.value, count: $c.count } } }
    let stat = {|values: list<float>| if ($values | is-empty) { { median: 0.0, max: 0.0 } } else { { median: ($values | math median | math round -p 2), max: ($values | math max | math round -p 2) } } }
    {
        seconds_logged: ((($events | last | get ts) - $t0) | math round -p 1),
        flips: ($done | length),
        uploads_per_flip: ($done | get size | uniq --count | sort-by count --reverse | first 6 | each {|c| { uploads: $c.value, count: $c.count } }),
        flip_span_ms: (do $stat $spans),
        upload_gap_ms: (do $stat $gaps),
        flip_cadence_ms: (do $hist $cadence),
        renders: ($renders | length),
        render_interval_ms: (do $hist $intervals),
        renders_inside_flip: ($inside | length),
        inside_cases: ($inside | first 8),
        polls: ($polls | length),
        other_uploads: ($others | length),
        upload_callers: ($uploads | get callers | uniq --count | sort-by count --reverse | first 2 | each {|c| { callers: $c.value, count: $c.count } }),
        other_upload_callers: ($others | get callers | uniq --count | sort-by count --reverse | first 2 | each {|c| { callers: $c.value, count: $c.count } }),
        render_callers: ($kinds | where kind == "render" | get callers | uniq --count | sort-by count --reverse | first 2 | each {|c| { callers: $c.value, count: $c.count } }),
    }
}

# Build the kernel and every program of the workspace at `ws`; release
# unless --set says otherwise.
def "main workspace build" [ws: path, --set: string = ""] {
    workspace-build $ws (symbols $set)
}

# Test every program, a category, or one program, on a build with DEBUG
# set beside whatever --set names; prints each test's output and a
# summary, exits 1 if any fails. A test that drives the API asks
# `jab launch` for the port itself.
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
# release unless --set says otherwise, the API's port on the machine
# with --api; the keyboard and the tablet on by default and off with
# --no-kbm; the gamepad found on the host attached by default and left
# off with --no-pad.
def "main workspace run" [ws: path, category: string, name: string, --set: string = "", --api, --kbm, --no-kbm, --pad, --no-pad] {
    let names = (symbols $set)
    workspace-build $ws $names
    run-program ($ws | path join $category $name) $names $api (kbm-choice $kbm $no_kbm) (pad-choice $pad $no_pad)
}

# The keyboard and the tablet on the line: on unless --no-kbm, and
# never both flags of the pair.
def kbm-choice [kbm: bool, no_kbm: bool]: nothing -> bool {
    if $kbm and $no_kbm { error make {msg: "--kbm and --no-kbm together: one or the other"} }
    not $no_kbm
}

# The gamepad on the line: on unless --no-pad, and never both flags.
def pad-choice [pad: bool, no_pad: bool]: nothing -> bool {
    if $pad and $no_pad { error make {msg: "--pad and --no-pad together: one or the other"} }
    not $no_pad
}

# Build everything, then probe one program under a window for
# --seconds: `just probe sdl example walk`; release unless --set says
# otherwise. Prints one NUON record on how the program's flips reached
# the window.
def "main workspace probe" [ws: path, kind: string, category: string, name: string, --seconds: int = 12, --set: string = ""] {
    let names = (symbols $set)
    workspace-build $ws $names
    probe ($ws | path join $category $name) $kind $names $seconds
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
# unless --set says otherwise, the API's port on the machine with --api,
# the keyboard and the tablet off with --no-kbm, the gamepad off with
# --no-pad.
def "main run" [dir: path, --set: string = "", --api, --kbm, --no-kbm, --pad, --no-pad] {
    run-program $dir (symbols $set) $api (kbm-choice $kbm $no_kbm) (pad-choice $pad $no_pad)
}

# Build the program at `dir` and probe it under a window for --seconds;
# release unless --set says otherwise. `sdl` is the one probe.
def "main probe" [dir: path, kind: string, --seconds: int = 12, --set: string = ""] {
    probe $dir $kind (symbols $set) $seconds
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
    print "nu jab.nu <build|test|clean> <dir> [--kernel] [--set names]; nu jab.nu run <dir> [--set names] [--api] [--no-kbm] [--no-pad]; nu jab.nu probe <dir> sdl [--seconds N] [--set names]; nu jab.nu workspace <build|test|run> <ws> [category [name]] [--set names] [--api] [--no-kbm] [--no-pad]; nu jab.nu workspace probe <ws> sdl <category> <name> [--seconds N]; nu jab.nu watch <ws>; nu jab.nu watched <ws> [--skip N]"
}
