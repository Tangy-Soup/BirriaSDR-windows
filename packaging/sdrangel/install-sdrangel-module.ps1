# Install the BirriaSDR SoapySDR module into an SDRangel 8.0.0 bundle.
# Verifies the SoapySDR ABI/variant the module was built for, stages module +
# runtime DLLs + a %~dp0-relative launcher, and (optionally) fills in the
# BIRRIASDR_SOAPY_ALLOW device filter. See README.md next to this file.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File install-sdrangel-module.ps1 `
#       -SdrangelDir "C:\path\to\SDRangel" [-StagingDir <dir>] `
#       [-Allow 001:002] [-AutoDetect [-BirriaRx C:\path\birria_rx.exe]] [-Force]
#
# -SdrangelDir  SDRangel 8.0.0 install root (sdrangel.exe + SoapySDR.dll).
# -StagingDir   output dir; default <SdrangelDir parent>\sdrangel-birriasdr.
# -SourceDir    payload location; default <script dir>\dist (module + DLLs).
# -Allow        usb location filter (label suffix format [bus:addr], three
#               digits each, e.g. 001:002). Single-adapter hosts can omit.
# -AutoDetect   find adapters via birria_rx --list (or SoapySDRUtil --find)
#               and write the filter when exactly one is present.
# -BirriaRx     birria_rx.exe to use for auto-detection (or on PATH).
# -Force        overwrite an existing staging dir / skip the pinned-hash check.
param(
    [Parameter(Mandatory = $true)] [string] $SdrangelDir,
    [string] $StagingDir = "",
    [string] $SourceDir = "",
    [string] $Allow = "",
    [switch] $AutoDetect,
    [string] $BirriaRx = "",
    [switch] $Force
)
$ErrorActionPreference = "Stop"

if (-not $SourceDir) { $SourceDir = Join-Path $PSScriptRoot "dist" }
if (-not $StagingDir) { $StagingDir = Join-Path (Split-Path -Parent $SdrangelDir) "sdrangel-birriasdr" }

function Fail([string] $message) { Write-Host "ERROR: $message" -ForegroundColor Red; exit 1 }
function Note([string] $message) { Write-Host $message -ForegroundColor Yellow }

# --- Inputs exist ------------------------------------------------------------
foreach ($f in @(
        (Join-Path $SdrangelDir "sdrangel.exe"),
        (Join-Path $SdrangelDir "SoapySDR.dll"),
        (Join-Path $SourceDir "birriasdrSupport.dll"),
        (Join-Path $SourceDir "libbirriasdr.dll"),
        (Join-Path $SourceDir "libwinpthread-1.dll"))) {
    if (-not (Test-Path $f)) { Fail "missing $f" }
}

# --- ABI / variant check -----------------------------------------------------
# The prebuilt module pairs with SDRangel's bundled SoapySDR FORK
# v0.8.1-g1667b4e6 (ABI "0.8-3"): that tree adds two getSettingInfo
# overloads, shifting every later vtable slot. A module/host mismatch
# misdispatches virtuals and crashes SDRangel ~5 s after add-device.
$dllText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $SdrangelDir "SoapySDR.dll")))
$modText = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $SourceDir "birriasdrSupport.dll")))
if (-not $modText.Contains("0.8-3")) { Fail "the module in $SourceDir was not built for ABI 0.8-3" }
if (-not $dllText.Contains("0.8-3")) {
    $why = ("{0}\SoapySDR.dll is not the ABI 0.8-3 fork this module needs (vanilla SoapySDR found). " -f $SdrangelDir) +
           "Rebuild the module for that variant - README.md, 'Rebuilding for another SDRangel/SoapySDR variant'."
    Fail $why
}
if (-not $dllText.Contains("1667b4e6")) {
    Note "SoapySDR.dll is ABI 0.8-3 but not the pinned v0.8.1-g1667b4e6 build - the vtable may differ."
    if (-not $Force) { Fail "refusing without -Force (README.md explains how to rebuild for this variant)." }
    else { Note "proceeding because -Force was given." }
}
Write-Host "ABI check OK: SDRangel SoapySDR is the v0.8.1-g1667b4e6 fork (ABI 0.8-3), module matches." -ForegroundColor Green

