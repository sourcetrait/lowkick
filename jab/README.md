# LowKick Jab

An assembly ecosystem on QEMU: an assembly kernel that is itself the API,
running RISC-V programs a hobbyist drops in. Everything is virtio, and it
runs only under QEMU's `virt` machine.

- `kernel/` the kernel, GNU assembler sources.
- `sdk/` what a program includes: `jab.inc` and the program link script.
- `doc/syscalls.nuon` the system call table of record.
- `prog/test/<name>/` test programs, one directory each.
- `target/` build output, ignored.

Build and run with `just` (see the `justfile`): `just kernel`,
`just prog helloworld`, `just test helloworld`, `just run helloworld`.
