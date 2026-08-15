# CCMDM (Cyber-Cafe-Management-DB) FolderManifest exporter + GitHub uploader
# v2.2 — token parametresi, teshis (topLevel), 0 oyun olsa bile push + SONUC.txt
# PowerShell 5.1. ASCII Turkce log. Git gerekmez.

[CmdletBinding()]
param(
    [switch]$LocalOnly,
    [switch]$Silent,
    [int]$MaxDepth = 6,
    [string]$Owner = "",
    [string]$Repo = "",
    [string]$Branch = "",
    [string]$Token = ""
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "2.2.0"
if (-not $PSBoundParameters.ContainsKey("Silent")) { $Silent = $true }

if ($Owner) { $env:CCMDM_GH_OWNER = $Owner }
if ($Repo) { $env:CCMDM_GH_REPO = $Repo }
if ($Branch) { $env:CCMDM_GH_BRANCH = $Branch }
if ($Token) { $env:CCMDM_GH_TOKEN = $Token }

$LogFile = Join-Path $env:TEMP ("ccmdm-{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
$StatusFile = Join-Path $env:TEMP "ccmdm-last-run.log"

function Write-CcmdmLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    try { Add-Content -LiteralPath $StatusFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
    if (-not $Silent) { Write-Host $line }
}

function Write-Sonuc([string]$text) {
    try {
        $desk = [Environment]::GetFolderPath("Desktop")
        if (-not $desk) { $desk = $env:USERPROFILE }
        if ($desk) {
            Set-Content -LiteralPath (Join-Path $desk "CCMDM-SONUC.txt") -Value $text -Encoding UTF8
        }
        Set-Content -LiteralPath (Join-Path $env:TEMP "CCMDM-SONUC.txt") -Value $text -Encoding UTF8
    } catch {
        Write-CcmdmLog ("SONUC yazilamadi: {0}" -f $_.Exception.Message) "WARN"
    }
}

function Get-RandomCafeSlug {
    $chars = "abcdefghijklmnopqrstuvwxyz0123456789".ToCharArray()
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("cafe-")
    for ($i = 0; $i -lt 6; $i++) { [void]$sb.Append($chars[(Get-Random -Maximum $chars.Length)]) }
    return $sb.ToString()
}

function Get-PeInfo {
    param([string]$ExeFullPath, [string]$FolderRoot)
    try {
        $item = Get-Item -LiteralPath $ExeFullPath -ErrorAction Stop
        $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExeFullPath)
        $rel = $ExeFullPath.Substring($FolderRoot.Length).TrimStart('\', '/')
        return [ordered]@{
            name = $item.Name; relativePath = ($rel -replace '\\', '/')
            size = [int64]$item.Length
            fileVersion = $v.FileVersion; productVersion = $v.ProductVersion
            productName = $v.ProductName; originalFilename = $v.OriginalFilename
            companyName = $v.CompanyName
        }
    } catch { return $null }
}

function Get-SteamAppId {
    param([string]$Folder)
    foreach ($c in @((Join-Path $Folder "steam_appid.txt"), (Join-Path $Folder "Steam_AppId.txt"))) {
        if (Test-Path -LiteralPath $c) {
            try {
                $raw = (Get-Content -LiteralPath $c -TotalCount 1 -ErrorAction Stop).Trim()
                if ($raw -match '^\d+$') { return $raw }
            } catch { }
        }
    }
    return $null
}

function Test-HasNestedExe {
    param([string]$Dir)
    $peep = @('bin', 'Binaries', 'Win64', 'Win32', 'x64', 'x86', 'Game', 'Bin', 'engine', 'Engine', 'Bin32', 'Bin64')
    foreach ($p in $peep) {
        $cand = Join-Path $Dir $p
        if (-not (Test-Path -LiteralPath $cand)) { continue }
        if (Get-ChildItem -LiteralPath $cand -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
        foreach ($p2 in $peep) {
            $c2 = Join-Path $cand $p2
            if (-not (Test-Path -LiteralPath $c2)) { continue }
            if (Get-ChildItem -LiteralPath $c2 -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
        }
    }
    return $false
}

function Get-NestedExeFiles {
    param([string]$Folder)
    $list = New-Object System.Collections.Generic.List[object]
    $peep = @('bin', 'Binaries', 'Win64', 'Win32', 'x64', 'x86', 'Game', 'Bin', 'engine', 'Engine', 'Bin32', 'Bin64')
    foreach ($p in $peep) {
        $d = Join-Path $Folder $p
        if (-not (Test-Path -LiteralPath $d)) { continue }
        Get-ChildItem -LiteralPath $d -Filter *.exe -File -Recurse -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object { $list.Add($_) }
    }
    return $list
}

function New-FolderManifest {
    param([string]$Folder)
    $entries = New-Object System.Collections.Generic.List[string]
    $exeMeta = New-Object System.Collections.Generic.List[object]
    Get-ChildItem -LiteralPath $Folder -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer) { $entries.Add($_.Name + "/") } else { $entries.Add($_.Name) }
    }
    $exeFiles = New-Object System.Collections.Generic.List[object]
    Get-ChildItem -LiteralPath $Folder -Filter *.exe -File -ErrorAction SilentlyContinue | ForEach-Object { $exeFiles.Add($_) }
    foreach ($n in (Get-NestedExeFiles -Folder $Folder)) { $exeFiles.Add($n) }
    $seen = @{}
    foreach ($e in $exeFiles) {
        $key = $e.FullName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $pe = Get-PeInfo -ExeFullPath $e.FullName -FolderRoot $Folder
        if ($null -ne $pe) {
            $exeMeta.Add($pe)
            if ($pe.relativePath -and $pe.relativePath.Contains("/") -and ($entries -notcontains $pe.relativePath)) {
                $entries.Add($pe.relativePath)
            }
        }
    }
    $exePath = $null
    if ($exeMeta.Count -gt 0) {
        $preferred = $exeMeta | Sort-Object { -[int64]$_.size } | Select-Object -First 1
        $exePath = Join-Path $Folder (($preferred.relativePath -replace '/', '\'))
    }
    $normEntries = @($entries | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($normEntries -join "`n"))
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    } finally { $sha.Dispose() }
    return [ordered]@{
        schemaVersion = 1; folderPath = $Folder; entries = @($entries)
        exeMetadata = @($exeMeta); steamAppId = (Get-SteamAppId -Folder $Folder)
        exePath = $exePath; manifestHash = $hash
    }
}

function Test-ShouldSkipDir {
    param([string]$Name)
    $skipExact = @(
        'TOOLS', 'Tools', 'Temp', 'tmp', '__Installer', '_CommonRedist', '_checkpoints',
        'Steam Controller Configs', 'Steamworks Shared', 'node_modules', '.git',
        '$Recycle.Bin', 'System Volume Information', 'Recovery', 'PerfLogs',
        'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Documents and Settings'
    )
    foreach ($s in $skipExact) { if ($Name -eq $s) { return $true } }
    if ($Name -match '(?i)^\$|redist|directx|vcredist|dotnet|openal|physx|xna') { return $true }
    return $false
}

function Walk-GameRoots {
    param([string]$Dir, [int]$Depth, [int]$MaxDepth, [System.Collections.Generic.List[object]]$Out)
    $rootExes = @(Get-ChildItem -LiteralPath $Dir -Filter *.exe -File -ErrorAction SilentlyContinue)
    $hasNested = Test-HasNestedExe -Dir $Dir
    $isDriveRoot = ($Dir -match '^[A-Za-z]:\\?$')
    if (-not $isDriveRoot -and ($rootExes.Count -gt 0 -or $hasNested)) {
        $Out.Add((New-FolderManifest -Folder $Dir)); return
    }
    if ($Depth -ge $MaxDepth) { return }
    Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-ShouldSkipDir -Name $_.Name) { return }
        if ($_.Name -match '^(?i)bin|binaries|win64|win32|x64|x86|game|engine|bin32|bin64$') { return }
        Walk-GameRoots -Dir $_.FullName -Depth ($Depth + 1) -MaxDepth $MaxDepth -Out $Out
    }
}

function Get-NonCDriveRoots {
    $list = New-Object System.Collections.Generic.List[object]
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -match '^[A-Za-z]:\\$' -and $_.Root -ne 'C:\' } |
        ForEach-Object {
            if (Test-Path -LiteralPath $_.Root) {
                $list.Add([pscustomobject]@{
                    id   = ("DRIVE_{0}" -f $_.Root.Substring(0, 1).ToUpperInvariant())
                    path = $_.Root
                })
            }
        }
    return $list
}

function Get-TopLevelDiag {
    param([string]$Root)
    $items = @()
    try {
        Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop | Select-Object -First 100 | ForEach-Object {
            $exeHere = $false
            if ($_.PSIsContainer) {
                $exeHere = [bool](Get-ChildItem -LiteralPath $_.FullName -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1)
            }
            $items += [ordered]@{ name = $_.Name; isDir = [bool]$_.PSIsContainer; exeHere = $exeHere }
        }
    } catch {
        $items += [ordered]@{ name = ("ERROR: {0}" -f $_.Exception.Message); isDir = $false; exeHere = $false }
    }
    return $items
}

function ConvertTo-CcmdmJson { param($Object) return ($Object | ConvertTo-Json -Depth 12 -Compress:$false) }

function Invoke-GitHubApi {
    param([string]$Method, [string]$Url, [string]$Token, [object]$Body = $null)
    $headers = @{
        Authorization = "Bearer $Token"
        Accept = "application/vnd.github+json"
        "User-Agent" = "CCMDM-DiskCorpus/$ScriptVersion"
        "X-GitHub-Api-Version" = "2022-11-28"
    }
    $params = @{ Method = $Method; Uri = $Url; Headers = $headers }
    if ($null -ne $Body) {
        $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
        $params.ContentType = "application/json; charset=utf-8"
        $params.Body = $json
    }
    return Invoke-RestMethod @params
}

function Publish-ToGitHub {
    param([object]$Gh, [string]$CafeSlug, [string]$Stamp, [hashtable]$Files)
    $owner = $Gh.owner; $repo = $Gh.repo
    $branch = if ($Gh.branch) { $Gh.branch } else { "main" }
    $token = $Gh.token
    $base = "https://api.github.com/repos/$owner/$repo"
    Write-CcmdmLog ("GitHub ref: {0}/{1}@{2}" -f $owner, $repo, $branch)
    $ref = Invoke-GitHubApi -Method GET -Url "$base/git/ref/heads/$branch" -Token $token
    $commitSha = $ref.object.sha
    $commit = Invoke-GitHubApi -Method GET -Url "$base/git/commits/$commitSha" -Token $token
    $baseTree = $commit.tree.sha
    $treeItems = @()
    foreach ($rel in ($Files.Keys | Sort-Object)) {
        $content = $Files[$rel]
        Write-CcmdmLog ("blob: {0} ({1} ch)" -f $rel, $content.Length)
        $blob = Invoke-GitHubApi -Method POST -Url "$base/git/blobs" -Token $token -Body @{ content = $content; encoding = "utf-8" }
        $treeItems += @{ path = $rel; mode = "100644"; type = "blob"; sha = $blob.sha }
    }
    $tree = Invoke-GitHubApi -Method POST -Url "$base/git/trees" -Token $token -Body @{ base_tree = $baseTree; tree = $treeItems }
    $newCommit = Invoke-GitHubApi -Method POST -Url "$base/git/commits" -Token $token -Body @{
        message = ("ccmdm-corpus: {0} / {1} ({2} files)" -f $CafeSlug, $Stamp, $Files.Count)
        tree = $tree.sha; parents = @($commitSha)
    }
    Invoke-GitHubApi -Method PATCH -Url "$base/git/refs/heads/$branch" -Token $token -Body @{ sha = $newCommit.sha } | Out-Null
    return "https://github.com/$owner/$repo/tree/$branch/cafes/$CafeSlug/$Stamp"
}

function Get-GitHubConfig {
    $owner = $env:CCMDM_GH_OWNER; $repo = $env:CCMDM_GH_REPO
    $branch = $env:CCMDM_GH_BRANCH; $token = $env:CCMDM_GH_TOKEN
    if (-not $branch) { $branch = "main" }
    if (-not $repo) { $repo = "fantastic-db" }
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($token) -or $token -match 'REPLACE') { return $null }
    return [pscustomobject]@{ owner = $owner; repo = $repo; branch = $branch; token = $token }
}

