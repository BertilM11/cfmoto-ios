# Integraciones, proveedores y licencias (0.6.1)

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
  app calcula su propia ruta) y termina la guía de CFMoto Link **solo si iOS confirma que la abrió**
  (0.6.1). Si no se pudo abrir, aparece un aviso y la guía y el destino siguen en CFMoto Link.
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
  anterior, sin pantalla negra ni pérdida de la ruta. Desde la 0.6.1, los tramos de la ruta por
  los que se pasará después del atardecer se guardan ya en oscuro (y al revés al amanecer), así
  que con el iPhone bloqueado el mapa guardado cambia de tema a su hora. Una imagen del otro
  tema solo se usa si no hay ninguna del correcto.
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

### Mapa de Apple con el iPhone bloqueado

- **Lo que dice Apple:** si una instantánea de `MKMapSnapshotter` se pide con la app en
  segundo plano (o la app pasa a segundo plano mientras se genera), la entrega se retrasa hasta
  que la app vuelve al primer plano. Con el iPhone bloqueado la app está en segundo plano.
- **Lo que hace la 0.6.1:** con la app abierta guarda la ruta entera por delante (lo que quepa en
  16–64 MB de memoria, hasta 400 imágenes), en paralelo al mapa en vivo, y con el iPhone
  bloqueado usa esas imágenes. Navegación muestra "Mapa guardado: X de Y km".
- **Pantalla negra:** la app sigue al frente con la pantalla en negro y el brillo al mínimo; así
  Apple sigue entregando el mapa en vivo todo el viaje. Se sale manteniendo pulsado.
- **Términos de Apple Maps:** prohíben la descarga masiva de datos del mapa y mostrar datos de
  Apple (por ejemplo, la ruta) sobre un mapa que no sea de Apple. Por eso solo se guarda la ruta
  del viaje en curso, en memoria, y se borra al terminar; y por eso no se mezclan calles de otro
  proveedor con la ruta de Apple.

### Alternativa para tener calles nuevas con el iPhone bloqueado

Solo es posible sin Apple: datos de calles de **OpenStreetMap** (licencia ODbL, con la
atribución "© OpenStreetMap"), un **dibujo propio de calles por CPU** (el procesador sí se puede
usar en segundo plano) y **rutas calculadas también con OpenStreetMap**, para no dibujar la ruta
de Apple sobre otro mapa. Haría falta:

1. Descargar las calles del recorrido (por ejemplo con la API Overpass; su uso público
   recomendado es de pocas peticiones al día por aplicación y exige un User-Agent propio).
2. Un servidor de rutas basado en OpenStreetMap con política de uso compatible (o uno propio).
3. Un dibujo de calles, nombres y cruces hecho por la app.
4. Mantener la guía por voz e indicaciones con esas rutas.

Es un proyecto aparte (un "modo OpenStreetMap"), no un ajuste de la 0.6.1. Mapbox, HERE y el
SDK de Google dibujan con la tarjeta gráfica, así que tampoco generan mapa con el iPhone
bloqueado, además de requerir cuenta y clave propias.

### Resto del viaje con el iPhone bloqueado

| Tema | Qué hace la app | Qué no se puede garantizar |
| --- | --- | --- |
| Ubicación en segundo plano | Modo `location` con `allowsBackgroundLocationUpdates`, tipo navegación en coche y sin pausas automáticas. El diagnóstico cuenta los fijos recibidos en segundo plano | iOS puede cerrar una app en segundo plano por memoria o batería, o si el usuario la cierra |
| Guía y voz | Siguen con el iPhone bloqueado (avance, giros y voz no dependen del mapa) | Dentro de túneles el GPS pierde precisión |
| Recálculo | Se registra cuánto tarda; si no responde en 20 s se pide otra vez y la tarjeta dice a cuánto está la ruta | Apple puede no responder hasta abrir la app (se verá en el registro) |
| Mapa en la moto | Imágenes guardadas de la ruta; mapa simple fuera de ellas | Sin imágenes nuevas de Apple con el iPhone bloqueado |
| Vídeo a la moto | Dibujo por CPU; el codificador se recrea si iOS lo invalida; ritmo y edad del último fotograma en el diagnóstico | **Sin comprobar en la moto** con el iPhone bloqueado |
| Spotify | Sigue sonando (lo reproduce la app de Spotify) | La información en la moto puede dejar de actualizarse si Spotify corta la conexión; la app reintenta dos veces y vuelve a conectar al abrirse |
| Intercomunicador Bluetooth | La voz usa la sesión de audio `playback` con modo de indicaciones de voz: baja el volumen de la música mientras habla y sale por la salida activa (A2DP) | No probado con tu intercomunicador |
| Reconexión con la moto | Diez avisos seguidos y después uno cada 10 s mientras el enlace esté activo; actualiza la IP si el Wi-Fi cambió | Sin prueba sistemática en la moto |
| Energía y temperatura | Pantalla de la moto a 10 imágenes por segundo, GPS continuo y Wi-Fi; el diagnóstico muestra batería y temperatura | El consumo no se ha medido; conviene llevar el iPhone cargando |
