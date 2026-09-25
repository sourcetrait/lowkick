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
is present and otherwise serves the console over VNC on 127.0.0.1:5930,
to tunnel and view; `JAB_DISPLAY` overrides with any `-display` value.
The toolchain is found by its install directory, the one holding
`bin/`: `RISCV_TOOLCHAIN`, else an `extern/riscv` link beside the kernel
or program, else `extern/riscv` beside this file, else the tools on
`PATH`.

A build is described by its symbols: `just build --set debug,data`
names them, in any case, and each reaches the assembler as a defined
symbol, `DEBUG` and `DATA`, for `.ifdef` to read in the kernel and in
your program alike. A build with `DEBUG` lands in `.target/debug` and
any other in `.target/release`, so the two coexist. `just test` always
sets `DEBUG`, so a program's own debug reporting is there for its test;
`just build` and `just run` are release unless asked otherwise, and a
release kernel carries no debug code and no debug text, which
`test/purity` checks.

With `DEBUG` the kernel's own lines leave the console: they go to a
debug channel, a virtio-serial port, which `just run ... --set debug`
writes to `debug.log` beside the program's build output and a test reads
back as `debug` from `jab launch`. The console UART carries only what
the program sends it, and the fault lines, in every build.
