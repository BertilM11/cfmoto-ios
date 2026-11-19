# Registro de cambios

## 0.7.2 — Más lugares: coordenadas, enlaces, destinos guardados y búsqueda en internet (19 de noviembre de 2026)

Respaldo de la versión anterior: rama `backup/v0.7.1` y etiqueta `v0.7.1`. No cambian la conexión
con la moto, el vídeo, el protocolo, los indicadores originales, el dibujo del mapa ni el cálculo
de rutas.

- **Pegar una ubicación** en el buscador: coordenadas (`14.6349, -90.5069`, con espacio, entre
  paréntesis, al revés o en grados/minutos/segundos), enlaces de Google Maps (largos y cortos
  `maps.app.goo.gl`), Apple Maps, Waze, OpenStreetMap y `geo:`. En los enlaces de Google se toma el
  lugar marcado (`!3d…!4d…`), no el centro de la vista. Los enlaces cortos se abren con internet
  y solo se leen sus direcciones (no el contenido de las páginas). Botón «Pegar ubicación» al
  tocar el buscador (sin el aviso de «permitir pegar»).
- **Destinos guardados**: ☆ en la tarjeta de la ruta → Casa, Trabajo o favorito. Aparecen al tocar
  el buscador y al escribir su nombre. Mantener presionado para cambiar el nombre o quitarlo.
- **Recientes**: los últimos 8 destinos, sin repetir; se pueden guardar desde ahí.
- **Buscar en internet** (modo OpenStreetMap): fila al final de los resultados que consulta
  OpenStreetMap en línea (Nominatim) solo al tocarla, como máximo una vez por segundo, limitada a
  Guatemala y priorizando lo cercano. Encuentra direcciones y lugares que no vienen en el mapa
  guardado. Sin conexión lo avisa y la búsqueda sin internet sigue igual.
- Por qué faltan lugares desde la 0.7: el modo OpenStreetMap ya no usa el buscador de Apple (sus
  datos no se pueden usar sobre un mapa que no es de Apple) y OpenStreetMap no tiene todos los
  negocios de Guatemala. Para esos: búsqueda en internet, o pegar el enlace o las coordenadas.

## 0.7.1 — Nuevo nombre: MotoLink (19 de noviembre de 2026)

Respaldo de la versión anterior: rama `backup/v0.7` y etiqueta `v0.7` (ver `docs/ROLLBACK.md`).
Solo cambian el nombre, el ícono y la marca; no cambian la conexión Wi-Fi Direct, el vídeo H.264,
el protocolo con la moto ni sus indicadores, el mapa, la ruta ni la música.

- **Nombre MotoLink** en el iPhone, en la app, en los permisos y en la transmisión de pantalla. El
  identificador interno (`io.github.cfmotolink.app`) no cambia: se instala encima de la 0.7 y se
  conservan los ajustes.
- **Ícono nuevo** (la moto con el eslabón azul), diseño de Bertil.
- **Logo de BERL**: en la pantalla de la moto, pequeño y tenue junto a «© OpenStreetMap» (abajo a
  la izquierda del mapa, del mismo color); en la app, al final de la portada y en «Acerca de».
  Con Mapas de Apple no se dibuja, para no acercarlo a su logotipo.

## 0.7 — Mapa propio de OpenStreetMap (18 de noviembre de 2026)

Respaldo de la versión anterior: rama `backup/v0.6.5`, etiqueta `v0.6.5`, publicación `build-16` y
carpeta `BACKUP_ORIGINAL_0.6.5` con sus huellas SHA-256 (ver `docs/ROLLBACK.md`). No cambian la
conexión Wi-Fi Direct, el vídeo H.264, el protocolo con la moto ni sus indicadores, la música, la
distribución de los modos ni el modo día/noche. Detalles: `docs/DISENO_0.7.md`.

### Mapa de Guatemala dentro de la app (modo nuevo, el de serie)
- **Todo con OpenStreetMap**: el mapa de la moto, la búsqueda, la ruta, las indicaciones y el
  recálculo salen del mapa de Guatemala que viene en la app (unos 25 MB). **No descarga nada**:
  funciona sin internet y con el iPhone bloqueado, también al desviarse.
