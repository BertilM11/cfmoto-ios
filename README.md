# CFMoto Link 0.6.0 — Navegación y multimedia

App de iPhone, de código abierto y **no oficial**, que envía a la pantalla TFT de una moto CFMOTO
(probada en una 450NK) un panel hecho a medida: navegación GPS propia, música y avisos, con la
distribución que elijas desde el teléfono. También puede duplicar la pantalla del iPhone.

No está afiliada a CFMOTO, Carbit ni EasyConn. No es CarPlay. Úsala parado: configura el
destino, la música y el panel antes de arrancar.

## Qué hace

- **Imagen completa**: la app usa los 800×400 que pide la moto; los indicadores de la moto
  (velocidad, rpm, marcha, testigos) siguen en su propia franja, debajo, sin taparse
  (comprobado con fotos de la 0.3 y la 0.5).
- **Mapa de calles de Apple Maps** en la moto, con nombres de calles, la ruta resaltada con
  borde, la flecha del próximo giro dibujada sobre la ruta, la posición, la brújula, vista 3D,
  tráfico (iOS 17+), zoom automático y las rutas propuestas antes de empezar.
- **Proveedor de navegación** (0.6): CFMoto Link guía en la moto giro a giro; Mapas de Apple,
  Google Maps o Waze se abren con el destino mediante su enlace oficial y la moto muestra el
  mapa, tu posición y el destino (esas apps no comparten sus giros). El destino se conserva al
  cambiar de proveedor.
- **Día y noche automáticos** (0.6) según el amanecer y el atardecer donde estás, o siempre
  claro, o siempre oscuro: es el estilo de día o de noche de Apple Maps, con un fundido suave.
- **Tarjeta de música con los colores de la portada** (0.6), para Spotify y Apple Music, con el
  texto siempre legible y las reglas de marca de Spotify.
- **Modos**: 1 · Navegación completa, 2 · Navegación + música compacta, 3 · Pantalla dividida
  (mapa a la izquierda, música grande a la derecha), 4 · Música completa, 5 · Personalizado, y
  los de la 0.4 (Panel completo, Navegación + Avisos, Música + Avisos).
- **Personalización del tablero** (0.6): navegación, día y noche, estilo de la ruta, música,
  tamaños, animaciones y diseño predeterminado en una sola pantalla, con vista previa real.
- **Mi pantalla**: editor de tarjetas flotantes y perfiles.
- **Navegación** con los mapas de Apple: búsqueda, rutas reales, guía con voz en español y
  recálculo.
- **Música**: Apple Music (app Música) o **Spotify** con su SDK oficial (con tu propio Client ID).
- **Avisos**: navegación, conexión con la moto y batería baja del iPhone.
- **Duplicar pantalla** (extensión ReplayKit) para ver Waze o Google Maps en la moto con el
  iPhone desbloqueado.

Proveedores, licencias y límites: [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md).
Lo que es real, lo que está limitado por iOS y lo que falta: [docs/FEATURES.md](docs/FEATURES.md).

## Abrir y compilar

Requisitos: macOS con Xcode 16 o posterior y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate          # crea CFMotoLink.xcodeproj a partir de project.yml
open CFMotoLink.xcodeproj
```

El paquete `CFMotoLink_0.6.0_NavegacionMultimedia.zip` trae el código, la documentación, las
láminas de las pruebas y los resultados.
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
4. Elige el modo (1 a 5) en Inicio o en Más > Personalización del tablero; el cambio va en la
   siguiente imagen, sin reconectar.
5. Busca el destino en **Navegación**. En la tarjeta de la ruta, "Guiar con" elige quién da la
   guía: con CFMoto Link pulsa **Iniciar**; con Waze, Google Maps o Mapas de Apple pulsa
   **Abrir en …** y vuelve a CFMoto Link si quieres cambiar algo.
6. Al iniciar una ruta, deja CFMoto Link abierta unos segundos: así guarda las calles del
   recorrido para cuando bloquees el iPhone. Con la app abierta, el mapa se actualiza en vivo.
7. Spotify: Música > Spotify y sigue los cuatro pasos (necesitas una app registrada en
   developer.spotify.com; desde 2026 Spotify pide Premium a la cuenta dueña).

## Documentación

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): estructura y componentes.
- [docs/CONNECTION.md](docs/CONNECTION.md): comunicación con la moto.
- [docs/FEATURES.md](docs/FEATURES.md): estado real de cada función.
- [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md): proveedores de navegación y música, licencias, día y noche, iPhone bloqueado.
- [docs/PANTALLA.md](docs/PANTALLA.md): análisis de la pantalla de la moto y del proveedor de mapas.
- [docs/TESTING.md](docs/TESTING.md): pruebas y resultados.

## Créditos y licencia

La conexión con la moto se basa en el trabajo de
[OpenCfMoto](https://github.com/zanderp/open-cfmoto). Licencia AGPL-3.0-or-later.
