#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/build.conf"

: "${DISTRO:=$HOME/distro}"
SYSROOT="${SYSROOT:-$DISTRO/sysroot}"
IMAGES="${IMAGES:-$DISTRO/images}"
ROOTFS_IMAGE="${ROOTFS_IMAGE:-$IMAGES/distro-rootfs.ext4}"
INITRAMFS="${INITRAMFS:-$IMAGES/initramfs.cpio.gz}"
MEMORY="${MEMORY:-1024}"

QEMU="$(command -v qemu-system-x86_64 || true)"
if [[ -z "$QEMU" ]]; then
    echo "Missing qemu-system-x86_64" >&2
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

if [[ ! -f "$ROOTFS_IMAGE" ]]; then
    echo "Missing rootfs image: $ROOTFS_IMAGE" >&2
    exit 1
fi

args=(
    -m "$MEMORY"
    -machine accel=kvm:tcg
    -kernel "$KERNEL"
    -append "root=/dev/vda rw console=ttyS0"
    -drive "file=$ROOTFS_IMAGE,format=raw,if=virtio"
    -net none
    -nographic
)

if [[ -f "$INITRAMFS" ]]; then
    args+=( -initrd "$INITRAMFS" )
fi

exec "$QEMU" "${args[@]}"