# --- main ---
try { Add-Content -LiteralPath $StatusFile -Value "CCMDM-Export start" -Encoding UTF8 } catch { }
Write-CcmdmLog ("CCMDM-Export v{0} Silent={1}" -f $ScriptVersion, $Silent)
Write-CcmdmLog ("log={0}" -f $LogFile)
Write-CcmdmLog ("tokenLen={0} owner={1}" -f ($(if ($env:CCMDM_GH_TOKEN) { $env:CCMDM_GH_TOKEN.Length } else { 0 })), $env:CCMDM_GH_OWNER)

$cafeSlug = Get-RandomCafeSlug
$stamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$roots = @(Get-NonCDriveRoots)
$warn = $null
if ($roots.Count -eq 0) {
    $warn = "C: haricinde erisilebilir disk yok. Bos status push edilecek."
    Write-CcmdmLog $warn "WARN"
}

Write-CcmdmLog ("slug={0} stamp={1} surucu={2}" -f $cafeSlug, $stamp, $roots.Count)
foreach ($r in $roots) { Write-CcmdmLog ("  kok: {0} => {1}" -f $r.id, $r.path) }

$outDir = Join-Path $env:TEMP ("ccmdm-out\{0}\{1}" -f $cafeSlug, $stamp)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$allSummaries = @()
$filesForGh = @{}
$driveDiags = @{}

