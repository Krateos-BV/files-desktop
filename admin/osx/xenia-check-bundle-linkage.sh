#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Krateos B.V.
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fail if a built macOS app bundle would not launch because a library it links
# cannot be found inside the bundle (XEN-343).
#
# Checks every Mach-O executable in Contents/MacOS and every library in
# Contents/Frameworks. Each dependency must be a system library, or resolve to a
# file inside the bundle: @rpath/X must exist as Contents/Frameworks/X, and
# @loader_path/X or @executable_path/X must exist relative to the binary or to
# Contents/MacOS. Any other absolute path (for example a CI build directory)
# fails the check.
#
# Usage: xenia-check-bundle-linkage.sh "/path/to/Xenia Files.app"

set -euo pipefail

APP="${1:?usage: $0 /path/to/App.app}"
CONTENTS="${APP%/}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
FW_DIR="${CONTENTS}/Frameworks"

[ -d "${MACOS_DIR}" ] || { echo "::error::${MACOS_DIR} does not exist"; exit 1; }

is_macho() {
    file -b "$1" | grep -q '^Mach-O'
}

failures=0
checked=0

check_binary() {
    local bin="$1" self_id dep resolved bin_dir
    bin_dir="$(dirname "${bin}")"
    self_id="$(otool -D "${bin}" 2>/dev/null | sed -n '2p')"
    checked=$((checked + 1))
    # otool -L prints the file name first, then one dependency per line.
    while IFS= read -r dep; do
        [ -n "${dep}" ] || continue
        [ "${dep}" = "${self_id}" ] && continue
        case "${dep}" in
            /System/Library/* | /usr/lib/*)
                continue
                ;;
            @rpath/*)
                resolved="${FW_DIR}/${dep#@rpath/}"
                ;;
            @loader_path/*)
                resolved="${bin_dir}/${dep#@loader_path/}"
                ;;
            @executable_path/*)
                resolved="${MACOS_DIR}/${dep#@executable_path/}"
                ;;
            *)
                echo "::error::${bin#"${APP%/}/"} links ${dep}, an absolute path outside the bundle"
                failures=$((failures + 1))
                continue
                ;;
        esac
        if [ ! -e "${resolved}" ]; then
            echo "::error::${bin#"${APP%/}/"} links ${dep}, but ${resolved#"${APP%/}/"} is not in the bundle"
            failures=$((failures + 1))
        fi
    done < <(otool -L "${bin}" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*$//')
}

# Executables in Contents/MacOS. Stray dylibs there are not loaded by the app
# (it resolves @rpath through Contents/Frameworks), so only executables count.
while IFS= read -r -d '' f; do
    is_macho "$f" || continue
    file -b "$f" | grep -q 'executable' || continue
    check_binary "$f"
done < <(find "${MACOS_DIR}" -maxdepth 1 -type f -print0)

# Libraries and framework binaries in Contents/Frameworks.
if [ -d "${FW_DIR}" ]; then
    while IFS= read -r -d '' f; do
        is_macho "$f" || continue
        check_binary "$f"
    done < <(find "${FW_DIR}" -type f \( -name '*.dylib' -o -path '*.framework/Versions/*/*' \) \
                -not -path '*/Headers/*' -not -path '*/Resources/*' -not -path '*/_CodeSignature/*' -print0)
fi

if [ "${failures}" -gt 0 ]; then
    echo "::error::${failures} unresolved library reference(s) in ${checked} binaries. The app would fail to launch."
    exit 1
fi
echo "Bundle linkage OK: ${checked} binaries checked, every library resolves inside the bundle."
