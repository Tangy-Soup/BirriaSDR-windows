# BirriaSDR → SDRangel (Windows)

Run a MediaTek MT7921AU (EDUP `0e8d:7961`, MT7961+MT7972) as a receive-only
SDR inside **SDRangel 8.0.0** on native Windows, through this repo's SoapySDR
module. This directory packages the pieces a fork user needs on a fresh
system: a prebuilt module payload + installer, and the from-source build
script both were made with.

## Supported combo (pinned)

| Component | Version | Why pinned |
| --- | --- | --- |
| SDRangel | 8.0.0 win64 bundle | the only bundle validated end-to-end |
| SoapySDR (bundled by SDRangel) | **fork v0.8.1-g1667b4e6, ABI "0.8-3"** | the fork's `Device` class adds two `getSettingInfo` overloads, shifting every later vtable slot — the module must match that exact layout |
| libusb | SDRangel's own bundled **1.0.30** | same version the library pins; `libbirriasdr.dll` binds it from the SDRangel dir. **Do not replace or shadow it** with another libusb. |
| libbirriasdr | this repo's UCRT64 build | receive path, measured gain/LPF tables |

The installer refuses a target whose `SoapySDR.dll` is not ABI `0.8-3`, and
warns + requires `-Force` when the DLL is `0.8-3` but not the pinned
`g1667b4e6` build. A wrong pairing does not fail politely — it **crashes
SDRangel ~5 s after you add the device** (see Troubleshooting).

## Quickstart (prebuilt payload)

Prerequisites:

1. **Driver**: the adapter's `WiFi_If` interface (USB interface 3) bound to
   **libusbK via Zadig**. libusbK is the measured-good binding; plain WinUSB
   rejects one control transfer the boot needs (`0xde` host-wrapper read,
   error 87). Use Zadig's device list, target only YOUR adapter's interface —
   never a VID/PID-wide INF, which would rebind every MT7921AU on the machine.
2. **VC++ redist** (system-wide `msvcp140`/`vcruntime140`): the module is
   built `/MD`. If SDRangel itself runs, this is already satisfied.
3. Windows 10/11 x64.

Then:

```powershell
powershell -ExecutionPolicy Bypass -File install-sdrangel-module.ps1 `
    -SdrangelDir "C:\Path\To\SDRangel" -AutoDetect
```

This checks the ABI, stages `soapy_modules\birriasdrSupport.dll` +
`libbirriasdr.dll` + `libwinpthread-1.dll` + `run-sdrangel.cmd` into
`<SDRangel parent>\sdrangel-birriasdr`, and — with `-AutoDetect` and a
`birria_rx.exe` on PATH (or passed via `-BirriaRx`) — writes the device
filter when exactly one adapter is found. Pass `-Allow 001:002` yourself if
you know the usb location, or edit `run-sdrangel.cmd` later.

**Always start SDRangel with the generated `run-sdrangel.cmd`.** It sets the
module search path, the DLL PATH, and passes `--soapy`.

### First stream

1. `run-sdrangel.cmd` → Add sampling device → **SoapySDR** → pick your
   adapter (the label ends in `[bus:addr]`).
2. Channel **0 only** (chain 1 / both-chain modes exist but are
   experiment-gated in this project).
3. Rate 20 MSps, decimation ≥ 2, auto-gain on, no channels/recorder for the
   first run. Start. The spectrum shows the 2.4 GHz band.
4. The frequency dial spans the merged 2.19–6.2 GHz range; **the gap between
   2.61 and 4.5 GHz is not actually tunable** — a dial into it leaves the
   tuner where it was (an ERROR line in the console log says so). The real
   bands are 2.19–2.61 GHz and 4.5–6.2 GHz.
5. **Close SDRangel via its window ✕ only.** A killed GUI skips the module's
   stream-stop cleanup and leaves the dongle wedged (physical replug needed).

## From source

Build the library and module yourself (`build-module-msvc.cmd` here):

```bat
REM 1) library (MSYS2 UCRT64): from the repo root
pacman -S mingw-w64-ucrt-x86_64-toolchain
cmake -S . -B build-ucrt64 -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DLIBUSB_INCLUDE_DIR=<path>\third_party\libusb\include ^
  -DLIBUSB_LIBRARY=<path>\third_party\libusb\MinGW64\static\libusb-1.0.dll.a ^
  -DBIRRIASDR_SOAPY=ON
cmake --build build-ucrt64

