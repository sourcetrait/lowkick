const DIR_SELF: directory = path self .

export def start [cfg: record, img: record]: nothing -> nothing {
    let share_dir = (qemu-system-aarch64 -L help | lines | first)
    let efi = match $nu.os-info.name {
        linux => ($share_dir | path join '../qemu-efi-aarch64/QEMU_EFI.fd' | path expand)
        macos => ($share_dir | path join 'edk2-aarch64-code.fd' | path expand)
        windows => (error make 'todo: windows')
        _ => (error make --unspanned 'unspported operating system')
    }
    
    let arch_args: list<string> = match [$nu.os-info.name, $nu.os-info.arch] {
        [linux aarch64] => [
            -machine virt,accel=kvm,highmem=on
            -cpu host
        ]
        [linux _] => [
            -machine virt,highmem=on
            -cpu max
        ]
        [macos aarch64] => [
            -machine virt,accel=hvf,highmem=on
            -cpu host
        ]
        [macos _] => [
            -machine virt,highmem=on
            -cpu max
        ]
        windows => { error make 'todo: windows' }
        _ => { error make --unspanned 'unspported operating system' }
    }

    let generic_args: list<string> = [
        -smp 4
        -m ($cfg.img.qemu.low.memory)G
        -drive if=pflash,format=raw,readonly=on,file=($efi)
        -drive if=pflash,format=raw,file=($cfg.dir.qemu.nvram | path join 'lowkick.fd')
        -drive if=virtio,format=qcow2,file=($cfg.dir.disk | path join 'lowkick.qcow2')
        -fw_cfg name=opt/com.coreos/config,file=($DIR_SELF | path join 'fcos.ign')
        -device virtio-gpu-pci
        -device qemu-xhci
        -device virtio-keyboard-pci
        -device virtio-tablet-pci
        -netdev user,id=net0,hostfwd=tcp::($cfg.img.qemu.ssh_port)-:22
        -device virtio-net-pci,netdev=net0
        -serial mon:stdio
    ]

    qemu-system-aarch64 ...[...$arch_args ...$generic_args]
}