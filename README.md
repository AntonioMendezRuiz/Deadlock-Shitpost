# Deadlock Mods Framework

Framework de mods **solo cliente** para [Deadlock](https://store.steampowered.com/app/1422450/Deadlock/).
Permite empaquetar varios mods (texturas, audio, textos) para que los usuarios los instalen,
actualicen y reviertan con un instalador automático.

> Los mods son locales: los demás jugadores no ven ni escuchan tus cambios.

## Requisitos

- Windows 10/11
- Deadlock instalado vía Steam (se detecta solo, en cualquier disco)
- PowerShell 5.1 (incluido en Windows)

## Instalación (usuarios)

1. Descarga el ZIP de la última versión desde **Releases** de este repositorio.
2. Extrae el ZIP en una carpeta (por ejemplo `Documentos\DeadlockMods`).
3. Cierra Deadlock y ejecuta **`Instalar.bat`**.
4. Elige qué mods quieres instalar (números separados por comas, `A` para todos,
   `N` para ninguno; Enter usa la selección actual).

El instalador:

- Detecta Deadlock automáticamente (registro de Steam + `libraryfolders.vdf` + todos los discos).
- Copia los VPK de los mods elegidos a `game\citadel\addons`.
- Agrega los paths de mods a `gameinfo.gi` (con copia de seguridad).
- Aplica parches de localización (con copia de seguridad).
- Guarda el estado original en `state\`.

## Actualizaciones

- **Automáticas:** al ejecutar `Instalar.bat`, si hay una versión nueva en GitHub se descarga,
  se aplica y se reinstala sola, conservando los mods que tenías instalados.
- `framework\install.ps1 -CheckUpdate` solo consulta la versión.
- `framework\install.ps1 -NoUpdate` instala sin comprobar actualizaciones.

La actualización descarga el release, reemplaza el framework y los mods (sin tocar `state\`)
y vuelve a instalar automáticamente.

## Revertir

Ejecuta **`Revertir.bat`** y elige qué mods quitar (números, `A` para todos,
`N` o Enter para cancelar). Si quitas todos, restaura `gameinfo.gi`, los textos
y los archivos originales. Después reinicia Deadlock.

## Personajes incluidos

| Personaje | Descripción |
|---|---|
| Billy | Camiseta del Real Betis para Billy. |
| Grey Talon | Cubo de Glovo con logo para Grey Talon (reemplaza el carcaj y quita la falda). |
| Infernus | Audio de "A robar carteras" al usar Flame Dash y habilidad renombrada. |
| Mo & Krill | Camiseta roja del PSOE con logo para Mo & Krill. |
| Rat King | Bandera de Rat King con logo PP, audio de la definitiva y texto "¡Por España!". |


## Estructura

```
.
├─ Instalar.bat / Revertir.bat
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

1. Crea `mods\<id>\payload\` y pon ahí tus archivos (normalmente `pakNN_dir.vpk`).
2. Crea `mods\<id>\mod.json`:

```json
{
  "id": "mi-mod",
  "name": "Mi Personaje",
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

- **`name`**: nombre del personaje que aparece en el instalador.
- **`addons`**: nombres de archivos dentro de `payload\` que se copian a `game\citadel\addons\`.
- **`files`** *(opcional)*: copias arbitrarias. `source` es relativo a la carpeta del mod;
  `dest` es relativo a la raíz de Deadlock.
- **`localization`** *(opcional)*: parches de texto. `file` es relativo a `game\citadel\`.
  Se hace una copia de seguridad automática y se revierte con `Revertir.bat`.

Los mods con `"enabled": false` se omiten. También puedes elegir mods puntuales:

- `install.ps1 -Select` muestra un menú para elegir qué instalar.
- `install.ps1 -Mods "ratking-pp,mi-mod"` instala solo esos mods.
- `install.ps1 -Revert -Select` muestra un menú para elegir qué desinstalar.
- `install.ps1 -Revert -Mods "ratking-pp"` desinstala solo esos mods.

## Publicar una versión

1. Actualiza `version` en `framework/version.json` (y en `mod.json` si cambió el mod).
2. Genera el paquete:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\pack-release.ps1
   ```

3. Sube el tag y el ZIP como release (el tag debe ser `vX.Y.Z`). Ejecuta esto
   **desde la carpeta del repo** o pasa `-R` para indicar el repositorio:

   ```powershell
   git tag v1.0.0
   git push origin v1.0.0
   gh release create v1.0.0 dist\deadlock-mods-1.0.0.zip -R AntonioMendezRuiz/Deadlock-Shitpost --title "v1.0.0" --notes "Cambios..."
   ```

El instalador consulta `https://api.github.com/repos/<OWNER>/<REPO>/releases/latest`
y descarga el asset que coincida con `assetPattern` de `version.json`.

## Notas

- Un parche de Deadlock puede sobrescribir `gameinfo.gi` o los textos: vuelve a ejecutar
  `Instalar.bat` después de una actualización grande del juego.
- Si mueves la carpeta del framework, mantén `state\` junto a `framework\` para poder revertir.
- `-Force` permite instalar con Deadlock abierto (no recomendado).