# --- Staging -----------------------------------------------------------------
if ((Test-Path $StagingDir) -and -not $Force) { Fail "$StagingDir already exists (use -Force to overwrite its BirriaSDR files)" }
New-Item -ItemType Directory -Force -Path (Join-Path $StagingDir "soapy_modules") | Out-Null
Copy-Item (Join-Path $SourceDir "birriasdrSupport.dll") (Join-Path $StagingDir "soapy_modules\birriasdrSupport.dll") -Force
Copy-Item (Join-Path $SourceDir "libbirriasdr.dll") (Join-Path $StagingDir "libbirriasdr.dll") -Force
Copy-Item (Join-Path $SourceDir "libwinpthread-1.dll") (Join-Path $StagingDir "libwinpthread-1.dll") -Force
# soapy_modules must hold ONLY Support DLLs: SoapySDR tries every DLL there.

# --- Device filter -----------------------------------------------------------
# BIRRIASDR_SOAPY_ALLOW=<usb location> hides every other adapter from the
# host app. Mandatory when several MT7921AU dongles are attached (a twin on
# another owner - e.g. a WSL2 VM - must never appear in the device list).
$found = @()
if ($AutoDetect -and -not $Allow) {
    $rx = $BirriaRx
    if (-not $rx) { $rx = (Get-Command birria_rx.exe -ErrorAction SilentlyContinue).Source }
    if ($rx) {
        $out = & $rx --list 2>$null
        foreach ($line in $out) {
            if ($line -match "bus\s+(\d+)\s+address\s+(\d+)") {
                $found += ("{0:d3}:{1:d3}" -f [int]$Matches[1], [int]$Matches[2])
            }
        }
    } else {
        $util = (Get-Command SoapySDRUtil.exe -ErrorAction SilentlyContinue).Source
        if ($util) {
            $env:SOAPY_SDR_PLUGIN_PATH = Join-Path $StagingDir "soapy_modules"
            $out = & $util --find=birriasdr 2>$null
            foreach ($line in $out) { if ($line -match "usb\s*=\s*(\d{3}:\d{3})") { $found += $Matches[1] } }
        }
    }
    if ($found.Count -eq 1) { $Allow = $found[0] }
    elseif ($found.Count -gt 1) { Note ("several adapters found: {0} - no filter written; edit run-sdrangel.cmd" -f ($found -join ", ")) }
    else { Note "no adapter found by auto-detect - filter left commented; edit run-sdrangel.cmd" }
}

# --- Launcher ----------------------------------------------------------------
$allowLine = if ($Allow) { "set BIRRIASDR_SOAPY_ALLOW=$Allow" } else { "REM set BIRRIASDR_SOAPY_ALLOW=bus:addr" }
$launcher = @(
    "@echo off",
    "REM BirriaSDR -> SDRangel launcher, generated by install-sdrangel-module.ps1.",
    "set SOAPY_SDR_PLUGIN_PATH=%~dp0soapy_modules",
    $allowLine,
    ("set PATH=%~dp0;" + $SdrangelDir + ";%PATH%"),
    "REM --soapy is mandatory: SDRangel skips its Soapy plugins without it",
    "start `"`" `"$SdrangelDir\sdrangel.exe`" --soapy"
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $StagingDir "run-sdrangel.cmd"), $launcher + "`r`n")

# --- Report ------------------------------------------------------------------
Write-Host ""
Write-Host "Installed to: $StagingDir" -ForegroundColor Green
Get-ChildItem -Recurse $StagingDir | ForEach-Object { Write-Host ("  " + $_.FullName.Substring($StagingDir.Length + 1)) }
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Launch via $StagingDir\run-sdrangel.cmd (double-click)."
Write-Host "     Close SDRangel via its window X only - a killed GUI leaves the dongle wedged."
if (-not $Allow) {
    Write-Host "  2. No device filter set. If several MT7921AU adapters are attached, launch"
    Write-Host "     once, read the [bus:addr] suffix of YOUR adapter in the device list, then"
    Write-Host "     uncomment/edit the BIRRIASDR_SOAPY_ALLOW line in run-sdrangel.cmd."
} else {
    Write-Host "  2. Device filter BIRRIASDR_SOAPY_ALLOW=$Allow is set; only that adapter is listed."
}
Write-Host "  3. Add device: SoapySDR entry, channel 0 only (chain 1 / both-chain need approval)."
Write-Host "  4. Start at 20 MSps, decimation >= 2; use LNA/LPF/DIG sliders, not the global"
Write-Host "     gain slider. birria_rx stays the canonical lossless capture path."