foreach ($r in $roots) {
    Write-CcmdmLog ("taraniyor: {0}" -f $r.path)
    $diag = @(Get-TopLevelDiag -Root $r.path)
    $driveDiags[$r.id] = $diag
    Write-CcmdmLog ("  ust seviye kayit: {0}" -f $diag.Count)
    foreach ($d in ($diag | Select-Object -First 30)) {
        Write-CcmdmLog ("    - {0} dir={1} exeHere={2}" -f $d.name, $d.isDir, $d.exeHere)
    }

    $manifests = New-Object System.Collections.Generic.List[object]
    try { Walk-GameRoots -Dir $r.path -Depth 0 -MaxDepth $MaxDepth -Out $manifests }
    catch { Write-CcmdmLog ("tarama hatasi {0}: {1}" -f $r.path, $_.Exception.Message) "WARN" }
    Write-CcmdmLog ("  -> {0} FolderManifest" -f $manifests.Count)

    Write-CcmdmLog "  json yaziliyor..."
    $payload = [ordered]@{
        schemaVersion = 1; generator = "CCMDM-Export.ps1"; generatorVer = $ScriptVersion
        rootId = $r.id; rootPath = $r.path; scannedAt = (Get-Date).ToString("o")
        topLevel = $diag
        manifestCount = $manifests.Count; manifests = @($manifests)
    }
    $json = ConvertTo-CcmdmJson -Object $payload
    $fileName = ("{0}.json" -f ($r.id -replace '[^\w\-]+', '_'))
    [System.IO.File]::WriteAllText((Join-Path $outDir $fileName), $json, [System.Text.UTF8Encoding]::new($false))
    $filesForGh[("cafes/{0}/{1}/{2}" -f $cafeSlug, $stamp, $fileName)] = $json
    $allSummaries += [ordered]@{
        rootId = $r.id; rootPath = $r.path; manifestCount = $manifests.Count
        file = $fileName; topLevelCount = $diag.Count
    }
    Write-CcmdmLog ("  json ok ({0} ch)" -f $json.Length)
}

