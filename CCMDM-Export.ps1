# CCMDM (Cyber-Cafe-Management-DB) FolderManifest exporter + GitHub uploader
# v2.3 — JSON yazimi guvenli; exe yoksa bile ust klasor snapshot; push kesin denenir
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
$ScriptVersion = "2.3.0"
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
        if ($desk) { Set-Content -LiteralPath (Join-Path $desk "CCMDM-SONUC.txt") -Value $text -Encoding UTF8 }
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

function ConvertTo-CcmdmJson {
    param($Object)
    # PS 5.1: Generic.List / ordered bazen takiliyor; once düz diziye cevir
    try {
        return (ConvertTo-Json -InputObject $Object -Depth 10 -Compress:$false)
    } catch {
        Write-CcmdmLog ("ConvertTo-Json hata: {0}" -f $_.Exception.Message) "ERROR"
        throw
    }
}

function Get-PeInfo {
    param([string]$ExeFullPath, [string]$FolderRoot)
    try {
        $item = Get-Item -LiteralPath $ExeFullPath -ErrorAction Stop
        $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExeFullPath)
        $rel = $ExeFullPath.Substring($FolderRoot.Length).TrimStart('\', '/')
        return @{
            name = [string]$item.Name
            relativePath = [string]($rel -replace '\\', '/')
            size = [int64]$item.Length
            fileVersion = [string]$v.FileVersion
            productVersion = [string]$v.ProductVersion
            productName = [string]$v.ProductName
            originalFilename = [string]$v.OriginalFilename
            companyName = [string]$v.CompanyName
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
    $list = @()
    $peep = @('bin', 'Binaries', 'Win64', 'Win32', 'x64', 'x86', 'Game', 'Bin', 'engine', 'Engine', 'Bin32', 'Bin64')
    foreach ($p in $peep) {
        $d = Join-Path $Folder $p
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $list += @(Get-ChildItem -LiteralPath $d -Filter *.exe -File -Recurse -Depth 2 -ErrorAction SilentlyContinue)
    }
    return @($list | Sort-Object -Property FullName -Unique)
}

function New-FolderManifest {
    param([string]$Folder)
    $entryList = New-Object System.Collections.ArrayList
    Get-ChildItem -LiteralPath $Folder -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer) { [void]$entryList.Add($_.Name + "/") } else { [void]$entryList.Add($_.Name) }
    }

    $exeMetaList = New-Object System.Collections.ArrayList
    $exeFiles = @()
    $exeFiles += @(Get-ChildItem -LiteralPath $Folder -Filter *.exe -File -ErrorAction SilentlyContinue)
    $exeFiles += @(Get-NestedExeFiles -Folder $Folder)
    $seen = @{}
    foreach ($e in $exeFiles) {
        if (-not $e) { continue }
        $key = $e.FullName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $pe = Get-PeInfo -ExeFullPath $e.FullName -FolderRoot $Folder
        if ($null -ne $pe) {
            [void]$exeMetaList.Add($pe)
            $rel = $pe.relativePath
            if ($rel -and $rel.Contains("/") -and -not $entryList.Contains($rel)) {
                [void]$entryList.Add($rel)
            }
        }
    }

    $exePath = $null
    if ($exeMetaList.Count -gt 0) {
        $preferred = $exeMetaList | Sort-Object { -[int64]$_.size } | Select-Object -First 1
        $exePath = Join-Path $Folder (($preferred.relativePath -replace '/', '\'))
    }

    $entriesArr = @($entryList.ToArray())
    $norm = @($entriesArr | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($norm -join "`n"))
        $hash = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
    } finally { $sha.Dispose() }

    return @{
        schemaVersion = 1
        folderPath    = [string]$Folder
        entries       = $entriesArr
        exeMetadata   = @($exeMetaList.ToArray())
        steamAppId    = (Get-SteamAppId -Folder $Folder)
        exePath       = $exePath
        manifestHash  = $hash
    }
}

function Test-ShouldSkipDir {
    param([string]$Name)
    if ($Name -match '(?i)^\$') { return $true }
    $skipExact = @(
        'TOOLS', 'Tools', 'Temp', 'tmp', '__Installer', '_CommonRedist', '_checkpoints',
        'Steam Controller Configs', 'Steamworks Shared', 'node_modules', '.git',
        'System Volume Information', 'Recovery', 'PerfLogs',
        'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Documents and Settings'
    )
    foreach ($s in $skipExact) { if ($Name -eq $s) { return $true } }
    if ($Name -match '(?i)redist|directx|vcredist|dotnet|openal|physx|xna') { return $true }
    return $false
}

function Walk-GameRoots {
    param([string]$Dir, [int]$Depth, [int]$MaxDepth, [System.Collections.ArrayList]$Out)
    $rootExes = @(Get-ChildItem -LiteralPath $Dir -Filter *.exe -File -ErrorAction SilentlyContinue)
    $hasNested = Test-HasNestedExe -Dir $Dir
    $isDriveRoot = ($Dir -match '^[A-Za-z]:\\?$')

    if (-not $isDriveRoot -and ($rootExes.Count -gt 0 -or $hasNested)) {
        [void]$Out.Add((New-FolderManifest -Folder $Dir))
        return
    }
    if ($Depth -ge $MaxDepth) { return }

    Get-ChildItem -LiteralPath $Dir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-ShouldSkipDir -Name $_.Name) { return }
        if ($_.Name -match '^(?i)bin|binaries|win64|win32|x64|x86|engine|bin32|bin64$') { return }
        Walk-GameRoots -Dir $_.FullName -Depth ($Depth + 1) -MaxDepth $MaxDepth -Out $Out
    }
}

