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
export CONFIG_SITE=/dev/null

mkdir -p "$SOURCES" "$BUILD" "$TOOLS" "$SYSROOT"

BUILD_TRIPLET="$("$SOURCES/binutils-2.47/config.guess" 2>/dev/null || true)"

if [[ -z "$BUILD_TRIPLET" ]]; then
    BUILD_TRIPLET="$(gcc -dumpmachine)"
fi

get_source() {
    local name="$1"
    local archive="$SOURCES/$name"

    if [[ -d "$SOURCES/$name" ]]; then
        echo "$SOURCES/$name"
        return
    fi

    if [[ ! -f "$archive" ]]; then
        echo "Missing source archive: $archive" >&2
        exit 1
    fi

    tar -xf "$archive" -C "$SOURCES"
    echo "$SOURCES/$(basename "$archive" | sed 's/\.tar\..*$//')"
}

run_make() {
    make -j"$JOBS" "$@"
}

# Binutils Pass 1
BINUTILS="$(get_source binutils-2.47.tar.xz)"

mkdir -p "$BUILD/binutils-pass1"
cd "$BUILD/binutils-pass1"

"$BINUTILS/configure" \
    --prefix="$TOOLS" \
    --target="$TARGET" \
    --with-sysroot="$SYSROOT" \
    --disable-nls \
    --disable-werror \
    --enable-deterministic-archives

run_make
make install

# GCC Pass 1
GCC="$(get_source gcc-16.2.0.tar.xz)"

GMP="$(get_source gmp-6.3.0.tar.xz)"
MPFR="$(get_source mpfr-4.2.2.tar.xz)"
MPC="$(get_source mpc-1.4.1.tar.xz)"

ln -sfn "$GMP" "$GCC/gmp"
ln -sfn "$MPFR" "$GCC/mpfr"
ln -sfn "$MPC" "$GCC/mpc"

mkdir -p "$BUILD/gcc-pass1"
cd "$BUILD/gcc-pass1"

"$GCC/configure" \
    --build="$BUILD_TRIPLET" \
    --host="$BUILD_TRIPLET" \
    --target="$TARGET" \
    --prefix="$TOOLS" \
    --with-sysroot="$SYSROOT" \
    --with-newlib \
    --without-headers \
    --disable-nls \
    --disable-shared \
    --disable-multilib \
    --disable-threads \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libquadmath \
    --disable-libssp \
    --disable-libvtv \
    --disable-libstdcxx \
    --enable-languages=c

run_make all-gcc
run_make all-target-libgcc

make install-gcc
make install-target-libgcc

# Linux API Headers
LINUX="$(get_source "linux-$LINUX_VERSION.tar.xz")"

cd "$LINUX"

make mrproper
make ARCH=x86 headers

make ARCH=x86 \
    INSTALL_HDR_PATH="$SYSROOT/usr" \
    headers_install

# Glibc
GLIBC="$(get_source glibc-2.44.tar.xz)"

mkdir -p "$BUILD/glibc"
cd "$BUILD/glibc"

BUILD_CC=gcc \
CC="$TARGET-gcc" \
AR="$TARGET-ar" \
RANLIB="$TARGET-ranlib" \
"$GLIBC/configure" \
    --build="$BUILD_TRIPLET" \
    --host="$TARGET" \
    --prefix=/usr \
    --with-headers="$SYSROOT/usr/include" \
    --enable-kernel=4.14 \
    --disable-werror \
    --disable-nscd \
    libc_cv_slibdir=/usr/lib

run_make

make DESTDIR="$SYSROOT" install

# GCC Pass 2
mkdir -p "$BUILD/gcc-pass2"
cd "$BUILD/gcc-pass2"

"$GCC/configure" \
    --build="$BUILD_TRIPLET" \
    --host="$BUILD_TRIPLET" \
    --target="$TARGET" \
    --prefix="$TOOLS" \
    --with-sysroot="$SYSROOT" \
    --with-native-system-header-dir=/usr/include \
    --enable-languages=c,c++ \
    --enable-shared \
    --enable-threads=posix \
    --disable-nls \
    --disable-multilib \
    --disable-libsanitizer \
    --disable-libvtv

run_make all-gcc
run_make all-target-libgcc

make install-gcc
make install-target-libgcc

# Libstdc++
run_make -C "$BUILD/gcc-pass2" all-target-libstdc++-v3
make -C "$BUILD/gcc-pass2" install-target-libstdc++-v3

# Validation
"$TOOLS/bin/$TARGET-gcc" --version