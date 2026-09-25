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
# workspace, else beside the kernel or program), and the manifests. A
# build is skipped when its output is newer than every input and the
# flags match the last build.

# The riscv64 binutils prefixes: the official toolchain's triple first,
# then the names distributions package the tools under.
const triples = [
    "riscv64-unknown-linux-gnu-" "riscv64-linux-gnu-"
    "riscv64-unknown-elf-" "riscv64-elf-"
]
const program_base = "0x80800000"
const machine = [
    "-machine" "virt" "-cpu" "rv64" "-accel" "tcg" "-smp" "4"
    "-global" "virtio-mmio.force-legacy=false"
]
# The process is named, and so are its threads (CPU 0/TCG and the
# rest), so a per-thread listing reads.
const name = ["-name" "jab,debug-threads=on"]
const display_device = ["-device" "virtio-gpu-device,xres=1920,yres=1080"]
const devices = [
    "-device" "virtio-keyboard-device"
    "-device" "virtio-tablet-device"
    "-device" "virtio-net-device,netdev=net0" "-netdev" "user,id=net0"
    "-device" "virtio-sound-device,audiodev=snd0" "-audiodev" "none,id=snd0"
    "-device" "virtio-rng-device"
]

# Run a program on the kernel under QEMU with no window, the UART to
# serial.log in `out`, for at most `seconds`. The status is what jab.exit
# gave, 1 on a program fault, 124 when the bound ended the run. With
# `capture`, the screen is taken into screen.ppm that long after the
# start and the run is then ended (status 0). QEMU's own complaints
# about the guest go to qemu.log; cpu_seconds is the QEMU process's CPU
# time over the run and wall_seconds the run's length.
export def launch [
    --kernel: path             # the kernel ELF
    --image: path              # the program's .jab
    --out: path                # where serial.log and the rest go
    --seconds: int = 10        # the bound
    --capture: duration = 0sec # when to take the screen and end the run; 0 never
]: nothing -> record<status: int, serial: string, screen: string, qemu_log: string, cpu_seconds: float, wall_seconds: float> {
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
    let args = ([
        "--signal=TERM" $"($seconds)" "qemu-system-riscv64"
    ] ++ $machine ++ $name ++ ["-m" "128M"] ++ $display_device ++ [
        "-bios" "none" "-kernel" ($kernel | path expand)
        "-device" $"loader,file=($image | path expand),addr=($program_base),force-raw=on"
        "-display" "none" "-monitor" $"pipe:($monitor)" "-serial" $"file:($log)"
        "-pidfile" $pidfile "-d" "guest_errors" "-D" $qemu_log
    ])
    let started = (date now)
    job spawn { ^timeout ...$args | complete | job send 0 }
    mut result: any = null
    mut cpu = 0.0
    mut captured = ($capture == 0sec)
    while $result == null {
        $result = (try { job recv --timeout 100ms } catch { null })
        let pid = (if ($pidfile | path exists) { open --raw $pidfile | str trim } else { "" })
        let sample = (if $pid == "" { null } else { cpu-seconds $pid })
        if $sample != null { $cpu = $sample }
        if (not $captured) and (((date now) - $started) >= $capture) {
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

# The kernel's or a program's context: manifest, workspace, toolchain,
# target, and output directory (the workspace-relative path under the
# target, or the name when standalone).
def context [dir: path, kind: string]: nothing -> record {
    let here = ($dir | path expand)
    let manifest_path = ($here | path join $"($kind).jab.toml")
    let manifest = (open $manifest_path)
    let workspace = (workspace-dir $here)
    let target = (if $workspace == null { $here | path join ".target" } else { $workspace | path join ".target" })
    let relative = (if $workspace == null { $manifest.name } else { $here | path relative-to $workspace })
    let tc = (toolchain $here $workspace)
    {
        here: $here,
        manifest: $manifest,
        manifest_path: $manifest_path,
        workspace: $workspace,
        toolchain: $tc,
        prefix: (tool-prefix $tc),
        target: $target,
        out: ($target | path join $relative),
    }
}

# The kernel ELF a program runs on: the workspace's, or JAB_KERNEL. Left
# untyped because it ends in an error, which the output check rejects.
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

def build-kernel [dir: path]: nothing -> nothing {
    let c = (context $dir "kernel")
    let m = $c.manifest
    let includes = ($m | get -o includes | default [])
    let include_flags = ($includes | each {|i| ["-I" $i] } | flatten)
    let debug = (if ($env.JAB_DEBUG? | default "") != "" { ["--defsym" "JAB_DEBUG=1"] } else { [] })
    let flags = (($include_flags ++ $debug ++ [$c.prefix]) | str join " ")
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
        ^$asm ...$include_flags ...$debug $f -o $obj
    }
    ^$ld -T $m.link -nostdlib ...(glob ($c.out | path join "*.o")) -o $elf
    ^$objdump -d $elf | save -f ($c.out | path join "jab.disas")
    $flags | save -f $stamp
}

def build-program [dir: path]: nothing -> nothing {
    let c = (context $dir "program")
    let m = $c.manifest
    let includes = ($m | get -o includes | default [])
    let include_flags = ($includes | each {|i| ["-I" $i] } | flatten)
    let flags = (($include_flags ++ [$c.prefix]) | str join " ")
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
    ^$asm ...$include_flags src/main.S -o $obj
    ^$ld -T $m.link -nostdlib $obj -o $elf
    ^$objcopy -O binary $elf $image
    $flags | save -f $stamp
}

# What a program's test or run needs, after building it.
def prepared [dir: path]: nothing -> record {
    build-program $dir
    let c = (context $dir "program")
    let kernel = (kernel-elf $c)
    if not ($kernel | path exists) { error make {msg: $"no kernel at ($kernel); build the kernel first"} }
    { context: $c, kernel: $kernel, image: ($c.out | path join $"($c.manifest.name).jab") }
}

# Build the kernel and every program of the workspace at `ws`.
def "main workspace build" [ws: path] {
    let m = (open ($ws | path join "workspace.jab.toml"))
    build-kernel ($ws | path join $m.kernel)
    for p in $m.programs { build-program ($ws | path join $p) }
}

# Test every program, a category, or one program; prints each test's
# output and a summary, exits 1 if any fails.
def "main workspace test" [ws: path, category: string = "", name: string = ""] {
    main workspace build $ws
    let m = (open ($ws | path join "workspace.jab.toml"))
    let selected = ($m.programs | where {|p| ($category == "" or ($p | str starts-with $"($category)/")) and ($name == "" or ($p | path basename) == $name) })
    if ($selected | is-empty) { error make {msg: $"no program matches ($category) ($name)"} }
    let results = ($selected | each {|p|
        let ready = (prepared ($ws | path join $p))
        let script = ($ready.context.here | path join "test" "test.nu")
        if not ($script | path exists) { error make {msg: $"($p) has no test/test.nu"} }
        let r = (^nu $script --kernel $ready.kernel --image $ready.image --out $ready.context.out | complete)
        print $"--- ($p)"
        print -n $r.stdout
        if $r.exit_code != 0 { print -n $r.stderr }
        { program: $p, passed: ($r.exit_code == 0) }
    })
    print ($results | table)
    if not ($results | all {|r| $r.passed }) { exit 1 }
}

# Build everything, then run one program with the console window.
def "main workspace run" [ws: path, category: string, name: string] {
    main workspace build $ws
    main run ($ws | path join $category $name)
}

# Build the kernel at `dir` (--kernel) or the program at `dir`.
def "main build" [dir: path, --kernel] {
    if $kernel { build-kernel $dir } else { build-program $dir }
}

# Build the program at `dir` and run its test/test.nu on the kernel.
def "main test" [dir: path] {
    let ready = (prepared $dir)
    let script = ($ready.context.here | path join "test" "test.nu")
    if not ($script | path exists) { error make {msg: $"($ready.context.manifest.name) has no test/test.nu"} }
    ^nu $script --kernel $ready.kernel --image $ready.image --out $ready.context.out
}

# Build the program at `dir` and run it with the console window and the
# full virtio device set, the UART on stdio; QEMU's exit code is the
# program's exit status.
def "main run" [dir: path] {
    let ready = (prepared $dir)
    let c = $ready.context
    let disk = ($c.target | path join "disk.img")
    if not ($disk | path exists) { ^truncate -s 64M $disk }
    let window = (display $c.manifest)
    if ($window | str starts-with "vnc=") {
        print "no display server here, so this is a development run: the display is served over VNC on 127.0.0.1:5930; tunnel it with `ssh -N -L 5930:127.0.0.1:5930 <this host>` and view it with `vncviewer 127.0.0.1:5930`"
    }
    let args = ($machine ++ $name ++ ["-m" "4G"] ++ $display_device ++ $devices ++ [
        "-drive" $"if=none,id=disk0,file=($disk),format=raw" "-device" "virtio-blk-device,drive=disk0"
        "-bios" "none" "-kernel" $ready.kernel
        "-device" $"loader,file=($ready.image),addr=($program_base),force-raw=on"
        "-display" $window "-serial" "stdio" "-monitor" "none"
    ])
    ^qemu-system-riscv64 ...$args
}

# Remove the kernel's (--kernel) or the program's build output.
def "main clean" [dir: path, --kernel] {
    let c = (context $dir (if $kernel { "kernel" } else { "program" }))
    if ($c.out | path exists) { rm -r $c.out }
}

def main [] {
    print "nu jab.nu <build|test|run|clean> <dir> [--kernel]; nu jab.nu workspace <build|test|run> <ws> [category [name]]"
}
