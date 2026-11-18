# La pantalla de la 450NK: qué controla la app y qué no

Análisis hecho antes de la versión 0.5.0, con el registro de la conexión y la foto del
propietario de la TFT mostrando la navegación de la 0.3.

## 1. Resolución y área de dibujo

- La moto pide **vídeo H.264 de 800×400** (lo dice el registro de la conexión). Es lo único
  que la app puede dibujar.
- En la foto se ve **la imagen de 800×400 completa** y, **debajo**, una franja negra propia de
  la moto con la velocidad, las rpm, la marcha, la gasolina, la temperatura y los testigos.
  Esa franja no forma parte de nuestra imagen: la dibuja el firmware de la moto.
- No sabemos la resolución física del panel ni si el firmware escala la imagen; no hace falta
  para diseñar, porque la app solo controla esos 800×400.

## 2. La franja negra que se veía con la 0.4

Era **de la app**. Hasta la 0.4, la app dejaba vacío el 22 % inferior de la imagen porque se
creía que la moto ponía sus indicadores encima. La foto de la 0.3 lo desmiente: la fila de
llegada, tiempo y distancia se ve completa y, debajo, el hueco vacío de la app; los indicadores
de la moto están más abajo, fuera de la imagen. Con el tema oscuro de la 0.4 ese hueco se veía
como una franja negra entre el panel y los indicadores.

**Desde la 0.5.0 la app usa la imagen entera.** Si en algún caso hiciera falta, **Más > Ajustes
> Dejar vacía la parte de abajo de la imagen** recupera el comportamiento anterior.

## 3. Qué se transmite

Se transmite **una imagen** (vídeo H.264), no datos de navegación ni comandos: la moto no sabe
que hay un mapa, solo muestra los fotogramas. Por eso:

- todo el diseño (mapa, tarjetas, música) se compone en el iPhone en una sola imagen;
- la pantalla de la moto no es táctil para la app y el protocolo conocido no envía botones,
  así que los controles de música están en el iPhone (desde la 0.6.4 la moto dibuja los mismos
  botones, pero solo se ven: no se pueden pulsar);
- la app no puede leer la velocidad, las rpm ni la marcha de la moto, ni ocultarlas.

## 4. ¿Se puede ampliar la región?

No más allá de 800×400: es lo que la moto pide en el saludo. La franja de indicadores la pone
el firmware y no se puede tapar ni mover (tampoco se debe).

## 5. Proveedor de mapas

| Opción | Calles y nombres | Coste y claves | En segundo plano | Elegida |
| --- | --- | --- | --- | --- |
| Apple Maps (MapKit, instantáneas) | Sí, con tráfico, 3D y modo noche | Gratis, sin claves | Solo con la app al frente | **Sí** |
| Mapbox | Sí, muy personalizable | Requiere cuenta y token propios | Sí (SDK propio) | No: haría falta tu cuenta y su SDK |
| Google Maps SDK | Sí | Clave de pago; sus condiciones prohíben la guía giro a giro en apps de terceros | — | No |
| Teselas de OpenStreetMap | Sí | Los servidores públicos no permiten este uso intensivo | Sí | No |

Apple solo genera las imágenes del mapa con la app abierta. Para el iPhone bloqueado, al
iniciar una ruta la app guarda imágenes del recorrido (hasta unos 8 km por delante) y las usa
mientras la app está en segundo plano. Si te sales de esa zona, la moto muestra el dibujo
simple de la ruta hasta que vuelvas a abrir la app.

## 6. Lo que falta comprobar en la moto

- Que el mapa de calles se lee bien en la TFT (tamaño de letras, contraste de día y de noche).
- Que la imagen sigue llegando con el iPhone bloqueado y que se usan las imágenes guardadas.
- Que el cambio de modo no corta el vídeo.
