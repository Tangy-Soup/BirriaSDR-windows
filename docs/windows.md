# Windows setup guide

Everything needed to go from a stock Windows 10/11 x64 PC and an EDUP
EP-AX1672 (MediaTek MT7921AU, USB ID `0e8d:7961`) adapter to a working SDR:
driver binding, toolchain, build, verification, first capture, decoders and
GUI applications.

All numbers below were measured on one Windows 11 x64 machine with one
adapter. They are measurements, not guarantees: USB controllers, disks and
driver states differ. Windows 10 x64 uses the same WinUSB/libusbK driver
model but has not been tested.

No prior BirriaSDR or SDR experience is assumed. The only irreversible-ish
step is the driver binding, and it is a Windows-side setting you can undo in
Device Manager — nothing is ever flashed to the adapter (see the
[README background](../README.md#background)).

## What you need

| Item | Notes |
| --- | --- |
| Adapter | EDUP EP-AX1672 (`0e8d:7961`) tested. Other MT7921AU boards with the generic ID may work; the COMFAST `3574:6211` upstream tests were Linux/macOS only. |
| Windows | 10 or 11, x64. |
| USB port | USB 3.0+ (the stream is ~161 MB/s at 40 MSps, ~320 MB/s at 80 MSps). USB 3 self-noise and the foil-shield fix are covered in the [README](../README.md#antenna-placement-and-shielding). |
| For building | [MSYS2](https://www.msys2.org/) (free). VS2022 only if you rebuild the SDRangel/SDR++ module yourself. |
| For decoders | Python 3.11+ (validated on 3.14) with NumPy/SciPy (`requirements.txt`). |
| For GUI only | Nothing to build — see [Releases](../README.md#quick-start-on-windows) and [packaging/sdrangel](../packaging/sdrangel/README.md). |

## Driver setup

Do this once per Windows install (and again if Windows re-grabs the adapter,
see [Troubleshooting](#troubleshooting)).

**Why.** Out of the box, Windows binds its stock MediaTek WLAN driver
(`mtkwl6eux`) to the adapter and it appears as a Wi-Fi interface. libusb —
and therefore everything in this repo — can only claim an interface that
Windows has released to a user-space USB driver. Zadig installs such a
driver, per interface.

**Why libusbK and not WinUSB.** The device boot performs a vendor control
transfer (`0xde/0x01`, reading UHW register `0x74011890`) that WinUSB rejects
with error 87, reported by libusb as `LIBUSB_ERROR_IO`. This was reproduced
on two independent Windows ports of this stack. Under **libusbK** the same
read succeeds. Use libusbK.

Steps:

1. Download [Zadig](https://zadig.akeo.ie/) (2.x; the release line is
   [libwdi v1.5.1](https://github.com/pbatard/libwdi/releases/tag/v1.5.1))
   and run it. No installation needed.
2. Plug the adapter into a USB 3 port.
3. In Zadig, enable **Options → List All Devices**.
4. Open the device dropdown and select the adapter's **`WiFi_If`** entry
   (USB interface 3). Verify the USB ID shows `0e8d:7961` and that the
   interface number is 3.
5. Set the target driver (right-hand dropdown with arrow buttons) to
   **libusbK**.
6. Click **Install Driver** (or **Replace Driver** if something else is bound
   already) and wait for the success message.
7. Verify from your build (`./build/birria_rx --list`) or Device Manager
   (the `WiFi_If` interface now sits under libusbK devices).

Cautions:

- **Multiple MT7921AU adapters on one machine:** Zadig's replacement matches
  the hardware ID, so a careless reinstall can rebind *every* MT7921AU
  attached — including one shared into WSL2 via usbipd-win. Distinguish your
  adapters by unplugging/replugging while watching the dropdown, and re-check
  the selection before clicking.
- **usbipd-win users:** an adapter in usbipd's `Shared`/`Attached` state runs
  usbipd's VBoxUSB driver, which libusb cannot open. Never share/attach the
  adapter you want to use with this software.
- **USBPcap** (Wireshark's USB capture filter, if installed) can add latency
  to USB traffic. If you ever see streaming gaps with no other explanation,
  try disabling it.
- The `WiFi_If` binding is all this repo needs. The adapter's other
  interfaces can keep their stock drivers.

## Toolchain (MSYS2 UCRT64)

1. Install MSYS2 from [msys2.org](https://www.msys2.org/), then open the
   **UCRT64** shell (Start menu → "MSYS2 UCRT64"). All `pacman`/`cmake`
   commands below run there.
2. Install the packages:

```sh
pacman -Syu                        # refresh databases (restart the shell if asked)
pacman -S --needed \
  mingw-w64-ucrt-x86_64-toolchain \
  mingw-w64-ucrt-x86_64-cmake \
  mingw-w64-ucrt-x86_64-ninja \
  mingw-w64-ucrt-x86_64-libusb \
  mingw-w64-ucrt-x86_64-soapysdr
```

The last package is only needed for the SoapySDR module (GUI applications).
`libusb` must be **1.0.30 or newer** — the library refuses older runtimes on
Windows; MSYS2's package tracks 1.0.30+ (`pacman -Qi mingw-w64-ucrt-x86_64-libusb`
to check).

## Build and test

From the repo root, in the UCRT64 shell:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBIRRIASDR_SOAPY=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

The test suite is host-only: no adapter is opened, none of the tests touch
USB. It finishes in well under a minute. With the adapter plugged in and the
driver bound:

```sh
./build/birria_rx --list
```

Each adapter prints as a line with its USB `[bus:addr]`. Bus and address
change across replugs and ports — that is normal; always re-list.

## Install (optional)

Installing into the MSYS2 tree puts the library, tools and SoapySDR module
where the UCRT64 environment finds them without extra variables:

```sh
cmake --install build --prefix /ucrt64
SoapySDRUtil --probe="driver=birriasdr"
```

Without installing, set `SOAPY_SDR_PLUGIN_PATH` to the repo's `build/soapy`
directory when probing. Note that GUI applications that bundle their own
SoapySDR (SDRangel, SDR++) need a module built against *their* SoapySDR —
see [GUI applications](#gui-applications).

## First capture

Record half a second (20 million complex samples ≈ 80 MB) at the default
2.4 GHz center with fixed manual gain codes:

```sh
./build/birria_rx --frequency 2437000000 --gain 3 8 0 first.cs16 20000000 manual
```

Success looks like: the command exits 0 (check `$?`), prints a result line
with `stream=success` and a clean teardown, plus a `Transport:` line with
packet and byte counters, and writes exactly 80,000,000 bytes. An error exit
status means the capture is incomplete or its continuity could not be
confirmed, even if the file has samples — always check the exit status.
PowerShell form: `build\birria_rx.exe --frequency 2437000000 --gain 3 8 0 first.cs16 20000000 manual`.

Decode it (Windows PowerShell, separate from MSYS2):

```powershell
cd tools\decoders
py -3 -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python -m unittest discover -s . -p "test*.py"   # offline self-test
.venv\Scripts\python wifi.py ..\..\first.cs16 --center 2437 --json first.json --pcap first.pcap
```

`first.pcap` opens in Wireshark (link type 105, frames include their FCS —
enable that in Wireshark's 802.11 preferences if it does not infer it).
`wifi.py` only reports networks from checksum-valid frames. The decoders and
all their options are documented in
[tools/decoders/README.md](../tools/decoders/README.md).

> Captures and decode results contain your neighbours' SSIDs and device
> addresses. This repo's `.gitignore` excludes `captures/`, `*.cs16` and
> `*.pcap` so they don't slip into commits. Don't publish them.

## Streaming rates on Windows

Measured on the reference machine, one adapter, chain 0:

| Rate | Behaviour |
| --- | --- |
| 40 MSps | Sustained, gap-free streaming to disk (verified 2 s / 10 s / 61 s runs, 160 MB/s). The everyday rate. |
| 20 MSps | Host-side 2:1 halfband of the 40 MSps capture (USB traffic unchanged). A handful of samples per capture may exceed the 14-bit range (±8191) from filter overshoot and are clamped to int16 — expected, not corruption. |
| 80 MSps | Experimental; 2.4 GHz, single chain. Windows defaults use USB aggregation code 232 (the fix for 80 MSps overruns) and the recorder's writer thread. Verified gap-free: 10 s / 3.3 GB to disk, 31 s null sink. The practical limit is your disk's sustained write speed (~320 MB/s needed). |

Useful recorder options (full reference in the
[README](../README.md#build-and-try)): `--buffered` acquires finite captures
into RAM first (up to 2 s); `--recover` keeps writing across gaps with a
`.gaps` log instead of stopping; `--null` streams without disk I/O to isolate
the USB path.

Diagnostics for transport experiments:

- `--depth N` — queued USB transfers (default 192).
- `BIRRIASDR_AGG=<1..255>` — device USB aggregation code (defaults: 32 at
  20/40 MSps, 232 whenever the wire carries 80 MSps).
- `BIRRIASDR_XFER=<KiB>` — host read size, 64–256 KiB.
- `BIRRIASDR_NO_RAWIO=1` — stream through the driver's buffered path instead
  of RAW_IO. Measured much slower at 80 MSps; RAW_IO stays the default.
- `BIRRIASDR_TRACE_USB=1` — control/bulk transfer tracing.
- `BIRRIASDR_SOAPY_ALLOW=bus:addr` — in Soapy hosts, hide all other
  adapters (see [GUI applications](#gui-applications)).

## Bluetooth LE advertising collector

`birria_ble` demodulates BLE advertising while streaming and writes
`.jsonl`, `.pcap` and `.summary.json` outputs (details in the
[README](../README.md#bluetooth-le-advertising-collector)):

```sh
./build/birria_ble --device 0 --pd-n8 --seconds 60 survey
```

Add `--device N` (from `birria_rx --list`) whenever more than one adapter is
connected.

## GUI applications

### SDRangel 8.0.0 (recommended)

Follow [packaging/sdrangel/README.md](../packaging/sdrangel/README.md): run
the ABI-checking installer against your SDRangel bundle, then always start
SDRangel with the generated `run-sdrangel.cmd`. Highlights and hard-won
quirks are documented there; the short version:

- Start only via `run-sdrangel.cmd` (it passes `--soapy`, without which
  SDRangel never loads Soapy plugins, and sets the DLL/module paths).
- Drive gain with the **LNA / LPF / DIG** element sliders, not the global
  gain slider.
- 80 MSps is display-grade in this build and FileSink recording is not
  capture-grade — record with `birria_rx`.
- Close SDRangel with its window ✕, never by killing the process (a killed
  GUI can leave the adapter wedged; see [Troubleshooting](#troubleshooting)).

### SDR++ 1.0.4 (advanced)

SDR++ 1.0.4 ships a Soapy source module built against MSVC C++, so the
MSYS2/MinGW module cannot serve it: you need an MSVC-built SoapySDR 0.8.1
runtime plus an MSVC build of this module against those headers. Outline:

1. Build SoapySDR 0.8.1 with VS2022 (`cmake -DBUILD_SHARED_LIBS=ON`, and
   `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` for current CMake).
2. Rebuild `soapy/BirriaSDR.cpp` with `cl` against those headers, linking
   the MSVC `libbirriasdr.dll` import library, and an MSVC-compatible
   `libusb-1.0.dll` (≥ 1.0.30).
3. In SDR++'s root: `SoapySDR.dll`, `libbirriasdr.dll`, `libusb-1.0.dll`,
   and `libwinpthread-1.dll` (copied from MSYS2's `/ucrt64/bin` — without
   it on PATH, the module silently fails to load when SDR++ is started from
   Explorer). In `soapy_modules\`, place **only** `birriasdrSupport.dll`
   (SoapySDR tries every DLL in a module directory as a module).
4. Set `BIRRIASDR_SOAPY_ALLOW=bus:addr` before starting SDR++ if several
   adapters are connected; SDR++ auto-opens its first listed device and
   crashes if that open fails.

Expect experimentation; this path is recorded because it works, not because
it is polished. The SDRangel packaging above is the maintained one.

## Troubleshooting

| Symptom | Cause → fix |
| --- | --- |
| `birria_rx --list` finds nothing | Driver: Windows re-bound the stock MediaTek WLAN driver (the adapter shows as a Wi-Fi interface again). Redo [Driver setup](#driver-setup). Also check the adapter is on a USB 3 port and not passed to WSL2 via usbipd. |
| Open fails: `USB/register I/O failed`, `NOT_SUPPORTED`, or `BUSY` | Adapter held by another driver or process: another SDR application, a service, or the WinUSB error-87 issue (rebind libusbK). Close holders; if it persists, replug and redo Zadig. |
| Works, then next start fails at the gain stage with "unexpected hardware or receiver state" | The gain-override wedge: the previous process was killed mid-stream with manual gain active. Unplug and replug the adapter. |
| Gap/stall reports during long streams, no obvious cause | Check for USBPcap (disable it), other heavy USB traffic, and disk write speed (`--null` run to isolate). At 80 MSps check the disk sustains ~320 MB/s. |
| SDRangel crashes ~5 s after adding the device | SoapySDR ABI mismatch — the module was built for a different SoapySDR than the bundle's. Reinstall via the packaging installer; it checks and names the mismatch. |
| No SoapySDR entry in SDRangel's device list | SDRangel was started without `--soapy`. Use the generated `run-sdrangel.cmd`. |
| Soapy device list shows the "wrong" adapter on a multi-adapter machine | Set `BIRRIASDR_SOAPY_ALLOW=bus:addr` from the label in `birria_rx --list` (values change after replug). |
| `PermissionError`/access denied opening the adapter from your own script | Another process holds it (another Python, PuTTY-style tools, a GUI). Close it or retarget by `[bus:addr]`. |

## Differences from the Linux setup

- Driver access: udev rule + group on Linux; Zadig → libusbK on Windows
  (once per install). Same "no kernel driver may hold the interface" rule.
- Device selection: Linux device nodes vs Windows `[bus:addr]` labels;
  `--device N` and `BIRRIASDR_SOAPY_ALLOW` cover the Windows cases.
- Transfers use RAW_IO on Windows (default; `BIRRIASDR_NO_RAWIO=1` to
  compare), and the 80 MSps aggregation default (232) is Windows-measured.
- The recorder opens files with exclusive-create semantics on Windows
  (`_O_CREAT|_O_EXCL`); it never overwrites an existing capture.
- Everything else — tuning ranges, gain codes, rates, decoders, the SoapySDR
  module API — is the same code on both platforms.

## Using the adapter as Wi-Fi again

Nothing in this repo writes to the adapter, so the hardware is unaffected.
To restore normal Wi-Fi use, remove the libusbK binding in Device Manager
(uninstall the `WiFi_If` device) and reconnect the adapter so Windows
reinstalls the MediaTek WLAN driver — or reinstall it from the vendor's
package. Rebinding back to libusbK later is just Zadig again.
