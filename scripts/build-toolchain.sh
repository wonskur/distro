#!/usr/bin/env bash
cd "$BUILD" 
mkdir -p src
mkdir -p cross
set -e

source "$SCRIPT_DIR/config/build.conf"

mkdir -p "$BUILD" "$TOOLS" "$SYSROOT"
export PATH="$TOOLS/bin:$PATH"

# Binutils Pass 1
mkdir -p "$BUILD/binutils"
cd "$BUILD/binutils"
"$SOURCES/binutils-2.47/configure" \
    --prefix="$TOOLS" \
    --target="$TARGET" \
    --with-sysroot="$SYSROOT" \
    --disable-nls \
    --disable-werror
make -j"$JOBS"
make install

# GCC Pass 1
mkdir -p "$BUILD/gcc"
cd "$BUILD/gcc"
"$SOURCES/gcc-16.2.0/configure" \
    --prefix="$TOOLS" \
    --target="$TARGET" \
    --with-sysroot="$SYSROOT" \
    --disable-nls \
    --disable-werror \
    --enable-languages=c,c++ \
    --disable-multilib \
    --disable-shared \
    --without-headers
make -j"$JOBS"
make install
# Linux API Headers
# IDK how compile it | Iam seriously

# Glibc
mkdir -p "$BUILD/glibc"
cd "$BUILD/glibc"
"$SOURCES/glibc-2.44/configure" \
    --prefix="$TOOLS" \
    --target="$TARGET" \
    --with-sysroot="$SYSROOT" \
    --disable-nls \
    --disable-werror
make -j"$JOBS"
make install
# Libstdc++
mkdir -p "$BUILD/libstdc++"
cd "$BUILD/libstdc++"
"$SOURCES/gcc-16.2.0/libstdc++-v3/configure" \
    --prefix="$TOOLS" \
    --target="$TARGET" \
    --with-sysroot="$SYSROOT" \
    --disable-nls \
    --disable-werror
make -j"JOBS"
make install