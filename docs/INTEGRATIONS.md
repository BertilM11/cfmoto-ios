# Integraciones, proveedores y licencias (0.6.0)

Qué usa la app de cada proveedor, qué se puede y qué no se puede hacer con él, y por qué.
Nada de lo que aparece aquí como "no disponible" se simula en la moto.

## Resumen

| Proveedor | Cómo se integra | Qué muestra la moto | Requisitos | Estado |
| --- | --- | --- | --- | --- |
| **CFMoto Link** (MapKit de Apple) | Rutas con `MKDirections`, mapa con `MKMapSnapshotter` | Mapa de calles, ruta, flecha del giro, tarjeta de maniobra, voz | Ninguno (MapKit viene con iOS; no hace falta clave) | Real. Mapa y ruta verificados en la moto (foto de la 0.5) |
| **Mapas de Apple** (app) | `MKMapItem.openInMaps` con indicaciones en coche | Mapa de calles de CFMoto Link, tu posición y el destino. **Sin giros** | Ninguno | Real (abre la app con el destino) |
| **Google Maps** (app) | Enlace oficial: `comgooglemaps://?daddr=…&directionsmode=driving`; sin la app, `https://www.google.com/maps/dir/?api=1&destination=…&travelmode=driving` | Igual que Mapas de Apple: mapa, posición y destino, **sin giros** | Ninguno | Real (abre la app o la web con el destino) |
| **Waze** (app) | Enlace oficial: `waze://ul?ll=…&navigate=yes` (con la app) o `https://waze.com/ul?ll=…&navigate=yes` (sin ella), con `utm_source` | Igual: mapa, posición y destino, **sin giros** | Ninguno | Real (abre la app o la web con el destino) |
| **Spotify** | SDK oficial de iOS (App Remote), por Swift Package Manager | Canción, artista, portada, progreso y colores de la portada | Tu propia app en developer.spotify.com (Client ID) y Premium en la cuenta dueña | Programado y compilado; falta verlo en la moto |
| **Apple Music** | `MPMusicPlayerController.systemMusicPlayer` | Igual que Spotify | Permiso de "Contenido multimedia y Apple Music" | Programado; falta en un iPhone real |

El proveedor se elige en **Más > Personalización del tablero > Proveedor de navegación** o en
la tarjeta de la ruta, antes de pulsar Iniciar ("Guiar con: …").

## Por qué Google Maps y Waze no dan giros en la moto

Ninguna de las dos apps comparte con otras apps su ruta activa, sus giros ni su interfaz. Al
abrirlas con el enlace oficial, CFMoto Link solo sabe el destino que le pasó; por eso la moto
muestra el mapa de calles de Apple, tu posición y la bandera del destino, con la tarjeta
"Guía en Waze" (o Google Maps), y nada más. La guía y la voz las da la otra app en el iPhone.

Para ver la propia pantalla de Waze o Google Maps en la moto sigue existiendo **Duplicar
pantalla** (ReplayKit), con sus límites: el iPhone tiene que estar desbloqueado y la imagen es
la del teléfono, no un diseño para la TFT.

### Lo que se evaluó y se descartó

- **Navigation SDK de Google para iOS**: daría la navegación de Google dentro de la app, pero
  se factura por cada destino pedido a la SKU "Navigation Request" (de tipo Enterprise), exige
  activar la facturación en un proyecto de Google Cloud con su propia clave de API y tiene
  restricciones de licencia en los términos de Google Maps Platform. Además dibuja su propio
  mapa en una vista de la app; llevarlo a la TFT obligaría a copiar esa imagen, y los términos
  prohíben exportar o extraer contenido de Google Maps para usarlo fuera de sus servicios. No se
  integró. Si algún día se quiere, haría falta tu proyecto de pago, tu clave y una revisión de
  los términos; la app no incluye ninguna clave.
- **Waze Transport SDK**: era el único camino para recibir de Waze el próximo giro y la
  distancia. Era exclusivo para empresas de transporte con conductores profesionales, solo para
  socios aprobados, y Google anunció el fin de su soporte el 1 de noviembre de 2026. No está
  disponible para esta app.
- **Navigation Connect** (Google Maps Platform): abre Google Maps o Waze con un "trip token"
  creado por una petición de Google Maps Platform y devuelve datos del viaje (posición, ETA)
  al socio. Está en vista previa, es para empresas de movilidad y no documenta giros. No aplica.
- **Waze Audio Kit**: sirve para que una app de audio aparezca dentro de Waze; no da datos de
  navegación.

### Cambio de proveedor con una ruta en curso

`RouteManager` (en `App/Nav/NavProviders.swift`) conserva el destino:

- De CFMoto Link a Waze, Google Maps o Mapas de Apple: abre esa app con el mismo destino (esa
  app calcula su propia ruta) y termina la guía de CFMoto Link.
