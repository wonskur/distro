#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/build.conf"

: "${DISTRO:=$HOME/distro}"
SYSROOT="${SYSROOT:-$DISTRO/sysroot}"
INITRAMFS="${INITRAMFS:-$DISTRO/initramfs}"
IMAGES="${IMAGES:-$DISTRO/images}"

if [[ ! -d "$SYSROOT" ]]; then
    echo "Missing sysroot: $SYSROOT" >&2
    exit 1
fi

rm -rf "$INITRAMFS"
mkdir -p "$INITRAMFS"/{bin,sbin,etc,proc,sys,dev,run,tmp,newroot,usr/lib}
ln -sfn usr/lib "$INITRAMFS/lib"
ln -sfn usr/lib "$INITRAMFS/lib64"
chmod 1777 "$INITRAMFS/tmp"
mkdir -p "$IMAGES"

mknod -m 600 "$INITRAMFS/dev/console" c 5 1 2>/dev/null || true
mknod -m 666 "$INITRAMFS/dev/null" c 1 3 2>/dev/null || true
mknod -m 666 "$INITRAMFS/dev/zero" c 1 5 2>/dev/null || true

cat > "$INITRAMFS/etc/os-release" <<'EOF'
NAME="distro"
PRETTY_NAME="distro"
ID=distro
EOF

find_binary() {
    find -L "$SYSROOT/usr/bin" "$SYSROOT/usr/sbin" -maxdepth 1 -name "$1" -type f -print -quit 2>/dev/null || true
}

find_lib() {
    find -L "$SYSROOT/usr/lib" "$SYSROOT/usr/lib64" -maxdepth 2 -name "$1" -type f -print -quit 2>/dev/null || true
}

declare -A COPIED_LIBS=()

copy_lib() {
    local name="$1"
    local src="${2:-}"
    local dep rel

    if [[ -n "${COPIED_LIBS[$name]:-}" ]]; then
        return 0
    fi
    COPIED_LIBS["$name"]=1

    if [[ -z "$src" ]]; then
        src="$(find_lib "$name")"
    fi
    if [[ -z "$src" ]]; then
        return 0
    fi

    rel="${src#"$SYSROOT"}"
    install -D -m 0755 "$src" "$INITRAMFS$rel"

    while IFS= read -r dep; do
        if [[ -n "$dep" ]]; then
            copy_lib "$dep" ""
        fi
    done < <(readelf -d "$src" 2>/dev/null | awk -F'[][]' '/NEEDED/ {print $2}')
}

copy_absolute() {
    local path="$1"
    local src

    src="$SYSROOT$path"
    if [[ ! -e "$src" ]]; then
        src="$(find_lib "$(basename "$path")")"
    fi
    if [[ -z "$src" || ! -e "$src" ]]; then
        return 0
    fi

    install -D -m 0755 "$src" "$INITRAMFS$path"
}

copy_binary() {
    local src="$1"
    local dest="$2"
    local interpreter dep

    if [[ -z "$src" || ! -f "$src" ]]; then
        return 1
    fi

    install -D -m 0755 "$src" "$INITRAMFS$dest"

    interpreter="$(readelf -l "$src" 2>/dev/null | sed -n 's/.*interpreter: \(.*\)]/\1/p' | head -n 1)"
    if [[ -n "$interpreter" ]]; then
        copy_absolute "$interpreter"
    fi

    while IFS= read -r dep; do
        if [[ -n "$dep" ]]; then
            copy_lib "$dep" ""
        fi
    done < <(readelf -d "$src" 2>/dev/null | awk -F'[][]' '/NEEDED/ {print $2}')
}

BASH_SRC="$(find_binary bash)"
MOUNT_SRC="$(find_binary mount)"
SWITCH_ROOT_SRC="$(find_binary switch_root)"

for tool in BASH_SRC MOUNT_SRC SWITCH_ROOT_SRC; do
    if [[ -z "${!tool}" ]]; then
        echo "Missing ${tool%_SRC} in $SYSROOT" >&2
        exit 1
    fi
done

copy_binary "$BASH_SRC" /bin/bash
copy_binary "$MOUNT_SRC" /bin/mount
copy_binary "$SWITCH_ROOT_SRC" /sbin/switch_root
ln -sfn bash "$INITRAMFS/bin/sh"

cat > "$INITRAMFS/init" <<'EOF'
#!/bin/sh

export PATH=/sbin:/bin:/usr/sbin:/usr/bin

mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t tmpfs tmpfs /run 2>/dev/null || true

exec </dev/console >/dev/console 2>&1

root=/dev/vda
fstype=ext4
read -r cmdline < /proc/cmdline

for arg in $cmdline; do
    case "$arg" in
        root=*) root="${arg#root=}" ;;
        rootfstype=*) fstype="${arg#rootfstype=}" ;;
    esac
done

if mount -t "$fstype" "$root" /newroot; then
    exec switch_root /newroot /sbin/init
fi

echo "Unable to mount $root, starting rescue shell."
exec /bin/sh
EOF
chmod 755 "$INITRAMFS/init"

chown -R 0:0 "$INITRAMFS"

( cd "$INITRAMFS" && find . -print0 | cpio --null -o --format=newc 2>/dev/null ) | gzip -9n > "$IMAGES/initramfs.cpio.gz"

ls -lh "$IMAGES/initramfs.cpio.gz"
