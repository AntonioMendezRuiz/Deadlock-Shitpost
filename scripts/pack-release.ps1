param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$cfgPath = Join-Path $root "framework\version.json"
$cfg = Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
if(-not $Version){ $Version = [string]$cfg.version }
if(-not $Version){ throw "No hay version (framework\version.json)." }

$dist  = Join-Path $root "dist"
$stage = Join-Path $dist "DeadlockMods"

if(Test-Path -LiteralPath $dist){ Remove-Item -LiteralPath $dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Copy-Item -LiteralPath (Join-Path $root "framework") -Destination $stage -Recurse -Force
Copy-Item -LiteralPath (Join-Path $root "mods")      -Destination $stage -Recurse -Force
foreach($name in @("Instalar.bat", "Revertir.bat", "README.md")){
    $p = Join-Path $root $name
    if(Test-Path -LiteralPath $p){ Copy-Item -LiteralPath $p -Destination $stage -Force }
}

$zip = Join-Path $dist ("deadlock-mods-$Version.zip")
Compress-Archive -Path $stage -DestinationPath $zip -Force
Remove-Item -LiteralPath $stage -Recurse -Force

Write-Host ("[+] Generado: " + $zip) -ForegroundColor Green
