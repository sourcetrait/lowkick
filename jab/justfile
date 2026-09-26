# LowKick Jab workspace. Every recipe hands off to the SDK's nushell tool,
# sdk/nu/jab.nu, which reads workspace.jab.toml and does all lookups and
# up-to-date checks in one process. Needs nushell, just, a riscv64 GNU
# toolchain, and qemu-system-riscv64; see the tool for how the toolchain
# and the target directory are found. `--set debug,stats` after a recipe
# names the build symbols; a build lands in .target/debug with DEBUG set
# and in .target/release otherwise. `--api` on a run puts the API's
# port on the machine; every build carries the API and runs either
# way.

set shell := ["nu", "-c"]
set windows-shell := ["nu", "-c"]
set quiet := true

here := justfile_directory()
jab := here / "sdk" / "nu" / "jab.nu"

default: build

# Build the kernel, then every program, skipping what is up to date;
# release, or `just build --set debug`
build *args:
    ^nu "{{jab}}" workspace build "{{here}}" {{args}}

# Build everything with DEBUG set, then run the integration test of every
# program, of one category (`just test example`), or of one program
# (`just test example helloworld`); prints each test's output and a
# summary, fails if any fails
test category="" name="" *args:
    ^nu "{{jab}}" workspace test "{{here}}" "{{category}}" "{{name}}" {{args}}

# Build everything, then run one program with the console window:
# `just run example helloworld`; release, or `just run example bounce
# --set debug`, which writes the kernel's debug channel to a file; `just
# run example wasd --api` with the API's port on the machine; the host's
# gamepad attached when one is found, or `--no-pad`; the keyboard and
# the tablet off with `--no-kbm`, which a pad run with a port needs
run category name *args:
    ^nu "{{jab}}" workspace run "{{here}}" "{{category}}" "{{name}}" {{args}}

# Build, then probe one program under a window and print one NUON
# record on how its flips reached it: `just probe sdl example walk`,
# twelve seconds or `--seconds N`; Linux, with cargo for the shim
probe kind category name *args:
    ^nu "{{jab}}" workspace probe "{{here}}" "{{kind}}" "{{category}}" "{{name}}" {{args}}

# Record the running Jab QEMU per thread, once a second, to
# .target/watch.nuonl: `just watch` from any shell while a program
# runs, until the run ends
watch:
    ^nu "{{jab}}" watch "{{here}}"

# Report on the last recording as one NUON record to paste: per thread
# the steady CPU seconds a second after the first five, or `--skip N`
watched *args:
    ^nu "{{jab}}" watched "{{here}}" {{args}}

clean:
    rm -rf "{{here}}/.target"
