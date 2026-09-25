# LowKick Jab

An assembly ecosystem on QEMU: an assembly kernel that is itself the API,
running RISC-V programs a hobbyist drops in. Everything is virtio, and it
runs only under QEMU's `virt` machine.

- `workspace.jab.toml` the workspace: the kernel and the programs.
- `kernel/` the kernel: `kernel.jab.toml`, a `justfile`, sources under
  `src/`.
- `sdk/` what a program uses: `jab.inc`, the program link script, and
  `nu/jab.nu` for its test.
- `doc/syscalls.nuon` the system call table of record.
- `example/<name>/`, `test/<name>/` programs by category, each with
  `program.jab.toml`, a `justfile`, `src/main.S`, and its integration
  test at `test/test.nu`.
- `.target/` build output, ignored; `extern/` local links, ignored.

Build and run with `just` and nushell: `just build`, `just test` (or
`just test example`, `just test example helloworld`), `just run example
helloworld` from here, or `just build` and `just test` inside the kernel
or a program. The toolchain is found by its install directory, the one
holding `bin/`: `RISCV_TOOLCHAIN`, else an `extern/riscv` link beside the
kernel or program, else `extern/riscv` beside this file, else the tools
on `PATH`.
