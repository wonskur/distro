#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/build.conf"

: "${DISTRO:=$HOME/distro}"
SYSROOT="${SYSROOT:-$DISTRO/sysroot}"
ROOTFS="${ROOTFS:-$DISTRO/rootfs}"
ROOT_DEV="${ROOT_DEV:-/dev/vda}"

if [[ ! -d "$SYSROOT" ]]; then
    echo "Missing sysroot: $SYSROOT" >&2
    exit 1
fi

if [[ -z "$ROOTFS" || "$ROOTFS" == "/" ]]; then
    echo "Invalid rootfs path: $ROOTFS" >&2
    exit 1
fi

rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
cp -a "$SYSROOT/." "$ROOTFS/"

mkdir -p "$ROOTFS"/{boot,dev,etc,home,mnt,opt,proc,root,run,srv,sys,tmp,var,usr/{bin,sbin,lib}}

if [[ ! -e "$ROOTFS/bin" && ! -L "$ROOTFS/bin" ]]; then
    ln -sfn usr/bin "$ROOTFS/bin"
fi
if [[ ! -e "$ROOTFS/sbin" && ! -L "$ROOTFS/sbin" ]]; then
    ln -sfn usr/sbin "$ROOTFS/sbin"
fi
if [[ ! -e "$ROOTFS/lib" && ! -L "$ROOTFS/lib" ]]; then
    ln -sfn usr/lib "$ROOTFS/lib"
fi
if [[ ! -e "$ROOTFS/lib64" && ! -L "$ROOTFS/lib64" ]]; then
    ln -sfn usr/lib "$ROOTFS/lib64"
fi

chmod 1777 "$ROOTFS/tmp"
chmod 755 "$ROOTFS/root"

mknod -m 600 "$ROOTFS/dev/console" c 5 1 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/zero" c 1 5 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/random" c 1 8 2>/dev/null || true
mknod -m 666 "$ROOTFS/dev/urandom" c 1 9 2>/dev/null || true

cat > "$ROOTFS/etc/os-release" <<'EOF'
NAME="distro"
PRETTY_NAME="distro"
ID=distro
EOF

cat > "$ROOTFS/etc/issue" <<'EOF'
distro \r (\l)
EOF

cat > "$ROOTFS/etc/motd" <<'EOF'
Welcome to distro.
EOF

if [[ -f "$ROOTFS/etc/fstab" ]] && ! grep -qE "^[^#].*[[:space:]]/[[:space:]]" "$ROOTFS/etc/fstab"; then
    printf '%s / ext4 defaults 0 1\n' "$ROOT_DEV" >> "$ROOTFS/etc/fstab"
fi

printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$ROOTFS/etc/resolv.conf"

if [[ -x "$ROOTFS/bin/bash" ]]; then
    ln -sfn bash "$ROOTFS/bin/sh"
fi

cat > "$ROOTFS/sbin/init" <<'EOF'
#!/bin/sh

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TERM=linux

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true

exec </dev/console >/dev/console 2>&1

hostname distro 2>/dev/null || true
echo
echo "distro"
echo

if [ -x /bin/bash ]; then
    exec /bin/bash -l
fi

exec /bin/sh
EOF
chmod 755 "$ROOTFS/sbin/init"

chown -R 0:0 "$ROOTFS"

echo "Root filesystem ready: $ROOTFS"
