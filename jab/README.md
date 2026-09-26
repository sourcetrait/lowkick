# LowKick Jab

An assembly ecosystem on QEMU: an assembly kernel that is itself the API,
running RISC-V programs a hobbyist drops in. Everything is virtio, and it
runs only under QEMU's `virt` machine.

- `workspace.jab.toml` the workspace: the kernel and the programs.
- `kernel/` the kernel: `kernel.jab.toml`, a `justfile`, sources under
  `src/`.
- `sdk/` what a program uses: `jab.inc`, the program link script, and
  `nu/jab.nu` for its test.
- `doc/syscalls.nuon` the system call table of record; `doc/lists.md`
  how every call that fills a buffer with records works.
- `example/<name>/`, `test/<name>/` programs by category, each with
  `program.jab.toml`, a `justfile`, `src/main.S`, and its integration
  test at `test/test.nu`.
- `shim/` the preload shims, a cargo workspace, a crate each under
  `crates/`: `sdl` for the probe and `evdev` for the pad tests.
- `../disco/` discovery, a cargo workspace beside this one: the
  library `jabdisco` and its binary `jabdisco`, which finds the
  gamepad a run attaches.
- `.target/release/` and `.target/debug/` build output, ignored;
  `extern/` local links, ignored.

Build and run with `just` and nushell: `just build`, `just test` (or
`just test example`, `just test example helloworld`), `just run example
helloworld` from here, or `just build` and `just test` inside the kernel
or a program. `just run` opens QEMU's own window when a display server
is present, SDL with OpenGL on Linux and Windows and Cocoa on macOS,
and otherwise serves the console over VNC on 127.0.0.1:5930, to tunnel
and view; `JAB_DISPLAY` overrides with any `-display` value.
The toolchain is found by its install directory, the one holding
`bin/`: `RISCV_TOOLCHAIN`, else an `extern/riscv` link beside the kernel
or program, else `extern/riscv` beside this file, else the tools on
`PATH`.

A build is described by its symbols: `just build --set debug,stats`
names them, in any case, and each reaches the assembler as a defined
symbol, `DEBUG` and `STATS`, for `.ifdef` to read in the kernel and in
your program alike. A build with `DEBUG` lands in `.target/debug` and
any other in `.target/release`, so the two coexist. `just test` always
sets `DEBUG`, so a program's own debug reporting is there for its test;
`just build` and `just run` are release unless asked otherwise, and a
release kernel carries no debug code and no debug text, which
`test/purity` checks.

The kernel reports what it was built with to a program through
`jab.kernel.flags`, a mask with `JAB_KERNEL_DEBUG` at bit 0, the same
fact at run time that `.ifdef DEBUG` is at build. A list of rectangles
flipped at once crosses to the host rectangle by rectangle and is
painted once, as the rectangle holding them all: a paint costs the
host's window a fixed price and a wait however small it is, and a
window drawn on a timer draws late by as long as the paints take, so
one a tick is what keeps a busy screen smooth under SDL and Cocoa
alike.

With `DEBUG` the kernel's own lines leave the console: they go to a
debug channel, a virtio-serial port, which `just run ... --set debug`
writes to `debug.log` beside the program's build output and a test reads
back as `debug` from `jab launch`. The console UART carries only what
the program sends it, and the fault lines, in every build.

The API is a second port, bytes both ways between a program and the
host through `jab.api.write`, `jab.api.read`, and `jab.api.await`.
Every kernel carries it and any build runs with or without it: `just
run example wasd --api` puts the port on the machine, and without the
flag the calls report that there is none. The host's end sits beside
the build output: `api.in`, a named pipe the host writes into, and
`api.out`, a file the program's bytes land in, which a test drives
through `jab launch --api --send`. `example/wasd` speaks a small binary
API over it, its records at the top of its `main.S`.

A run prints nothing of its own; what the kernel says in a debug build
is in `debug.log` beside the program's build output, and what a program
sends over the API is in `api.out` there. `just watch`, from any shell
while a program runs, records the QEMU process per thread once a
second to `.target/watch.nuonl` until the run ends, printing each
second's rates as it goes: on Linux the harts as `CPU 0/TCG` and on
and the main loop under the process name, which is where the host's
copy and paint of each flip lands; on macOS, whose threads carry no
names, the first row is the thread that draws the window and the rest
are numbered. `just watched` then prints one NUON record on the
recording, the run as it was (host, QEMU, window, the symbols the
kernel was built with) and per thread the steady CPU seconds a second
after the first five, which `--skip` changes, ready to paste. On
macOS a thread is its row, and QEMU's worker threads come and go, so
a row that changed identity during the recording is reported with
`stable: false` and no peak.

`just probe sdl example walk` looks at the window itself: it runs the
program under SDL with OpenGL for twelve seconds (`--seconds N`) with a
small library preloaded into QEMU, `shim/crates/sdl`, built with cargo
into `.target/shim`, which logs every SDL call the window makes with a
timestamp and its callers; then it prints one NUON record on how the
program's flips reached the window, ready to paste: the uploads per
flip and their spacing, the flip cadence, the drawn frames and their
interval, and any frame drawn inside a flip, which is a half-drawn
tick. Linux only, since it preloads into QEMU; with no display server
SDL runs its offscreen driver, drawing nothing along the same path.

A gamepad on the host reaches a program as a device: on Linux a run
finds it through `jabdisco`, built with cargo into `../disco/target`
on first use, and passes it through as `virtio-input-host-device`, QEMU holding
it for the run; `JAB_PAD=/dev/input/eventN` names one outright, and
`--no-pad` leaves it off. A program reads it with `jab.pad.read`, the
keys as a mask and every axis by its evdev code normalised to signed
16 bits, `jab.pad.input` for the events as evdev sends them, and
`jab.pad.axis` for an axis's own range and `jab.pad.name` for its name;
`example/pad` is wasd on the left stick, the dpad, and South, every
other button painting the sphere a colour of its own and naming itself
at the top of the screen for three seconds after it is let go, the
pad's own name there at startup, and the right stick painting the
sphere a colour made from its exact position while driving it by
thirds of its throw, through `jab.display.text`, which draws a string
anywhere in the framebuffer with the console's font at any scale. The
window is titled `Jab: <program>` after QEMU's own prefix, which every
front end hardcodes. The keyboard and the tablet come off
the line with `--no-kbm`. QEMU's `virt` has eight virtio transports and
the full line uses them all with a pad and the serial device, so a
pad run with `--set debug` or `--api` needs `--no-kbm`; the tool
refuses a ninth and says so. A test plays a gamepad with no device on
the host: `jab launch --pad <file>` takes a NUON table of timed
events, makes a fifo, and preloads `shim/crates/evdev` into QEMU to
answer the device's questions as an 8BitDo pad would, Linux only.

The CPU is RVA23, `-cpu rva23s64`, which QEMU carries from 9.2; on an
older QEMU the tool runs the generic `rv64`, which has what the kernel
needs, and `JAB_CPU` overrides either with any `-cpu` value.

The machine has 4 GiB of RAM, and a program owns nearly all of it: the
kernel keeps the first 2 MiB and the framebuffer the 8 MiB after, and
the window from there to the end of RAM is the program's, `sdk/jab.inc`
naming its base, its size, and the stack top at its end. A program's
assets ship on a romfs disk the tool builds from the directory its
manifest names, read with `jab.romfs.*`; a PNG among them, as GIMP 3
exports one, decodes in the kernel into a sprite with `jab.sprite.png`
and draws with `jab.sprite.draw`, which `example/logo` shows.
