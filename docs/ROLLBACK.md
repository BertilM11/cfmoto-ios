# Volver a la 0.6.0

La 0.6.0 se conserva intacta en cuatro sitios. Si la 0.6.1 falla o pierde la conexión con la
moto, se puede volver en un par de minutos.

## Dónde está la 0.6.0

| Dónde | Qué |
| --- | --- |
| Tu PC: `Descargas\CFMotoLink_BACKUP_ORIGINAL_0.6.0\` | `CFMotoLink_0.6.0.ipa`, el paquete original, `SHA256SUMS.txt`, `MANIFEST_0.6.0.txt` y `VERSION.txt` |
| Entrega de la 0.6.1: `BACKUP_ORIGINAL_0.6.0\` | Los mismos archivos |
| GitHub, publicación `build-8` | El IPA y el paquete de la 0.6.0 tal como se compilaron |
| GitHub, rama `backup/v0.6.0` y etiquetas `build-8` y `v0.6.0` | El código exacto (commit `88dfe27`) |

Huellas SHA-256 de la copia original:

```
9fe3703cb5270078fce417385db9786a14d94322d49210b000b56f667252a413  CFMotoLink_0.6.0.ipa
146373ea905bab2712c87e332f13ad58ecefe7684fc1a36fd66ecf76d91f4991  CFMotoLink_0.6.0_NavegacionMultimedia.zip
```

Comprobarlas en Windows (PowerShell o CMD, dentro de la carpeta del respaldo):

```
certutil -hashfile CFMotoLink_0.6.0.ipa SHA256
```

## Reinstalar la 0.6.0 en el iPhone

1. Abre Sideloadly y conecta el iPhone con el cable.
2. Toca el icono del IPA y elige `Descargas\CFMotoLink_BACKUP_ORIGINAL_0.6.0\CFMotoLink_0.6.0.ipa`.
3. Pulsa **Start**. Se instala encima de la 0.6.1 (mismo identificador `io.github.cfmotolink.app`).

Los ajustes del panel se conservan: la 0.6.1 no cambia el formato guardado (sigue siendo la
versión 3 de la configuración), así que la 0.6.0 los lee igual. El Client ID de Spotify también
se conserva; el permiso de Spotify hay que pedirlo otra vez (dura una hora y vive en memoria).

## Volver al código de la 0.6.0

Con Git:

```sh
git fetch origin
git checkout v0.6.0          # o: git checkout backup/v0.6.0
```

Con GitHub Desktop: *Branch > backup/v0.6.0*.

Para que la rama `main` vuelva a ser la 0.6.0 (solo si se decide abandonar la 0.6.1):

```sh
git checkout main
git revert --no-edit v0.6.0..HEAD   # deshace los cambios sin borrar el historial
git push
```

Cada envío a `main` vuelve a compilar y publica un IPA nuevo en *Releases*.

## Cuándo volver

- La moto no recibe imagen con la 0.6.1 y sí con la 0.6.0 (misma moto, mismo Wi-Fi).
- La app se cierra sola de forma repetida.
- Antes de volver, si puedes: **Más > Diagnóstico > Exportar informe**, para saber qué falló.
