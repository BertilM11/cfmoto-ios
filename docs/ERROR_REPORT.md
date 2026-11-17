# Informe de errores y correcciones (0.6.0 → 0.6.1)

Cada error indica la evidencia, la corrección y cómo quedó comprobado. "Pruebas automáticas" y
"simulador" no son pruebas en la moto; lo que falta comprobar en la 450NK está marcado.

## 1. El mapa deja de actualizarse con el iPhone bloqueado — CRÍTICO

### Qué pasa y por qué

| Posible causa | Qué dice la evidencia |
| --- | --- |
| MKMapSnapshotter deja de generar imágenes | **Sí, por diseño de Apple.** La documentación de `MKMapSnapshotter.start` dice que, si una instantánea se pide con la app en segundo plano o la app pasa a segundo plano mientras se genera, la entrega se retrasa hasta que la app vuelve al primer plano. Con el iPhone bloqueado la app está en segundo plano. Además, iOS restringe el uso de la tarjeta gráfica a las apps en segundo plano. |
| El mapa deja de obtener datos nuevos | Consecuencia de lo anterior: no hay instantáneas nuevas aunque haya internet. |
| La caché se agota | **Sí, y era pronto** (error propio, ver abajo). |
| El GPS deja de actualizarse | No debería: la app usa el modo de ubicación en segundo plano (`allowsBackgroundLocationUpdates`, tipo navegación). La 0.6.1 cuenta los fijos recibidos en segundo plano para comprobarlo en la moto. |
| El tablero deja de recibir imágenes | No es lo que describes (la moto sigue mostrando la ruta, sin calles). El dibujo es solo CPU y el vídeo tiene recuperación del codificador. La 0.6.1 muestra el ritmo de envío y la edad del último fotograma. |
| El Wi-Fi Direct impide internet | No: con la 0.5 conectada a la moto, la TFT mostró calles de Apple (tu foto de la 0.5), así que los datos móviles funcionan a la vez. La 0.6.1 registra la red (`[RED]`). |
| La app queda suspendida | No mientras haya navegación o enlace (ubicación en segundo plano). Si iOS la cerrara, el registro se cortaría. |

### Errores propios que lo empeoraban (revisión de `TFTMap.swift` de la 0.6.0)

1. **El mapa guardado casi no avanzaba en marcha.** Solo se pedía cuando el mapa en vivo no
   tenía nada que pedir (`if liveSnapshotter == nil && cacheSnapshotter == nil`), y en marcha el
   mapa en vivo pide una imagen nueva cada fracción de segundo.
2. **Tope de 40 imágenes y 8 km**, de una en una.
3. **Al recalcular la ruta se borraba todo lo guardado** (`cache.removeAll()` al cambiar de
   ruta), justo cuando más falta hace con el iPhone bloqueado.
4. **Una instantánea que no llegaba nunca dejaba el mapa en vivo congelado** (no había tiempo
   límite).
5. **Una imagen pedida justo antes de bloquear llegaba al desbloquear** y se mostraba como si
   fuera actual (salto de posición).
6. Las imágenes con el tema equivocado (día/noche) podían ganar a las del tema correcto si
   estaban mejor colocadas.

Y uno de la propia 0.6.1, encontrado con la prueba del simulador antes de publicarla:

7. **El mapa guardado se repetía cerca de la moto en vez de avanzar.** En la primera prueba en
   segundo plano había 26 imágenes guardadas pero solo 0,8 km seguidos. Los puntos donde
   guardar imagen se contaban desde la posición actual, y la separación cambiaba un poco con
   cada imagen (calibración): al avanzar unos metros nada de lo guardado coincidía con los
   puntos nuevos y se volvía a pedir lo más cercano. Lo mismo pasaba al recalcular desde la
   posición actual: la ruta nueva empieza en otro sitio y se volvía a pedir casi todo.
8. **Con el iPhone bloqueado el tema del mapa se quedaba congelado.** El tema pedido (día o
   noche), el avance por la ruta y la cobertura solo se actualizaban con la app al frente. Si
   anochecía con el iPhone bloqueado, el dibujo seguía prefiriendo las imágenes claras, y el
   diagnóstico mostraba la cobertura de cuando se bloqueó.

Y uno que venía de la 0.5, visto en la captura en segundo plano del simulador:

9. **En rectas largas no se veía la línea de la ruta por delante de la moto** sobre las
   imágenes planas (todas las guardadas). Apple describe una avenida recta con muy pocos
   puntos; si el siguiente quedaba lejos, caía muy fuera de la imagen, se descartaba y la
   línea no se dibujaba. Ahora la línea lleva un punto cada 40 m como mucho.

### Corrección

- La ruta se guarda **entera por delante** (hasta el límite de memoria: 16–64 MB según la
  memoria libre, 400 imágenes como máximo), **en paralelo** al mapa en vivo (2 peticiones a la
  vez), de lo más cercano a lo más lejano, sin repetir lo ya guardado.
- Una imagen extra **justo después de cada giro**, ya orientada a la calle nueva.
- Cada tramo se guarda con el **tema que tocará al pasar por él** (hora prevista de paso y
  amanecer/atardecer de ese punto).
- Al recalcular se **conservan** las imágenes que siguen sobre la ruta nueva y en la misma
  dirección; solo se pide lo nuevo.
- Los puntos donde guardar imagen forman una **rejilla fija desde el inicio de la ruta** y la
  separación solo cambia si la calibración varía más de un 15 %; además no se pide un tramo
  que ya cubren otras imágenes (por ejemplo, las conservadas al recalcular).
- En segundo plano se siguen calculando el tema, el avance y la cobertura (sin pedir nada a
  Apple): al anochecer se eligen las imágenes oscuras guardadas para ese tramo.
