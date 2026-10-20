<#
    Deadlock Mods - instalador / revertidor / actualizador

    Uso:
        Instalar (y actualizar): install.ps1
        Elegir mods al instalar: install.ps1 -Select
        Revertir:                install.ps1 -Revert
        Elegir mods al revertir: install.ps1 -Revert -Select
        Ver actualizaciones:     install.ps1 -CheckUpdate
        Omitir actualizacion:    install.ps1 -NoUpdate
        Ruta manual:             install.ps1 -GamePath "D:\...\common\Deadlock"
        Solo algunos mods:       install.ps1 -Mods "ratking-pp"
        Quitar algunos mods:     install.ps1 -Revert -Mods "ratking-pp"

    El framework instala los mods definidos en mods\<id>\mod.json:
      - addons:  VPKs que se copian a game\citadel\addons
      - files:   copias arbitrarias (source -> dest relativo al juego)
      - localization: parches de texto con respaldo
    Guarda el estado original en state\ para poder revertir.
#>
[CmdletBinding()]
param(
    [string]$GamePath = "",
    [switch]$Revert,
    [switch]$Force,
    [switch]$NoUpdate,
    [switch]$CheckUpdate,
    [switch]$SkipUpdate,
    [switch]$Select,
    [string]$Mods = "",
    [string]$ModDir = "",
    [string]$StateDir = ""
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$FrameworkDir = $PSScriptRoot
if(-not $FrameworkDir){ $FrameworkDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = Split-Path $FrameworkDir -Parent
if(-not $ModDir){ $ModDir = Join-Path $Root "mods" }
if(-not $StateDir){ $StateDir = Join-Path $Root "state" }
$ConfigPath   = Join-Path $FrameworkDir "version.json"
$ManifestPath = Join-Path $StateDir "manifest.json"

function Info($m){ Write-Host "[*] $m" }
function Ok($m){ Write-Host "[+] $m" -ForegroundColor Green }
function Warn($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Fail($m){ Write-Host "[x] $m" -ForegroundColor Red; exit 1 }

function Read-JsonFile($p){
    if(-not (Test-Path -LiteralPath $p)){ return $null }
    try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Write-JsonFile($p, $obj){
    $dir = Split-Path -Parent $p
    if($dir -and -not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    ($obj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $p -Encoding UTF8
}

$Config = Read-JsonFile $ConfigPath
if(-not $Config){ Fail "No encuentro la configuracion del framework: $ConfigPath" }
if(-not $Config.version){ Fail "version.json no tiene el campo 'version'." }

# =====================  VERSIONES  =====================
function ConvertTo-Ver($s){
    if(-not $s){ return $null }
    $t = ([string]$s).Trim()
    if($t -match '^[vV]'){ $t = $t.Substring(1) }
    $t = ($t -split '[-+]')[0]
    try { return [version]$t } catch { return $null }
}

# =====================  DETECCION DE DEADLOCK  =====================
function Get-SteamAppsDirs {
    $result  = New-Object System.Collections.Generic.List[string]
    $roots   = New-Object System.Collections.Generic.List[string]
    $vdfList = New-Object System.Collections.Generic.List[string]

    foreach($reg in @("HKCU:\Software\Valve\Steam","HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam")){
        try {
            $prop = Get-ItemProperty -Path $reg -ErrorAction Stop
            foreach($name in @("SteamPath","InstallPath")){
                if($prop.PSObject.Properties.Name -contains $name -and $prop.$name){
                    $roots.Add(($prop.$name -replace '/', '\'))
                }
            }
        } catch {}
    }

    $drives = @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Root)
    foreach($d in $drives){
        foreach($rel in @("Steam","SteamLibrary","Program Files (x86)\Steam","Program Files\Steam","Games\Steam","Games\SteamLibrary","SteamApps")){
            $cand = Join-Path $d $rel
            if(Test-Path -LiteralPath $cand){ $roots.Add($cand) }
        }
    }

    foreach($r in ($roots | Select-Object -Unique)){
        if((Split-Path $r -Leaf) -eq "steamapps"){ $result.Add($r) }
        foreach($rel in @("steamapps\libraryfolders.vdf","config\libraryfolders.vdf","libraryfolders.vdf")){
            $v = Join-Path $r $rel
            if(Test-Path -LiteralPath $v){ $vdfList.Add($v) }
        }
    }

    foreach($d in $drives){
        foreach($pattern in @("libraryfolders.vdf","*\libraryfolders.vdf","*\*\libraryfolders.vdf","*\steamapps\libraryfolders.vdf","*\*\steamapps\libraryfolders.vdf")){
            Get-ChildItem -Path (Join-Path $d $pattern) -File -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $vdfList.Add($_.FullName) }
        }
    }

    foreach($vdf in ($vdfList | Select-Object -Unique)){
        try {
            foreach($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')){
                $lib = $m.Groups[1].Value -replace '\\\\','\'
                $sa  = Join-Path $lib "steamapps"
                if(Test-Path -LiteralPath $sa){ $result.Add($sa) }
            }
            $homeDir = Split-Path $vdf -Parent
            if((Split-Path $homeDir -Leaf) -eq "steamapps"){ $result.Add($homeDir) }
        } catch {}
    }

    return ($result | Select-Object -Unique)
}

function Resolve-GamePath {
    param([string]$Explicit)
    if($Explicit){
        if(Test-Path (Join-Path $Explicit "game\citadel\gameinfo.gi")){ return $Explicit }
        Fail "La ruta indicada no parece ser Deadlock: $Explicit"
    }
    $steamApps = Get-SteamAppsDirs
    foreach($sa in $steamApps){
        $cand = Join-Path $sa "common\Deadlock"
        if(Test-Path (Join-Path $cand "game\citadel\gameinfo.gi")){ return $cand }
    }
    $rootsTxt = (($steamApps | ForEach-Object { Split-Path $_ -Parent } | Select-Object -Unique) -join " | ")
    Fail "No pude detectar Deadlock automaticamente. Librerias revisadas: $rootsTxt. Proba con -GamePath ""X:\ruta\a\common\Deadlock"""
}

function Assert-GameClosed {
    if($Force){ return }
    $p = @(Get-Process -Name "deadlock" -ErrorAction SilentlyContinue)
    if($p.Count -gt 0){
        Fail "Deadlock esta abierto (PID $($p.Id -join ', ')). Cerralo y volve a intentar (o usa -Force)."
    }
}

# =====================  ACTUALIZACIONES (GitHub Releases)  =====================
function Get-LatestRelease {
    if($env:DLMODS_OFFLINE -eq "1"){ return $null }
    if(-not $Config.repo -or $Config.repo -match '^OWNER/'){ return $null }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $headers = @{ "User-Agent" = "DeadlockMods"; "Accept" = "application/vnd.github+json" }
        return Invoke-RestMethod -Uri "https://api.github.com/repos/$($Config.repo)/releases/latest" -Headers $headers -TimeoutSec 10
    } catch { return $null }
}

function Get-UpdateInfo {
    $rel = Get-LatestRelease
    if(-not $rel){ return $null }
    $rv = ConvertTo-Ver $rel.tag_name
    $lv = ConvertTo-Ver $Config.version
    if(-not $rv -or -not $lv -or $rv -le $lv){ return $null }
    $pattern = if($Config.assetPattern){ [string]$Config.assetPattern } else { '\.zip$' }
    $assets = @($rel.assets)
    $asset = $assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
    if(-not $asset){ $asset = $assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1 }
    if(-not $asset){ return $null }
    return [pscustomobject]@{
        Version = $rv
        Tag     = [string]$rel.tag_name
        Notes   = [string]$rel.body
        Asset   = [string]$asset.name
        Url     = [string]$asset.browser_download_url
    }
}

function Invoke-SelfUpdate {
    param($info)
    $tmp = Join-Path $env:TEMP ("dlmods-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp "update.zip"

    Info "Descargando $($info.Asset)..."
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $info.Url -OutFile $zip -UseBasicParsing -TimeoutSec 180
    } catch {
        Fail "No se pudo descargar la actualizacion: $($_.Exception.Message)"
    }

    $ex = Join-Path $tmp "pkg"
    try { Expand-Archive -LiteralPath $zip -DestinationPath $ex -Force } catch {
        Fail "No se pudo descomprimir la actualizacion."
    }

    $srcRoot = $ex
    if(-not (Test-Path (Join-Path $srcRoot "framework\install.ps1"))){
        $hit = Get-ChildItem $ex -Recurse -Filter "install.ps1" -File -ErrorAction SilentlyContinue |
               Where-Object { (Split-Path $_.FullName -Parent) -like "*\framework" } |
               Select-Object -First 1
        if($hit){ $srcRoot = Split-Path (Split-Path $hit.FullName -Parent) -Parent }
    }
    if(-not (Test-Path (Join-Path $srcRoot "framework\install.ps1"))){
        Fail "El ZIP descargado no tiene la estructura esperada (framework\install.ps1)."
    }

    $apply = Join-Path $srcRoot "framework\apply-update.ps1"
    if(-not (Test-Path -LiteralPath $apply)){
        Fail "La actualizacion no incluye framework\apply-update.ps1."
    }

    $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$apply`" -Source `"$srcRoot`" -Dest `"$Root`""
    if($GamePath){ $argLine += " -GamePath `"$GamePath`"" }
    if($Force){ $argLine += " -Force" }

    Ok "Actualizacion lista. Se aplicara y se reabrira el instalador..."
    Start-Process -FilePath "powershell.exe" -ArgumentList $argLine
    exit 0
}

# =====================  MODS  =====================
function Get-AllMods {
    if(-not (Test-Path -LiteralPath $ModDir)){ Fail "No existe la carpeta de mods: $ModDir" }
    $list = @()
    foreach($dir in (Get-ChildItem -LiteralPath $ModDir -Directory -ErrorAction SilentlyContinue)){
        $mp = Join-Path $dir.FullName "mod.json"
        $j = Read-JsonFile $mp
        if(-not $j){ Warn "Ignorado (sin mod.json valido): $($dir.Name)"; continue }
        if(-not $j.id){ $j | Add-Member -NotePropertyName id -NotePropertyValue $dir.Name -Force }
        $j | Add-Member -NotePropertyName dir -NotePropertyValue $dir.FullName -Force
        $list += $j
    }
    if(-not $list){ Fail "No hay mods en $ModDir" }
    return $list
}

function Get-ManifestModIds {
    param($manifest, $all)
    $ids = @()
    if($manifest -and ($manifest.PSObject.Properties.Name -contains "mods")){
        $ids = @($manifest.mods | ForEach-Object { [string]$_ } | Where-Object { $_ })
    }
    if($ids.Count -eq 0 -and $manifest -and ($manifest.PSObject.Properties.Name -contains "installedAddons")){
        $installed = @($manifest.installedAddons | ForEach-Object { [string]$_ } | Where-Object { $_ })
        foreach($mod in $all){
            foreach($a in @($mod.addons)){
                if($installed -contains [string]$a){ $ids += [string]$mod.id; break }
            }
        }
    }
    return @($ids | Select-Object -Unique)
}

function Read-ModSelection {
    param($all, [string[]]$defaultIds, [string[]]$installedIds, [switch]$AllowNone)
    $items = @($all | Sort-Object @{Expression={[string]$_.name}}, @{Expression={[string]$_.id}})
    Write-Host ""
    Info "Mods disponibles:"
    for($i = 0; $i -lt $items.Count; $i++){
        $mod = $items[$i]
        $mark = ""
        if($installedIds -contains [string]$mod.id){ $mark = " [instalado]" }
        Write-Host ("  [{0}] {1} ({2}) v{3}{4}" -f ($i + 1), $mod.name, $mod.id, $mod.version, $mark)
    }
    $defNums = @()
    for($i = 0; $i -lt $items.Count; $i++){
        if($defaultIds -contains [string]$items[$i].id){ $defNums += [string]($i + 1) }
    }
    $defText = if($defNums.Count -gt 0){ $defNums -join "," } else { "ninguno" }
    $tries = 0
    while($true){
        $tries++
        if($tries -gt 20){ Fail "Demasiados intentos de seleccion." }
        $raw = Read-Host ("Seleccion [1-{0}, A=todos, N=ninguno] (Enter = {1})" -f $items.Count, $defText)
        $chosen = @()
        if([string]::IsNullOrWhiteSpace($raw)){
            if($defNums.Count -gt 0){
                $chosen = @($items | Where-Object { $defaultIds -contains [string]$_.id })
            } elseif($AllowNone){
                return @()
            } else {
                $chosen = @($items | Where-Object {
                    $enabled = $true
                    if($_.PSObject.Properties.Name -contains "enabled"){ $enabled = [bool]$_.enabled }
                    $enabled
                })
            }
        } elseif($raw -match '^(a|t|all|todos|\*)$'){
            $chosen = @($items)
        } elseif($raw -match '^(n|none|ninguno|0)$'){
            if($AllowNone){ return @() }
            Warn "Elegi al menos un mod."
            continue
        } else {
            $bad = @()
            foreach($n in @($raw -split '[,\s]+' | Where-Object { $_ })){
                $idx = 0
                if(-not [int]::TryParse($n, [ref]$idx) -or $idx -lt 1 -or $idx -gt $items.Count){
                    $bad += $n
                    continue
                }
                $chosen += $items[$idx - 1]
            }
            if($bad.Count -gt 0){ Warn "Opcion invalida: $($bad -join ', ')"; continue }
        }
        if(-not $chosen -and -not $AllowNone){ Warn "Elegi al menos un mod."; continue }
        return @($chosen | Sort-Object id -Unique)
    }
}

function Select-Mods {
    param($all)
    $manifest = Read-Manifest
    $installedIds = @(Get-ManifestModIds $manifest $all)
    if($Mods){
        $ids = @($Mods.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $sel = @()
        foreach($m in $all){
            if($ids -contains [string]$m.id){ $sel += $m }
        }
        foreach($id in $ids){
            if(-not ($all | Where-Object { [string]$_.id -eq $id })){ Warn "Mod inexistente: $id" }
        }
        if(-not $sel){ Fail "No hay mods para instalar." }
        return $sel
    }
    if($Select){
        $defaultIds = @()
        if($installedIds.Count -gt 0){
            $defaultIds = $installedIds
        } else {
            $defaultIds = @($all | Where-Object {
                $enabled = $true
                if($_.PSObject.Properties.Name -contains "enabled"){ $enabled = [bool]$_.enabled }
                $enabled
            } | ForEach-Object { [string]$_.id })
        }
        $sel = @(Read-ModSelection -all $all -defaultIds $defaultIds -installedIds $installedIds)
        if(-not $sel){ Fail "No hay mods para instalar." }
        return $sel
    }
    if($installedIds.Count -gt 0){
        $sel = @($all | Where-Object { $installedIds -contains [string]$_.id })
        if($sel.Count -gt 0){ return $sel }
    }
    $sel = @($all | Where-Object {
        $enabled = $true
        if($_.PSObject.Properties.Name -contains "enabled"){ $enabled = [bool]$_.enabled }
        $enabled
    })
    if(-not $sel){ Fail "No hay mods para instalar." }
    return $sel
}

# =====================  ESTADO  =====================
function Read-Manifest { return (Read-JsonFile $ManifestPath) }
function Write-Manifest($m){ Write-JsonFile $ManifestPath $m }

function Ensure-State {
    $m = Read-Manifest
    if($m){ return $m }

    $legacy = Join-Path $Root "installer\state"
    if(($legacy -ne $StateDir) -and (Test-Path (Join-Path $legacy "manifest.json")) -and -not (Test-Path -LiteralPath $ManifestPath)){
        Info "Migrando respaldo del instalador anterior..."
        New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
        foreach($item in (Get-ChildItem -LiteralPath $legacy -Force)){
            Copy-Item -LiteralPath $item.FullName -Destination $StateDir -Recurse -Force
        }
        $m = Read-Manifest
        if($m){
            if($m.PSObject.Properties.Name -contains "addedFiles" -and -not ($m.PSObject.Properties.Name -contains "installedAddons")){
                $m | Add-Member -NotePropertyName installedAddons -NotePropertyValue @($m.addedFiles) -Force
            }
            if(($m.PSObject.Properties.Name -contains "locPatched") -and @($m.locPatched | Where-Object { $_ -is [string] }).Count -gt 0){
                $norm = @()
                foreach($e in @($m.locPatched)){
                    if($e -is [string]){
                        $found = Get-ChildItem (Join-Path $citadel "resource\localization") -Recurse -File -Filter $e -ErrorAction SilentlyContinue | Select-Object -First 1
                        if($found){
                            $rel = $found.FullName.Substring($citadel.Length + 1)
                            $norm += [pscustomobject]@{ file = $rel; backup = $e }
                        }
                    } else { $norm += $e }
                }
                $m | Add-Member -NotePropertyName locPatched -NotePropertyValue $norm -Force
            }
            if(-not ($m.PSObject.Properties.Name -contains "mods")){ $m | Add-Member -NotePropertyName mods -NotePropertyValue @() -Force }
            $m | Add-Member -NotePropertyName frameworkVersion -NotePropertyValue $Config.version -Force
            Write-Manifest $m
        }
        try { Remove-Item -LiteralPath $legacy -Recurse -Force } catch {}
        Ok "Respaldo migrado a: $StateDir"
        return $m
    }

    Info "Primera vez: creando respaldo del estado original..."
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    Copy-Item -LiteralPath $gi -Destination (Join-Path $StateDir "gameinfo.gi") -Force
    $backed = @()
    if(Test-Path -LiteralPath $addons){
        $bak = Join-Path $StateDir "addons"
        New-Item -ItemType Directory -Force -Path $bak | Out-Null
        foreach($f in (Get-ChildItem -LiteralPath $addons -File)){
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $bak $f.Name) -Force
            $backed += $f.Name
        }
    }
    $m = [pscustomobject]@{
        version          = 2
        frameworkVersion = $Config.version
        createdAt        = (Get-Date).ToString("s")
        gamePath         = $GamePath
        gameInfoModified = $false
        installedAddons  = @()
        backedUpAddons   = $backed
        locPatched       = @()
        mods             = @()
    }
    Write-Manifest $m
    Ok "Respaldo guardado en: $StateDir"
    return $m
}

# =====================  PARCHES DEL JUEGO  =====================
function Enable-GameInfoPaths {
    $raw = [System.IO.File]::ReadAllText($gi)
    if($raw -match "(?m)^\s*Mod\s+citadel\s*$"){
        Info "gameinfo.gi ya tenia los paths del mod."
        return $false
    }
    $nl     = if($raw -match "`r`n"){ "`r`n" } else { "`n" }
    $anchor = "`t`t`tGame`t`t`t`tcitadel"
    $idx    = $raw.IndexOf($anchor)
    if($idx -lt 0){ Fail "No encontre la linea 'Game citadel' en gameinfo.gi." }
    $block  = "`t`t`tMod`t`t`t`tcitadel$nl" +
              "`t`t`tWrite`t`t`t`tcitadel$nl" +
              "`t`t`tGame`t`t`t`tcitadel/addons$nl"
    $new = $raw.Substring(0,$idx) + $block + $raw.Substring($idx)
    [System.IO.File]::WriteAllText($gi, $new, (New-Object System.Text.UTF8Encoding($false)))
    Ok "gameinfo.gi actualizado (paths de mods agregados)."
    return $true
}

function Apply-ModLocalization {
    param($mod)
    $records = @()
    foreach($entry in @($mod.localization)){
        if(-not $entry){ continue }
        $rel = ([string]$entry.file) -replace '/', '\'
        if(-not $rel){ continue }
        $full = Join-Path $citadel $rel
        if(-not (Test-Path -LiteralPath $full)){
            Warn "No existe '$rel' (mod $($mod.id)); se omite."
            continue
        }
        $bytes  = [System.IO.File]::ReadAllBytes($full)
        $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        $text   = [System.Text.Encoding]::UTF8.GetString($bytes)
        if($hasBom -and $text.Length -gt 0){ $text = $text.Substring(1) }
        $before = $text
        foreach($r in @($entry.replacements)){
            if($r -and $null -ne $r.from -and $null -ne $r.to){
                $text = $text.Replace([string]$r.from, [string]$r.to)
            }
        }
        if($text -eq $before){ Info "Sin cambios: $rel"; continue }

        $leaf = Split-Path $rel -Leaf
        $bak  = Join-Path $LocDir $leaf
        if(-not (Test-Path -LiteralPath $bak)){
            New-Item -ItemType Directory -Force -Path $LocDir | Out-Null
            Copy-Item -LiteralPath $full -Destination $bak -Force
        }
        [System.IO.File]::WriteAllText($full, $text, (New-Object System.Text.UTF8Encoding($hasBom)))
        Ok "Texto parcheado: $rel"
        $records += [pscustomobject]@{ file = $rel; backup = $leaf }
    }
    return $records
}

function Restore-LocalizationBackups {
    param($manifest)
    $entries = @()
    if($manifest.PSObject.Properties.Name -contains "locPatched"){ $entries = @($manifest.locPatched) }
    foreach($e in $entries){
        if($e -is [string]){
            $bak = Join-Path $LocDir $e
            $found = Get-ChildItem (Join-Path $citadel "resource\localization") -Recurse -File -Filter $e -ErrorAction SilentlyContinue | Select-Object -First 1
            if($found -and (Test-Path -LiteralPath $bak)){
                Copy-Item -LiteralPath $bak -Destination $found.FullName -Force
                Ok "Localizacion restaurada: $e"
            }
        } else {
            $bak = Join-Path $LocDir ([string]$e.backup)
            $dst = Join-Path $citadel ([string]$e.file)
            if((Test-Path -LiteralPath $bak) -and (Test-Path -LiteralPath $dst)){
                Copy-Item -LiteralPath $bak -Destination $dst -Force
                Ok "Localizacion restaurada: $($e.file)"
            }
        }
    }
}

function Invoke-ModUninstall {
    param($manifest, $all, [string[]]$removeIds)
    $installedIds = @(Get-ManifestModIds $manifest $all)
    $removeIds = @($removeIds | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Unique)
    foreach($id in $removeIds){
        if(-not ($installedIds -contains $id)){ Warn "No estaba instalado: $id" }
    }
    $removeIds = @($removeIds | Where-Object { $installedIds -contains $_ })
    if($removeIds.Count -eq 0){ return $true }
    $keepIds = @($installedIds | Where-Object { $removeIds -notcontains $_ })
    if($keepIds.Count -eq 0){ return $false }

    $keepMods = @($all | Where-Object { $keepIds -contains [string]$_.id })
    $removeMods = @($all | Where-Object { $removeIds -contains [string]$_.id })

    Restore-LocalizationBackups $manifest

    $keepAddons = @()
    foreach($mod in $keepMods){ foreach($a in @($mod.addons)){ if($a){ $keepAddons += [string]$a } } }
    $removeAddons = @()
    foreach($mod in $removeMods){ foreach($a in @($mod.addons)){ if($a){ $removeAddons += [string]$a } } }

    foreach($name in ($removeAddons | Select-Object -Unique)){
        if($keepAddons -contains $name){ continue }
        $target = Join-Path $addons $name
        if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Force; Ok "Eliminado del juego: $name" }
        $bak = Join-Path $bakAddons $name
        if(Test-Path -LiteralPath $bak){ Copy-Item -LiteralPath $bak -Destination $target -Force; Ok "Restaurado original: $name" }
    }

    $locNew = @()
    foreach($mod in $keepMods){ $locNew += @(Apply-ModLocalization $mod) }

    $manifest | Add-Member -NotePropertyName installedAddons -NotePropertyValue @($keepAddons | Select-Object -Unique) -Force
    $manifest | Add-Member -NotePropertyName locPatched -NotePropertyValue @($locNew) -Force
    $manifest | Add-Member -NotePropertyName mods -NotePropertyValue @($keepIds) -Force
    $manifest | Add-Member -NotePropertyName frameworkVersion -NotePropertyValue $Config.version -Force
    $manifest | Add-Member -NotePropertyName gamePath -NotePropertyValue $GamePath -Force
    Write-Manifest $manifest
    Ok "Desinstalados: $($removeIds -join ', ')"
    Ok "Conservados: $($keepIds -join ', ')"
    return $true
}

# =====================  MAIN  =====================
if($CheckUpdate){
    $info = Get-UpdateInfo
    if($info){
        Ok "Actualizacion disponible: $($info.Tag) (instalada v$($Config.version))."
        if($info.Notes){ Write-Host ""; Write-Host $info.Notes }
    } else {
        Ok "Estas al dia (v$($Config.version)) o no se pudo consultar GitHub."
    }
    exit 0
}

if(-not $Revert -and -not $NoUpdate -and -not $SkipUpdate){
    $info = Get-UpdateInfo
    if($info){
        Warn "Nueva version disponible: $($info.Tag) (tenes v$($Config.version)). Actualizando..."
        if($info.Notes){ Write-Host ""; Write-Host $info.Notes; Write-Host "" }
        Invoke-SelfUpdate $info
    }
}

$GamePath = Resolve-GamePath -Explicit $GamePath
$citadel  = Join-Path $GamePath "game\citadel"
$addons   = Join-Path $citadel "addons"
$gi       = Join-Path $citadel "gameinfo.gi"
$bakAddons= Join-Path $StateDir "addons"
$LocDir   = Join-Path $StateDir "loc"

Info "Deadlock: $GamePath"
Assert-GameClosed

if($Revert){
    $m = Read-Manifest
    if(-not $m){ Fail "No hay respaldo para revertir (no existe $ManifestPath)." }

    $removeIds = @()
    if($Mods){
        $removeIds = @($Mods.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } elseif($Select){
        $allRevert = @(Get-AllMods)
        $installedIds = @(Get-ManifestModIds $m $allRevert)
        if($installedIds.Count -eq 0){ Fail "No hay mods instalados para desinstalar." }
        $picked = @(Read-ModSelection -all $allRevert -defaultIds @() -installedIds $installedIds -AllowNone)
        if($picked.Count -eq 0){ Info "No se desinstalo nada."; exit 0 }
        $removeIds = @($picked | ForEach-Object { [string]$_.id })
    }

    if($removeIds.Count -gt 0){
        $allRevert = @(Get-AllMods)
        if(Invoke-ModUninstall $m $allRevert $removeIds){
            Ok "Reinicia Deadlock."
            exit 0
        }
    }

    $bakGi = Join-Path $StateDir "gameinfo.gi"
    if(Test-Path -LiteralPath $bakGi){
        Copy-Item -LiteralPath $bakGi -Destination $gi -Force
        Ok "gameinfo.gi restaurado al original."
    } else {
        Warn "No habia gameinfo.gi en el respaldo; no lo toco."
    }

    Restore-LocalizationBackups $m

    $names = @()
    if($m.PSObject.Properties.Name -contains "installedAddons"){ $names = @($m.installedAddons) }
    elseif($m.PSObject.Properties.Name -contains "addedFiles"){ $names = @($m.addedFiles) }
    if(Test-Path -LiteralPath $ModDir){
        foreach($d in (Get-ChildItem -LiteralPath $ModDir -Directory -ErrorAction SilentlyContinue)){
            $j = Read-JsonFile (Join-Path $d.FullName "mod.json")
            if($j){ foreach($a in @($j.addons)){ $names += [string]$a } }
        }
    }
    foreach($name in ($names | Where-Object { $_ } | Select-Object -Unique)){
        $target = Join-Path $addons $name
        if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Force; Ok "Eliminado del juego: $name" }
        $bak = Join-Path $bakAddons $name
        if(Test-Path -LiteralPath $bak){ Copy-Item -LiteralPath $bak -Destination $target -Force; Ok "Restaurado original: $name" }
    }

    if((Test-Path -LiteralPath $addons) -and -not (Get-ChildItem -LiteralPath $addons -Force)){
        Remove-Item -LiteralPath $addons -Recurse -Force
        Info "Carpeta 'addons' vacia eliminada."
    }

    Remove-Item -LiteralPath $StateDir -Recurse -Force
    Ok "Mods revertidos por completo. Reinicia Deadlock."
    exit 0
}

if(-not (Test-Path -LiteralPath $ModDir)){ Fail "No existe la carpeta de mods: $ModDir" }
$allMods  = Get-AllMods
$selected = Select-Mods $allMods

$m = Ensure-State
if(-not (Test-Path -LiteralPath $addons)){ New-Item -ItemType Directory -Force -Path $addons | Out-Null }

$installedAddons = @()
$fileCount = 0
foreach($mod in $selected){
    $modDir = [string]$mod.dir
    foreach($name in @($mod.addons)){
        if(-not $name){ continue }
        $src = Join-Path $modDir ("payload\" + [string]$name)
        if(-not (Test-Path -LiteralPath $src)){ Fail "Falta el archivo del mod '$($mod.id)': $src" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $addons ([string]$name)) -Force
        Ok "Instalado: $name ($($mod.id))"
        $installedAddons += [string]$name
    }
    foreach($f in @($mod.files)){
        if(-not $f -or -not $f.source -or -not $f.dest){ continue }
        $src = Join-Path $modDir ([string]$f.source)
        $dst = Join-Path $GamePath ([string]$f.dest)
        if(-not (Test-Path -LiteralPath $src)){ Fail "Falta el archivo '$($f.source)' (mod $($mod.id))." }
        $dstDir = Split-Path $dst -Parent
        if($dstDir -and -not (Test-Path -LiteralPath $dstDir)){ New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
        Copy-Item -LiteralPath $src -Destination $dst -Force
        Ok "Copiado: $($f.dest) ($($mod.id))"
        $fileCount++
    }
}

$needsGameInfo = ($installedAddons.Count -gt 0) -or ($fileCount -gt 0)
if($needsGameInfo){ if(Enable-GameInfoPaths){ $m.gameInfoModified = $true } }

$locNew = @()
foreach($mod in $selected){ $locNew += @(Apply-ModLocalization $mod) }

$prevAddons = @()
if($m.PSObject.Properties.Name -contains "installedAddons"){ $prevAddons = @($m.installedAddons) }
elseif($m.PSObject.Properties.Name -contains "addedFiles"){ $prevAddons = @($m.addedFiles) }
foreach($old in ($prevAddons | Where-Object { $_ } | Select-Object -Unique)){
    if(-not ($installedAddons -contains $old)){
        $target = Join-Path $addons $old
        if(Test-Path -LiteralPath $target){ Remove-Item -LiteralPath $target -Force; Ok "Quitado (ya no esta en mods): $old" }
        $bak = Join-Path $bakAddons $old
        if(Test-Path -LiteralPath $bak){ Copy-Item -LiteralPath $bak -Destination $target -Force; Ok "Restaurado original: $old" }
    }
}

$locMap = [ordered]@{}
if($m.PSObject.Properties.Name -contains "locPatched"){
    foreach($e in @($m.locPatched)){
        if($e -and -not ($e -is [string])){ $locMap[(([string]$e.file) -replace '/', '\')] = $e }
    }
}
foreach($r in $locNew){ $locMap[(([string]$r.file) -replace '/', '\')] = $r }

$m | Add-Member -NotePropertyName installedAddons  -NotePropertyValue @($installedAddons | Select-Object -Unique) -Force
$m | Add-Member -NotePropertyName locPatched       -NotePropertyValue @($locMap.Values) -Force
$m | Add-Member -NotePropertyName mods             -NotePropertyValue @($selected | ForEach-Object { [string]$_.id }) -Force
$m | Add-Member -NotePropertyName frameworkVersion -NotePropertyValue $Config.version -Force
$m | Add-Member -NotePropertyName gamePath         -NotePropertyValue $GamePath -Force
Write-Manifest $m

Ok "Instalacion completa. Abri Deadlock y elegi a Rat King."
