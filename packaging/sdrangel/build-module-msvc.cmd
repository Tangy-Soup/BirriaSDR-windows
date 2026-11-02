@echo off
REM Build birriasdrSupport.dll with MSVC for an SDRangel 8.0.0 bundle and
REM stage module + MinGW deps + launcher. From-source path for
REM packaging/sdrangel/ (see README.md there); the workspace-local
REM tools/build_sdrangel_module_msvc.cmd is the fixed-path equivalent this
REM was de-hardcoded from - keep the recipes in sync on purpose.
REM
REM SDRangel bundles a SoapySDR FORK (v0.8.1-g1667b4e6, ABI "0.8-3") whose
REM Device class adds two getSettingInfo overloads, shifting every later
REM vtable slot. The module must be compiled against THAT tree's headers and
REM linked against an import lib generated from SDRangel's own SoapySDR.dll -
REM both done below. A module built against vanilla 0.8.1 headers misdispatches
REM and crashes the app ~5 s after add-device.
REM
REM Usage: build-module-msvc.cmd [SDRangelDir] [StageDir] [ForkTree] [SoapyMsvc]
REM   SDRangelDir  bundle root with sdrangel.exe + SoapySDR.dll
REM   StageDir     output staging (created; module in StageDir\soapy_modules)
REM   ForkTree     SoapySDR fork source root (include\SoapySDR\Version.h)
REM   SoapyMsvc    optional MSVC SoapySDR install, for SoapySDRUtil.exe copy
REM Env overrides (args win): BIRRIA_WS, SDRANGEL_DIR, STAGE_DIR, FORK_DIR,
REM   SOAPY_MSVC_DIR, LIBWINPTHREAD, BIRRIASDR_ALLOW_DEFAULT (usb location
REM   filter written into the launcher; unset = filter left commented),
REM   BIRRIASDR_ABI_FORCE=1 (proceed despite a non-pinned fork hash).
REM Needs VS2022 (vcvars64) and a UCRT64 build of this repo (build-ucrt64\
REM with libbirriasdr.dll; MSYS2: pacman -S mingw-w64-ucrt-x86_64-toolchain).
setlocal enabledelayedexpansion
set REPO=%~dp0..\..
for %%i in ("%REPO%") do set REPO=%%~fi

if not "%~1"=="" (set SDRANGEL=%~1) else if defined SDRANGEL_DIR (set SDRANGEL=%SDRANGEL_DIR%) else if defined BIRRIA_WS (set SDRANGEL=%BIRRIA_WS%\downloads\SDRangel) else (set SDRANGEL=)
if not "%~2"=="" (set STAGE=%~2) else if defined STAGE_DIR (set STAGE=%STAGE_DIR%) else if defined BIRRIA_WS (set STAGE=%BIRRIA_WS%\downloads\sdrangel_soapy) else (set STAGE=)
if not "%~3"=="" (set FORK=%~3) else if defined FORK_DIR (set FORK=%FORK_DIR%) else if defined BIRRIA_WS (set FORK=%BIRRIA_WS%\downloads\soapy_fork_1667b4e6\SoapySDR-1667b4e6301d7ad47b340dcdcd6e9969bf57d843) else (set FORK=)
if not "%~4"=="" (set SOAPY=%~4) else if defined SOAPY_MSVC_DIR (set SOAPY=%SOAPY_MSVC_DIR%) else if defined BIRRIA_WS (set SOAPY=%BIRRIA_WS%\downloads\soapy_msvc_build\install) else (set SOAPY=)

for %%p in ("%SDRANGEL%\sdrangel.exe" "%SDRANGEL%\SoapySDR.dll" "%FORK%\include\SoapySDR\Version.h" "%REPO%\build-ucrt64\libbirriasdr.dll" "%REPO%\soapy\BirriaSDR.cpp") do if not exist %%p (
  echo ERROR: missing %%p - pass SDRangelDir/StageDir/ForkTree args or BIRRIA_WS/SDRANGEL_DIR/FORK_DIR env.
  exit /b 1
)

REM ABI gate: the staging pairs with the pinned fork combo only.
findstr /m /C:"0.8-3" "%SDRANGEL%\SoapySDR.dll" >nul || (
  echo ERROR: %SDRANGEL%\SoapySDR.dll is not ABI 0.8-3 - this recipe builds the
  echo fork-header module only. See README.md "Rebuilding for another variant".
  exit /b 1
)
findstr /m /C:"1667b4e6" "%SDRANGEL%\SoapySDR.dll" >nul || (
  echo WARNING: SoapySDR.dll says 0.8-3 but not g1667b4e6 - vtable may differ
  echo from the pinned combo. Set BIRRIASDR_ABI_FORCE=1 to proceed anyway.
  if not defined BIRRIASDR_ABI_FORCE exit /b 1
)
findstr /C:"0.8-3" "%FORK%\include\SoapySDR\Version.h" >nul || (
  echo ERROR: %FORK% headers are not the 0.8-3 fork tree.
  exit /b 1
)

call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 exit /b 1

set BLD=%STAGE%\build
mkdir "%BLD%" 2>nul
mkdir "%STAGE%\soapy_modules" 2>nul

