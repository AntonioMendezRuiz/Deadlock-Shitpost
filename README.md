# Deadlock Mods Framework

Framework de mods **solo cliente** para [Deadlock](https://store.steampowered.com/app/1422450/Deadlock/).
Permite empaquetar varios mods (texturas, audio, textos) y que los usuarios los instalen,
actualicen y reviertan con un instalador automático.

> Los mods son locales: los demás jugadores no ven ni escuchan tus cambios.

## Requisitos

- Windows 10/11
- Deadlock instalado vía Steam (se detecta solo, en cualquier disco)
- PowerShell 5.1 (incluido en Windows)

## Instalación (usuarios)

1. Descargá el ZIP de la última versión desde **Releases** de este repositorio.
2. Extraé el ZIP en una carpeta (por ejemplo `Documentos\DeadlockMods`).
3. Cerrá Deadlock y ejecutá **`Instalar.bat`**.

El instalador:

- Detecta Deadlock automáticamente (registro de Steam + `libraryfolders.vdf` + todos los discos).
- Copia los VPK a `game\citadel\addons`.
- Agrega los paths de mods a `gameinfo.gi` (con respaldo).
- Aplica parches de localización (con respaldo).
- Guarda el estado original en `state\`.

## Actualizaciones

- Al ejecutar `Instalar.bat`, si hay una versión nueva en GitHub **te avisa y ofrece descargarla**.
- `Actualizar.bat` fuerza la comprobación y actualiza sin preguntar.
- `framework\install.ps1 -CheckUpdate` solo consulta la versión.

La actualización descarga el release, reemplaza el framework y los mods (sin tocar `state\`)
y vuelve a instalar automáticamente.

## Revertir

Ejecutá **`Revertir.bat`**: restaura `gameinfo.gi`, los textos y los archivos originales,
y borra el mod. Después reiniciá Deadlock.

## Mods incluidos

| Mod | Descripción |
|---|---|
| `ratking-pp` | Bandera de Rat King con logo PP, audio de la definitiva y texto "¡Por España!". |

## Estructura

```
.
├─ Instalar.bat / Revertir.bat / Actualizar.bat
├─ framework/
│  ├─ install.ps1          # instalador / revertidor / actualizador
│  ├─ apply-update.ps1     # aplica una actualización descargada
│  └─ version.json         # versión del framework y repo de GitHub
├─ mods/
│  └─ ratking-pp/
│     ├─ mod.json          # manifiesto del mod
│     └─ payload/          # VPKs del mod
├─ scripts/
│  └─ pack-release.ps1     # genera el ZIP de release
└─ src/                    # fuentes (texturas, audio)
```

## Crear un mod nuevo

1. Creá `mods\<id>\payload\` y poné ahí tus archivos (normalmente `pakNN_dir.vpk`).
2. Creá `mods\<id>\mod.json`:

```json
{
  "id": "mi-mod",
  "name": "Mi Mod",
  "version": "1.0.0",
  "author": "TuNombre",
  "description": "Qué hace el mod.",
  "enabled": true,
  "addons": ["pak10_dir.vpk"],
  "files": [
    { "source": "payload/extra.vpk", "dest": "game/citadel/addons/extra_dir.vpk" }
  ],
  "localization": [
    {
      "file": "resource/localization/citadel_heroes/citadel_heroes_spanish.txt",
      "replacements": [
        { "from": "Texto original", "to": "Texto nuevo" }
      ]
    }
  ]
}
```

Campos:

- **`addons`**: nombres de archivos dentro de `payload\` que se copian a `game\citadel\addons\`.
- **`files`** *(opcional)*: copias arbitrarias. `source` es relativo a la carpeta del mod;
  `dest` es relativo a la raíz de Deadlock.
- **`localization`** *(opcional)*: parches de texto. `file` es relativo a `game\citadel\`.
  Se hace respaldo automático y se revierte con `Revertir.bat`.

Los mods con `"enabled": false` se omiten. También podés elegir mods puntuales:
`install.ps1 -Mods "ratking-pp,mi-mod"`.

## Publicar una versión

1. Actualizá `version` en `framework/version.json` (y en `mod.json` si cambió el mod).
2. Generá el paquete:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\pack-release.ps1
   ```

3. Subí el tag y el ZIP como release (el tag debe ser `vX.Y.Z`). Ejecutá esto
   **desde la carpeta del repo** o pasá `-R` para indicar el repositorio:

   ```powershell
   git tag v1.0.0
   git push origin v1.0.0
   gh release create v1.0.0 dist\deadlock-mods-1.0.0.zip -R AntonioMendezRuiz/Deadlock-Mod --title "v1.0.0" --notes "Cambios..."
   ```

El instalador consulta `https://api.github.com/repos/<OWNER>/<REPO>/releases/latest`
y descarga el asset que coincida con `assetPattern` de `version.json`.

## Notas

- Un parche de Deadlock puede sobrescribir `gameinfo.gi` o los textos: volvé a ejecutar
  `Instalar.bat` después de una actualización grande del juego.
- Si movés la carpeta del framework, mantené `state\` junto a `framework\` para poder revertir.
- `-Force` permite instalar con Deadlock abierto (no recomendado).
