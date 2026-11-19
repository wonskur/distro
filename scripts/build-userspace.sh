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

export CC="$TOOLS/bin/$TARGET-gcc"
export CXX="$TOOLS/bin/$TARGET-g++"
export AR="$TOOLS/bin/$TARGET-ar"
export AS="$TOOLS/bin/$TARGET-as"
export LD="$TOOLS/bin/$TARGET-ld"
export RANLIB="$TOOLS/bin/$TARGET-ranlib"
export STRIP="$TOOLS/bin/$TARGET-strip"

export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export PKG_CONFIG_PATH=""

mkdir -p "$BUILD/userspace" "$SYSROOT"

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

    local build="$BUILD/userspace/$name"

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

build_cmake() {
    local archive="$1"
    shift

    local src
    src="$(get_source "$archive")"

    local name
    name="$(basename "$src")"

    local cmake_src="$src"

    if [[ ! -f "$cmake_src/CMakeLists.txt" ]] &&
       [[ -f "$src/build/cmake/CMakeLists.txt" ]]; then
        cmake_src="$src/build/cmake"
    fi

    if [[ ! -f "$cmake_src/CMakeLists.txt" ]]; then
        echo "Missing CMakeLists.txt: $src" >&2
        exit 1
    fi

    local build="$BUILD/userspace/$name"

    rm -rf "$build"
    mkdir -p "$build"

    cmake -S "$cmake_src" -B "$build" \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_AR="$AR" \
        -DCMAKE_RANLIB="$RANLIB" \
        -DCMAKE_SYSROOT="$SYSROOT" \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_FIND_ROOT_PATH="$SYSROOT" \
        -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
        -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
        -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
        "$@"

    cmake --build "$build" --parallel "$JOBS"
    DESTDIR="$SYSROOT" cmake --install "$build"
}

build_zlib() {
    local src
    src="$(get_source zlib-1.4.tar.gz)"

    cd "$src"

    CHOST="$TARGET" CC="$CC" AR="$AR" RANLIB="$RANLIB" \
        ./configure --prefix=/usr

    make -j"$JOBS"
    make DESTDIR="$SYSROOT" install
}

build_openssl() {
    local src
    src="$(get_source openssl-4.1.0.tar.gz)"

    cd "$src"

    CC="$CC" ./Configure linux-x86_64 \
        --prefix=/usr \
        --openssldir=/etc/ssl \
        --libdir=lib \
        no-tests

    make -j"$JOBS"
    make DESTDIR="$SYSROOT" install_sw
}

build_bzip2() {
    local src
    src="$(get_source bzip2-1.0.8.tar.gz)"

    cd "$src"

    make -j"$JOBS" \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$RANLIB"

    rm -f blocksort.o huffman.o crctable.o randtable.o compress.o decompress.o bzlib.o

    make -f Makefile-libbz2_so \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$RANLIB"

    make \
        CC="$CC" \
        AR="$AR" \
        RANLIB="$RANLIB" \
        PREFIX="$SYSROOT/usr" \
        install

    install -D -m 0755 libbz2.so.1.0.8 "$SYSROOT/usr/lib/libbz2.so.1.0.8"
    ln -sfn libbz2.so.1.0.8 "$SYSROOT/usr/lib/libbz2.so.1.0"
    ln -sfn libbz2.so.1.0 "$SYSROOT/usr/lib/libbz2.so.1"
    ln -sfn libbz2.so.1.0.8 "$SYSROOT/usr/lib/libbz2.so"
}

build_file() {
    local src name native build
    src="$(get_source "file-5.48.tar.gz")"
    name="$(basename "$src")"
    native="$BUILD/userspace/$name-native"
    build="$BUILD/userspace/$name"

    rm -rf "$native" "$build"
    mkdir -p "$native" "$build"

    cd "$native"
    CC=gcc CXX=g++ AR=ar RANLIB=ranlib AS=as LD=ld STRIP=strip \
        "$src/configure" \
            --build="$(gcc -dumpmachine)" \
            --disable-nls \
            --disable-bzlib \
            --disable-xzlib \
            --disable-zlib \
            --disable-libseccomp
    make -j"$JOBS" CC=gcc CXX=g++ AR=ar RANLIB=ranlib AS=as LD=ld STRIP=strip

    cd "$build"
    "$src/configure" \
        --build="$(gcc -dumpmachine)" \
        --host="$TARGET" \
        --prefix=/usr \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-nls
    make -j"$JOBS" FILE_COMPILE="$native/src/file"
    make DESTDIR="$SYSROOT" install
}

build_zlib

build_autotools "expat-2.10.0.tar.xz" \
    --without-docbook

build_autotools "libffi-3.8.0.tar.gz"

build_autotools "libxcrypt-4.5.2.tar.xz" \
    --enable-hashes=strong,glibc \
    --enable-obsolete-api=no \
    --disable-werror

build_autotools "pcre2-10.49.tar.bz2" \
    --enable-unicode \
    --enable-jit

build_autotools "ncurses-6.6.tar.gz" \
    --with-shared \
    --with-termlib \
    --without-debug \
    --without-ada \
    --enable-widec \
    --with-build-cc=gcc \
    --with-pkg-config-libdir=/usr/lib/pkgconfig

build_autotools "readline-8.3.tar.gz"

build_openssl

build_autotools "m4-1.4.21.tar.xz"

build_autotools "bash-5.3.tar.gz" \
    --without-bash-malloc

build_autotools "coreutils-9.12.tar.xz" \
    --enable-no-install-program=kill,uptime

build_autotools "findutils-4.11.0.tar.xz"

build_autotools "grep-3.12.tar.xz"

build_autotools "sed-4.10.tar.xz"

build_autotools "gawk-5.4.1.tar.xz"

build_autotools "diffutils-3.12.tar.xz" \
    gl_cv_func_strcasecmp_works=yes

TAR_SRC="$(get_source "tar-1.35.tar.xz")"

if grep -q '^static acl_t acl_get_file_at' "$TAR_SRC/src/xattrs.c"; then
    sed -i \
        -e 's/\bacl_get_file_at\b/tar_acl_get_file_at/g' \
        -e 's/\bacl_set_file_at\b/tar_acl_set_file_at/g' \
        -e 's/\bacl_delete_def_file_at\b/tar_acl_delete_def_file_at/g' \
        "$TAR_SRC/src/xattrs.c"
fi

build_autotools "tar-1.35.tar.xz"

build_autotools "gzip-1.15.tar.xz"

build_bzip2

build_autotools "xz-5.8.4.tar.xz" \
    --disable-static

build_autotools "make-4.4.1.tar.gz"

build_autotools "patch-2.8.1.tar.xz"

build_file

build_autotools "less-710.tar.gz"

build_autotools "gettext-1.0.tar.xz"

build_cmake "zstd-1.5.7.tar.gz" \
    -DZSTD_BUILD_PROGRAMS=ON \
    -DZSTD_BUILD_SHARED=ON \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_BUILD_TESTS=OFF

build_cmake "lz4-1.10.0.tar.gz" \
    -DLZ4_BUILD_CLI=ON \
    -DLZ4_BUILD_LEGACY_LZ4C=OFF \
    -DBUILD_SHARED_LIBS=ON