- De una app externa a CFMoto Link: vuelve a calcular la ruta aquí con el mismo destino y
  muestra "Ruta recalculada por CFMoto Link con el mismo destino. Toca Iniciar."
- Desde los ajustes, si hay un destino en curso, la app pregunta antes: pasar el destino o
  solo cambiar el proveedor predeterminado.

## Día y noche

- **Automático** (predeterminado): claro entre el amanecer y el atardecer del lugar donde
  estás, oscuro el resto. El cálculo (`SunClock`, ecuación del amanecer) se comprobó contra la
  biblioteca astronómica *astral*: Ciudad de Guatemala el 17 de noviembre de 2026, amanecer
  6:04 y atardecer 17:29–17:30; Oslo, Sídney y Madrid coinciden al minuto. Sin posición, se usa
  la hora: noche de 18:30 a 5:30.
- **Siempre claro** y **Siempre oscuro**.
- Es el estilo de día o de noche **de Apple Maps** (la instantánea se pide con apariencia clara
  u oscura), no un filtro encima. El cambio se hace con un fundido de 0,3 s sobre la imagen
  anterior, sin pantalla negra ni pérdida de la ruta; con el iPhone bloqueado se siguen usando
  las imágenes guardadas del otro estilo hasta que haya nuevas.
- MapKit no ofrece una "recomendación de iluminación" como la del SDK de Google; por eso se usa
  el sol.

**Por qué el mapa salía siempre oscuro (0.5):** el tema del panel venía fijo en "oscuro" por
defecto, y los seis perfiles de fábrica también. Al actualizar a la 0.6, una configuración que
seguía en oscuro pasa a automático; si habías elegido claro, se respeta.

## Spotify: reglas de presentación aplicadas

Según las reglas de diseño y marca de Spotify para desarrolladores:

- La portada se muestra entera, sin recortes, sin nada encima y con esquinas de 4 px (pequeña)
  u 8 px (grande).
- El fondo de la tarjeta sale de los colores de la portada; si no hay portada, se usa el color
  de Spotify `#191414`.
- El nombre "Spotify" va en verde solo sobre fondo negro; sobre cualquier otro fondo, en blanco
  o negro.
- El título y el artista se recortan solo si no caben (completos en el iPhone).
- La pantalla de Música tiene el enlace **ABRIR SPOTIFY** (u **OBTENER SPOTIFY GRATIS** si no
  está instalado).

Limitación: el repositorio no incluye el archivo del logotipo oficial de Spotify; la atribución
en la moto es el nombre "Spotify" en texto. Para publicar la app habría que añadir el logotipo
oficial desde el kit de marca de Spotify.

Otros límites del SDK: el permiso dura una hora (se guarda solo en memoria); Spotify puede
cortar la conexión con la app en segundo plano o tras unos segundos en pausa. CFMoto Link
reintenta dos veces y, si no, vuelve a conectar al abrir la app.

## Colores de la portada (Spotify y Apple Music)

`ArtPalette` reduce la portada a 32×32 y busca el color dominante y uno de acento.
`MusicCardColors` arma un degradado sobrio (saturación limitada), elige el texto blanco o
negro con contraste WCAG de al menos 4,5:1 y ajusta la barra de progreso a 3:1. Al cambiar de
canción los colores pasan de una a otra en 0,3 s. Opciones: colores de la portada (con
intensidad), fondo oscuro fijo, fondo claro fijo, y animaciones sí/no.

## iPhone bloqueado y uso real

| Tema | Qué hace la app | Qué no se puede garantizar |
| --- | --- | --- |
| Ubicación en segundo plano | Modo `location` con `allowsBackgroundLocationUpdates`, tipo navegación en coche y sin pausas automáticas | iOS puede cerrar una app en segundo plano por memoria o batería, o si el usuario la cierra |
| Continuidad del GPS | La guía y la voz siguen con el iPhone bloqueado | Dentro de túneles o edificios el GPS pierde precisión |
| Mapa en la moto | Imágenes guardadas del recorrido (hasta ~8 km) | Apple no genera imágenes nuevas en segundo plano: fuera de lo guardado, mapa simple |
| Vídeo a la moto | Dibujo por CPU; el codificador se recrea si iOS lo invalida | **Sin comprobar en la moto** con el iPhone bloqueado |
| Spotify | Sigue sonando (lo reproduce la app de Spotify) | La información en la moto puede dejar de actualizarse si Spotify corta la conexión |
| Intercomunicador Bluetooth | La voz usa la sesión de audio `playback` con modo de indicaciones de voz: baja el volumen de la música mientras habla y sale por la salida activa (A2DP) | No probado con tu intercomunicador |
| Reconexión con la moto | Reintenta sola si se pierde el enlace | Sin prueba sistemática; con la app suspendida no hay reconexión |
| Energía | Pantalla de la moto a 10 imágenes por segundo, GPS continuo y Wi-Fi | El consumo no se ha medido; conviene llevar el iPhone cargando |
