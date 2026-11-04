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
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
Copy-Item $msi[0].FullName $OutDir
$out = Join-Path $OutDir $msi[0].Name
Write-Host ":: Built $out ($([math]::Round($msi[0].Length / 1MB, 1)) MB)"
if ($env:GITHUB_OUTPUT) { "msi=$out" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append }
