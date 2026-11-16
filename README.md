# CFMoto Link (iOS, experimental)

App de iPhone que intenta enviar imagen a la pantalla TFT de una moto CFMOTO por el
Wi-Fi de la moto, usando el mismo protocolo EasyConnect que la app oficial de Android.

**Estado: experimental.** La versión 0.3 añade navegación GPS propia con los mapas de Apple
(búsqueda, rutas reales con alternativas, guía giro a giro con voz y recálculo) y una pantalla
de navegación dibujada a la medida de la moto. También puede duplicar la pantalla del iPhone
(extensión ReplayKit) para ver Waze o Google Maps. No es CarPlay.

No está afiliada a CFMOTO ni a Carbit. Úsala bajo tu propia responsabilidad y nunca
mientras conduces.

## Cómo probarla

1. Descarga `CFMotoLink.ipa` de la página de *Releases* de este repositorio.
2. Instálala en el iPhone desde un PC con [Sideloadly](https://sideloadly.io/) o AltStore,
   con tu Apple ID. Con una cuenta gratuita hay que reinstalarla cada 7 días.
3. En el iPhone: Ajustes > General > VPN y gestión de dispositivos > confía en tu Apple ID.
4. En la moto, abre la pantalla del código QR ("Conéctese con el teléfono móvil") y déjala abierta.
5. En el iPhone: Ajustes > Wi-Fi > conéctate a la red `DIRECT-…-CFMOTO-…` de la moto.
6. Abre CFMoto Link, pulsa **Transmitir pantalla a la moto** y luego **Iniciar transmisión**
   (también se puede desde el Centro de control: mantén pulsado *Grabar pantalla* y elige
   CFMoto Link). La opción *Prueba con imagen de prueba* sigue disponible.
7. Mira la pantalla de la moto. Pase lo que pase, pulsa **Copiar registro** y guarda el texto:
   es lo que permite saber hasta dónde llegó la conexión.

## Compilación

La compila GitHub Actions en un Mac (`.github/workflows/build.yml`): genera el proyecto con
XcodeGen, compila sin firma y publica el `.ipa` como release. No hace falta un Mac propio.

## Créditos y licencia

El protocolo fue documentado por el proyecto
[OpenCfMoto](https://github.com/zanderp/open-cfmoto) (© Alexandru y colaboradores,
AGPL-3.0-or-later), y esta app se escribió a partir de su documentación y su código.
Por eso este proyecto se publica también bajo **GNU AGPL-3.0-or-later** (ver `LICENSE`).
