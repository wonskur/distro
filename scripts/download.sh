#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
: "${DISTRO:=$HOME/distro}"
SOURCES="${SOURCES:-$DISTRO/sources}"

source "$SCRIPT_DIR/config/packages.sh"

download() {
    local name="$1"
    local url="$2"
    echo "Downloading $name"
    if [[ -f "$SOURCES/${url##*/}" ]]; then
        echo "Already exists: $name"
        return 0
    fi
    wget -P "$SOURCES" "$url"
}

for name in "${!packages[@]}"; do
    url="${packages[$name]}"
    download "$name" "$url"
done
