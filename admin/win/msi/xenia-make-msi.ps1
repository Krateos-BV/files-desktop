# SPDX-FileCopyrightText: 2026 Nextcloud GmbH and Nextcloud contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# XEN-304: build the Xenia Files MSI in CI from a craft build.
#
# Expects, before it runs:
#   - the client compiled by craft with -DBUILD_WIN_MSI=ON (installs make-msi.bat,
#     the .wxs sources and NCMsiHelper64.dll to msi/, and the app .ico to bin/);
#   - `craft --package` run with [Packager]PackageType=PortablePackager, which
#     collects the client and its runtime dependencies into <buildRoot>\archive;
#   - WiX Toolset 3 installed, with the WIX environment variable set.
#
# It stages a flat install dir from that archive, runs make-msi.bat against it and
# prints the path of the resulting MSI. It signs nothing.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $CraftRoot,
    [Parameter(Mandatory = $true)] [string] $OutDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$buildRoot = Join-Path $CraftRoot 'build\nextcloud-client'
$archive = Join-Path $buildRoot 'archive'
foreach ($p in @("$archive\bin", "$archive\msi\make-msi.bat")) {
    if (-not (Test-Path $p)) { throw "Missing $p. Did craft --package run with PortablePackager after a BUILD_WIN_MSI=ON compile?" }
}

Write-Host ':: Top level of the craft archive'
Get-ChildItem $archive | Format-Table -AutoSize Mode, Name | Out-String | Write-Host

if (-not $env:WIX -or -not (Test-Path (Join-Path $env:WIX 'bin\heat.exe'))) {
    throw "WiX Toolset 3 not found (WIX='$env:WIX')."
}

# The branded executable name, as configured into OEM.wxi.
$oem = Get-Content "$archive\msi\OEM.wxi" -Raw
if ($oem -notmatch '<\?define AppExe = "([^"]+)" \?>') { throw 'AppExe not found in OEM.wxi' }
$appExe = $Matches[1]
if ($oem -notmatch '<\?define AppIcon = "([^"]+)" \?>') { throw 'AppIcon not found in OEM.wxi' }
$appIcon = $Matches[1]
Write-Host ":: AppExe=$appExe AppIcon=$appIcon"

# Stage the install dir. Work on copies so the craft archive stays as craft left it.
$stage = Join-Path $env:RUNNER_TEMP 'msi-harvest'
$work = Join-Path $env:RUNNER_TEMP 'msi-work'
foreach ($d in @($stage, $work)) {
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    New-Item -ItemType Directory -Path $d | Out-Null
}
Copy-Item "$archive\bin\*" $stage -Recurse

# The nextcloud-client blueprint's package blacklist drops every bin\*.exe whose
# name does not start with "nextcloud", which removes the branded xenia-files*.exe.
# Put back the executables this package itself installs, from its image dir.
$image = Get-ChildItem $buildRoot -Directory -Filter 'image-*' |
    Where-Object { $_.Name -notlike '*-dbg*' } | Select-Object -First 1
if (-not $image) { throw "No image-* dir under $buildRoot" }
Get-ChildItem (Join-Path $image.FullName 'bin') -Filter '*.exe' -ErrorAction SilentlyContinue | ForEach-Object {
    $dest = Join-Path $stage $_.Name
    if (-not (Test-Path $dest)) {
        Write-Host ":: Restoring $($_.Name) from $($image.Name) (dropped by the craft blacklist)"
        Copy-Item $_.FullName $dest
    }
}

# Windows builds install the client translations to <prefix>\i18n, but the client
# looks for them in <exe dir>\i18n (src/gui/application.cpp).
if (Test-Path "$archive\i18n") {
    Write-Host ':: Moving i18n next to the executable'
    New-Item -ItemType Directory -Path "$stage\i18n" -Force | Out-Null
    Copy-Item "$archive\i18n\*" "$stage\i18n" -Recurse -Force
}

foreach ($f in @($appExe, $appIcon, 'NCContextMenu.dll', 'NCOverlays.dll')) {
    if (-not (Test-Path (Join-Path $stage $f))) { throw "Staged install dir is missing $f" }
}

# make-msi.bat calls uuidgen for the per-build ProductCode; it ships with the Windows SDK.
$uuidgen = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\uuidgen.exe' -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $uuidgen) { throw 'uuidgen.exe not found in the Windows SDK' }
$env:PATH = "$($uuidgen.DirectoryName);$env:PATH"

