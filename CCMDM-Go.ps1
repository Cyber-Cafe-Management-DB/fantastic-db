# CCMDM-Go.ps1 v5 — Export + izsiz temizlik (temp, launcher, Desktop, Downloads)
# Secrets: -Token / -Owner / -Repo / -Branch
# -LauncherPath: bitince silinecek CCMDM.cmd yolu

[CmdletBinding()]
param(
    [string]$Owner = "",
    [string]$Repo = "",
    [string]$Branch = "",
    [string]$Token = "",
    [string]$LauncherPath = ""
)

$ErrorActionPreference = "Stop"
$status = Join-Path $env:TEMP "ccmdm-last-run.log"
function Log([string]$m) {
    try { Add-Content -LiteralPath $status -Value ("[{0}] {1}" -f (Get-Date -Format "o"), $m) -Encoding UTF8 } catch { }
}

function Clear-CcmdmLeftovers {
    param([string]$ExportPs1, [string]$Launcher)
    # Once log dosyasina yaz; sonra her seyi sil (log en sonda)
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add(("[{0}] cleanup basladi" -f (Get-Date -Format "o")))

    $toDelete = New-Object System.Collections.ArrayList
    foreach ($pat in @(
        (Join-Path $env:TEMP "ccmdm-export-*.ps1"),
        (Join-Path $env:TEMP "ccmdm-boot*.ps1"),
        (Join-Path $env:TEMP "ccmdm-go.ps1")
    )) {
        Get-Item -Path $pat -ErrorAction SilentlyContinue | ForEach-Object { [void]$toDelete.Add($_.FullName) }
    }
    if ($ExportPs1) { [void]$toDelete.Add($ExportPs1) }
    $outRoot = Join-Path $env:TEMP "ccmdm-out"
    if (Test-Path -LiteralPath $outRoot) { [void]$toDelete.Add($outRoot) }

    foreach ($p in $toDelete) {
        if (-not $p) { continue }
        try {
            if (Test-Path -LiteralPath $p) {
                Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop
                [void]$lines.Add(("[{0}] del {1}" -f (Get-Date -Format "o"), $p))
            }
        } catch {
            [void]$lines.Add(("[{0}] del fail {1}: {2}" -f (Get-Date -Format "o"), $p, $_.Exception.Message))
        }
    }

    if ($Launcher -and (Test-Path -LiteralPath $Launcher)) {
        Start-Sleep -Milliseconds 500
        try {
            Remove-Item -LiteralPath $Launcher -Force -ErrorAction Stop
            [void]$lines.Add(("[{0}] del launcher {1}" -f (Get-Date -Format "o"), $Launcher))
        } catch {
            Start-Sleep -Seconds 1
            try {
                Remove-Item -LiteralPath $Launcher -Force -ErrorAction Stop
                [void]$lines.Add(("[{0}] del launcher retry ok" -f (Get-Date -Format "o")))
            } catch {
                [void]$lines.Add(("[{0}] launcher silinemedi: {1}" -f (Get-Date -Format "o"), $_.Exception.Message))
            }
        }
    }

    # Masaustu + Indirilenler: CCMDM.cmd / CCMDM (1).cmd / eski SONUC fisi
    $visibleDirs = New-Object System.Collections.ArrayList
    foreach ($folderName in @('Desktop', 'CommonDesktopDirectory')) {
        try {
            $p = [Environment]::GetFolderPath($folderName)
            if ($p) { [void]$visibleDirs.Add($p) }
        } catch { }
    }
    try {
        $shell = New-Object -ComObject Shell.Application
        $ns = $shell.NameSpace('shell:Downloads')
        if ($ns -and $ns.Self -and $ns.Self.Path) { [void]$visibleDirs.Add($ns.Self.Path) }
    } catch { }
    $dlFallback = Join-Path $env:USERPROFILE 'Downloads'
    if (Test-Path -LiteralPath $dlFallback) { [void]$visibleDirs.Add($dlFallback) }

    $seenDir = @{}
    foreach ($dir in $visibleDirs) {
        if (-not $dir -or $seenDir.ContainsKey($dir)) { continue }
        $seenDir[$dir] = $true
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($filter in @('CCMDM*.cmd', 'CCMDM*.cmd.crdownload', 'CCMDM-SONUC.txt')) {
            Get-ChildItem -LiteralPath $dir -Filter $filter -File -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    [void]$lines.Add(("[{0}] del visible {1}" -f (Get-Date -Format "o"), $_.FullName))
                } catch {
                    [void]$lines.Add(("[{0}] del visible fail {1}: {2}" -f (Get-Date -Format "o"), $_.FullName, $_.Exception.Message))
                }
            }
        }
    }

    # Temp sonuc/log temizligi
    foreach ($pat in @(
        (Join-Path $env:TEMP "CCMDM-SONUC.txt"),
        (Join-Path $env:TEMP "ccmdm-launcher-error.log"),
        (Join-Path $env:TEMP "ccmdm-*.log"),
        (Join-Path $env:TEMP "ccmdm-last-run.log")
    )) {
        if (-not $pat) { continue }
        Get-Item -Path $pat -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue } catch { }
        }
    }
}

Log "CCMDM-Go.ps1 v5 start"
if (-not $Branch) { $Branch = "main" }
Log ("owner={0} repo={1} branch={2} tokenLen={3}" -f $Owner, $Repo, $Branch, ($(if ($Token) { $Token.Length } else { 0 })))
Log ("launcher={0}" -f $LauncherPath)

$code = 1
$ps1 = $null
try {
    if (-not $Owner -or -not $Repo -or -not $Token -or $Token -match "REPLACE") {
        Log "ERROR missing Owner/Repo/Token"
        $code = 2
        throw "missing token"
    }

    $url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/CCMDM-Export.ps1"
    $ps1 = Join-Path $env:TEMP ("ccmdm-export-{0}.ps1" -f [guid]::NewGuid().ToString("N"))

    Log ("download {0}" -f $url)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $ps1 -UseBasicParsing
    Unblock-File -LiteralPath $ps1 -ErrorAction SilentlyContinue
    Log ("run export in-process size={0}" -f (Get-Item -LiteralPath $ps1).Length)

    & $ps1 -Silent -Owner $Owner -Repo $Repo -Branch $Branch -Token $Token
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    Log ("export exit={0}" -f $code)
} catch {
    Log ("ERROR {0}" -f $_.Exception.Message)
    try { $_ | Out-File -FilePath (Join-Path $env:TEMP "ccmdm-launcher-error.log") -Encoding utf8 } catch { }
    if ($code -eq 0) { $code = 1 }
} finally {
    Clear-CcmdmLeftovers -ExportPs1 $ps1 -Launcher $LauncherPath
}

exit $code
