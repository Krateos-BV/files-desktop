#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Krateos B.V.
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Make every library reference in a macOS app bundle resolve inside the bundle,
# before the bundle is signed (XEN-383).
#
# macdeployqt leaves some references to the Craft install tree in place. Since
# Craft moved liblzma to xz 5.8.4 (built with CMake), libKF6Archive links
# <craft root>/lib/liblzma.5.dylib by absolute path, so the app would not launch
# on another Mac. For each Mach-O file in Contents/MacOS and Contents/Frameworks,
# every dependency that is an absolute path outside /System/Library and /usr/lib
# is:
#   - copied into Contents/Frameworks under its file name, if it is not there yet
#     (its install name becomes @rpath/<name>), and
#   - rewritten to @rpath/<name>.
# Copied libraries are scanned too, until nothing changes. A dependency that
# does not exist on disk is an error. xenia-check-bundle-linkage.sh verifies the
# result after signing.
#
# Usage: xenia-fix-bundle-linkage.sh "/path/to/App.app"

set -euo pipefail

APP="${1:?usage: $0 /path/to/App.app}"
CONTENTS="${APP%/}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
FW_DIR="${CONTENTS}/Frameworks"

[ -d "${MACOS_DIR}" ] || { echo "error: ${MACOS_DIR} does not exist" >&2; exit 1; }
mkdir -p "${FW_DIR}"

is_macho() {
    file -b "$1" | grep -q '^Mach-O'
}

list_binaries() {
    find "${MACOS_DIR}" "${FW_DIR}" -type f -print0
}

changed=1
pass=0
while [ "${changed}" -eq 1 ]; do
    changed=0
    pass=$((pass + 1))
    if [ "${pass}" -gt 10 ]; then
        echo "error: library references still changing after 10 passes" >&2
        exit 1
    fi
    while IFS= read -r -d '' bin; do
        is_macho "${bin}" || continue
        self_id="$(otool -D "${bin}" 2>/dev/null | sed -n '2p')"
        while IFS= read -r dep; do
            [ -n "${dep}" ] || continue
            [ "${dep}" = "${self_id}" ] && continue
            case "${dep}" in
                /System/Library/* | /usr/lib/*) continue ;;
                /*) ;;
                *) continue ;;
            esac
            name="$(basename "${dep}")"
            target="${FW_DIR}/${name}"
            if [ ! -e "${target}" ]; then
                if [ ! -e "${dep}" ]; then
                    echo "error: ${bin#"${APP%/}/"} links ${dep}, which does not exist" >&2
                    exit 1
                fi
                echo "Copying ${dep} into Contents/Frameworks"
                cp -L "${dep}" "${target}"
                chmod u+w "${target}"
                install_name_tool -id "@rpath/${name}" "${target}"
            fi
            echo "Rewriting ${dep} to @rpath/${name} in ${bin#"${APP%/}/"}"
            install_name_tool -change "${dep}" "@rpath/${name}" "${bin}"
            changed=1
        done < <(otool -L "${bin}" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*$//')
    done < <(list_binaries)
done

echo "Bundle library references are inside the bundle."