Copy-Item "$archive\msi\*" $work -Recurse
Push-Location $work
try {
    # make-msi.bat tests %ERRORLEVEL% inside parenthesised loops, where it is expanded
    # before the tool runs, so a failing candle/light does not stop it. Fail on any
    # WiX error line instead (the first CI run produced an MSI despite LGHT0204/ICE03).
    $log = & cmd /c "make-msi.bat `"$stage`" 2>&1"
    $code = $LASTEXITCODE
    $log | ForEach-Object { Write-Host $_ }
    if ($code -ne 0) { throw "make-msi.bat exited with $code" }
    $errors = @($log | Where-Object { $_ -match ' : error [A-Z]+[0-9]+' })
    if ($errors.Count -gt 0) { throw "WiX reported $($errors.Count) error(s); the MSI is not trustworthy." }
} finally {
    Pop-Location
}

$msi = @(Get-ChildItem $work -Filter '*.msi')
if ($msi.Count -ne 1) { throw "Expected one MSI in $work, found $($msi.Count)" }
# Read back what the MSI actually contains, so the CI log is evidence and a wrong
# UpgradeCode, product name or missing executable fails here, not on a user's PC.
function Get-MsiRows([string] $path, [string] $query) {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $db = $installer.GetType().InvokeMember('OpenDatabase', 'InvokeMethod', $null, $installer, @($path, 0))
    $view = $db.GetType().InvokeMember('OpenView', 'InvokeMethod', $null, $db, @($query))
    $view.GetType().InvokeMember('Execute', 'InvokeMethod', $null, $view, $null) | Out-Null
    $rows = @()
    while ($rec = $view.GetType().InvokeMember('Fetch', 'InvokeMethod', $null, $view, $null)) {
        $n = $rec.GetType().InvokeMember('FieldCount', 'GetProperty', $null, $rec, $null)
        # A plain for loop: an index taken from the pipeline ($_) reaches COM wrapped,
        # and StringData rejects it with DISP_E_TYPEMISMATCH.
        $fields = @()
        for ([int] $i = 1; $i -le $n; $i++) {
            $fields += [string] $rec.GetType().InvokeMember('StringData', 'GetProperty', $null, $rec, [object[]] @($i))
        }
        $rows += , $fields
    }
    $view.GetType().InvokeMember('Close', 'InvokeMethod', $null, $view, $null) | Out-Null
    return , $rows
}
$props = @{}
foreach ($r in (Get-MsiRows $msi[0].FullName "SELECT Property, Value FROM Property")) { $props[$r[0]] = $r[1] }
Write-Host ':: MSI properties'
foreach ($k in 'ProductName', 'Manufacturer', 'ProductVersion', 'ProductCode', 'UpgradeCode', 'ARPPRODUCTICON') {
    Write-Host ("   {0,-15} {1}" -f $k, $props[$k])
}
$fileRows = Get-MsiRows $msi[0].FullName "SELECT FileName FROM File"
$fileNames = @($fileRows | ForEach-Object { ($_[0] -split '\|')[-1] })
Write-Host ":: MSI File table: $($fileNames.Count) files"
$upgrade = Get-MsiRows $msi[0].FullName "SELECT UpgradeCode, Attributes FROM Upgrade"
Write-Host ":: MSI Upgrade table: $(($upgrade | ForEach-Object { $_ -join ' ' }) -join '; ')"
# WiX writes non-advertised <Class> elements as Registry rows (HKCR\CLSID\{...}),
# not into the Class table.
# Key is a reserved word in MSI SQL, so the column names are quoted.
$regRows = Get-MsiRows $msi[0].FullName 'SELECT `Root`, `Key` FROM `Registry`'
Write-Host ":: MSI Registry table: $($regRows.Count) rows"
$clsids = @($regRows | ForEach-Object { if ($_[1] -match '^CLSID\\(\{[0-9A-Fa-f-]+\})$') { $Matches[1].ToUpper() } } | Sort-Object -Unique)
Write-Host ":: MSI registers CLSIDs: $($clsids -join ', ')"

$cmake = Get-Content (Join-Path $PSScriptRoot '..\..\..\NEXTCLOUD.cmake') -Raw
if ($cmake -notmatch 'WIN_MSI_UPGRADE_CODE\s+"([0-9A-Fa-f-]+)"') { throw 'WIN_MSI_UPGRADE_CODE not found in NEXTCLOUD.cmake' }
$expectedUpgrade = "{$($Matches[1].ToUpper())}"
$problems = @()
if ($props['UpgradeCode'] -ne $expectedUpgrade) { $problems += "UpgradeCode $($props['UpgradeCode']) is not $expectedUpgrade" }
if ($props['UpgradeCode'] -eq '{FD2FCCA9-BB8F-4485-8F70-A0621B84A7F4}') { $problems += 'UpgradeCode is upstream Nextcloud''s' }
foreach ($f in @($appExe, 'NCContextMenu.dll', 'NCOverlays.dll', 'Qt6Core.dll')) {
    if ($fileNames -notcontains $f) { $problems += "File table lacks $f" }
}
$shellExtGuids = @([regex]::Matches($cmake, 'WIN_SHELLEXT_[A-Z_]+\s+"(\{[0-9A-Fa-f-]+\})"') | ForEach-Object { $_.Groups[1].Value.ToUpper() })
if ($shellExtGuids.Count -ne 6) { $problems += "found $($shellExtGuids.Count) WIN_SHELLEXT_* GUIDs in NEXTCLOUD.cmake, expected 6" }
foreach ($g in $shellExtGuids) {
    if ($clsids -notcontains $g) { $problems += "MSI does not register $g" }
}
# Upstream Nextcloud's context-menu and overlay CLSIDs must not appear.
foreach ($g in '{BC6988AB-ACE2-4B81-84DC-DC34F9B24401}', '{E0342B74-7593-4C70-9D61-22F294AAFE05}', '{E1094E94-BE93-4EA2-9639-8475C68F3886}',
               '{E243AD85-F71B-496B-B17E-B8091CBE93D2}', '{E3D6DB20-1D83-4829-B5C9-941B31C0C35A}', '{E4977F33-F93A-4A0A-9D3C-83DEA0EE8483}') {
    if ($clsids -contains $g) { $problems += "MSI registers upstream Nextcloud CLSID $g" }
}
if ($problems) { throw "MSI check failed: $($problems -join '; ')" }
Write-Host ':: MSI check passed'

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Copy-Item $msi[0].FullName $OutDir
$out = Join-Path $OutDir $msi[0].Name
Write-Host ":: Built $out ($([math]::Round($msi[0].Length / 1MB, 1)) MB)"
if ($env:GITHUB_OUTPUT) { "msi=$out" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append }
