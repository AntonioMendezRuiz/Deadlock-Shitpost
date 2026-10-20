<#
    Aplica una actualizacion ya descargada y relanza el instalador.
    Se ejecuta desde la version nueva (en %TEMP%) despues de que el
    instalador anterior termine, para poder sobrescribir sus archivos.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Source,
    [Parameter(Mandatory)][string]$Dest,
    [string]$GamePath = "",
    [switch]$Force
)

Start-Sleep -Milliseconds 800

if(-not (Test-Path -LiteralPath $Source)){
    Write-Host "[x] Origen inexistente: $Source" -ForegroundColor Red
    Read-Host "Enter para cerrar"
    exit 1
}
if(-not (Test-Path -LiteralPath $Dest)){
    Write-Host "[x] Destino inexistente: $Dest" -ForegroundColor Red
    Read-Host "Enter para cerrar"
    exit 1
}

$exclude = @("state", ".git", ".github")
foreach($it in (Get-ChildItem -LiteralPath $Source -Force | Where-Object { $exclude -notcontains $_.Name })){
    Copy-Item -LiteralPath $it.FullName -Destination $Dest -Recurse -Force
}
Write-Host "[+] Archivos actualizados en: $Dest" -ForegroundColor Green

$install = Join-Path $Dest "framework\install.ps1"
$argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $install, "-SkipUpdate")
if($GamePath){ $argList += @("-GamePath", $GamePath) }
if($Force){ $argList += "-Force" }

& powershell.exe @argList
Read-Host "Enter para cerrar"
