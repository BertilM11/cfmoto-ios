# Arquitectura

La app separa servicios, configuración, dibujo y transmisión. La moto recibe **una sola
imagen** por fotograma con todos los módulos activos; no hay una transmisión por módulo.

```
GPS ─► NavEngine ─► HUDState ─┐
Música ─► MusicService ───────┤
Avisos ─► DashStore ──────────┼─► DashState ─► HUDRenderer.drawDashboard ─► H264Encoder ─► BikeLink ─► moto
Mi pantalla ─► DashStore ─────┘        │
                                       └─► vista previa del iPhone (misma función de dibujo)
```

## Correspondencia con los componentes pedidos

| Componente pedido | Dónde está | Archivos |
| --- | --- | --- |
| ConnectionManager | `LinkModel` (estado para la interfaz) y `BikeLink` (protocolo, reconexión, diagnóstico) | `App/MotoPanel.swift`, `Shared/BikeLink.swift` |
| NavigationManager | `NavEngine`, `GuidedRoute`, `LocationService`, `PlaceSearch`, `VoiceGuide` | `App/Nav/` |
| DashboardLayoutEngine | `DashLayoutEngine` | `App/Dashboard/DashModel.swift` |
| DashboardRenderer | `HUDRenderer.drawDashboard` | `App/Dashboard/DashRenderer.swift`, `App/HUD/HUDRenderer.swift` |
| MusicManager | `MusicService` | `App/Dashboard/MusicService.swift` |
| NotificationManager | `DashStore.notify` y sus fuentes | `App/Dashboard/DashStore.swift` |
| DashboardModeManager | `DashStore` + `DashRulesEngine` | `App/Dashboard/DashStore.swift`, `DashModel.swift` |
| DashboardConfiguration | `DashConfig`, `DashLayout`, `DashProfile`, `DashRules` | `App/Dashboard/DashModel.swift` |
| TransmissionManager | `NavHUDSource` → `H264Encoder` → `BikeLink` | `App/HUD/NavHUDSource.swift`, `Shared/` |
| DashboardSimulator | `TFTPreview`, `DashPreview`, `DashDemo` | `App/UI/Common.swift`, `DashRenderer.swift`, `DashModel.swift` |

## Modelo del panel

- **Módulos** (`DashModule`): navegación (mapa de ruta con tarjeta de giro y datos del viaje),
  próximo giro, mapa de ruta, viaje, música, avisos y reloj.
- **Plantillas** (`DashTemplate`): 1 zona, 2 columnas, principal + 2 laterales. Cada zona lleva
  un módulo o queda vacía; una zona vacía cede su espacio a la vecina.
- **Modos** (`DashMode`): seis combinaciones predefinidas y el modo personalizado. Un modo no
  es una pantalla aparte: es una plantilla con módulos, dibujada por el mismo código.
- **Área útil**: `DashLayoutEngine.usableArea` usa la imagen entera desde la 0.5 (solo descuenta
  una franja inferior si el usuario lo pide en Ajustes)
  donde la moto dibuja velocidad, marcha y testigos. Ahí la app no dibuja nada.

Las zonas salen de dividir el área útil, así que por construcción no se solapan ni se salen.

## Hilos

`NavEngine`, `MusicService` y `DashStore` viven en el hilo principal y escriben en `HUDState` y
`DashState`, que están protegidos con un cerrojo. `NavHUDSource` dibuja en su propia cola a
10 imágenes por segundo y entrega cada imagen al codificador.

## Dibujo sin UIKit

El modelo y el dibujo usan solo Foundation, CoreGraphics y CoreText. Eso permite dibujar con la
app en segundo plano (iOS niega la tarjeta gráfica ahí) y compilar el mismo código en macOS
para las pruebas (`Tools/DashboardCheck`).

## Targets

- `CFMotoLink`: la app (`App/` + `Shared/`).
- `CFMotoLinkBroadcast`: extensión de transmisión de pantalla (`Broadcast/` + `Shared/`).

No hay dependencias externas.


## Mapa de calles (0.5)

| Pieza | Archivo | Qué hace |
| --- | --- | --- |
| `MapBase` | `App/Dashboard/MapBase.swift` | Una imagen de Apple Maps y su proyección (homografía de 4 puntos): sitúa cualquier coordenada en la imagen, igual en 2D que en 3D. Sin MapKit, se prueba en macOS. |
| `TFTMap` | `App/Dashboard/TFTMap.swift` | Pide instantáneas a `MKMapSnapshotter` siguiendo la posición (rumbo, zoom según velocidad y giros, 3D, tráfico, noche) y guarda imágenes del recorrido para el iPhone bloqueado. Elige la que mejor encaja en cada fotograma. Se autocalibra con lo que devuelve Apple. |
| `drawStreetMap` | `App/Dashboard/DashMapRenderer.swift` | Dibuja la imagen y, encima, alternativas, ruta con borde, tramo recorrido, maniobra, destino, posición y brújula. |
| `overlayCards` | `App/Dashboard/DashModel.swift` | Coloca las tarjetas flotantes por esquinas, las apila y garantiza que no se monten ni se salgan. |
| `SpotifyService` | `App/Dashboard/SpotifyService.swift` | SDK oficial de Spotify (App Remote): permiso, canción, portada y controles. |

El dibujo sigue siendo solo CPU (CoreGraphics). Lo único que necesita la app al frente es la
generación de las imágenes de Apple; el dibujo de cada fotograma no.