- **El mapa de la moto** se dibuja en el teléfono como en el vídeo de muestra: calles con borde
  según su tipo, parques y agua, nombres de las calles y «© OpenStreetMap». Día o noche según el
  tema elegido, siempre (no hay imágenes de otro tema que esperar).
- **Rutas calculadas en el iPhone**: la principal y hasta dos alternativas, con indicaciones en
  español y el nombre de la calle («Gira a la derecha por 12 Calle», «En la rotonda, toma la 3.ª
  salida hacia…»). Rutas largas también (Quetzaltenango, Flores); las que dan un rodeo grande se
  calculan con las carreteras principales de todo el país.
- **Búsqueda sin internet**: ciudades, pueblos, zonas y colonias, calles, gasolineras, hospitales,
  centros comerciales, hoteles, aeropuertos… sin acentos, «6a» = «6», «z10» = «zona 10», otros
  nombres («Xela») y por tipo de lugar («gasolinera» da la más cercana aunque se llame Texaco).
  Cada resultado dice dónde está (zona, municipio, departamento).
- En el iPhone, el aviso del mapa dice «Mapa de Guatemala en el iPhone · sin internet».

### Apple Maps sigue como opción
- **Personalizar > Mapa y navegación**: OpenStreetMap (sin internet) o Apple Maps (lo de la 0.6.5,
  con internet). La vista 3D es solo de Apple Maps.
- Por las condiciones de Apple, en el modo OpenStreetMap no se usa nada de Apple Maps (sus rutas o
  resultados no pueden ir sobre otro mapa). Si se cambia de mapa con una ruta en pantalla, la ruta
  se vuelve a calcular con el mapa nuevo.

### Diagnóstico
- Más > Diagnóstico muestra el mapa elegido, la fecha y el tamaño del mapa de Guatemala y la
  última ruta propia (distancia y tiempo de cálculo).

### Pruebas
- Nuevas pruebas con el mapa completo: búsquedas, rutas largas, maniobras en su cruce, recálculo,
  tiempos de dibujo y de cálculo. El simulador se compila optimizado (como en el iPhone). Ver
  `docs/TEST_RESULTS.md`.

### Licencia de los datos
- Datos © colaboradores de OpenStreetMap, licencia ODbL 1.0. El mapa armado se publica en la
  versión `mapa-guatemala` del repositorio con su origen y su fecha.

## 0.6.5 — Mapa guardado y tema (18 de noviembre de 2026)

Respaldo de la versión anterior: rama `backup/v0.6.4`, etiqueta `v0.6.4`, publicación `build-15` y
carpeta `BACKUP_ORIGINAL_0.6.4` con sus huellas SHA-256 (ver `docs/ROLLBACK.md`). No cambian la
conexión Wi-Fi Direct, el vídeo H.264, el protocolo con la moto ni sus indicadores, la navegación,
la música ni la distribución de los modos. Solo cambian el mapa guardado y el tema de la moto.

### Tema claro con el mapa oscuro
- **La moto usa el tema del mapa que se ve.** Con el iPhone bloqueado solo hay imágenes guardadas;
  si la que tocaba era del otro tema (cambio de tema, o el amanecer o el atardecer llegó antes o
  después de lo previsto), salían las tarjetas claras sobre el mapa oscuro. Ahora todo el tablero
  toma el tema de esa imagen hasta que haya imágenes del tema elegido.
- Diagnóstico: «Tema de la moto» dice si se está usando el del mapa guardado.

### El guardado que se quedaba parado (10 de 21 km)
- **Pausa tras los fallos de Apple**: antes, si Apple no entregaba una imagen, se volvía a pedir
  enseguida; si Apple estaba limitando las peticiones, el guardado podía quedarse parado. Ahora se
  espera 2, 4, 8… hasta 60 s y se sigue.
- **El iPhone lo dice**: bajo «Guardando el mapa» aparece «Apple no entregó la última imagen (…).
  Reintento en N s», en vez de parecer parado.
- **Imágenes extra para huecos**: si una imagen llega cubriendo menos de lo previsto, queda un
  hueco que la rejilla ya no volvía a pedir (su punto ya tenía imagen). Ahora se pide una imagen
  justo en el hueco, como mucho dos veces por sitio.
