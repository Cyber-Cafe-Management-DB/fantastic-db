# CCMDM elevate+download helper (public). Secrets via -Token param (RunAs env miras almaz).
# PowerShell 5.1.

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

Log "CCMDM-Go.ps1 start"
if ($Owner) { $env:CCMDM_GH_OWNER = $Owner }
if ($Repo) { $env:CCMDM_GH_REPO = $Repo }
if ($Branch) { $env:CCMDM_GH_BRANCH = $Branch }
if ($Token) { $env:CCMDM_GH_TOKEN = $Token }

$owner = $env:CCMDM_GH_OWNER
$repo = $env:CCMDM_GH_REPO
$branch = $env:CCMDM_GH_BRANCH
$token = $env:CCMDM_GH_TOKEN
if (-not $branch) { $branch = "main" }

Log ("owner={0} repo={1} branch={2} tokenLen={3}" -f $owner, $repo, $branch, ($(if ($token) { $token.Length } else { 0 })))

if (-not $owner -or -not $repo -or -not $token -or $token -match "REPLACE") {
    Log "ERROR missing Owner/Repo/Token"
    exit 2
}

$url = "https://raw.githubusercontent.com/$owner/$repo/$branch/CCMDM-Export.ps1"
$ps1 = Join-Path $env:TEMP ("ccmdm-export-{0}.ps1" -f [guid]::NewGuid().ToString("N"))

try {
    Log ("download {0}" -f $url)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $url -OutFile $ps1 -UseBasicParsing
    Unblock-File -LiteralPath $ps1 -ErrorAction SilentlyContinue
    Log ("run export size={0}" -f (Get-Item $ps1).Length)
    $p = Start-Process -FilePath "powershell.exe" -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
        "-File", $ps1, "-Silent"
    )
    # Child also needs env — Start-Process inherits from THIS elevated process, OK
    Log ("export exit={0}" -f $p.ExitCode)
    exit $p.ExitCode
} catch {
    Log ("ERROR {0}" -f $_.Exception.Message)
    $_ | Out-File -FilePath (Join-Path $env:TEMP "ccmdm-launcher-error.log") -Encoding utf8
    exit 1
} finally {
    Remove-Item -LiteralPath $ps1 -Force -ErrorAction SilentlyContinue
}
