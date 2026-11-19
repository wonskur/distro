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

fix_la_paths() {
    local la
    while IFS= read -r -d '' la; do
        sed -i -E 's#/usr/lib/lib([^[:space:]]+)\.la#-l\1#g' "$la"
    done < <(find "$SYSROOT" -name '*.la' -print0 2>/dev/null)
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
    if command -v fakeroot >/dev/null 2>&1; then
        fakeroot make DESTDIR="$SYSROOT" install
    else
        make DESTDIR="$SYSROOT" install
    fi
    fix_la_paths
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
    --with-zstd \
    --disable-manpages

build_autotools "shadow-4.20.3.tar.xz" \
    --sysconfdir=/etc \
    --with-group-name-max-length=32 \
    --disable-logind

build_autotools "psmisc-23.7.tar.xz"

build_autotools "psmisc-23.7.tar.xz"

build_autotools "util-linux-2.42.4.tar.xz" \
    --libdir=/usr/lib \
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

build_autotools "e2fsprogs-1.47.4.tar.gz" \
    --enable-elf-shlibs \
    --disable-fsck \
    --disable-libblkid \
    --disable-libuuid

build_autotools "inetutils-2.8.tar.gz" \
    --with-path-procnet-dev=/proc/net/dev \
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

install -D -m 0644 protocols "$SYSROOT/etc/protocols"
install -D -m 0644 services "$SYSROOT/etc/services"

MANPAGES="$(get_source man-pages-6.20.tar.xz)"

for dir in "$MANPAGES"/man[0-9]*; do
    name="$(basename "$dir")"
    install -d "$SYSROOT/usr/share/man/$name"
    for page in "$dir"/*; do
        install -m 0644 "$page" "$SYSROOT/usr/share/man/$name/"
    done
done

build_autotools "texinfo-7.3.tar.xz"

build_autotools "man-db-2.13.1.tar.xz" \
    --disable-setuid \
    --disable-manual

VIM="$(get_source vim-9.2.1225.tar.gz)"

cd "$VIM/src"

./configure \
    --build="$(gcc -dumpmachine)" \
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