- **No está confirmada la causa** de lo que pasó en tu ruta de 21 km. Se probó la sospecha de las
  curvas cerradas y no era: la rejilla las cubre enteras. Si vuelve a pasar, exporta el informe
  (Más > Diagnóstico > Exportar informe): ahora incluye los fallos seguidos de Apple y las imágenes
  extra para huecos.

### Pruebas
- 208 pruebas automáticas: las 200 de la 0.6.4 y 8 nuevas del mapa guardado (curvas cerradas, hueco
  por una imagen que cubre menos, sin peticiones de más, sin bucles).
- Falta probarlo en la moto: pruebas X e Y de `docs/TESTING.md`.

## 0.6.4 — Acabado premium del reproductor (18 de noviembre de 2026)

Respaldo de la versión anterior: rama `backup/v0.6.3`, etiqueta `v0.6.3`, publicación `build-14`
(el mismo código que la `build-12`) y carpeta `BACKUP_ORIGINAL_0.6.3` con sus huellas SHA-256
(ver `docs/ROLLBACK.md`). No cambian la conexión Wi-Fi Direct, el vídeo H.264, el protocolo con la
moto ni sus indicadores, la navegación, la hora, el modo día/noche ni el mapa guardado. Ningún
módulo cambia de sitio ni de tamaño.

### Botones de la referencia en todos los modos con música
- **Anterior, reproducir/pausar y siguiente**, como en la referencia: iconos de barra y triángulo
  y un **círculo grande** con ❚❚ (sonando) o ▶ (en pausa). Van donde estaba el estado
  («Reproduciendo»), en **Música completa**, **Dividida**, **Música + Avisos** (con y sin ruta),
  las tarjetas de **Nav + Música**, **Completo** y **Personalizado** (compacta y grande) y la zona
  lateral de los diseños por zonas.
- **Proporcionales al sitio**: círculo de 62 px en Música completa, 44 px en las columnas, 40 px en
  Música + Avisos con ruta, 26 px en la tarjeta grande y 22 px en la compacta. Los tres botones
  caben en todos los tamaños.
- **Solo dibujo**: la moto no envía toques ni teclas a la app, así que en la TFT no se pueden
  pulsar. No se tocó el protocolo. La música se sigue controlando con los botones del iPhone
  (Más > Música), que no cambian, o con el intercomunicador.
- **Estado real**: ❚❚ mientras suena y ▶ en pausa, con un fundido corto (0,25 s) al cambiar. Sin
  música se ven apagados.
- De noche, iconos blancos y círculo blanco con el símbolo oscuro; de día, al revés (iconos y
  círculo oscuros), para que se vean sobre el fondo claro.

### Acabado premium
- **Luz de la portada** en el fondo, como en CarPlay: sus colores, difuminados, sobre el degradado
  de la portada, con el resplandor detrás de ella y, de noche, un velo algo más oscuro abajo.
- **Portada** con sombra difuminada y un filo fino que la separa del fondo; las que no son
  cuadradas se ven enteras, sin estirarse.
- **Barra de progreso** con degradado del color de la barra y el punto con halo; en la tarjeta
  compacta, fina al pie, y en la grande con los tiempos a los lados.
- **Tarjeta compacta**: título y artista; debajo, los botones con el nombre del servicio a la
  derecha. **Tarjeta grande**: servicio, título, artista, botones y barra con tiempos.
- **Cambio de canción**: el fondo de cada canción se dibuja una vez y se guarda; al cambiar, se
  funden el anterior y el nuevo sin volver a dibujarlos.
- **Mismo rendimiento que la 0.6.3**, medido en la misma máquina (mediana de 3 pasadas): 17,3 ms
  por fotograma en plena transición (0.6.3: 17,0) y 9,8 ms sin transición (0.6.3: 10,1). La moto
  pide un fotograma cada 100 ms.

### En el iPhone
- Más > Música explica que en la moto los botones se ven pero no se pueden pulsar. El ajuste
  «Nombre del servicio y estado» pasa a llamarse «Nombre del servicio» (el estado lo muestra ahora
  el botón central).

