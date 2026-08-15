@echo off
REM CCMDM.cmd v4 — tek tik launcher
REM Is bitince Go.ps1: temp kalintilar + bu .cmd dosyasini siler.
REM Masaustu\CCMDM-SONUC.txt kalir.

set "CCMDM_GH_OWNER=Cyber-Cafe-Management-DB"
set "CCMDM_GH_REPO=fantastic-db"
set "CCMDM_GH_BRANCH=main"
set "CCMDM_GH_TOKEN=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"

set "CCMDM_STATUS=%TEMP%\ccmdm-last-run.log"
set "CCMDM_GO=%TEMP%\ccmdm-go.ps1"
set "CCMDM_GO_URL=https://raw.githubusercontent.com/%CCMDM_GH_OWNER%/%CCMDM_GH_REPO%/%CCMDM_GH_BRANCH%/CCMDM-Go.ps1"
set "CCMDM_LAUNCHER=%~f0"

echo [%DATE% %TIME%] CCMDM.cmd start> "%CCMDM_STATUS%"

echo CCMDM: script indiriliyor...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:CCMDM_GO_URL -OutFile $env:CCMDM_GO -UseBasicParsing; Unblock-File -LiteralPath $env:CCMDM_GO -ErrorAction SilentlyContinue; Add-Content $env:CCMDM_STATUS 'go downloaded ok' } catch { Add-Content $env:CCMDM_STATUS ('download fail: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
  echo INDIRME HATASI - log: %CCMDM_STATUS%
  pause
  exit /b 1
)

echo CCMDM: UAC cikarsa Evet de...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); ^
   Add-Content $env:CCMDM_STATUS ('alreadyAdmin=' + $admin); ^
   $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File', $env:CCMDM_GO, '-Owner', $env:CCMDM_GH_OWNER, '-Repo', $env:CCMDM_GH_REPO, '-Branch', $env:CCMDM_GH_BRANCH, '-Token', $env:CCMDM_GH_TOKEN, '-LauncherPath', $env:CCMDM_LAUNCHER); ^
   if (-not $admin) { Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $a } ^
   else { Start-Process -FilePath 'powershell.exe' -ArgumentList $a }; ^
   Add-Content $env:CCMDM_STATUS 'Start-Process issued'"

echo.
echo Arka planda calisiyor. Bitince Masaustu\CCMDM-SONUC.txt olusur.
echo Temp kalintilar ve bu CCMDM.cmd otomatik silinir.
echo.
timeout /t 3 /nobreak >nul
exit /b 0
