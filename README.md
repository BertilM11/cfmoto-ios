# CFMoto Link 0.7 — Mapa propio de OpenStreetMap

App de iPhone, de código abierto y **no oficial**, que envía a la pantalla TFT de una moto CFMOTO
(probada en una 450NK) un panel hecho a medida: navegación GPS propia, música y avisos, con la
distribución que elijas desde el teléfono. También puede duplicar la pantalla del iPhone.

No está afiliada a CFMOTO, Carbit ni EasyConn. No es CarPlay. Úsala parado: configura el
destino, la música y el panel antes de arrancar.

## En resumen

| | |
| --- | --- |
| **Plataforma** | iPhone, iOS 16 o posterior |
| **Lenguajes** | Swift y SwiftUI (app), Python (generador del mapa) |
| **Frameworks** | CoreGraphics, CoreText, CoreLocation, VideoToolbox (H.264), ReplayKit, AVFoundation, MapKit, Spotify iOS SDK |
| **Datos** | OpenStreetMap (Geofabrik), en un formato binario propio (`.cfmap`) |
| **Automatización** | GitHub Actions: compila la app y publica el `.ipa`, arma el mapa y prueba el panel |
| **Tamaño** | Unas 19 000 líneas de Swift y 550 de Python |

Lo más interesante por dentro:

- **Conexión con la moto:** la app abre servidores TCP en el iPhone, hace el intercambio de
  claves RSA con la pantalla y le envía video H.264 a 10 imágenes por segundo por Wi-Fi Direct
  ([docs/CONNECTION.md](docs/CONNECTION.md)).
- **Mapa y rutas sin internet:** un script de Python convierte el extracto de OpenStreetMap de
  Guatemala en cuadros comprimidos con índice; la app los lee directo del archivo, dibuja las calles
  y calcula la ruta con **A\*** por tiempo, respetando el sentido de las calles
  ([Tools/OSM/build_cfmap.py](Tools/OSM/build_cfmap.py), [App/OSM/](App/OSM/)).