### Pruebas
- 200 pruebas automáticas del panel: las de antes y las nuevas de los botones (en todos los
  sitios, dentro de su tarjeta o zona, sin tocar textos ni la hora, proporciones, estado
  ❚❚/▶, contraste de los iconos ≥ 3:1, apagados sin música, fundido, tarjetas del mismo tamaño
  y portadas que no son cuadradas). Resultados en `docs/TEST_RESULTS.md`.
- Falta verlo en la moto: pruebas U, V y W de `docs/TESTING.md`.

## 0.6.3 — Rediseño premium y correcciones de navegación (18 de noviembre de 2026)

Respaldo de la versión anterior: etiqueta `v0.6.2`, rama `backup/v0.6.2`, publicación
`build-11` y carpeta `BACKUP_ORIGINAL_0.6.2` con sus huellas SHA-256 (ver `docs/ROLLBACK.md`).
No cambian la conexión Wi-Fi Direct, el vídeo H.264, el protocolo con la moto ni sus
indicadores (velocidad, RPM, marcha, combustible y testigos).

### Rediseño premium (referencia 01), sin mover nada
- **Un solo sistema visual** para todas las tarjetas y zonas: vidrio azul oscuro (blanco de día)
  con degradado, borde luminoso más claro arriba, brillo interior, halo azul suave de noche y
  sombra. Iconos en mosaicos con degradado y brillo. Ver `docs/DISENO_0.6.3.md`.
- **Mismas posiciones y tamaños que la 0.6.2** en todos los modos (prueba automática con las
  medidas exactas); la hora sigue fija arriba a la derecha.
- **Maniobra** como en la referencia: mosaico azul con la flecha, distancia en grande y la calle;
  la tarjeta grande añade la instrucción completa y «Luego» con la maniobra siguiente.
- **Datos del viaje** en tres bloques, como en la referencia: **Distancia · Restante · Llegada**,
  cada cifra sobre su nombre, y el avance en el borde de abajo.
- **Hora actual** con un pequeño reloj, para que no se confunda con la de llegada.
- **Avisos**: icono propio por remitente (navegación, moto, iPhone), remitente, título, mensaje y
  «Ahora / 2 min»; la zona de avisos tiene campana y contador, y **sin avisos muestra un estado
  vacío centrado** en vez de la zona en blanco.
- **Mapa**: ruta con resplandor y brillo central, marca de posición nueva (disco de vidrio con la
  flecha azul), destino rojo, brújula de vidrio y el mapa simple en azul oscuro.
- **Música**: el mismo vidrio (sombra y borde, del color de la portada), nombre del servicio con
  su punto de color, punto en la barra de progreso y píldora del estado de vidrio, en todos los
  tamaños.
- Sin botones de reproducción ni de zoom: en la moto no funcionarían (no envía toques ni teclas).
- Los fondos de las tarjetas se dibujan una vez y se reutilizan: menos de 8 ms por fotograma en
  todos los modos en las pruebas.

### Música: el mismo reproductor en todos los modos
- Un solo reproductor en tres formas que comparten fondo (degradado con los colores de la
  portada y un resplandor detrás de ella), portada con sombra, letra, estado y barra:
  - **Música sola**: la pantalla al estilo de CarPlay de la 0.6.2 (sin cambios de medidas).
  - **Dividida** y **Música + Avisos**: columna con la portada arriba, título y artista
    centrados, la píldora «Reproduciendo / En pausa» y la barra con el tiempo transcurrido y la
    duración.
  - **Nav + Música**, **Completo** y zonas bajas: tarjeta con la portada a la izquierda, el
    servicio con el símbolo del estado, título, artista y barra (con tiempos en la tarjeta
    grande). Antes la tarjeta tenía otro diseño.
- Los textos se ajustan al sitio: si no caben, primero se reduce la letra y se quita lo
  secundario; en la tarjeta compacta el título puede pasar a dos líneas (sin el artista). Solo un
  título muy largo termina en «…», nunca cortado por el borde.
- Sin botones: el protocolo de la moto no envía teclas, así que solo se muestran el estado y el
  progreso (la música se controla desde el iPhone o el intercomunicador).
- El fundido al cambiar de canción funciona en todas las formas.