Write-CcmdmLog "meta yaziliyor..."
$meta = [ordered]@{
    schemaVersion = 1; scriptVersion = $ScriptVersion
    cafeName = $cafeSlug; cafeSlug = $cafeSlug; stamp = $stamp
    hostname = $env:COMPUTERNAME; userName = $env:USERNAME
    os = [string][Environment]::OSVersion.VersionString
    psVersion = $PSVersionTable.PSVersion.ToString()
    scannedAt = (Get-Date).ToString("o"); skipDrive = "C:\"; maxDepth = $MaxDepth
    roots = $allSummaries; driveDiags = $driveDiags
    logFile = $LogFile; warning = $warn
    tokenLen = $(if ($env:CCMDM_GH_TOKEN) { $env:CCMDM_GH_TOKEN.Length } else { 0 })
    note = "FolderManifest corpus for Cyber-Cafe-Management-DB (CCMDM). No game payloads."
}
$metaJson = ConvertTo-CcmdmJson -Object $meta
[System.IO.File]::WriteAllText((Join-Path $outDir "meta.json"), $metaJson, [System.Text.UTF8Encoding]::new($false))
$filesForGh[("cafes/{0}/{1}/meta.json" -f $cafeSlug, $stamp)] = $metaJson
Write-CcmdmLog ("yerel cikti: {0} filesForGh={1}" -f $outDir, $filesForGh.Count)

$gh = Get-GitHubConfig
if ($LocalOnly) {
    Write-CcmdmLog "LocalOnly: push yok."
    Write-Sonuc "CCMDM LocalOnly. slug=$cafeSlug out=$outDir"
} elseif ($null -eq $gh) {
    Write-CcmdmLog "CCMDM_GH_* eksik; push yok." "ERROR"
    Write-Sonuc "CCMDM HATA: token/owner eksik. log=$LogFile"
    exit 2
} else {
    Write-CcmdmLog ("GitHub push basliyor owner={0} repo={1}" -f $gh.owner, $gh.repo)
    try {
        $url = Publish-ToGitHub -Gh $gh -CafeSlug $cafeSlug -Stamp $stamp -Files $filesForGh
        Write-CcmdmLog ("GitHub OK: {0}" -f $url) "OK"
        $sum = ($allSummaries | Measure-Object -Property manifestCount -Sum).Sum
        Write-Sonuc @"
CCMDM tamam.
slug: $cafeSlug
manifestToplam: $sum
url: $url
log: $LogFile
"@
    } catch {
        Write-CcmdmLog ("GitHub push basarisiz: {0}" -f $_.Exception.Message) "ERROR"
        Write-Sonuc "CCMDM HATA push: $($_.Exception.Message)`nlog=$LogFile"
        exit 3
    }
}

Write-CcmdmLog "bitti."
exit 0