- **Funciona con el iPhone bloqueado:** el panel se dibuja solo con CoreGraphics y CoreText, sin
  UIKit, porque iOS no da la tarjeta gráfica en segundo plano. El mismo código compila en macOS
  para las pruebas automáticas ([docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).
- **Un solo motor de dibujo:** cada modo del panel es una plantilla con módulos (mapa, giro,
  música, avisos, reloj) que se reparten la pantalla de 800×400 sin solaparse; la vista previa
  del iPhone usa la misma función que la moto.

## Qué hace

- **Mapa de Guatemala dentro de la app** (0.7): el mapa de la moto, la búsqueda, la ruta, las
  indicaciones y el recálculo salen de OpenStreetMap y se hacen en el iPhone, **sin internet y con
  el iPhone bloqueado**. Apple Maps sigue como opción en Personalizar > Mapa y navegación.
  Detalles: [docs/DISENO_0.7.md](docs/DISENO_0.7.md). Datos © colaboradores de OpenStreetMap
  (ODbL).
- **Tema «Póster»** (0.9.0): colores y estilo inspirados en
  [prettymaps](https://github.com/marceloprates/prettymaps) de Marcelo Prates (AGPL-3.0), con los
  edificios de OpenStreetMap de toda Guatemala guardados de forma compacta en el mapa.
- **Mapa guardado más fiable** (0.6.5, modo Apple Maps): la moto usa siempre el tema del mapa que se ve (nunca
  tarjetas claras con el mapa oscuro); si Apple no entrega imágenes, el guardado espera y sigue,
  y el iPhone lo dice; si queda un hueco que no se volvía a pedir, se pide una imagen ahí.
- **Reproductor premium con botones** (0.6.4): anterior, reproducir/pausar (grande, en un círculo)
  y siguiente en todos los modos con música, como en la referencia, con el estado real (❚❚ o ▶).
  Son solo dibujo: en la moto no se pueden pulsar (la música se controla desde el iPhone). Fondo
  con la luz de la portada, portada con sombra y barra de progreso nueva. **Sin mover ni agrandar
  nada.** Detalles: [docs/DISENO_0.6.4.md](docs/DISENO_0.6.4.md).
- **Rediseño premium** (0.6.3): todas las tarjetas con el mismo vidrio azul oscuro (blanco de día),
  borde luminoso, brillo y sombra, como en la referencia; maniobra con mosaico azul, datos del viaje
  en bloques «Distancia · Restante · Llegada», hora actual con su reloj, avisos con remitente y
  hora, ruta con resplandor y una marca de posición nueva. **Sin mover nada**: mismas posiciones y
  tamaños que la 0.6.2. Detalles: [docs/DISENO_0.6.3.md](docs/DISENO_0.6.3.md).
- **El mismo reproductor en todos los modos** (0.6.3): música completa, columna, zonas y tarjetas
  comparten fondo con los colores de la portada, portada, letra, estado y barra.
- **Instrucciones compactas también en la pantalla dividida** (0.6.3), con el tamaño y la esquina
  elegidos en el iPhone.
- **Mapa guardado con más cobertura** (0.6.3): hasta 800 imágenes y 96 MB (unos 140 km), tres a la
  vez, y el aviso «Ruta completa guardada / Guardando / Mapa parcial» con los km reales. Informe:
  [docs/MAPA_IPHONE_BLOQUEADO.md](docs/MAPA_IPHONE_BLOQUEADO.md).
- **Música completa al estilo de CarPlay** (0.6.2): portada grande, título, artista y álbum
  centrados, estado de la reproducción, barra de progreso con el tiempo transcurrido y la
  duración, fondo con los colores de la portada y un fundido corto al cambiar de canción. Desde
  la 0.6.4 lleva los botones de la referencia (solo dibujo: la moto no es táctil para la app).
- **Instrucciones compactas** (0.6.2): en los modos con mapa, la tarjeta del próximo giro es un
  30 % más pequeña por lado (flecha, distancia y calle) y deja libre el centro para la ruta.
- **Hora actual fija** (0.6.2): siempre arriba a la derecha, en todos los modos y con o sin
  ruta; la llegada va en su bloque con la palabra «Llegada».
- **Mapa con el iPhone bloqueado** (0.6.1): la app guarda la ruta entera por delante mientras
  está abierta y la usa al bloquear; Navegación avisa cuándo ya se puede bloquear. Con la
  **Pantalla negra** el mapa sigue en vivo sin bloquear.
- **Diagnóstico** (0.6.1): Más > Diagnóstico, con informe exportable.
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
# El mapa de Guatemala no está en el repositorio: se descarga de la versión «mapa-guatemala»
# (el archivo cuya huella está en Tools/OSM/Guatemala.cfmap.sha256) y va en App/Map/.
xcodegen generate          # crea CFMotoLink.xcodeproj a partir de project.yml
open CFMotoLink.xcodeproj
```

El paquete `CFMotoLink_0.7_MapaPropio.zip` trae el código, el mapa de Guatemala
(`App/Map/Guatemala.cfmap`), la documentación, las láminas de las pruebas y los resultados.
Instalación paso a paso: [docs/INSTALL.md](docs/INSTALL.md).
Volver a la 0.6.5, 0.6.4, 0.6.3, 0.6.2, 0.6.1 o 0.6.0: [docs/ROLLBACK.md](docs/ROLLBACK.md). Mapa
propio de la 0.7: [docs/DISENO_0.7.md](docs/DISENO_0.7.md). Diseño de la 0.6.4:
[docs/DISENO_0.6.4.md](docs/DISENO_0.6.4.md) (y los de la 0.6.3 y la 0.6.2 en
[docs/DISENO_0.6.3.md](docs/DISENO_0.6.3.md) y [docs/DISENO_0.6.2.md](docs/DISENO_0.6.2.md)).
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
2. En el iPhone conéctate al Wi-Fi `DIRECT-…-CFMOTO` (clave `12345678`). Ese Wi-Fi no da
   internet: con el mapa propio (de serie desde la 0.7) no hace falta para el mapa, la búsqueda ni
   la ruta; deja los datos móviles activos para Spotify, Apple Music o el modo Apple Maps.
3. En **Inicio** pulsa **Conectar y enviar el panel**.
4. Elige el modo (1 a 5) en Inicio o en Más > Personalización del tablero; el cambio va en la
   siguiente imagen, sin reconectar.
5. Busca el destino en **Navegación**. En la tarjeta de la ruta, "Guiar con" elige quién da la
   guía: con CFMoto Link pulsa **Iniciar**; con Waze, Google Maps o Mapas de Apple pulsa
   **Abrir en …** y vuelve a CFMoto Link si quieres cambiar algo.
6. Con el mapa propio puedes bloquear el iPhone en cuanto empieza la ruta. En el modo Apple Maps,
   deja CFMoto Link abierta unos segundos: así guarda las calles del recorrido para cuando
   bloquees el iPhone.
7. Spotify: Música > Spotify y sigue los cuatro pasos (necesitas una app registrada en
   developer.spotify.com; desde 2026 Spotify pide Premium a la cuenta dueña).

## Documentación

- [CHANGELOG.md](CHANGELOG.md): cambios de cada versión.
- [docs/ERROR_REPORT.md](docs/ERROR_REPORT.md): errores encontrados (en la 0.6.0 y durante la 0.6.1) y su corrección.
- [docs/INSTALL.md](docs/INSTALL.md) y [docs/ROLLBACK.md](docs/ROLLBACK.md): instalar y volver atrás.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): estructura y componentes.
- [docs/CONNECTION.md](docs/CONNECTION.md): comunicación con la moto.
- [docs/FEATURES.md](docs/FEATURES.md): estado real de cada función.
- [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md): proveedores de navegación y música, licencias, día y noche, iPhone bloqueado.
- [docs/PANTALLA.md](docs/PANTALLA.md): análisis de la pantalla de la moto y del proveedor de mapas.
- [docs/TESTING.md](docs/TESTING.md): cómo se prueba (automáticas, simulador y moto).
- [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md): resultados de las pruebas (0.7, 0.6.5, 0.6.4, 0.6.3, 0.6.2 y 0.6.1).
- [docs/DISENO_0.7.md](docs/DISENO_0.7.md): mapa propio de OpenStreetMap (datos, dibujo, rutas, búsqueda, licencias y límites).
- [docs/DISENO_0.6.4.md](docs/DISENO_0.6.4.md): botones y acabado del reproductor de la 0.6.4 (cada modo, estados, pruebas).
- [docs/DISENO_0.6.3.md](docs/DISENO_0.6.3.md): rediseño premium de la 0.6.3 (sistema visual, cada modo, lo que no se puede llevar a la moto).
- [docs/MAPA_IPHONE_BLOQUEADO.md](docs/MAPA_IPHONE_BLOQUEADO.md): mapa con el iPhone bloqueado (qué permite Apple, cobertura y alternativas).
- [docs/DISENO_0.6.2.md](docs/DISENO_0.6.2.md): diseño de la 0.6.2 (música, instrucciones y hora) con capturas.
- [docs/LIMITATIONS.md](docs/LIMITATIONS.md): limitaciones pendientes y qué haría falta.

## Créditos y licencia

La conexión con la moto se basa en el trabajo de
[OpenCfMoto](https://github.com/zanderp/open-cfmoto). Licencia AGPL-3.0-or-later.
