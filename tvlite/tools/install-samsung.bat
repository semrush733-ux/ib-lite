@echo off
rem ============================================================================
rem  IBO Lite Player - put the newest Samsung TV build on your TV (one click)
rem
rem  Double-click this file. It downloads the newest LitePlayer.wgt from GitHub,
rem  signs it with your Samsung certificate profile and installs it on the TV.
rem
rem  Needs: Tizen Studio in C:\tizen-studio, the certificate profile "ibolite",
rem         the TV on, in Developer Mode, with this PC's IP as "Host PC IP".
rem  Change the lines below if the TV gets another IP or you use another profile.
rem ============================================================================
setlocal
set TIZEN=C:\tizen-studio
set PROFILE=ibolite
set TV_IP=192.168.1.112
set APP_ID=pv1QB2aTAP.LitePlayer
set FOLDER=C:\tv
set URL=https://github.com/semrush733-ux/ib-lite/releases/download/tizen-latest/LitePlayer.wgt

if not exist %FOLDER% mkdir %FOLDER%
cd /d %FOLDER%

echo.
echo [1/4] Downloading the newest Samsung build ...
rem The old file goes first, so an old build can never be installed again by mistake.
if exist LitePlayer.wgt del /f /q LitePlayer.wgt
if exist LitePlayer.wgt (
  echo The old LitePlayer.wgt in %FOLDER% could not be deleted. Close Tizen Studio and try again.
  goto fail
)
curl -L --fail -H "Cache-Control: no-cache" -o LitePlayer.wgt "%URL%"
if errorlevel 1 goto fail
if not exist LitePlayer.wgt goto fail
set VER=
for /f "tokens=2 delims=:, " %%v in ('tar -xOf LitePlayer.wgt js/config.js 2^>nul ^| findstr version') do set VER=%%~v
if "%VER%"=="" set VER=unknown
echo.
echo     Downloaded: IBO Lite Player version %VER%

echo.
echo [2/4] Signing it with the certificate "%PROFILE%" ...
call %TIZEN%\tools\ide\bin\tizen.bat package -t wgt -s %PROFILE% -- %FOLDER%\LitePlayer.wgt

echo.
echo [3/4] Connecting to the TV at %TV_IP% ...
%TIZEN%\tools\sdb.exe connect %TV_IP%
set TV=
for /f "tokens=3" %%d in ('%TIZEN%\tools\sdb.exe devices ^| findstr /b /c:"%TV_IP%"') do set TV=%%d
if "%TV%"=="" (
  echo The TV was not found. Check: TV on, Developer Mode ON, Host PC IP = this PC, same Wi-Fi.
  goto fail
)

echo.
echo [4/4] Installing on %TV% ...
call %TIZEN%\tools\ide\bin\tizen.bat install -n LitePlayer.wgt -t %TV% -- %FOLDER%
call %TIZEN%\tools\ide\bin\tizen.bat run -p %APP_ID% -t %TV%

echo.
echo Done: IBO Lite Player %VER% is on the TV and opening now.
echo On the TV: Settings shows "Version %VER%" on the left.
pause
exit /b 0

:fail
echo.
echo Something went wrong - see the lines above.
pause
exit /b 1
