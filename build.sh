#!/usr/bin/env bash

set -euo pipefail

# Configuration
BUILDER="builder"
DISTRO="/home/$BUILDER/distro"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Check root
if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script as root."
    exit 1
fi

# Create builder user
if ! id "$BUILDER" &>/dev/null; then
    echo "Creating user: $BUILDER"
    useradd -m -s /bin/bash "$BUILDER"
fi

# Create f
mkdir -p "$DISTRO"/{sources,build,tools,sysroot}

# Set permissions
chown -R "$BUILDER:$BUILDER" "$DISTRO"

# Export environment
export DISTRO
export SOURCES="$DISTRO/sources"
export BUILD="$DISTRO/build"
export TOOLS="$DISTRO/tools"
export SYSROOT="$DISTRO/sysroot"

echo "Environment prepared."
echo "Starting build process..."

# Run download script as builder
runuser -u "$BUILDER" -- \
    env DISTRO="$DISTRO" \
        SOURCES="$SOURCES" \
        BUILD="$BUILD" \
        TOOLS="$TOOLS" \
        SYSROOT="$SYSROOT" \
        bash "$SCRIPT_DIR/scripts/download.sh"

echo "Build process completed."