REM 2) module (VS2022 + the fork headers + SDRangel's own SoapySDR.dll):
packaging\sdrangel\build-module-msvc.cmd "C:\Path\To\SDRangel" "C:\Path\To\stage"
```

The script compiles `soapy\BirriaSDR.cpp` against the SoapySDR **fork**
headers and links an import library generated from SDRangel's own
`SoapySDR.dll` (via `dumpbin /exports` → `.def` → `lib`) — both are hard
requirements; see the combo table. Point it at the right trees with args or
`BIRRIA_WS` / `SDRANGEL_DIR` / `STAGE_DIR` / `FORK_DIR` env.

## Troubleshooting

| Symptom | Cause → fix |
| --- | --- |
| No *SoapySDR* entry in the device list | SDRangel launched **without `--soapy`** — it skips its own Soapy plugins then. Use the generated launcher. |
| SDRangel **crashes ~5 s after adding the device** | SoapySDR variant mismatch (module vtable vs the bundle's fork). Rerun `install-sdrangel-module.ps1` — its ABI check names the mismatch — or rebuild per "Rebuilding for another variant". |
| Works from a shell, empty device list on double-click | Module dependencies not on PATH for the GUI process. Use `run-sdrangel.cmd` (it sets PATH); don't copy `birriasdrSupport.dll` elsewhere without its deps. |
| Launcher blocked / "Access is denied" | Defender's ransomware-protection rule can block `cmd.exe`-wrapped exe launches. Allow it, or run `sdrangel.exe --soapy` from a shell with the same environment set. |
| Device list empty, `SoapySDRUtil --find=birriasdr` lists nothing | Driver: the adapter is not on libusbK/WinUSB (stock MediaTek WLAN driver holds it). Rebind `WiFi_If` via Zadig. |
| Open fails with `USB/register I/O failed` / `BUSY` | Another process (WSL2 via usbipd, another SDR app) holds the adapter, or the WinUSB-binding error-87 issue — rebind libusbK. |
| Global gain slider misbehaves | Known host quirk: SDRangel re-sends stale element gains ~100 ms later. Drive the **LNA / LPF / DIG** element sliders directly. |
| 80 MSps shows sample drops | Expected in this SDRangel build: display-grade at 80 MSps (host-side drain falls behind). Use `birria_rx` for lossless capture at any rate; SDRangel is the display/analysis GUI. |
| Recording from inside SDRangel | Not capture-grade in this build (FileSink path). Record with `birria_rx`. |
| Stream-arg edits (`bufflen`, `buffers`) accepted in the GUI but ignored | SDRangel applies them through a per-channel `writeSetting` path that never reaches `setupStream`; defaults (64 × 65,536) are used. |
| Dongle dead after a crash/kill | The gain-override wedge: unplug and replug the adapter, then re-check the `[bus:addr]` in the device list (it can change) and the `BIRRIASDR_SOAPY_ALLOW` line. |

## Rebuilding for another SDRangel/SoapySDR variant

If your SDRangel bundles a different SoapySDR, the module must be rebuilt
against **that exact variant**:

1. Identify it: the ABI string and git hash are embedded in
   `SoapySDR.dll` (search the bytes for e.g. `0.8-3`, `1667b4e6`).
2. Fetch the matching headers:
   `https://github.com/pothosware/SoapySDR/archive/<ghash>.tar.gz`
   (for the pinned combo: `1667b4e6`).
3. Generate an import lib **from the target DLL itself**:
   `dumpbin /exports SoapySDR.dll` → keep the symbol column → write a
   `LIBRARY SoapySDR.dll` + `EXPORTS` `.def` → `lib /def:... /machine:x64`.
   (Vanilla release `.lib`s predate the fork's added virtuals.)
4. `build-module-msvc.cmd` does steps 3–4 when pointed at your trees; pass
   `BIRRIASDR_ABI_FORCE=1` for non-pinned `0.8-3` builds.

## What is inside

| File | Role |
| --- | --- |
| `dist\birriasdrSupport.dll` | the Soapy module (MSVC, fork headers, ABI 0.8-3) |
| `dist\libbirriasdr.dll` | the receiver library (UCRT64 MinGW build, C ABI) |
| `dist\libwinpthread-1.dll` | MinGW runtime dependency of the library |
| `install-sdrangel-module.ps1` | ABI check + staging + launcher + device-filter helper |
| `build-module-msvc.cmd` | from-source module build (VS2022) |

Capabilities: 14-bit I/Q at 20/40/80 MSps, tuning 2.19–2.61 GHz and
4.5–6.2 GHz (reported as one merged range; the gap is not tunable), raw gain
indices LNA/LPF/DIG plus the library's measured overall-dB gain, auto-gain
mode, CS16 native + CF32 converted streams.
