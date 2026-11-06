# MSI VM test (Xenia)

Automated install, upgrade and uninstall test of the Xenia Files MSI in a
VMware Fusion Windows VM, driven from macOS with `vmrun`.

- `xen304-vm-test.sh` runs on the Mac host.
- `xen304-guest.ps1` runs inside the guest, one phase per call.

Guest and test-account passwords come from the macOS Keychain
(`xenia-msi-test-guest`, `xenia-msi-test-account`); see the header of
`xen304-vm-test.sh`. Overlays and the context menu are not exercised on
Windows on ARM (ARM64 Explorer does not load x64 shell extensions).
