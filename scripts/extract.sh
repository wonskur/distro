#!/usr/bin/env bash
extract(){
    local archive="$1"
    if [ -f "$archive" ]; then
        tar -xf "$archive" -C "$(dirname "$archive")"
    else
        echo "File not found"
        return 1
    fi
}
source "$SCRIPT_DIR/config/packages.sh"
for name in "${!packages[@]}"; do
    url="${packages[$name]}"
    filename="$(basename "$url")"
    extract "$SOURCES/$filename"
done