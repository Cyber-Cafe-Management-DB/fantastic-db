# CCMDM (Cyber-Cafe-Management-DB) FolderManifest exporter + GitHub uploader
# v2.5 — OS friendly (Windows 11 25H2 vb.); fingerprint + recycle/SVI haric
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
$ScriptVersion = "2.5.0"
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

function Get-WindowsOsInfo {
    # Ornek cikti: "Windows 11, version 25H2 (build 26200.6584)"
    $nt = [string][Environment]::OSVersion.VersionString
    $ver = [Environment]::OSVersion.Version
    $info = @{
        ntVersionString = $nt
        major = $ver.Major
        minor = $ver.Minor
        build = $ver.Build
        revision = $ver.Revision
        productName = $null
        displayVersion = $null
        currentBuild = $null
        ubr = $null
        editionId = $null
        architecture = $null
        caption = $null
        friendly = $null
    }

    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $info.productName = [string](Get-ItemProperty -Path $key -Name ProductName -ErrorAction SilentlyContinue).ProductName
        $info.displayVersion = [string](Get-ItemProperty -Path $key -Name DisplayVersion -ErrorAction SilentlyContinue).DisplayVersion
        $info.currentBuild = [string](Get-ItemProperty -Path $key -Name CurrentBuild -ErrorAction SilentlyContinue).CurrentBuild
        $ubrObj = Get-ItemProperty -Path $key -Name UBR -ErrorAction SilentlyContinue
        if ($ubrObj) { $info.ubr = [int]$ubrObj.UBR }
        $info.editionId = [string](Get-ItemProperty -Path $key -Name EditionID -ErrorAction SilentlyContinue).EditionID
        $cm = Get-ItemProperty -Path $key -Name CurrentMajorVersionNumber -ErrorAction SilentlyContinue
        if ($cm) { $info.currentMajorVersionNumber = [int]$cm.CurrentMajorVersionNumber }
    } catch {
        Write-CcmdmLog ("OS registry okunamadi: {0}" -f $_.Exception.Message) "WARN"
    }

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $info.caption = [string]$os.Caption
        $info.architecture = [string]$os.OSArchitecture
        if (-not $info.currentBuild -and $os.BuildNumber) { $info.currentBuild = [string]$os.BuildNumber }
    } catch {
        try {
            $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
            $info.caption = [string]$os.Caption
            $info.architecture = [string]$os.OSArchitecture
            if (-not $info.currentBuild -and $os.BuildNumber) { $info.currentBuild = [string]$os.BuildNumber }
        } catch { }
    }

    $buildNum = 0
    if ($info.currentBuild) { [void][int]::TryParse($info.currentBuild, [ref]$buildNum) }
    if ($buildNum -le 0) { $buildNum = [int]$ver.Build }

    # Build -> Win10/11 + DisplayVersion fallback tablosu
    # DisplayVersion (22H2/24H2/25H2) registry'de varsa onu tercih et
    $family = $null
    if ($info.currentMajorVersionNumber -ge 11 -or $buildNum -ge 22000) {
        $family = 'Windows 11'
    } elseif ($buildNum -ge 10240) {
        $family = 'Windows 10'
    } else {
        $family = 'Windows'
    }

    $release = $info.displayVersion
    if ([string]::IsNullOrWhiteSpace($release)) {
        $map = @{
            10240 = '1507'; 10586 = '1511'; 14393 = '1607'; 15063 = '1703'
            16299 = '1709'; 17134 = '1803'; 17763 = '1809'; 18362 = '1903'
            18363 = '1909'; 19041 = '20H1'; 19042 = '20H2'; 19043 = '21H1'
            19044 = '21H2'; 19045 = '22H2'
            22000 = '21H2'; 22621 = '22H2'; 22631 = '23H2'
            26100 = '24H2'; 26200 = '25H2'
        }
        if ($map.ContainsKey($buildNum)) { $release = $map[$buildNum] }
        else {
            # en yakin bilinen alt build
            $known = ($map.Keys | Sort-Object)
            $prev = $null
            foreach ($k in $known) {
                if ($k -le $buildNum) { $prev = $k } else { break }
            }
            if ($null -ne $prev) { $release = $map[$prev] }
        }
    }

    $buildFull = [string]$buildNum
    if ($null -ne $info.ubr -and $info.ubr -gt 0) {
        $buildFull = "{0}.{1}" -f $buildNum, $info.ubr
    }

    if ($family -and $release) {
        $info.friendly = ("{0}, version {1} (build {2})" -f $family, $release, $buildFull)
    } elseif ($info.caption) {
        $info.friendly = ("{0} (build {1})" -f $info.caption.Trim(), $buildFull)
    } else {
        $info.friendly = $nt
    }

    if ($info.architecture) {
        $info.friendly = ("{0} [{1}]" -f $info.friendly, $info.architecture)
    }

    return $info
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
    # PS 5.1: Generic.List / ordered bazen takiliyor; once duz diziye cevir
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
    # $RECYCLE.BIN / System Volume Information ve benzeri
    if ($Name -match '(?i)^\$') { return $true }
    if ($Name -match '(?i)^System Volume Information$') { return $true }
    $skipExact = @(
        'TOOLS', 'Tools', 'Temp', 'tmp', '__Installer', '_CommonRedist', '_checkpoints',
        'Steam Controller Configs', 'Steamworks Shared', 'node_modules', '.git',
        'Recovery', 'PerfLogs',
        'Windows', 'Program Files', 'Program Files (x86)', 'ProgramData', 'Users', 'Documents and Settings'
    )
    foreach ($s in $skipExact) { if ($Name -eq $s) { return $true } }
    if ($Name -match '(?i)redist|directx|vcredist|dotnet|openal|physx|xna') { return $true }
    return $false
}

