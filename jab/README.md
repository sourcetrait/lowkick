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

One symbol the host sets on its own: `DISPLAY_FLUSH_SCALED`, on Linux
and Windows, where the window charges a flush of the screen by the
area it covers, and not on macOS, where every flush costs the same
whatever its size. It decides how the kernel shows a list of
rectangles, one flush each or one flush of the rectangle holding them
all, so that a busy screen is cheap under either window. The kernel
reports what it was built with to a program through `jab.kernel.flags`,
a mask of `JAB_KERNEL_DEBUG` and `JAB_KERNEL_DISPLAY_FLUSH_SCALED`;
`JAB_DISPLAY=cocoa just build` builds the other class anywhere, for
measuring.

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
after the first five, which `--skip` changes, ready to paste.

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