function Get-NonCDriveRoots {
    $list = New-Object System.Collections.ArrayList
    Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue |
        Where-Object { $_.Root -match '^[A-Za-z]:\\$' -and $_.Root -ne 'C:\' } |
        ForEach-Object {
            if (Test-Path -LiteralPath $_.Root) {
                [void]$list.Add(@{
                    id   = ("DRIVE_{0}" -f $_.Root.Substring(0, 1).ToUpperInvariant())
                    path = $_.Root
                })
            }
        }
    return ,$list.ToArray()
}

function Get-TopLevelDiag {
    param([string]$Root)
    $items = New-Object System.Collections.ArrayList
    try {
        Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop | Select-Object -First 100 | ForEach-Object {
            $exeHere = $false
            if ($_.PSIsContainer) {
                $exeHere = [bool](Get-ChildItem -LiteralPath $_.FullName -Filter *.exe -File -ErrorAction SilentlyContinue | Select-Object -First 1)
            }
            [void]$items.Add(@{ name = [string]$_.Name; isDir = [bool]$_.PSIsContainer; exeHere = $exeHere })
        }
    } catch {
        [void]$items.Add(@{ name = ("ERROR: {0}" -f $_.Exception.Message); isDir = $false; exeHere = $false })
    }
    return ,$items.ToArray()
}

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
        $json = if ($Body -is [string]) { $Body } else { ConvertTo-Json -InputObject $Body -Depth 20 -Compress }
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
    return @{ owner = $owner; repo = $repo; branch = $branch; token = $token }
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
    $warn = "C: haricinde disk yok."
    Write-CcmdmLog $warn "WARN"
}

Write-CcmdmLog ("slug={0} stamp={1} surucu={2}" -f $cafeSlug, $stamp, $roots.Count)
foreach ($r in $roots) { Write-CcmdmLog ("  kok: {0} => {1}" -f $r.id, $r.path) }

