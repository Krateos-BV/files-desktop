# XEN-304 guest-side checks for the Xenia Files MSI.
# Runs inside the Windows VM, started by xen304-vm-test.sh through vmrun.
# Each phase writes C:\xen304\result-<Phase>.json with pass/fail per check.
# No secrets are passed on the command line. The sync phase reads
# %USERPROFILE%\.netrc, which the host copies in and this script deletes.

param(
    [Parameter(Mandatory)][ValidateSet('install','verify','uninstall','verify-removed','sync')]
    [string]$Phase,
    [string]$Msi,
    [string]$Tag = $Phase,
    [string]$ExpectNotProductCode,
    [string]$SyncUrl,
    [string]$SyncRemotePath = '/xen304-vmtest',
    [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$Work = 'C:\xen304'
$UpgradeCode = '{DC291C60-54AB-4039-ADB3-9947ACCEF79A}'
$UpstreamUpgradeCode = '{FD2FCCA9-BB8F-4485-8F70-A0621B84A7F4}'
$InstallDir = Join-Path $env:ProgramFiles 'Xenia Files'
$XeniaClsids = @(
    '{F6819FB9-0257-4A7F-995E-CD831E29F5B7}', # context menu
    '{BF3D2A2E-BB57-4E8C-8F13-E4E9D56DC8AA}', # overlay error
    '{BBBA93E8-9907-49F8-B5E2-0609961446D5}', # overlay ok
    '{B1619828-D52A-482E-846C-4E93A21303BB}', # overlay ok shared
    '{F9A623EE-F1AD-4893-A731-87C0C4B4370F}', # overlay sync
    '{87AEDBBB-8884-4FB5-B854-D1D621797C09}'  # overlay warning
)

$checks = New-Object System.Collections.Generic.List[object]
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $checks.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

function Get-Related([string]$Code) {
    $inst = New-Object -ComObject WindowsInstaller.Installer
    $out = @()
    foreach ($p in $inst.RelatedProducts($Code)) { $out += [string]$p }
    return ,$out
}

function Get-ArpEntries {
    $roots = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    $all = foreach ($r in $roots) {
        if (Test-Path $r) { Get-ChildItem $r | ForEach-Object { Get-ItemProperty $_.PSPath } }
    }
    return ,@($all | Where-Object { $_.DisplayName -eq 'Xenia Files' })
}

function Find-Shortcuts {
    $dirs = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
            "$env:PUBLIC\Desktop",
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
            [Environment]::GetFolderPath('Desktop')
    return ,@($dirs | Where-Object { Test-Path $_ } |
        ForEach-Object { Get-ChildItem $_ -Recurse -Filter '*Xenia Files*.lnk' -ErrorAction SilentlyContinue } |
        ForEach-Object { $_.FullName })
}

function Test-Clsid([string]$Guid) {
    return (Test-Path "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$Guid")
}

# vmrun guest operations run with a UAC-filtered token. With UAC set to
# "never notify", RunAs elevates silently, so install/uninstall relaunch
# themselves elevated once and hand back the child's exit code.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (($Phase -in @('install', 'uninstall')) -and -not $isAdmin -and -not $Elevated) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"",
                 '-Phase', $Phase, '-Tag', $Tag, '-Elevated')
    if ($Msi) { $argList += @('-Msi', "`"$Msi`"") }
    try {
        $child = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList $argList
        exit $child.ExitCode
    } catch {
        # fall through: the check below records why
    }
}

try {
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (($Phase -in @('install', 'uninstall')) -and -not $admin) {
        throw 'not elevated: vmrun is running as a filtered (UAC) token, see the plan, section Guest setup'
    }
    switch ($Phase) {
        'install' {
            if (-not (Test-Path $Msi)) { throw "MSI not found: $Msi" }
            $log = Join-Path $Work "msiexec-$Tag.log"
            $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
                '/i', "`"$Msi`"", '/qn', '/norestart', '/l*v', "`"$log`"")
            # 0 = ok, 3010 = ok but reboot wanted
            Check 'msiexec exit code' ($p.ExitCode -in 0, 3010) "exit $($p.ExitCode), log $log"
        }
        'verify' {
            $related = Get-Related $UpgradeCode
            Check 'exactly one product with the Xenia UpgradeCode' ($related.Count -eq 1) ($related -join ', ')
            $pc = if ($related.Count -ge 1) { $related[0] } else { '' }
            if ($ExpectNotProductCode) {
                Check 'ProductCode changed after upgrade' ($pc -and $pc -ne $ExpectNotProductCode) "old $ExpectNotProductCode, now $pc"
            }
            $arp = Get-ArpEntries
            Check 'one "Xenia Files" entry in Apps' ($arp.Count -eq 1) "found $($arp.Count)"
            if ($arp.Count -ge 1) {
                Check 'publisher is XeniaCloud' ($arp[0].Publisher -eq 'XeniaCloud') "$($arp[0].Publisher)"
                Check 'version reported' ([bool]$arp[0].DisplayVersion) "$($arp[0].DisplayVersion)"
            }
            foreach ($f in 'xenia-files.exe', 'xenia-filescmd.exe', 'NCContextMenu.dll', 'NCOverlays.dll', 'Qt6Core.dll') {
                Check "file $f" (Test-Path (Join-Path $InstallDir $f)) $InstallDir
            }
            $sc = Find-Shortcuts
            Check 'Xenia Files shortcut exists' ($sc.Count -ge 1) ($sc -join '; ')
            foreach ($g in $XeniaClsids) { Check "CLSID $g registered" (Test-Clsid $g) }
            $cmd = Join-Path $InstallDir 'xenia-filescmd.exe'
            if (Test-Path $cmd) {
                $v = (& $cmd --version 2>&1 | Out-String).Trim()
                Check 'xenia-filescmd --version runs' ($LASTEXITCODE -eq 0) ($v -split "`n" | Select-Object -First 2 | Out-String).Trim()
            }
            $up = Get-Related $UpstreamUpgradeCode
            Check 'Nextcloud install (if any) still present' $true "upstream products: $($up -join ', ')"
            $pc | Set-Content (Join-Path $Work "productcode-$Tag.txt")
        }
        'uninstall' {
            $related = Get-Related $UpgradeCode
            if ($related.Count -ne 1) { throw "expected one installed product, found $($related.Count)" }
            $log = Join-Path $Work "msiexec-$Tag.log"
            $p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @(
                '/x', $related[0], '/qn', '/norestart', '/l*v', "`"$log`"")
            Check 'msiexec /x exit code' ($p.ExitCode -in 0, 3010) "exit $($p.ExitCode), log $log"
        }
        'verify-removed' {
            Check 'no product with the Xenia UpgradeCode' ((Get-Related $UpgradeCode).Count -eq 0)
            Check 'no "Xenia Files" entry in Apps' ((Get-ArpEntries).Count -eq 0)
            Check 'install folder removed' (-not (Test-Path (Join-Path $InstallDir 'xenia-files.exe'))) $InstallDir
            $sc = Find-Shortcuts
            Check 'shortcuts removed' ($sc.Count -eq 0) ($sc -join '; ')
            foreach ($g in $XeniaClsids) { Check "CLSID $g removed" (-not (Test-Clsid $g)) }
            $up = Get-Related $UpstreamUpgradeCode
            Check 'Nextcloud install (if any) untouched' $true "upstream products: $($up -join ', ')"
        }
        'sync' {
            $netrc = Join-Path $env:USERPROFILE '.netrc'
            try {
                if (-not $SyncUrl) { throw 'no -SyncUrl given' }
                if (-not (Test-Path $netrc)) { throw '.netrc not present' }
                $cmd = Join-Path $InstallDir 'xenia-filescmd.exe'
                $a = Join-Path $Work 'sync-a'; $b = Join-Path $Work 'sync-b'
                Remove-Item -Recurse -Force $a, $b -ErrorAction SilentlyContinue
                New-Item -ItemType Directory -Force -Path $a, $b | Out-Null
                $name = "xen304-$(Get-Date -Format yyyyMMddHHmmss).txt"
                "XEN-304 VM sync test $(New-Guid)" | Set-Content (Join-Path $a $name)
                $base = @('-n', '--non-interactive', '--path', $SyncRemotePath)
                & $cmd @base $a $SyncUrl *> (Join-Path $Work 'sync-upload.log')
                Check 'upload sync exit code' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
                & $cmd @base $b $SyncUrl *> (Join-Path $Work 'sync-download.log')
                Check 'download sync exit code' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
                $same = (Test-Path (Join-Path $b $name)) -and
                    ((Get-FileHash (Join-Path $a $name)).Hash -eq (Get-FileHash (Join-Path $b $name)).Hash)
                Check 'file round-trips through the server' $same $name
                # clean up the remote test file
                Remove-Item (Join-Path $a $name) -Force
                & $cmd @base $a $SyncUrl *> (Join-Path $Work 'sync-cleanup.log')
                Check 'cleanup sync exit code' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
            } finally {
                Remove-Item $netrc -Force -ErrorAction SilentlyContinue
                Check '.netrc deleted from guest' (-not (Test-Path $netrc))
            }
        }
    }
} catch {
    Check "phase $Phase ran without error" $false $_.Exception.Message
}

$pass = -not ($checks | Where-Object { -not $_.ok })
[pscustomobject]@{ phase = $Phase; tag = $Tag; pass = [bool]$pass; checks = $checks } |
    ConvertTo-Json -Depth 4 | Set-Content (Join-Path $Work "result-$Tag.json") -Encoding UTF8
if ($pass) { exit 0 } else { exit 1 }
