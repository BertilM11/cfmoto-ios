# Volver a una versión anterior

La 0.6.1 y la 0.6.0 se conservan intactas. Si la 0.6.2 falla o no te gusta el diseño nuevo, se
puede volver en un par de minutos. La 0.6.2 solo cambia el dibujo de la pantalla: la conexión
con la moto, el vídeo y el protocolo son los de la 0.6.1.

## Dónde está la 0.6.1

| Dónde | Qué |
| --- | --- |
| Entrega de la 0.6.2: `BACKUP_ORIGINAL_0.6.1\` | `CFMotoLink_0.6.1.ipa`, el paquete original, `SHA256SUMS.txt`, `MANIFEST_0.6.1.txt` y `VERSION.txt` |
| Tu PC: `Descargas\CFMotoLink_BACKUP_ORIGINAL_0.6.1\` | Los mismos archivos |
| Tu PC: `Descargas\CFMotoLink_entrega_0.6.1\` | La entrega completa de la 0.6.1 |
| GitHub, publicación `build-9` | El IPA y el paquete de la 0.6.1 tal como se compilaron |
| GitHub, rama `backup/v0.6.1` y etiquetas `build-9` y `v0.6.1` | El código exacto (commit `6f1667a`) |

Huellas SHA-256 de la copia de la 0.6.1:

```
2ad287a0aa3f1d929dc83d3b9f46e764eafa79089d4ba278bef1913ad3a303e0  CFMotoLink_0.6.1.ipa
6780072558fe46b6732eeed035c87739e69894c9581a78fbad0cfbdbd4f1dde6  CFMotoLink_0.6.1_Estabilidad.zip
```

## Dónde está la 0.6.0

| Dónde | Qué |
| --- | --- |
| Tu PC: `Descargas\CFMotoLink_BACKUP_ORIGINAL_0.6.0\` | `CFMotoLink_0.6.0.ipa`, el paquete original y sus huellas |
| GitHub, publicación `build-8`, rama `backup/v0.6.0` y etiquetas `build-8` y `v0.6.0` | El IPA, el paquete y el código (commit `88dfe27`) |

```
9fe3703cb5270078fce417385db9786a14d94322d49210b000b56f667252a413  CFMotoLink_0.6.0.ipa
146373ea905bab2712c87e332f13ad58ecefe7684fc1a36fd66ecf76d91f4991  CFMotoLink_0.6.0_NavegacionMultimedia.zip
```

Comprobar una huella en Windows (PowerShell o CMD, dentro de la carpeta del respaldo):

```
certutil -hashfile CFMotoLink_0.6.1.ipa SHA256
```

## Reinstalar la 0.6.1 (o la 0.6.0) en el iPhone

1. Abre Sideloadly y conecta el iPhone con el cable.
2. Toca el icono del IPA y elige `Descargas\CFMotoLink_BACKUP_ORIGINAL_0.6.1\CFMotoLink_0.6.1.ipa`
   (o el de la 0.6.0).
3. Pulsa **Start**. Se instala encima (mismo identificador `io.github.cfmotolink.app`).

Los ajustes se conservan: la 0.6.2 no cambia el formato guardado (sigue siendo la versión 3 de
la configuración). El Client ID de Spotify también; el permiso de Spotify hay que pedirlo otra
vez (dura una hora y vive en memoria).

## Volver al código anterior

Con Git:

```sh
git fetch origin
git checkout v0.6.1          # o: git checkout backup/v0.6.1   (v0.6.0 / backup/v0.6.0 para la 0.6.0)
```

Con GitHub Desktop: *Branch > backup/v0.6.1*.

Para que la rama `main` vuelva a ser la 0.6.1 (solo si se decide abandonar la 0.6.2):

```sh
git checkout main
git revert --no-edit v0.6.1..HEAD   # deshace los cambios sin borrar el historial
git push
```

Cada envío a `main` vuelve a compilar y publica un IPA nuevo en *Releases*.

## Cuándo volver

- La moto no recibe imagen con la 0.6.2 y sí con la 0.6.1 (misma moto, mismo Wi-Fi).
- La app se cierra sola de forma repetida.
- El diseño nuevo no se lee bien en la TFT y prefieres el anterior.
- Antes de volver, si puedes: **Más > Diagnóstico > Exportar informe**, para saber qué falló.
