#!/bin/bash
# XEN-304: automated install / upgrade / uninstall test of the Xenia Files MSI
# in a VMware Fusion Windows VM on the Mac Mini. Drives the guest with vmrun.
#
# Secrets come from the login Keychain at run time and are never printed:
#   security add-generic-password -s xenia-msi-test-guest   -a <windows-user> -w
#   security add-generic-password -s xenia-msi-test-account -a <xenia-user>   -w
#
# Usage:
#   xen304-vm-test.sh --vmx <path.vmx> --guest-user <user> \
#       --msi-a <first.msi> --msi-b <second.msi> \
#       [--snapshot xen304-clean] [--keep] \
#       [--sync-url https://... --xenia-user <user>]
#
# --msi-a and --msi-b must come from two different CI runs (each build has
# its own ProductCode, which is what makes B an upgrade over A).
# --sync is optional and only runs when --sync-url is given.

set -u
VMRUN="/Applications/VMware Fusion.app/Contents/Library/vmrun"
HERE="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT="xen304-clean"
KEEP=0
VMX="" GUSER="" MSI_A="" MSI_B="" SYNC_URL="" XUSER=""

while [ $# -gt 0 ]; do
    case "$1" in
        --vmx) VMX="$2"; shift 2 ;;
        --guest-user) GUSER="$2"; shift 2 ;;
        --msi-a) MSI_A="$2"; shift 2 ;;
        --msi-b) MSI_B="$2"; shift 2 ;;
        --snapshot) SNAPSHOT="$2"; shift 2 ;;
        --keep) KEEP=1; shift ;;
        --sync-url) SYNC_URL="$2"; shift 2 ;;
        --xenia-user) XUSER="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
for v in VMX GUSER MSI_A MSI_B; do
    [ -n "${!v}" ] || { echo "missing --$(echo $v | tr A-Z a-z)" >&2; exit 2; }
done
[ -x "$VMRUN" ] || { echo "vmrun not found at $VMRUN" >&2; exit 2; }
[ -f "$VMX" ] || { echo "vmx not found: $VMX" >&2; exit 2; }
[ -f "$MSI_A" ] && [ -f "$MSI_B" ] || { echo "MSI file missing" >&2; exit 2; }
if [ -n "$SYNC_URL" ] && [ -z "$XUSER" ]; then echo "--sync-url needs --xenia-user" >&2; exit 2; fi

GPASS="$(security find-generic-password -s xenia-msi-test-guest -a "$GUSER" -w 2>/dev/null)" \
    || { echo "Keychain item xenia-msi-test-guest for $GUSER not found" >&2; exit 2; }

OUT="$HERE/out/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
LOG="$OUT/run.log"
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# vmrun with guest credentials. The password is passed as an argument, which
# local users of the Mac can see in ps while the call runs; nothing is logged.
vg() { "$VMRUN" -T fusion -gu "$GUSER" -gp "$GPASS" "$@"; }

GW='C:\xen304'
PS='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
FAILED=0

guest_phase() { # tag phase [extra ps args...]
    local tag="$1" phase="$2"; shift 2
    log "phase $tag ($phase)"
    vg runProgramInGuest "$VMX" "$PS" \
        -NoProfile -ExecutionPolicy Bypass -File "$GW\\xen304-guest.ps1" \
        -Phase "$phase" -Tag "$tag" "$@" >>"$LOG" 2>&1
    vg copyFileFromGuestToHost "$VMX" "$GW\\result-$tag.json" "$OUT/result-$tag.json" >>"$LOG" 2>&1
    if [ -f "$OUT/result-$tag.json" ] && grep -q '"pass": *true' "$OUT/result-$tag.json"; then
        log "  PASS"
    else
        log "  FAIL (see $OUT/result-$tag.json)"; FAILED=1
    fi
}

cleanup() {
    for f in msiexec-a.log msiexec-b.log msiexec-uninstall.log sync-upload.log sync-download.log sync-cleanup.log; do
        vg copyFileFromGuestToHost "$VMX" "$GW\\$f" "$OUT/$f" >/dev/null 2>&1
    done
    if [ "$KEEP" = 0 ]; then
        log "reverting to snapshot $SNAPSHOT"
        "$VMRUN" -T fusion revertToSnapshot "$VMX" "$SNAPSHOT" >>"$LOG" 2>&1
    fi
    unset GPASS XPASS
}
trap cleanup EXIT

log "reverting to snapshot $SNAPSHOT and starting the VM"
"$VMRUN" -T fusion revertToSnapshot "$VMX" "$SNAPSHOT" >>"$LOG" 2>&1 || { log "revert failed"; exit 1; }
"$VMRUN" -T fusion start "$VMX" nogui >>"$LOG" 2>&1
for i in $(seq 1 60); do
    "$VMRUN" -T fusion checkToolsState "$VMX" 2>/dev/null | grep -q running && break
    sleep 5
done
"$VMRUN" -T fusion checkToolsState "$VMX" 2>/dev/null | grep -q running || { log "VMware Tools not running"; exit 1; }

log "copying scripts and MSIs into the guest"
vg createDirectoryInGuest "$VMX" "$GW" >>"$LOG" 2>&1
vg copyFileFromHostToGuest "$VMX" "$HERE/xen304-guest.ps1" "$GW\\xen304-guest.ps1" >>"$LOG" 2>&1
vg copyFileFromHostToGuest "$VMX" "$MSI_A" "$GW\\a.msi" >>"$LOG" 2>&1
vg copyFileFromHostToGuest "$VMX" "$MSI_B" "$GW\\b.msi" >>"$LOG" 2>&1

# A: fresh install
guest_phase a install -Msi "$GW\\a.msi"
guest_phase a-verify verify
vg captureScreen "$VMX" "$OUT/after-install.png" >>"$LOG" 2>&1
vg copyFileFromGuestToHost "$VMX" "$GW\\productcode-a-verify.txt" "$OUT/productcode-a.txt" >>"$LOG" 2>&1
PC_A="$(tr -d '\r\n' < "$OUT/productcode-a.txt" 2>/dev/null)"

# B: sync with the command line client (optional)
if [ -n "$SYNC_URL" ]; then
    XPASS="$(security find-generic-password -s xenia-msi-test-account -a "$XUSER" -w 2>/dev/null)" \
        || { log "Keychain item xenia-msi-test-account for $XUSER not found"; FAILED=1; }
    if [ -n "${XPASS:-}" ]; then
        host="$(echo "$SYNC_URL" | sed -E 's#^https?://([^/:]+).*#\1#')"
        NETRC="$(mktemp)"; chmod 600 "$NETRC"
        printf 'machine %s login %s password %s\n' "$host" "$XUSER" "$XPASS" > "$NETRC"
        vg copyFileFromHostToGuest "$VMX" "$NETRC" "C:\\Users\\$GUSER\\.netrc" >>"$LOG" 2>&1
        rm -f "$NETRC"; unset XPASS
        guest_phase sync sync -SyncUrl "$SYNC_URL"
    fi
fi

# C: upgrade over A with a different build
guest_phase b install -Msi "$GW\\b.msi"
guest_phase b-verify verify -ExpectNotProductCode "$PC_A"

# D: uninstall
guest_phase uninstall uninstall
guest_phase removed verify-removed

if [ "$FAILED" = 0 ]; then log "RESULT: PASS"; else log "RESULT: FAIL"; fi
log "results in $OUT"
exit "$FAILED"
