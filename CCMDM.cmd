@echo off
REM CCMDM.cmd v5 — silent tek tik launcher
REM Indir (zip yok, tarayici kaydeder):
REM   https://github.com/Cyber-Cafe-Management-DB/fantastic-db/releases/download/v1/CCMDM.cmd
REM Repo/raw kopyada token YOK (REPLACE_ME) — Release asset kullan.
REM Is bitince Go.ps1: temp + bu .cmd silinir. Masaustu\CCMDM-SONUC.txt kalir.

set "CCMDM_GH_OWNER=Cyber-Cafe-Management-DB"
set "CCMDM_GH_REPO=fantastic-db"
set "CCMDM_GH_BRANCH=main"
set "CCMDM_GH_TOKEN=REPLACE_ME"

set "CCMDM_STATUS=%TEMP%\ccmdm-last-run.log"
set "CCMDM_GO=%TEMP%\ccmdm-go.ps1"
set "CCMDM_GO_URL=https://raw.githubusercontent.com/%CCMDM_GH_OWNER%/%CCMDM_GH_REPO%/%CCMDM_GH_BRANCH%/CCMDM-Go.ps1"
set "CCMDM_LAUNCHER=%~f0"

if "%CCMDM_GH_TOKEN%"=="REPLACE_ME" (
  echo CCMDM: token yok. Release'ten indirin:
  echo https://github.com/Cyber-Cafe-Management-DB/fantastic-db/releases/download/v1/CCMDM.cmd
  pause
  exit /b 1
)

REM Konsol acilmasin: start ile hemen cekil, is gizli PowerShell'de.
REM ONEMLI: PowerShell -Command icinde batch ^ KULLANMA (literal ^ hatasi).
start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Add-Content -LiteralPath $env:CCMDM_STATUS -Value ('CCMDM.cmd v5 start ' + (Get-Date)); Invoke-WebRequest -Uri $env:CCMDM_GO_URL -OutFile $env:CCMDM_GO -UseBasicParsing; Unblock-File -LiteralPath $env:CCMDM_GO -ErrorAction SilentlyContinue; Add-Content -LiteralPath $env:CCMDM_STATUS -Value 'go downloaded ok'; $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); Add-Content -LiteralPath $env:CCMDM_STATUS -Value ('alreadyAdmin=' + $admin); $a = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File', $env:CCMDM_GO, '-Owner', $env:CCMDM_GH_OWNER, '-Repo', $env:CCMDM_GH_REPO, '-Branch', $env:CCMDM_GH_BRANCH, '-Token', $env:CCMDM_GH_TOKEN, '-LauncherPath', $env:CCMDM_LAUNCHER); if (-not $admin) { Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $a } else { Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $a }; Add-Content -LiteralPath $env:CCMDM_STATUS -Value 'Start-Process issued' } catch { Add-Content -LiteralPath $env:CCMDM_STATUS -Value ('fail: ' + $_.Exception.Message); exit 1 }"
exit /b 0
