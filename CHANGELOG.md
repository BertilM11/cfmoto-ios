# Registro de cambios

## 0.6.2 — Diseño de la pantalla (17 de noviembre de 2026)

Respaldo de la versión anterior: etiqueta `v0.6.1`, rama `backup/v0.6.1`, publicación
`build-9` y carpeta `BACKUP_ORIGINAL_0.6.1` (ver `docs/ROLLBACK.md`). No cambian la conexión
Wi-Fi Direct, el vídeo H.264 ni el protocolo con la moto.

### Modo 4 · Música completa (al estilo de CarPlay)
- Portada grande a la derecha (247 px de 400 de alto con el tamaño normal; antes 200).
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
