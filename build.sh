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
LOGS="$DISTRO/logs"

mkdir -p "$DISTRO"/{sources,build,tools,sysroot,logs}
chown -R "$BUILDER:$BUILDER" "$DISTRO"

export DISTRO
export SOURCES="$DISTRO/sources"
export BUILD="$DISTRO/build"
export TOOLS="$DISTRO/tools"
export SYSROOT="$DISTRO/sysroot"
export GLIBC_JOBS="${GLIBC_JOBS:-1}"
export ROOTFS="${ROOTFS:-$DISTRO/rootfs}"
export INITRAMFS="${INITRAMFS:-$DISTRO/initramfs}"
export IMAGES="${IMAGES:-$DISTRO/images}"
export ROOT_DEV="${ROOT_DEV:-/dev/vda}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

source "$SCRIPT_DIR/config/packages.sh"

log_permissions() {
    echo "$*" | tee -a "$LOGS/permissions.log"
}

ensure_path_access() {
    local dir="$1"
    local -a dirs=()
    local i d

    while [[ -n "$dir" && "$dir" != "/" ]]; do
        dirs+=("$dir")
        dir="$(dirname -- "$dir")"
    done

    for ((i = ${#dirs[@]} - 1; i >= 0; i--)); do
        d="${dirs[$i]}"
        if [[ -d "$d" ]] && ! runuser -u "$BUILDER" -- test -x "$d" 2>/dev/null; then
            chmod o+x "$d"
            log_permissions "chmod o+x $d"
        fi
    done
}

ensure_executable() {
    local file="$1"
    local before after

    [[ -f "$file" ]] || return 0
    before="$(stat -c %a "$file")"
    chmod a+rx "$file"
    after="$(stat -c %a "$file")"
    if [[ "$before" != "$after" ]]; then
        log_permissions "chmod a+rx $file"
    fi
}

echo "Preparing permissions for $BUILDER..."
ensure_path_access "$SCRIPT_DIR"
ensure_path_access "$SCRIPT_DIR/scripts"
ensure_path_access "$SCRIPT_DIR/config"

for file in "$SCRIPT_DIR"/scripts/*.sh "$SCRIPT_DIR"/config/*.sh; do
    ensure_executable "$file"
done

if [[ -f "$LOGS/permissions.log" ]]; then
    chown "$BUILDER:$BUILDER" "$LOGS/permissions.log"
fi

SUCCESS_STEPS=()
FAILED_STEPS=()
FAILED_LOGS=()

extract_error_lines() {
    local log="$1"
    grep -nE 'error:|Error|Permission denied|command not found|No such file|undefined reference' "$log" 2>/dev/null \
        | awk '!seen[$0]++' \
        | head -n 20 || true
}

extract_problem_packages() {
    local log="$1"
    local context pkg base

    context="$(tail -n 200 "$log" 2>/dev/null || true)"
    for pkg in "${!packages[@]}"; do
        base="$(basename "${packages[$pkg]}")"
        base="${base%.tar.*}"
        if grep -qF -- "$base" <<< "$context"; then
            printf '%s\n' "$pkg"
        elif grep -qE -- "(build|sources)/${pkg}([^A-Za-z0-9._+]|$)" <<< "$context"; then
            printf '%s\n' "$pkg"
        fi
    done
}

show_log_tail() {
    local log="$1"
    echo "--- tail of $log ---" >&2
    tail -n 40 "$log" >&2 || true
    echo "--- end of tail ---" >&2
}

run_step_command() {
    local user="$1"
    local script="$2"

    if [[ "$user" == "root" ]]; then
        bash "$script"
    else
        runuser -u "$user" -- \
            env DISTRO="$DISTRO" \
                SOURCES="$SOURCES" \
                BUILD="$BUILD" \
                TOOLS="$TOOLS" \
                SYSROOT="$SYSROOT" \
                GLIBC_JOBS="$GLIBC_JOBS" \
                ROOTFS="$ROOTFS" \
                INITRAMFS="$INITRAMFS" \
                IMAGES="$IMAGES" \
                ROOT_DEV="$ROOT_DEV" \
                bash "$script"
    fi
}

run_step() {
    local script="$1"
    local user="${2:-$BUILDER}"
    local step="${script%.sh}"
    local log="$LOGS/$step.log"
    local rc=0

    echo "==> Running $script as $user (log: $log)"
    if run_step_command "$user" "$SCRIPT_DIR/scripts/$script" 2>&1 | tee "$log"; then
        SUCCESS_STEPS+=("$step")
        echo "==> $step completed"
    else
        rc=${PIPESTATUS[0]}
        FAILED_STEPS+=("$step")
        FAILED_LOGS+=("$log")
        echo "==> $step failed (exit code $rc)" >&2
        show_log_tail "$log"
    fi
}

echo "Environment prepared."
echo "Starting build process..."

run_step "download.sh"
run_step "setup-sysroot.sh"
run_step "build-toolchain.sh"
run_step "build-kernel.sh"
run_step "build-userspace.sh"
run_step "build-utilities.sh"
run_step "build-rootfs.sh" root
run_step "build-initramfs.sh" root
run_step "make-image.sh" root

declare -A PROBLEM_PACKAGES=()

if ((${#FAILED_LOGS[@]})); then
    for log in "${FAILED_LOGS[@]}"; do
        while IFS= read -r pkg; do
            if [[ -n "$pkg" ]]; then
                PROBLEM_PACKAGES["$pkg"]=1
            fi
        done < <(extract_problem_packages "$log")
    done
fi

echo
echo "===== BUILD SUMMARY ====="
echo "Successful steps: ${#SUCCESS_STEPS[@]}"

if ((${#SUCCESS_STEPS[@]})); then
    for step in "${SUCCESS_STEPS[@]}"; do
        echo "  - $step"
    done
fi

echo "Failed steps: ${#FAILED_STEPS[@]}"

if ((${#FAILED_STEPS[@]})); then
    for i in "${!FAILED_STEPS[@]}"; do
        step="${FAILED_STEPS[$i]}"
        log="${FAILED_LOGS[$i]}"
        echo "  - $step (log: $log)"
        mapfile -t error_lines < <(extract_error_lines "$log")
        if ((${#error_lines[@]})); then
            printf '      %s\n' "${error_lines[@]}"
        else
            echo "      (no matching error lines)"
        fi
    done

    echo "Problem packages:"
    if ((${#PROBLEM_PACKAGES[@]})); then
        for pkg in "${!PROBLEM_PACKAGES[@]}"; do
            echo "  - $pkg"
        done | sort
    else
        echo "  - none detected"
    fi
else
    echo "  - none"
fi

if ((${#FAILED_STEPS[@]})); then
    echo "Build finished with failures. Logs are in $LOGS"
    exit 1
fi

echo "Build process completed successfully."
