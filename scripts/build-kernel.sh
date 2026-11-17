#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/config/build.conf"

: "${DISTRO:=$HOME/distro}"
SOURCES="$DISTRO/sources"
BUILD="$DISTRO/build"
TOOLS="$DISTRO/tools"
SYSROOT="$DISTRO/sysroot"

TARGET="${TARGET:-x86_64-unknown-linux-gnu}"
JOBS="${JOBS:-$(nproc)}"
LINUX_VERSION="7.3.4"

export PATH="$TOOLS/bin:$PATH"
export LC_ALL=C

get_source() {
    local archive="$SOURCES/$1"
    if [[ ! -f "$archive" ]]; then
        echo "Missing archive: $archive" >&2
        exit 1
    fi
    local dir
    dir="$(basename "$archive" | sed 's/\.tar\..*$//')"
    if [[ ! -d "$SOURCES/$dir" ]]; then
        tar -xf "$archive" -C "$SOURCES"
    fi
    echo "$SOURCES/$dir"
}

LINUX="$(get_source "linux-$LINUX_VERSION.tar.xz")"
cd "$LINUX"

make mrproper
make ARCH=x86_64 defconfig
make -j"$JOBS" ARCH=x86_64 CROSS_COMPILE="$TARGET-" bzImage modules

mkdir -p "$SYSROOT/boot"
cp arch/x86/boot/bzImage "$SYSROOT/boot/vmlinuz-$LINUX_VERSION"
cp System.map "$SYSROOT/boot/System.map-$LINUX_VERSION"
cp .config "$SYSROOT/boot/config-$LINUX_VERSION"

make ARCH=x86_64 CROSS_COMPILE="$TARGET-" INSTALL_MOD_PATH="$SYSROOT" modules_install
