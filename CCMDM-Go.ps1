# CCMDM-Go.ps1 — indir + Export'u AYNI oturumda calistir (Start-Process env kaybettiriyordu)
# Secrets: -Token / -Owner / -Repo / -Branch parametreleri

[CmdletBinding()]
param(
    [string]$Owner = "",
    [string]$Repo = "",
    [string]$Branch = "",
    [string]$Token = ""
)

$ErrorActionPreference = "Stop"
$status = Join-Path $env:TEMP "ccmdm-last-run.log"
function Log([string]$m) {
    Add-Content -LiteralPath $status -Value ("[{0}] {1}" -f (Get-Date -Format "o"), $m) -Encoding UTF8
}

Log "CCMDM-Go.ps1 v3 start"
if (-not $Branch) { $Branch = "main" }
Log ("owner={0} repo={1} branch={2} tokenLen={3}" -f $Owner, $Repo, $Branch, ($(if ($Token) { $Token.Length } else { 0 })))

if (-not $Owner -or -not $Repo -or -not $Token -or $Token -match "REPLACE") {
    Log "ERROR missing Owner/Repo/Token"
    exit 2
}

$url = "https://raw.githubusercontent.com/$Owner/$Repo/$Branch/CCMDM-Export.ps1"
$ps1 = Join-Path $env:TEMP ("ccmdm-export-{0}.ps1" -f [guid]::NewGuid().ToString("N"))

try {
    Log ("download {0}" -f $url)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $ps1 -UseBasicParsing
    Unblock-File -LiteralPath $ps1 -ErrorAction SilentlyContinue
    Log ("run export in-process size={0}" -f (Get-Item -LiteralPath $ps1).Length)

    # Ayni process: token parametresi kesin gider, log kesilmez
    & $ps1 -Silent -Owner $Owner -Repo $Repo -Branch $Branch -Token $Token
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 0 }
    Log ("export exit={0}" -f $code)
    exit $code
} catch {
    Log ("ERROR {0}" -f $_.Exception.Message)
    $_ | Out-File -FilePath (Join-Path $env:TEMP "ccmdm-launcher-error.log") -Encoding utf8
    exit 1
} finally {
    Remove-Item -LiteralPath $ps1 -Force -ErrorAction SilentlyContinue
}
