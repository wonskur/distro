#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/build.conf"

: "${DISTRO:=$HOME/distro}"
ROOTFS="${ROOTFS:-$DISTRO/rootfs}"
IMAGES="${IMAGES:-$DISTRO/images}"
IMAGE="${IMAGE:-$IMAGES/distro-rootfs.ext4}"
ROOTFS_SIZE="${ROOTFS_SIZE:-}"

if [[ ! -d "$ROOTFS" ]]; then
    echo "Missing rootfs: $ROOTFS" >&2
    exit 1
fi

MKE2FS="$(command -v mke2fs || true)"
if [[ -z "$MKE2FS" && -x /usr/sbin/mke2fs ]]; then
    MKE2FS=/usr/sbin/mke2fs
fi
if [[ -z "$MKE2FS" ]]; then
    echo "Missing mke2fs" >&2
    exit 1
fi

mkdir -p "$IMAGES"

if [[ -z "$ROOTFS_SIZE" ]]; then
    size_mb="$(du -sm "$ROOTFS" | awk '{print $1}')"
    size_mb=$((size_mb + 128))
    if ((size_mb < 256)); then
        size_mb=256
    fi
    ROOTFS_SIZE="${size_mb}M"
fi

rm -f "$IMAGE"
truncate -s "$ROOTFS_SIZE" "$IMAGE"
"$MKE2FS" -q -t ext4 -F -L distro -d "$ROOTFS" "$IMAGE"

tar -C "$ROOTFS" -czf "$IMAGES/rootfs.tar.gz" .

ls -lh "$IMAGE" "$IMAGES/rootfs.tar.gz"
