#!/usr/bin/env bash
set -euo pipefail

BUILDER="builder"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run this script as root." >&2
    exit 1
fi

if ! id "$BUILDER" &>/dev/null; then
    echo "Creating user: $BUILDER"
    useradd -m -s /bin/bash "$BUILDER"
fi

BUILDER_HOME="$(getent passwd "$BUILDER" | cut -d: -f6)"
DISTRO="$BUILDER_HOME/distro"

mkdir -p "$DISTRO"/{sources,build,tools,sysroot}
chown -R "$BUILDER:$BUILDER" "$DISTRO"

export DISTRO
export SOURCES="$DISTRO/sources"
export BUILD="$DISTRO/build"
export TOOLS="$DISTRO/tools"
export SYSROOT="$DISTRO/sysroot"

echo "Environment prepared."
echo "Starting build process..."

run_step() {
    local script="$1"
    echo "==> Running $script..."
    runuser -u "$BUILDER" -- \
        env DISTRO="$DISTRO" \
            SOURCES="$SOURCES" \
            BUILD="$BUILD" \
            TOOLS="$TOOLS" \
            SYSROOT="$SYSROOT" \
            bash "$SCRIPT_DIR/scripts/$script"
}

run_step "download.sh"
run_step "setup-sysroot.sh"
run_step "build-toolchain.sh"
run_step "build-kernel.sh"
run_step "build-userspace.sh"
run_step "build-utilities.sh"

echo "Build process completed successfully."
