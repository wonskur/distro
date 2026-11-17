#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
: "${DISTRO:=$HOME/distro}"
SOURCES="${SOURCES:-$DISTRO/sources}"

source "$SCRIPT_DIR/config/packages.sh"

extract() {
    local archive="$1"
    if [[ -f "$archive" ]]; then
        echo "Extracting $(basename "$archive")"
        tar -xf "$archive" -C "$SOURCES"
    else
        echo "File not found: $archive" >&2
        return 1
    fi
}

for name in "${!packages[@]}"; do
    url="${packages[$name]}"
    filename="$(basename "$url")"
    extract "$SOURCES/$filename"
done
