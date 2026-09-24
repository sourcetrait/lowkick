#!/usr/bin/env sh
set -euo pipefail

function alpine_version {
    cut -d. -f1,2 /etc/alpine-release
}

function start_network {
    ip link set eth0 up
    udhcpc -i eth0 -n -q
}

function install_packages {
    echo "https://dl-cdn.alpinelinux.org/alpine/v$(alpine_version)/main" >> /etc/apk/repositories
    apk update
    apk add bash doas libdrm-tests openssh
}

function setup_sshd {
    cat <<EOF > /etc/ssh/sshd_config
AllowTcpForwarding no
AllowAgentForwarding no
X11Forwarding no
PermitTunnel no

KbdInteractiveAuthentication no
PasswordAuthentication no
KerberosAuthentication no
GSSAPIAuthentication no
GatewayPorts no
UsePAM no
PermitRootLogin no

Subsystem sftp internal-sftp

AuthorizedKeysFile .ssh/authorized_keys

MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2

PubkeyAuthentication yes
AuthenticationMethods publickey
AllowGroups sshusr
EOF

    restart_sshd
}

function setup_groups {
    addgroup -S asusr
    addgroup -S sshusr
}

function permit_asusr {
    echo 'permit persist :asusr' > /etc/doas.d/asusr.confg
}

function restart_sshd {
    rc-service sshd restart
}

function setup_user_admin {
    local user
    user="${1:?username for admin}"

    setup_user "$user"
    addgroup "$user" sudousr
    echo "${user}:${user}" | chpasswd
}

function setup_user {
    local user pubkey
    user="${1:?username for user}"
    pubkey="${1:?pubkey for user}"

    adduser -D "$user"
    addgroup "$user" sshusr
    install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh"
    install -m 600 "$user" -g "$user" "$pubkey" "/home/$user/.ssh/authorized_keys"
}

start_network
install_packages
setup_groups
permit_asusr
setup_user kick
setup_user_admin kickadm
setup_sshd
