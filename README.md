# CFMoto Link 0.4.0 — Smart Dashboard

App de iPhone, de código abierto y **no oficial**, que envía a la pantalla TFT de una moto CFMOTO
(probada en una 450NK) un panel hecho a medida: navegación GPS propia, música y avisos, con la
distribución que elijas desde el teléfono. También puede duplicar la pantalla del iPhone.

No está afiliada a CFMOTO, Carbit ni EasyConn. No es CarPlay. Úsala parado: configura el
destino, la música y el panel antes de arrancar.

## Qué hace

- **Panel para la moto** con siete modos: Solo GPS, Solo música, GPS + Música, GPS + Avisos,
  Música + Avisos, Panel completo y Personalizado.
- **Mi pantalla**: editor con vista previa real (el mismo dibujo que recibe la moto), zonas que
  se arrastran para intercambiarlas, tamaños ajustables, temas y perfiles guardados.
- **Navegación** con los mapas de Apple: búsqueda, rutas reales con alternativas, guía giro a
  giro con voz en español y recálculo.
- **Música**: lee y controla la app Música (Apple Music).
- **Avisos**: navegación, conexión con la moto y batería baja del iPhone.
- **Duplicar pantalla** (extensión ReplayKit) para ver Waze o Google Maps en la moto.

Lo que es real, lo que está limitado por iOS y lo que falta está en [docs/FEATURES.md](docs/FEATURES.md).

## Abrir y compilar

Requisitos: macOS con Xcode 16 o posterior y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate          # crea CFMotoLink.xcodeproj a partir de project.yml
open CFMotoLink.xcodeproj
```

El paquete `CFMotoLink_0.4.0_SmartDashboard.zip` ya trae `CFMotoLink.xcodeproj` generado.
En Xcode elige tu equipo de firma en los dos targets (`CFMotoLink` y `CFMotoLinkBroadcast`) y
ejecuta en un iPhone con iOS 16 o posterior.

Sin Mac: cada cambio en la rama `main` se compila en GitHub Actions y publica un `.ipa` sin
firmar en *Releases*.

## Instalar el .ipa

1. Descarga `CFMotoLink.ipa` de *Releases*.
2. Instálalo con [Sideloadly](https://sideloadly.io) o AltStore; se firma con tu Apple ID.
   Con una cuenta gratuita hay que reinstalar cada 7 días.
3. En el iPhone: Ajustes > General > VPN y gestión de dispositivos > confiar en tu Apple ID.

## Usarla con la moto

1. En la moto abre la pantalla del código QR y déjala abierta.
2. En el iPhone conéctate al Wi-Fi `DIRECT-…-CFMOTO` (clave `12345678`). Deja los datos
   móviles activos: ese Wi-Fi no da internet y el mapa lo necesita.
3. En **Inicio** pulsa **Conectar y enviar el panel**.
4. Cambia de modo o edita el panel en **Mi pantalla**: la moto lo refleja sin reconectar.

## Documentación

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): estructura y componentes.
- [docs/CONNECTION.md](docs/CONNECTION.md): comunicación con la moto.
- [docs/FEATURES.md](docs/FEATURES.md): estado real de cada función.
- [docs/TESTING.md](docs/TESTING.md): pruebas y resultados.

## Créditos y licencia

La conexión con la moto se basa en el trabajo de
[OpenCfMoto](https://github.com/zanderp/open-cfmoto). Licencia AGPL-3.0-or-later.