### Navegación: instrucciones compactas en las pantallas compartidas
- **Dividida** y diseños por zonas: la tarjeta del giro es la misma que en el mapa completo
  (**200×96**, antes 426×155 a todo el ancho) y la barra del viaje es más baja. Más mapa a la
  vista (ver `docs/DISENO_0.6.3.md`).
- Respeta el **tamaño** (compacta o grande) y el **lugar** elegidos en el iPhone; en
  Personalización aparecen también para la Dividida.
- Nav + Música, Completo y Nav + Avisos siguen con la tarjeta compacta de la 0.6.2.
- Las etiquetas (SIMULACIÓN, SIN SEÑAL GPS…) van dentro de la zona del mapa, sin tapar la música.

### Mapa con el iPhone bloqueado
- **3 imágenes a la vez** (antes 2) y hasta **800 imágenes / 96 MB** (antes 400 / 64 MB): cabe una
  ruta de unos 140 km con el zoom por defecto (antes unos 70 km).
- Si iOS avisa de poca memoria, se sueltan las imágenes más lejanas durante 2 minutos.
- En Navegación y en la pantalla negra: **«Ruta completa guardada»**, **«Guardando el mapa: X de
  Y km»** o **«Mapa parcial: X de Y km (límite de memoria)»**, con un consejo de qué hacer.
- En la moto, con el iPhone bloqueado y menos de 2 km de mapa guardado: **MAPA GUARDADO: X KM**.
- Informe completo de lo que permite Apple y de las alternativas: `docs/MAPA_IPHONE_BLOQUEADO.md`.

### Hora actual y llegada
- Se mantiene la hora actual fija arriba a la derecha (ahora con su reloj); la llegada va en su
  bloque con la palabra «Llegada». Las pruebas comprueban que ningún texto tapa la hora en ningún
  modo y que la hora de llegada nunca aparece en el sitio de la hora actual.

### Pruebas
- Nuevas pruebas automáticas: textos cortados, montados o sobre la hora en todos los modos (día,
  noche, con y sin ruta y a 640×320), contraste del texto sobre el fondo real, forma del
  reproductor en cada modo, maniobra en cada esquina y tamaño, cobertura del mapa y precarga.

## 0.6.2 — Diseño de la pantalla (17 de noviembre de 2026)

Respaldo de la versión anterior: etiqueta `v0.6.1`, rama `backup/v0.6.1`, publicación
`build-9` y carpeta `BACKUP_ORIGINAL_0.6.1` (ver `docs/ROLLBACK.md`). No cambian la conexión
Wi-Fi Direct, el vídeo H.264 ni el protocolo con la moto.

### Modo 4 · Música completa (al estilo de CarPlay)
- Portada grande a la derecha: 274 px de alto (de 400) con el tamaño normal, 288 en grande
  (antes 267, a la izquierda). Con una ruta activa, 209 px (antes 220), porque abajo va el
  próximo giro.
- Título, artista y álbum centrados a la izquierda; el título en una línea si cabe.
- En lugar de botones, el **estado**: «Reproduciendo» o «En pausa». La pantalla de la moto no es
  táctil para la app y el protocolo no envía teclas, así que unos botones no funcionarían; la
  música se sigue controlando desde el iPhone o el intercomunicador.
- Barra de progreso a todo el ancho con el **tiempo transcurrido y la duración**.
- Fondo con un degradado de los colores de la portada y un resplandor suave detrás de ella.
- **Fundido** corto (menos de medio segundo) al cambiar de canción; la portada de Spotify que
  llega tarde se funde sola. Se puede desactivar con «Animaciones».
- Álbum de Apple Music y de Spotify.

### Modos con mapa: instrucciones compactas
- Tarjeta del próximo giro **un 30 % más pequeña por lado** (200×96; antes 284×136): flecha
  más pequeña, distancia y **nombre de la calle** (la flecha ya dice el giro), con menos margen.
- El centro del mapa, por donde va la ruta, queda libre de tarjetas.
- La tarjeta de música **no cambia de tamaño**. La tarjeta grande de la maniobra sigue igual.

### Hora actual fija
- La hora actual va **siempre arriba a la derecha**, en todos los modos, de día y de noche, con
  y sin ruta.
