#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/build.conf"

: "${DISTRO:=$HOME/distro}"
SYSROOT="$DISTRO/sysroot"

mkdir -p "$SYSROOT"/{boot,dev,etc,home,mnt,opt,proc,root,run,srv,sys,tmp,usr/{bin,include,lib,sbin,share,src},var/{cache,local,lock,log,mail,opt,run,spool,tmp}}

ln -sfn usr/bin "$SYSROOT/bin"
ln -sfn usr/sbin "$SYSROOT/sbin"
ln -sfn usr/lib "$SYSROOT/lib"
ln -sfn usr/lib "$SYSROOT/lib64"
ln -sfn lib "$SYSROOT/usr/lib64"

chmod 1777 "$SYSROOT/tmp" "$SYSROOT/var/tmp"

cat > "$SYSROOT/etc/passwd" << 'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/bin/false
daemon:x:6:6:Daemon User:/dev/null:/bin/false
nobody:x:65534:65534:Nobody:/:/bin/false
EOF

cat > "$SYSROOT/etc/group" << 'EOF'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
usb:x:14:
cdrom:x:15:
adm:x:16:
wheel:x:17:
nogroup:x:65534:
EOF

cat > "$SYSROOT/etc/shadow" << 'EOF'
root:::0:99999:7:::
bin:!::0:99999:7:::
daemon:!::0:99999:7:::
nobody:!::0:99999:7:::
EOF

chmod 600 "$SYSROOT/etc/shadow"
chmod 644 "$SYSROOT/etc/passwd" "$SYSROOT/etc/group"

cat > "$SYSROOT/etc/fstab" << 'EOF'
proc /proc proc nosuid,noexec,nodev 0 0
sysfs /sys sysfs nosuid,noexec,nodev 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
tmpfs /run tmpfs defaults 0 0
devtmpfs /dev devtmpfs mode=0755,nosuid 0 0
EOF

cat > "$SYSROOT/etc/hosts" << 'EOF'
127.0.0.1 localhost distro
::1       localhost ip6-localhost ip6-loopback
EOF

echo "distro" > "$SYSROOT/etc/hostname"

cat > "$SYSROOT/etc/os-release" << 'EOF'
NAME="distro"
PRETTY_NAME="distro GNU/Linux"
ID=distro
EOF
