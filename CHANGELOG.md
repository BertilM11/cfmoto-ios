# Registro de cambios

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
