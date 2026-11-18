# Mapa con el iPhone bloqueado — informe de la 0.6.3

Qué se puede hacer y qué no para que la moto siga viendo calles cuando el iPhone está bloqueado,
qué cambió en la 0.6.3 y cómo usarlo. Todo lo que dice "verificado" se comprobó con las pruebas
automáticas o en el simulador; **nada de esto se ha probado todavía en la 450NK**.

## 1. Por qué deja de llegar el mapa

| Pieza | Qué dice la documentación | Consecuencia |
| --- | --- | --- |
| `MKMapSnapshotter` (las imágenes de calles de Apple) | Entrega la imagen solo con la app en primer plano; si se pide en segundo plano, o la app pasa a segundo plano mientras se genera, la entrega se retrasa hasta que la app vuelve al frente ([Apple](https://developer.apple.com/documentation/mapkit/mkmapsnapshotter/start(with:completionhandler:))) | Con el iPhone bloqueado **no llegan imágenes nuevas de Apple**. No hay modo de segundo plano que lo cambie |
| Tarjeta gráfica (GPU) en segundo plano | iOS limita el acceso de las apps en segundo plano a la GPU; los trabajos que se envían no se ejecutan ([Apple, Metal](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background)) | Ningún SDK de mapas que dibuje con la GPU (MapKit, Mapbox, Google, HERE) puede generar mapa con el iPhone bloqueado. CFMoto Link dibuja la pantalla de la moto solo con la CPU por eso |
| Codificador H.264 (VideoToolbox) | La sesión del codificador puede quedar invalidada al pasar de primer a segundo plano y hay que recrearla ([FFmpeg, parche para iOS](https://ffmpeg.org/pipermail/ffmpeg-devel/2018-June/231467.html)) | La app recrea el codificador si iOS lo invalida (desde la 0.6.1). **Falta comprobarlo en la moto**: es la prueba Q de `TESTING.md` |
| Términos de Apple Maps (Acuerdo de desarrollador, anexo 6) | §2.5: no se pueden guardar ni precargar datos del mapa salvo de forma temporal y limitada para que el servicio funcione o vaya más rápido, y después hay que borrarlos. §2.2: nada de descargas masivas. §2.4: los datos de Apple solo se muestran sobre un mapa de Apple. §2.7: Apple puede limitar el número de peticiones ([Apple](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)) | Se guarda **solo la ruta del viaje en curso, en memoria**, y se borra al terminar. No se descargan zonas enteras ni se mezclan calles de otro proveedor con la ruta de Apple |
| Mapas sin conexión de Apple | Los mapas descargados de la app Mapas (iOS 17) no están disponibles para otras apps: un ingeniero de Apple confirma que no es posible con las API actuales; MapKit solo sirve sin conexión con teselas propias ([foro de Apple](https://developer.apple.com/forums/thread/765857)) | No se pueden usar los mapas que el usuario descargó en Mapas de Apple |

## 2. Qué hace la 0.6.3

**Al elegir el destino** (antes incluso de pulsar Iniciar) la app empieza a guardar la ruta,
desde la salida hasta el destino, con el iPhone desbloqueado:

1. **Por tramos y de cerca a lejos**: una imagen cada ~180 m de ruta (con el zoom por defecto) y
   otra justo después de cada giro, orientada a la calle nueva. Lo más cercano y los giros van
   primero.
2. **Calles, cruces, nombres y estilo**: cada imagen es una instantánea real de Apple Maps con el
   mismo estilo, los mismos lugares (gasolineras, aparcamientos, hospitales, policía, cargadores)
   y el mismo tema que el mapa en vivo.
3. **Día y noche correctos**: los tramos por los que se pasará después del atardecer se guardan
   ya en oscuro (se calcula la hora a la que se llegará a cada tramo y el sol en ese punto).
4. **Sin repetir ni pedir de más**: lo ya guardado o ya pedido no se vuelve a pedir; al
   recalcular se conservan las imágenes que siguen sirviendo; las que quedan atrás se sueltan.
5. **Memoria con límite** (nuevo): hasta **800 imágenes y 96 MB** (antes 400 y 64 MB), nunca más
   de la quinta parte de la memoria libre de la app. Si iOS avisa de poca memoria, se sueltan las
   imágenes más lejanas durante 2 minutos (se vuelven a pedir al acercarse) para que iOS no cierre
   la app.
6. **Más rápido** (nuevo): **3 imágenes a la vez** además del mapa en vivo (antes 2).
7. **Se sigue completando** cada vez que el iPhone está desbloqueado (por ejemplo, en un semáforo
   o en una parada); con el iPhone bloqueado se mantienen al día el tema, el avance y la cobertura,
   pero no llegan imágenes nuevas.
8. **Cobertura real** (nuevo): la app revisa cada 25 m de ruta si hay una imagen en la que la
   moto se vería bien y cuenta los kilómetros **seguidos** que tienen mapa desde donde estás. Los
   puntos de revisión son fijos sobre la ruta: en la prueba del simulador se vio que, cuando se
   movían con la moto, la cifra saltaba (4,0 → 1,8 → 3,9 km en 20 s sin imágenes nuevas); ahora
   es estable (prueba automática: el final de lo guardado no se mueve al avanzar).

### Qué ves en el iPhone (Navegación y pantalla negra)

| Aviso | Qué significa |
| --- | --- |
| **Ruta completa guardada: 12 km** (verde) | Toda la ruta que queda tiene mapa. Ya puedes bloquear |
| **Guardando el mapa: 3.2 km de 12 km** | Se está guardando; aún no está toda. Espera o usa la pantalla negra |
| **Mapa parcial: 141 km de 160 km (límite de memoria)** (naranja) | La ruta no cabe entera en la memoria. Con el iPhone bloqueado, después de esos kilómetros la moto mostrará el mapa simple |

### Qué ves en la moto

- Con el iPhone bloqueado se usan las imágenes guardadas; la moto avanza por ellas.
- **Nuevo:** si la ruta no está completa y quedan menos de 2 km de mapa guardado, arriba aparece
  **MAPA GUARDADO: 1.4 KM**, para saber que pronto se acaba.
- Fuera de lo guardado (o si te desvías), **MAPA SIMPLE**: la ruta y la flecha sin calles, hasta
  que desbloquees el iPhone.

## 3. Cuánto se guarda (cifras de las pruebas)

Medido con el planificador real de la app y tiempos de imagen supuestos (la prueba del simulador
de la 0.6.1 midió unos 4,5 s por imagen; en un iPhone real se espera menos, **sin medir**):

| Caso | 0.6.2 | 0.6.3 |
| --- | --- | --- |
| Ruta que cabe en la memoria (zoom por defecto) | ~70 km | ~140 km |
| Ruta de 15 km, parado, 2 s por imagen: guardado en 40 s | ver `TEST_RESULTS.md` | ver `TEST_RESULTS.md` |
| Ruta de 15 km: tiempo hasta «Ruta completa guardada» | — | poco más de 1 min (2 s por imagen) |
| Memoria máxima | 64 MB | 96 MB (y 1/5 de la libre como mucho) |
| Simulador de GitHub (prueba en segundo plano), ruta de 8,8 km | — | 31 imágenes en el primer minuto (unos 6 s por imagen y por petición: el simulador es más lento que un iPhone); al pasar a segundo plano la moto usó las guardadas |

## 4. Cómo usarlo

1. Elige el destino y la ruta; **espera a «Ruta completa guardada»** (o al aviso naranja si la
   ruta es muy larga) antes de bloquear.
2. Si la ruta es más larga que lo que cabe, o vas a desviarte, usa la **pantalla negra** (botón de
   la luna en Navegación): la app sigue al frente con el brillo al mínimo y Apple sigue entregando
   el mapa en vivo todo el viaje. Falta medir batería y temperatura en un viaje real.
3. En una parada, desbloquear el iPhone unos segundos completa lo que falte.

## 5. Lo que no se puede resolver con Apple Maps

- **Imágenes nuevas con el iPhone bloqueado**: imposible con `MKMapSnapshotter` (solo entrega en
  primer plano) y con cualquier mapa dibujado por la GPU.
- **Descargar mapas completos o zonas enteras de Apple**: lo prohíben los términos (§2.2 y §2.5).
- **Usar los mapas sin conexión de la app Mapas**: no hay API para otras apps.
- **Desvíos con el iPhone bloqueado**: si la ruta se recalcula por un camino nuevo, ese tramo no
  tiene imágenes hasta que se desbloquee.

## 6. Soluciones oficiales sin conexión evaluadas

| Opción | Qué ofrece | Por qué no resuelve el iPhone bloqueado tal cual |
| --- | --- | --- |
| **Mapbox Maps SDK** (iOS) | Descarga oficial de regiones con `OfflineManager` y `TileStore` (por defecto hasta 750 paquetes de teselas) ([Mapbox](https://docs.mapbox.com/ios/maps/examples/offline-pack/)); sus términos no permiten redistribuir los mapas descargados ([Mapbox](https://docs.mapbox.com/ios/maps/guides/offline/concepts/)) | Requiere cuenta, clave y pago por uso; **dibuja con la GPU**, así que con el iPhone bloqueado tampoco genera imágenes; y la ruta de Apple no puede mostrarse sobre su mapa (§2.4), así que habría que cambiar también las rutas |
| **Google Maps / Navigation SDK** | Mapa y guía de Google | De pago, con clave propia; sus términos no permiten llevar su mapa a otra pantalla; también usa la GPU |
| **MapKit con teselas propias** | MapKit puede mostrar teselas propias sin conexión (según Apple) | Habría que tener las teselas (por ejemplo, de OpenStreetMap) y seguiría dibujando con la GPU |
| **OpenStreetMap + dibujo propio por CPU** | Datos abiertos (licencia ODbL, con atribución), dibujo de calles hecho por la app con la CPU (que sí funciona en segundo plano) y rutas también de OpenStreetMap | **Es la única vía técnica** para tener calles nuevas con el iPhone bloqueado, pero es un proyecto aparte: descarga de datos del recorrido, dibujo de calles y nombres, servidor de rutas compatible y guía por voz con esas rutas. No se mezcla con Apple Maps |

**Conclusión:** con Apple Maps, lo máximo posible es lo que hace la 0.6.3: guardar la ruta entera
(hasta 800 imágenes) antes de bloquear, decir con exactitud cuántos kilómetros hay y avisar en la
moto cuando se acaban; y, para viajes largos o con desvíos, la pantalla negra. Un "modo
OpenStreetMap" con dibujo propio sería la siguiente versión grande si se quiere mapa nuevo con el
iPhone bloqueado.

## 7. Vídeo a la moto con el iPhone bloqueado

La pantalla de la moto se dibuja con la CPU y se codifica en H.264 a unas 10 imágenes por
segundo, también con el iPhone bloqueado (la app sigue activa por la ubicación en segundo plano).
Si iOS invalida el codificador al bloquear, la app lo recrea; el diagnóstico registra el ritmo de
envío (`[DIAG] envío fps`) y la edad del último fotograma.

**Esto no se puede dar por resuelto sin la moto**: que el GPS siga funcionando no demuestra que la
TFT siga recibiendo imágenes. La prueba Q de `TESTING.md` lo comprueba (bloquear el iPhone 10
minutos con la moto encendida y exportar el diagnóstico: el ritmo de envío debe seguir cerca de 10
y la edad del último fotograma por debajo de 1 s).