function Get-LnkTarget {
    param([string]$LnkPath)
    try {
        $sh = New-Object -ComObject WScript.Shell
        $sc = $sh.CreateShortcut($LnkPath)
        return [string]$sc.TargetPath
    } catch { return $null }
}

function Get-DesktopInventory {
    $desk = [Environment]::GetFolderPath("Desktop")
    $publicDesk = Join-Path $env:PUBLIC "Desktop"
    $roots = @()
    if ($desk) { $roots += $desk }
    if ($publicDesk -and (Test-Path -LiteralPath $publicDesk) -and $publicDesk -ne $desk) { $roots += $publicDesk }

    $items = New-Object System.Collections.ArrayList
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $target = $null
            if ($_.Extension -eq '.lnk') { $target = Get-LnkTarget -LnkPath $_.FullName }
            [void]$items.Add(@{
                desktopRoot = [string]$root
                name        = [string]$_.Name
                isDir       = [bool]$_.PSIsContainer
                target      = $target
            })
        }
    }
    return @{
        paths = @($roots)
        items = @($items.ToArray())
    }
}

function Test-NameHit {
    param([string]$Text, [string[]]$Needles)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $t = $Text.ToLowerInvariant()
    foreach ($n in $Needles) {
        if ($t.Contains($n.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Get-CafeFingerprint {
    # Imza listeleri — genisletilebilir
    $cafeAuto = @(
        'handycafe', 'handy cafe', 'pancafe', 'pan cafe', 'everycafe', 'every cafe',
        'cafebonzer', 'softcafe', 'antamedia', 'smartcafe', 'cafelatte', 'keycafe',
        'easycafe', 'cafeshare', 'gameover cafe', 'waitercafe', 'timestop',
        'cafeclient', 'cafeserver', 'nexcafe', 'truecafe', 'cybercafe'
    )
    $diskless = @(
        'ccboot', 'ccu diskless', 'ccudiskless', 'ccuclient', 'netcafem', 'netcafe',
        'icafecloud', 'diskless', 'thinstation', 'liberator', 'ccbootclient',
        'youngzsoft', 'disklessos'
    )
    $gameMenu = @(
        'nextplay', 'icafemenu', 'icafeclient', 'icafe', 'centerm', 'tikir',
        'gamemenu', 'gameportal', 'cyberarena', 'hsmanager', 'flashcafe',
        'oyunkafe', 'gamebox', 'launcher menu'
    )

    $procHits = New-Object System.Collections.ArrayList
    $svcHits = New-Object System.Collections.ArrayList
    $pathHits = New-Object System.Collections.ArrayList

    # Process listesi (tezgahta / tray'de yasayanlar genelde burada)
    try {
        Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
            $n = $_.ProcessName
            $path = $null
            try { $path = $_.Path } catch { }
            $blob = "$n $path"
            $cats = @()
            if (Test-NameHit $blob $cafeAuto) { $cats += 'cafeAutomation' }
            if (Test-NameHit $blob $diskless) { $cats += 'diskless' }
            if (Test-NameHit $blob $gameMenu) { $cats += 'gameMenu' }
            if ($cats.Count -gt 0) {
                [void]$procHits.Add(@{
                    name = [string]$n
                    path = [string]$path
                    categories = $cats
                })
            }
        }
    } catch {
        Write-CcmdmLog ("process listesi alinamadi: {0}" -f $_.Exception.Message) "WARN"
    }

    # Servisler (CCBoot client vs. sik servis olarak kalir)
    try {
        Get-Service -ErrorAction SilentlyContinue | ForEach-Object {
            $blob = "$($_.Name) $($_.DisplayName)"
            $cats = @()
            if (Test-NameHit $blob $cafeAuto) { $cats += 'cafeAutomation' }
            if (Test-NameHit $blob $diskless) { $cats += 'diskless' }
            if (Test-NameHit $blob $gameMenu) { $cats += 'gameMenu' }
            if ($cats.Count -gt 0) {
                [void]$svcHits.Add(@{
                    name = [string]$_.Name
                    displayName = [string]$_.DisplayName
                    status = [string]$_.Status
                    categories = $cats
                })
            }
        }
    } catch {
        Write-CcmdmLog ("servis listesi alinamadi: {0}" -f $_.Exception.Message) "WARN"
    }

    # Tipik kurulum yollari
    $probePaths = @(
        'C:\CCBootClient', 'C:\CCBoot', 'C:\Program Files\CCBoot', 'C:\Program Files (x86)\CCBoot',
        'C:\Program Files\CCU', 'C:\Program Files (x86)\CCU',
        'C:\NetCafeM', 'C:\Program Files\NetCafeM', 'C:\Program Files (x86)\NetCafeM',
        'C:\HandyCafe', 'C:\Program Files\HandyCafe', 'C:\Program Files (x86)\HandyCafe',
        'C:\PanCafe', 'C:\Program Files\PanCafe', 'C:\Program Files (x86)\PanCafe',
        'C:\EveryCafe', 'C:\Program Files\EveryCafe',
        'C:\iCafeMenu', 'C:\Program Files\iCafeMenu', 'C:\Program Files (x86)\iCafeMenu',
        'C:\Program Files\NextPlay', 'C:\Program Files (x86)\NextPlay',
        "$env:LOCALAPPDATA\NextPlay", "$env:ProgramData\NextPlay"
    )
    foreach ($pp in $probePaths) {
        if ($pp -and (Test-Path -LiteralPath $pp)) {
            $cats = @()
            if (Test-NameHit $pp $cafeAuto) { $cats += 'cafeAutomation' }
            if (Test-NameHit $pp $diskless) { $cats += 'diskless' }
            if (Test-NameHit $pp $gameMenu) { $cats += 'gameMenu' }
            if ($cats.Count -eq 0) { $cats = @('unknownInstall') }
            [void]$pathHits.Add(@{ path = [string]$pp; categories = $cats })
        }
    }

    $desktop = Get-DesktopInventory

    # Desktop kisayol / dosya adlarindan tahmin
    $desktopHints = New-Object System.Collections.ArrayList
    foreach ($it in $desktop.items) {
        $blob = "$($it.name) $($it.target)"
        $cats = @()
        if (Test-NameHit $blob $cafeAuto) { $cats += 'cafeAutomation' }
        if (Test-NameHit $blob $diskless) { $cats += 'diskless' }
        if (Test-NameHit $blob $gameMenu) { $cats += 'gameMenu' }
        if ($cats.Count -gt 0) {
            [void]$desktopHints.Add(@{
                name = $it.name; target = $it.target; categories = $cats
            })
        }
    }

    $guessCafe = $null
    $guessDisk = $null
    $guessMenu = $null
    foreach ($catPair in @(
        @{ cat = 'cafeAutomation'; dest = 'guessCafe' },
        @{ cat = 'diskless'; dest = 'guessDisk' },
        @{ cat = 'gameMenu'; dest = 'guessMenu' }
    )) {
        $scores = @{}
        foreach ($bucket in @($procHits, $svcHits, $pathHits, $desktopHints)) {
            foreach ($h in $bucket) {
                if ($h.categories -notcontains $catPair.cat) { continue }
                $label = $null
                if ($h.name) { $label = $h.name }
                elseif ($h.displayName) { $label = $h.displayName }
                elseif ($h.path) { $label = Split-Path -Leaf $h.path }
                if (-not $label) { continue }
                $key = $label.ToLowerInvariant()
                if (-not $scores.ContainsKey($key)) { $scores[$key] = @{ label = $label; score = 0 } }
                $scores[$key].score++
            }
        }
        if ($scores.Count -gt 0) {
            $best = $scores.GetEnumerator() | Sort-Object { $_.Value.score } -Descending | Select-Object -First 1
            if ($catPair.dest -eq 'guessCafe') { $guessCafe = $best.Value.label }
            elseif ($catPair.dest -eq 'guessDisk') { $guessDisk = $best.Value.label }
            else { $guessMenu = $best.Value.label }
        }
    }

    return @{
        desktop           = $desktop
        desktopHints      = @($desktopHints.ToArray())
        processesMatched  = @($procHits.ToArray())
        servicesMatched   = @($svcHits.ToArray())
        installPathsFound = @($pathHits.ToArray())
        guessed = @{
            cafeAutomation = $guessCafe
            diskless       = $guessDisk
            gameMenu       = $guessMenu
        }
    }
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
            if (Test-ShouldSkipDir -Name $_.Name) { return }
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

# Desktop + kafe/diskless/oyun-menu fingerprint
Write-CcmdmLog "fingerprint toplaniyor (desktop + process/servis imzalari)..."
$fingerprint = $null
$osInfo = $null
try {
    $osInfo = Get-WindowsOsInfo
    Write-CcmdmLog ("  os={0}" -f $osInfo.friendly)
} catch {
    Write-CcmdmLog ("OS bilgisi alinamadi: {0}" -f $_.Exception.Message) "WARN"
    $osInfo = @{ friendly = [string][Environment]::OSVersion.VersionString; error = $_.Exception.Message }
}
try {
    $fingerprint = Get-CafeFingerprint
    $g = $fingerprint.guessed
    Write-CcmdmLog ("  desktop items={0}" -f @($fingerprint.desktop.items).Count)
    Write-CcmdmLog ("  guessed cafeAutomation={0}" -f $g.cafeAutomation)
    Write-CcmdmLog ("  guessed diskless={0}" -f $g.diskless)
    Write-CcmdmLog ("  guessed gameMenu={0}" -f $g.gameMenu)
} catch {
    Write-CcmdmLog ("fingerprint hata: {0}" -f $_.Exception.Message) "WARN"
    $fingerprint = @{ error = $_.Exception.Message }
}

# fingerprint icine OS de gom
if ($fingerprint -is [hashtable]) {
    $fingerprint.os = $osInfo
}

# Desktop klasorunu de ayri "kok" gibi kaydet (oyun gosterme yazilimi kisayollari)
try {
    $deskInfo = $fingerprint.desktop
    if ($deskInfo -and $deskInfo.paths) {
        $deskPayload = @{
            schemaVersion = 1
            generator     = "CCMDM-Export.ps1"
            generatorVer  = $ScriptVersion
            rootId        = "DESKTOP"
            rootPaths     = @($deskInfo.paths)
            scannedAt     = (Get-Date).ToString("o")
            items         = @($deskInfo.items)
        }
        $deskJson = ConvertTo-CcmdmJson -Object $deskPayload
        [System.IO.File]::WriteAllText((Join-Path $outDir "DESKTOP.json"), $deskJson, [System.Text.UTF8Encoding]::new($false))
        $filesForGh[("cafes/{0}/{1}/DESKTOP.json" -f $cafeSlug, $stamp)] = $deskJson
        Write-CcmdmLog ("  DESKTOP.json ok ch={0}" -f $deskJson.Length)
    }
} catch {
    Write-CcmdmLog ("DESKTOP.json yazilamadi: {0}" -f $_.Exception.Message) "WARN"
}

try {
    $fpJson = ConvertTo-CcmdmJson -Object $fingerprint
    [System.IO.File]::WriteAllText((Join-Path $outDir "fingerprint.json"), $fpJson, [System.Text.UTF8Encoding]::new($false))
    $filesForGh[("cafes/{0}/{1}/fingerprint.json" -f $cafeSlug, $stamp)] = $fpJson
    Write-CcmdmLog ("  fingerprint.json ok ch={0}" -f $fpJson.Length)
} catch {
    Write-CcmdmLog ("fingerprint.json yazilamadi: {0}" -f $_.Exception.Message) "WARN"
}

Write-CcmdmLog "meta yaziliyor..."
$meta = @{
    schemaVersion = 1
    scriptVersion = $ScriptVersion
    cafeName = $cafeSlug; cafeSlug = $cafeSlug; stamp = $stamp
    hostname = [string]$env:COMPUTERNAME; userName = [string]$env:USERNAME
    os = $(if ($osInfo -and $osInfo.friendly) { $osInfo.friendly } else { [string][Environment]::OSVersion.VersionString })
    osInfo = $osInfo
    psVersion = $PSVersionTable.PSVersion.ToString()
    scannedAt = (Get-Date).ToString("o"); skipDrive = "C:\"; maxDepth = $MaxDepth
    roots = @($allSummaries); driveDiags = $driveDiags
    guessed = $(if ($fingerprint -and $fingerprint.guessed) { $fingerprint.guessed } else { $null })
    logFile = $LogFile; warning = $warn
    tokenLen = $(if ($env:CCMDM_GH_TOKEN) { $env:CCMDM_GH_TOKEN.Length } else { 0 })
    note = "FolderManifest + cafe fingerprint for CCMDM. No game payloads."
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
        $gAuto = $null; $gDisk = $null; $gMenu = $null
        if ($fingerprint -and $fingerprint.guessed) {
            $gAuto = $fingerprint.guessed.cafeAutomation
            $gDisk = $fingerprint.guessed.diskless
            $gMenu = $fingerprint.guessed.gameMenu
        }
        Write-Sonuc @"
CCMDM tamam.
slug: $cafeSlug
os: $(if ($osInfo) { $osInfo.friendly } else { '' })
manifestToplam: $sum
cafeAutomation: $gAuto
diskless: $gDisk
gameMenu: $gMenu
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
