#!/usr/bin/env nu

const DIR_SELF: directory = path self .
const LOG: string = "(ansi blue)[infra](ansi reset)"

const INFR: table<kind: string, namepath: path> = [
    [kind namepath];
    [qemu 'lowkick']
] 

def 'infr get' [kind: string, namepath: string]: nothing -> record {
    $INFR | where kind == $kind and namepath == $namepath | first
}


def 'xdg config' []: nothing -> directory {
    $env | get -o XDG_CONFIG_HOME| default -e ($nu.home-dir | path join '.config')
}

def 'xdg data' []: nothing -> directory {
    $env | get -o XDG_DATA_HOME | default -e ($nu.home-dir | path join '.local/share')
}

def init []: nothing -> record {
    let data_dir = xdg data | path join 'lowkick' | path expand
    let cfg = {
        dir: {
            data: $data_dir
            qemu: {
                attend: ($data_dir | path join 'qemu' 'attend')
                disk: ($data_dir | path join 'qemu' 'disk')
                iso: ($data_dir | path join 'qemu' 'iso')
                nvram: ($data_dir | path join 'qemu' 'nvram')
                image: ($data_dir | path join 'qemu' 'image')
            }
            fcos: {
                latest: ($data_dir | path join 'qemu' 'image' 'fcos' 'latest')
            }
        }
        fcos: {
            image: ($data_dir | path join 'qemu' 'image' 'fcos.qcow2')
            meta_url: 'https://builds.coreos.fedoraproject.org/streams/stable.json'
        }
        img: {
            qemu: {
                low: {
                    cores: 4
                    memory: 8
                }
            }
        }
    }

    if not ($cfg.dir.data | path exists) {
        mkdir $cfg.dir.data
        mkdir $cfg.dir.qemu.attend
        mkdir $cfg.dir.qemu.disk
        mkdir $cfg.dir.qemu.image
        mkdir $cfg.dir.qemu.iso
        mkdir $cfg.dir.qemu.nvram
        mkdir $cfg.dir.fcos.latest
    }

    $cfg
}

def update_fcos [cfg: record]: nothing -> nothing {
    let url = http get $cfg.fcos.meta_url
    | get $.architectures.aarch64.artifacts.qemu.formats.'qcow2.xz'.disk.location
    
    let filename_xz = $url | path basename
    let filename  = $filename_xz | path split | last | str replace -r '\.xz$' ''
    if ($cfg.dir.fcos.latest | path join $filename | path exists) {
        return
    }

    cd $cfg.dir.fcos.latest
    print $"($LOG) Downloading latest Fedora CoreOS ..."
    http get $url | save $filename_xz
    print $"($LOG) Extracting latest Fedora CoreOS ..."
    xz -d $filename_xz
    
    for $file in (ls ('.' | path join '*.*' | into glob) | get name) {
        if $file != $filename and (($file | path type) == 'file') {
            rm $file
        }
    }
    
    cd $cfg.dir.qemu.image
    rm -f 'fcos.qcow2'
    ln -s ('fcos' | path join 'latest' $filename) 'fcos.qcow2'
    print $"($LOG) Updated to latest Fedora CoreOS image"
}

export def 'main build qemu' [
    namepath: string
]: nothing -> nothing {
    let cfg = init
    let infr = infr get qemu $namepath
    update_fcos $cfg
}


export def main []: nothing -> nothing { help main }