$outDir = Join-Path $env:TEMP ("ccmdm-out\{0}\{1}" -f $cafeSlug, $stamp)
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Set-Content -LiteralPath (Join-Path $outDir "_progress.txt") -Value "started" -Encoding UTF8

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

    $manifests = New-Object System.Collections.ArrayList
    try { Walk-GameRoots -Dir $r.path -Depth 0 -MaxDepth $MaxDepth -Out $manifests }
    catch { Write-CcmdmLog ("tarama hatasi {0}: {1}" -f $r.path, $_.Exception.Message) "WARN" }

    # Hic oyun yoksa: ust seviye normal klasorleri yine snapshot'la (testgame vb.)
    if ($manifests.Count -eq 0) {
        Write-CcmdmLog "  0 manifest; ust klasor snapshot deneniyor..."
        foreach ($d in $diag) {
            if (-not $d.isDir) { continue }
            if (Test-ShouldSkipDir -Name $d.name) { continue }
            $folder = Join-Path $r.path $d.name
            try {
                [void]$manifests.Add((New-FolderManifest -Folder $folder))
                Write-CcmdmLog ("  snapshot: {0}" -f $folder)
            } catch {
                Write-CcmdmLog ("  snapshot fail {0}: {1}" -f $folder, $_.Exception.Message) "WARN"
            }
        }
    }

    Write-CcmdmLog ("  -> {0} FolderManifest" -f $manifests.Count)
    Write-CcmdmLog "  json yaziliyor..."
    Set-Content -LiteralPath (Join-Path $outDir "_progress.txt") -Value ("json {0}" -f $r.id) -Encoding UTF8

    $payload = @{
        schemaVersion = 1
        generator     = "CCMDM-Export.ps1"
        generatorVer  = $ScriptVersion
        rootId        = [string]$r.id
        rootPath      = [string]$r.path
        scannedAt     = (Get-Date).ToString("o")
        topLevel      = @($diag)
        manifestCount = [int]$manifests.Count
        manifests     = @($manifests.ToArray())
    }

    try {
        $json = ConvertTo-CcmdmJson -Object $payload
    } catch {
        # Minimal fallback JSON
        $json = "{`"rootId`":`"$($r.id)`",`"error`":`"json_failed`",`"manifestCount`":$($manifests.Count)}"
        Write-CcmdmLog "  fallback json kullanildi" "WARN"
    }

    $fileName = ("{0}.json" -f ($r.id -replace '[^\w\-]+', '_'))
    $full = Join-Path $outDir $fileName
    [System.IO.File]::WriteAllText($full, $json, [System.Text.UTF8Encoding]::new($false))
    $filesForGh[("cafes/{0}/{1}/{2}" -f $cafeSlug, $stamp, $fileName)] = $json
    $allSummaries += @{
        rootId = [string]$r.id; rootPath = [string]$r.path
        manifestCount = [int]$manifests.Count; file = $fileName; topLevelCount = [int]$diag.Count
    }
    Write-CcmdmLog ("  json ok file={0} ch={1}" -f $fileName, $json.Length)
}

Write-CcmdmLog "meta yaziliyor..."
$meta = @{
    schemaVersion = 1
    scriptVersion = $ScriptVersion
    cafeName = $cafeSlug; cafeSlug = $cafeSlug; stamp = $stamp
    hostname = [string]$env:COMPUTERNAME; userName = [string]$env:USERNAME
    os = [string][Environment]::OSVersion.VersionString
    psVersion = $PSVersionTable.PSVersion.ToString()
    scannedAt = (Get-Date).ToString("o"); skipDrive = "C:\"; maxDepth = $MaxDepth
    roots = @($allSummaries); driveDiags = $driveDiags
    logFile = $LogFile; warning = $warn
    tokenLen = $(if ($env:CCMDM_GH_TOKEN) { $env:CCMDM_GH_TOKEN.Length } else { 0 })
    note = "FolderManifest corpus for CCMDM. No game payloads."
}
try { $metaJson = ConvertTo-CcmdmJson -Object $meta }
catch { $metaJson = "{`"cafeSlug`":`"$cafeSlug`",`"error`":`"meta_json_failed`"}" }

[System.IO.File]::WriteAllText((Join-Path $outDir "meta.json"), $metaJson, [System.Text.UTF8Encoding]::new($false))
$filesForGh[("cafes/{0}/{1}/meta.json" -f $cafeSlug, $stamp)] = $metaJson
Set-Content -LiteralPath (Join-Path $outDir "_progress.txt") -Value "ready_to_push" -Encoding UTF8
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
        $sum = 0
        foreach ($s in $allSummaries) { $sum += [int]$s.manifestCount }
        Write-Sonuc @"
CCMDM tamam.
slug: $cafeSlug
manifestToplam: $sum
url: $url
log: $LogFile
"@
    } catch {
        Write-CcmdmLog ("GitHub push basarisiz: {0}" -f $_.Exception.Message) "ERROR"
        Write-Sonuc "CCMDM HATA push: $($_.Exception.Message)`nlog=$LogFile`nout=$outDir"
        exit 3
    }
}

Write-CcmdmLog "bitti."
exit 0
