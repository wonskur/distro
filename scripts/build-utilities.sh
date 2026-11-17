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

export PATH="$TOOLS/bin:$PATH"
export LC_ALL=C
export CONFIG_SITE=/dev/null

export CC="$TARGET-gcc"
export CXX="$TARGET-g++"
export AR="$TARGET-ar"
export RANLIB="$TARGET-ranlib"
export LD="$TARGET-ld"
export STRIP="$TARGET-strip"

export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""

mkdir -p "$BUILD/utilities" "$SYSROOT"

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

build_autotools() {
    local archive="$1"
    shift

    local src
    src="$(get_source "$archive")"

    local name
    name="$(basename "$src")"

    local build="$BUILD/utilities/$name"

    rm -rf "$build"
    mkdir -p "$build"
    cd "$build"

    "$src/configure" \
        --build="$(gcc -dumpmachine)" \
        --host="$TARGET" \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-nls \
        "$@"

    make -j"$JOBS"
    make DESTDIR="$SYSROOT" install
}

build_libcap() {
    local src
    src="$(get_source libcap-2.78.tar.xz)"

    cd "$src"

    make -j"$JOBS" \
        prefix=/usr \
        lib=lib \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$RANLIB"

    make \
        prefix=/usr \
        lib=lib \
        DESTDIR="$SYSROOT" \
        install
}

echo "Building system utilities"

build_libcap

build_autotools "attr-2.6.0.tar.gz"

build_autotools "acl-2.4.0.tar.xz"

build_autotools "libpipeline-1.5.8.tar.gz"

build_autotools "procps-ng-4.0.7.tar.xz" \
    --disable-kill

build_autotools "kmod-34.3.tar.xz" \
    --with-zlib \
    --with-xz \
    --with-zstd

build_autotools "shadow-4.20.3.tar.xz" \
    --sysconfdir=/etc \
    --with-group-name-max-length=32

build_autotools "psmisc-23.7.tar.xz"

build_autotools "e2fsprogs-1.47.4.tar.gz" \
    --enable-elf-shlibs \
    --disable-fsck

build_autotools "util-linux-2.42.4.tar.xz" \
    --disable-chfn-chsh \
    --disable-login \
    --disable-nologin \
    --disable-su \
    --disable-setpriv \
    --disable-runuser \
    --disable-pylibmount \
    --without-python \
    --without-systemd \
    --without-systemdsystemunitdir

build_autotools "inetutils-2.8.tar.gz" \
    --disable-logger \
    --disable-whois \
    --disable-rcp \
    --disable-rexec \
    --disable-rlogin \
    --disable-rsh

echo
echo "Building iproute2"

IPROUTE="$(get_source iproute2-7.3.0.tar.xz)"

cd "$IPROUTE"

make -j"$JOBS" \
    CC="$CC" \
    AR="$AR" \
    DESTDIR="$SYSROOT" \
    SBINDIR=/usr/sbin \
    LIBDIR=/usr/lib

make \
    CC="$CC" \
    AR="$AR" \
    DESTDIR="$SYSROOT" \
    SBINDIR=/usr/sbin \
    LIBDIR=/usr/lib \
    install

echo
echo "Installing iana-etc"

IANA="$(get_source iana-etc-20261015.tar.gz)"

cd "$IANA"

make -j"$JOBS"

make DESTDIR="$SYSROOT" install

MANPAGES="$(get_source man-pages-6.20.tar.xz)"

cd "$MANPAGES"

make -j"$JOBS" \
    prefix=/usr \
    DESTDIR="$SYSROOT" \
    install

build_autotools "texinfo-7.3.tar.xz"

build_autotools "man-db-2.13.1.tar.xz" \
    --disable-setuid

VIM="$(get_source vim-9.2.1225.tar.gz)"

cd "$VIM/src"

./configure \
    --host="$TARGET" \
    --prefix=/usr \
    --with-features=huge \
    --enable-multibyte \
    --disable-gui \
    --without-x

make -j"$JOBS" \
    CC="$CC" \
    STRIP="$STRIP"

make DESTDIR="$SYSROOT" install

GRUB="$(get_source grub-2.16.tar.xz)"

mkdir -p "$BUILD/utilities/grub"
cd "$BUILD/utilities/grub"

"$GRUB/configure" \
    --build="$(gcc -dumpmachine)" \
    --host="$TARGET" \
    --target=x86_64 \
    --prefix=/usr \
    --disable-werror \
    --disable-nls

make -j"$JOBS"
make DESTDIR="$SYSROOT" install
