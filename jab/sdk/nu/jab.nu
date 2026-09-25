# jab.nu: the Jab SDK's nushell module, for a program's integration test.
# `use` it by path; `jab launch` then runs a program on the kernel headless
# and hands back the exit status and the UART text.

# Run a program on the kernel under QEMU with no window, the UART to
# serial.log in `out`, for at most `seconds`. The status is what jab.exit
# gave, 1 on a program fault, 124 when the bound ended the run.
export def launch [
    --kernel: path      # the kernel ELF, .target/kernel/jab.elf
    --image: path       # the program's .jab
    --out: path         # where serial.log goes
    --seconds: int = 10 # the bound
]: nothing -> record<status: int, serial: string> {
    let log = ($out | path expand | path join "serial.log")
    let args = [
        "--signal=TERM" $"($seconds)" "qemu-system-riscv64"
        "-machine" "virt" "-cpu" "rv64" "-accel" "tcg" "-smp" "4" "-m" "128M"
        "-global" "virtio-mmio.force-legacy=false"
        "-bios" "none" "-kernel" ($kernel | path expand)
        "-device" $"loader,file=($image | path expand),addr=0x80800000,force-raw=on"
        "-display" "none" "-monitor" "none" "-serial" $"file:($log)"
    ]
    let r = (^timeout ...$args | complete)
    {
        status: $r.exit_code,
        serial: (if ($log | path exists) { open --raw $log | decode } else { "" }),
    }
}
