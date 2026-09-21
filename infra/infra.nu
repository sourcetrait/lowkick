#!/usr/bin/env nu

const DIR_SELF: directory = path self .

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

def init []: nothing -> record {
    let cfg = do {||
        let config_file = xdg config | path join 'lowkick' 'config.toml'
        if ($config_file | path exists) {
            open $config_file
        } else {
            open ($DIR_SELF | path join 'cfg' 'default.toml')  
        }
    }

    $cfg
}

export def 'main build qemu' [
    namepath: string
]: nothing -> nothing {
    let cfg = init
    let infr = infr get qemu $namepath
    print $infr
}


export def main []: nothing -> nothing { help main }
