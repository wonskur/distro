#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/build.conf"

: "${DISTRO:=$HOME/distro}"
SYSROOT="${SYSROOT:-$DISTRO/sysroot}"
ROOTFS="${ROOTFS:-$DISTRO/rootfs}"
IMAGES="${IMAGES:-$DISTRO/images}"
BUILD="${BUILD:-$DISTRO/build}"
ISO="${ISO:-$IMAGES/distro.iso}"

if [[ ! -d "$ROOTFS" ]]; then
    echo "Missing rootfs: $ROOTFS" >&2
    exit 1
fi

KERNEL=""
for candidate in "$SYSROOT"/boot/vmlinuz-*; do
    if [[ -f "$candidate" ]]; then
        KERNEL="$candidate"
        break
    fi
done

if [[ -z "$KERNEL" ]]; then
    echo "Missing kernel in $SYSROOT/boot" >&2
    exit 1
fi

if ! command -v grub-mkrescue >/dev/null 2>&1; then
    echo "Missing grub-mkrescue" >&2
    exit 1
fi

if ! command -v xorriso >/dev/null 2>&1; then
    echo "Missing xorriso" >&2
    exit 1
fi

work="$BUILD/iso"
rm -rf "$work"
mkdir -p "$work/boot/grub" "$IMAGES"

cp "$KERNEL" "$work/boot/vmlinuz"

( cd "$ROOTFS" && find . -print0 | cpio --null -o --format=newc 2>/dev/null ) \
    | gzip -9n > "$work/boot/rootfs.cpio.gz"

cat > "$work/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=3

menuentry "distro" {
    linux /boot/vmlinuz rdinit=/sbin/init console=ttyS0
    initrd /boot/rootfs.cpio.gz
}
EOF

rm -f "$ISO"
grub-mkrescue -o "$ISO" "$work" >/dev/null

ls -lh "$ISO"