REM Import library for the MinGW-built libbirriasdr.dll (pure C exports),
REM generated fresh from the DLL's export table - works across compilers.
dumpbin /exports "%REPO%\build-ucrt64\libbirriasdr.dll" > "%BLD%\exports_raw.txt"
if errorlevel 1 exit /b 1
(
echo LIBRARY libbirriasdr.dll
echo EXPORTS
for /f "tokens=4" %%a in ('findstr /r /c:"^ *[0-9][0-9]* " "%BLD%\exports_raw.txt"') do echo %%a
) > "%BLD%\birriasdr.def"
lib /nologo /def:"%BLD%\birriasdr.def" /machine:x64 /out:"%BLD%\birriasdr.lib"
if errorlevel 1 exit /b 1

REM Import lib generated from SDRangel's OWN SoapySDR.dll: the fork added two
REM getSettingInfo overloads whose base impls must be imported, and any vanilla
REM 0.8.1 SoapySDR.lib predates them. This lib matches the runtime exactly.
dumpbin /exports "%SDRANGEL%\SoapySDR.dll" > "%BLD%\soapy_exports_raw.txt"
if errorlevel 1 exit /b 1
(
echo LIBRARY SoapySDR.dll
echo EXPORTS
for /f "tokens=4" %%a in ('findstr /r /c:"^ *[0-9][0-9]* " "%BLD%\soapy_exports_raw.txt"') do echo %%a
) > "%BLD%\SoapySDR.def"
lib /nologo /def:"%BLD%\SoapySDR.def" /machine:x64 /out:"%BLD%\SoapySDR_sdrangel.lib"
if errorlevel 1 exit /b 1

REM The Soapy module: same compiler AND same SoapySDR header layout as the host.
cl /nologo /std:c++17 /EHsc /MD /O2 /LD ^
  "%REPO%\soapy\BirriaSDR.cpp" ^
  /I"%REPO%\include" /I"%FORK%\include" ^
  /Fe:"%STAGE%\soapy_modules\birriasdrSupport.dll" ^
  /Fo"%BLD%\\" /Fd"%BLD%\\" ^
  /link "%BLD%\SoapySDR_sdrangel.lib" "%BLD%\birriasdr.lib"
if errorlevel 1 exit /b 1

REM Module runtime deps (staging root; resolved via the launcher's PATH).
REM libwinpthread-1.dll is the Explorer-launch killer: without it on PATH,
REM libbirriasdr.dll silently fails to load. Source: env override, the UCRT64
REM toolchain that built the library, or the legacy SDR++ zip copy.
copy /y "%REPO%\build-ucrt64\libbirriasdr.dll" "%STAGE%\" >nul
if errorlevel 1 exit /b 1
set PTHREAD=
if defined LIBWINPTHREAD if exist "%LIBWINPTHREAD%" set PTHREAD=%LIBWINPTHREAD%
if not defined PTHREAD for %%d in ("C:\msys64\ucrt64\bin" "D:\msys64\ucrt64\bin") do if not defined PTHREAD if exist "%%~d\libwinpthread-1.dll" set PTHREAD=%%~d\libwinpthread-1.dll
if not defined PTHREAD if defined BIRRIA_WS if exist "%BIRRIA_WS%\downloads\sdrpp_v1.1.0\sdrpp104\sdrpp_windows_x64\libwinpthread-1.dll" set PTHREAD=%BIRRIA_WS%\downloads\sdrpp_v1.1.0\sdrpp104\sdrpp_windows_x64\libwinpthread-1.dll
if not defined PTHREAD (
  echo ERROR: libwinpthread-1.dll not found - set LIBWINPTHREAD to its path.
  exit /b 1
)
copy /y "%PTHREAD%" "%STAGE%\" >nul
if errorlevel 1 exit /b 1

REM Optional probe host: run with the SDRangel root on PATH so it binds the
REM bundle's own SoapySDR.dll. Skip quietly when the MSVC SoapySDR is absent.
if defined SOAPY if exist "%SOAPY%\bin\SoapySDRUtil.exe" copy /y "%SOAPY%\bin\SoapySDRUtil.exe" "%STAGE%\" >nul

REM Launcher: module search path, deps PATH, mandatory --soapy. The device
REM filter hides every adapter except the allowed usb location; single-adapter
REM hosts can leave it commented. Value format matches the device label's
REM [bus:addr] suffix (three digits each); re-check after any replug.
(
echo @echo off
echo REM BirriaSDR -^> SDRangel launcher, generated by build-module-msvc.cmd.
echo set SOAPY_SDR_PLUGIN_PATH=%%~dp0soapy_modules
if defined BIRRIASDR_ALLOW_DEFAULT (echo set BIRRIASDR_SOAPY_ALLOW=%BIRRIASDR_ALLOW_DEFAULT%) else (echo REM set BIRRIASDR_SOAPY_ALLOW=bus:addr)
echo set PATH=%%~dp0;%SDRANGEL%;%%PATH%%
echo REM --soapy is mandatory: SDRangel skips its Soapy plugins without it
echo start "" "%SDRANGEL%\sdrangel.exe" --soapy
) > "%STAGE%\run-sdrangel.cmd"
if errorlevel 1 exit /b 1

echo BUILD OK
echo Staging: %STAGE%
dir /b "%STAGE%\soapy_modules"
dir /b "%STAGE%"