- La barra de viaje dice **«Llegada 7:22 p.m. | 18 min | 7.4 km»**: la llegada con su nombre y
  el tiempo y la distancia separados. Sin ruta ya no muestra ninguna hora.
- En las pantallas por zonas, lo que cae debajo de la hora se aparta (la brújula baja, la
  cabecera de la música se acorta).

## 0.6.1 — Estabilidad y navegación premium (17 de noviembre de 2026)

Respaldo de la versión anterior: etiqueta `v0.6.0`, rama `backup/v0.6.0`, publicación
`build-8` y carpeta `BACKUP_ORIGINAL_0.6.0` (ver `docs/ROLLBACK.md`).

### Mapa con el iPhone bloqueado
- Se guarda la **ruta entera por delante** (hasta el límite de memoria), en paralelo al mapa en
  vivo. Antes solo avanzaba cuando el mapa en vivo estaba quieto, con un máximo de ~8 km.
- Una imagen más **después de cada giro**, orientada a la calle nueva.
- Los tramos por los que se pasará de noche se guardan **ya en oscuro**.
- Al **recalcular** se conservan las imágenes que siguen sirviendo (antes se borraban todas) y
  no se vuelve a pedir lo que ya cubren.
- Las imágenes se guardan en puntos fijos de la ruta: cada imagen nueva amplía el mapa por
  delante (en el simulador, 4,7 km seguidos en 60 s; antes 0,8 km con casi las mismas imágenes).
- Con el iPhone bloqueado se siguen calculando el tema (día/noche), el avance y la cobertura.
- En rectas largas la línea de la ruta vuelve a verse por delante de la moto sobre el mapa
  guardado (fallaba desde la 0.5).
- Peticiones atascadas canceladas y repetidas; imágenes que llegan tarde, descartadas.
- **Cobertura** visible en Navegación: "Guardando el mapa…" / "Mapa guardado: X de Y km".
- **Pantalla negra**: la app sigue al frente con brillo mínimo y el mapa sigue en vivo.

### Diagnóstico
- **Más > Diagnóstico**: moto, vídeo, GPS, mapa guardado, segundo plano, memoria, batería,
  temperatura, red, tema, música, proveedor y errores recientes.
- Exportar o copiar el informe (sin contraseñas, permisos de Spotify ni Client ID; posición
  redondeada).
- Línea `[DIAG]` en el registro cada 10 s durante la ruta o el enlace; `[RED]` con los cambios
  de red.

### Spotify y Apple Music
- Una portada que llega tarde ya no se queda con otra canción ni reescribe sus datos.
- Al elegir Spotify se muestra enseguida lo que suena; al elegir Apple Music, también.
- Los fallos de pausa, siguiente y anterior quedan en el registro.

### Navegación
- Waze, Google Maps y Mapas de Apple solo se marcan activos si iOS confirma que se abrieron.
- Recálculo: registro con el estado de la app, reintento a los 20 s y aviso de a cuánto está la
  ruta si no llega.
- Reconexión con la moto sin límite (uno cada 10 s después de los 10 primeros avisos) y con la
  IP actualizada si el Wi-Fi cambió.
- Tarjetas compactas más pequeñas (maniobra 284×136, música 250×84, viaje 400×46).

### Pruebas y compilación
- Pruebas nuevas del mapa guardado (ruta de 15 km), de la elección de imagen y de las portadas.
- Prueba en el simulador con la app en segundo plano.
- Compilación en macOS Intel en GitHub (los equipos arm64 no arrancaban).

## 0.6.0 — Navegación y multimedia
Proveedor de navegación (CFMoto Link, Mapas de Apple, Google Maps, Waze), día y noche
automáticos por el sol, colores de la portada, modos 1–5 con pantalla dividida,
Personalización del tablero.

## 0.5.0 — Mapa premium
Imagen completa de 800×400, mapa de calles de Apple Maps en la TFT, 3D, tráfico, tarjetas
flotantes, Spotify con su SDK oficial.

## 0.4.0 — Smart Dashboard
Panel modular con modos, perfiles y avisos.

## 0.1 a 0.3
Conexión con la moto, duplicar pantalla y navegación propia en la TFT.
