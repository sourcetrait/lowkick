#!/usr/bin/env sh
set -euo pipefail

alpine_version() {
    cut -d. -f1,2 /etc/alpine-release
}

start_network() {
    ip link set eth0 up
    udhcpc -i eth0 -n -q
}

install_packages() {
    echo "https://dl-cdn.alpinelinux.org/alpine/v$(alpine_version)/main" >> /etc/apk/repositories
    apk update
    apk add bash doas libdrm-tests openssh
}

setup_sshd() {
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

setup_groups() {
    addgroup -S asusr
    addgroup -S sshusr
}

permit_asusr {
    echo 'permit nopass :asusr' > /etc/doas.d/asusr.conf
    chmod 0400 /etc/doas.d/asusr.conf
}

restart_sshd() {
    rc-update add sshd
    rc-service sshd restart
}

setup_user_admin() {
    local user
    user="${1:?username for admin}"

    setup_user "$user"
    addgroup "$user" asusr
    echo "${user}:${user}" | chpasswd
}

setup_user() {
    local user pubkey
    user="${1:?username for user}"
    pubkey="${2:?pubkey for user}"

    adduser -D "$user"
    addgroup "$user" sshusr
    install -d -m 700 -o "$user" -g "$user" "/home/$user/.ssh"
    install -m 600 "$user" -g "$user" "$pubkey" "/home/$user/.ssh/authorized_keys"
}

finalize() {
    lbu commit -d
}

start_network
install_packages
setup_groups
permit_asusr
setup_user kick
setup_user_admin kickadm
setup_sshd
finalize