- Lo ya recorrido se suelta; si falta memoria, se sueltan las más lejanas.
- Peticiones atascadas: se cancelan a los 12 s (en vivo) o 25 s (ruta) y se repiten.
- Imágenes en vivo que llegan con más de 5 s de retraso se descartan.
- El tema correcto gana siempre; el otro tema solo se usa si no hay ninguna del correcto (y el
  diagnóstico lo marca).
- **Cobertura medida**: kilómetros seguidos con imagen desde la posición. En Navegación aparece
  "Guardando el mapa…" o "Mapa guardado: X de Y km" (en verde cuando ya se puede bloquear).
- **Pantalla negra**: alternativa para tener mapa en vivo todo el viaje sin bloquear (la app
  sigue al frente con el brillo al mínimo).

### Cómo quedó comprobado

- Pruebas automáticas (ruta de prueba de 15 km con dos giros): la ruta queda guardada entera y
  sin huecos, las curvas tienen su imagen, no se pide nada dos veces, con poca memoria se guarda
  lo más cercano, al recalcular se conserva el tramo común y solo se pide el nuevo, se detecta
  un tramo sin imagen, el tema correcto gana. Resultados en `TEST_RESULTS.md`.
- Simulador: prueba con la app en segundo plano (otra app al frente 50 s) con el registro de lo
  que pasa (`log-segundo-plano.txt`).
- **Falta en la moto**: pruebas A–J de `TESTING.md` con el informe de diagnóstico.

### Límite que queda (no se puede saltar con las APIs de Apple)

- Con el iPhone bloqueado **no hay imágenes nuevas de Apple**. Fuera de lo guardado (desvío por
  calles que no están en la ruta, o recálculo con el iPhone bloqueado) la moto vuelve al mapa
  simple de la ruta.
- Guardar más que la ruta del viaje sería una descarga masiva, que los términos de Apple Maps
  prohíben; tampoco se puede dibujar la ruta de Apple sobre un mapa de otro proveedor. Por eso
  no se mezclan mapas de OpenStreetMap con las rutas de Apple.
- Para tener calles nuevas con el iPhone bloqueado haría falta un sistema completo que no
  dependa de Apple: datos de calles de OpenStreetMap (licencia ODbL, con atribución), un dibujo
  propio de calles por CPU y rutas calculadas también con OpenStreetMap (por ejemplo, un
  servidor de rutas con su propia política de uso). Es un proyecto aparte; ver
  `INTEGRATIONS.md`.

## 2. Spotify: portada y datos de una canción anterior — ALTA

**Evidencia (código de la 0.6.0):** al llegar la portada (asíncrona), se publicaba una copia de
los datos de la canción **de cuando se pidió**. Si la canción cambiaba mientras tanto, la moto
volvía a mostrar el título, el artista y la portada de la anterior, y sus colores.

**Corrección:** cada portada se acepta solo si sigue sonando esa canción (`ArtworkGate`, con
pruebas) y completa los datos **actuales** de esa canción, no una copia vieja.

## 3. Spotify: tardaba en aparecer al elegirlo — ALTA

**Evidencia:** al cambiar de Apple Music a Spotify, la moto no mostraba nada hasta que cambiaba
algo en el reproductor de Spotify.

**Corrección:** al elegir Spotify se publica enseguida lo último y se pide el estado actual; al
elegir Apple Music se lee al momento. Los fallos de pausa, siguiente y anterior quedan en el
registro.

## 4. Waze / Google Maps / Mapas de Apple: activos aunque no se abrieran — ALTA

**Evidencia:** `UIApplication.open` es asíncrono y la 0.6.0 no miraba si iOS lo había abierto;
marcaba la guía externa como activa y terminaba la guía de CFMoto Link igualmente.

**Corrección:** solo se pasa la guía a la otra app si iOS confirma que se abrió. Si no: aviso,
el destino y la ruta siguen en CFMoto Link y el proveedor vuelve a CFMoto Link (o al anterior).

## 5. Recálculo de ruta que no responde — MEDIA

**Evidencia:** si el recálculo no respondía (sin datos, o con el iPhone bloqueado: Apple puede
retrasar la respuesta), la moto quedaba en "Recalculando la ruta…" sin más.

**Corrección:** se registra cuánto tarda y en qué estado estaba la app; si no responde en 20 s
se pide otra vez; a los 12 s la tarjeta dice a cuántos metros está la ruta.
**Falta comprobar en la moto** qué hace Apple con el recálculo y el iPhone bloqueado (el
registro lo dirá).

## 6. Reconexión con la moto que se rendía — MEDIA

**Evidencia:** tras perder el enlace, la 0.6.0 avisaba a la moto 10 veces (~45 s) y paraba.
Al apagar la moto un rato había que reconectar a mano.

**Corrección:** después de los 10 avisos sigue uno cada 10 s mientras el enlace esté activo, y
actualiza la IP si el Wi-Fi de la moto se cayó y volvió. **Falta comprobar en la moto.**

## 7. Tarjetas que tapaban mucho mapa — MEDIA

Tarjetas compactas más pequeñas: maniobra 284×136 (antes 300×150), música 250×84 (antes
262×84), datos del viaje 400×46 (antes 420×50). La letra se ajusta al tamaño.

## Revisado sin cambios

- **Protocolo con la moto (EasyConn/PXC)**: sin cambios. Solo se añadió la reconexión lenta y
  estadísticas.
- **Codificador H.264**: ya recreaba la sesión si iOS la invalidaba en segundo plano y probaba el
  de software; se añadieron estadísticas (codificados, fallos, tipo, último fotograma).
- **Contadores de BikeLink** que se tocan desde varios hilos sin cerrojo: solo afectan a los
  números del registro; se dejaron así para no tocar el protocolo.
