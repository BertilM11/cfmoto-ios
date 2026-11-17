# Estado real de cada función (0.5.0)

"Verificado en la moto" significa que el propietario lo vio funcionar en su CFMOTO 450NK.
"Verificado en pruebas" significa que pasa las pruebas automáticas o se vio en el simulador de
iPhone, pero no en la moto.

## Reales

| Función | Estado |
| --- | --- |
| Conexión con la moto y envío de vídeo | Verificado en la moto (0.1 a 0.3) |
| Navegación propia dibujada en la TFT | Verificado en la moto (0.3) |
| Imagen completa de 800×400, sin franja vacía (0.5) | Verificado en pruebas; la causa se comprobó con la foto de la 0.3 (ver `PANTALLA.md`); **falta la foto con la 0.5** |
| Mapa de calles de Apple Maps en la TFT, con la app abierta (0.5) | Verificado en el simulador con rutas reales; **falta la moto** |
| Mapa de calles con el iPhone bloqueado (imágenes guardadas del recorrido) (0.5) | Programado; **sin probar** (y depende de que el vídeo siga con el iPhone bloqueado) |
| Ruta resaltada con borde, tramo recorrido atenuado, punto de maniobra y destino | Verificado en pruebas (sobre un mapa de prueba) y simulador |
| Indicador de posición, brújula, vista 3D, norte arriba, zoom según velocidad y giros | Verificado en simulador; falta la moto |
| Rutas alternativas (al empezar la ruta) | Programado; se dibujan en gris los primeros 600 m |
| Tráfico en colores | Con iOS 17 o posterior, cuando Apple tiene datos de la zona (sobre las calles, no sobre la línea de la ruta) |
| Modo noche del mapa | Verificado en simulador |
| Tarjetas flotantes semitransparentes (maniobra, música, viaje, avisos, reloj) | Verificado en pruebas (3000 combinaciones sin solapes) |
| Modos A–D y los tres modos de la 0.4 | Verificado en pruebas; **falta la moto** |
| Editor "Mi pantalla": mover tarjetas, tamaños, mostrar u ocultar, estilo del mapa | Verificado en pruebas (lógica) y simulador |
| Perfiles y persistencia; la configuración de la 0.4 se conserva al actualizar | Verificado en pruebas |
| Cambios automáticos de modo | Verificado en pruebas; falta en ruta real |
| Apple Music (canción, artista, portada, progreso, controles) | Programado; **sin probar en un iPhone** |
| Spotify con su SDK oficial (canción, artista, portada, progreso, controles) | Programado y compilado; **sin probar**: necesita tu Client ID de developer.spotify.com |
| Avisos de navegación, conexión y batería | Programado; falta en uso real |
| Duplicar pantalla | Verificado en la moto (0.2) |

## Simuladas (y marcadas como tales)

- **Vista previa con datos de demostración** y miniaturas de los modos: llevan la etiqueta DEMO
  y el mapa simplificado. Esos datos nunca se envían a la moto.
- **Recorrido simulado** en Navegación: la app y la moto muestran SIMULACIÓN.
- **Aviso de prueba**: se titula "Aviso de prueba".
- **Mapa de prueba** de las pruebas automáticas: una cuadrícula dibujada por el programa de
  pruebas, solo para comprobar la proyección; no existe en la app.

## Limitadas por iOS o por el proveedor

| Función pedida | Qué pasa |
| --- | --- |
| Mapa de calles con el iPhone bloqueado | Apple solo genera imágenes del mapa con la app abierta. Se usan las guardadas al iniciar la ruta (hasta ~8 km por delante, si la app estuvo abierta el tiempo suficiente). Fuera de esa zona: dibujo simple de la ruta, con la etiqueta MAPA SIMPLE. |
| Tráfico sobre la línea de la ruta | MapKit no da el tráfico por tramo de la ruta: se ve en las calles del mapa. |
| Spotify | Desde 2026 Spotify exige que la cuenta dueña de la app de desarrollo tenga Premium, y limita a 5 usuarios. El permiso dura una hora. La app no trae ninguna credencial. |
| Notificaciones de WhatsApp, Telegram, llamadas | **No es posible.** iOS no deja que una app lea las notificaciones de otras apps. |
| YouTube Music y otras apps de música | **No es posible** leer lo que suena en otra app; no ofrecen SDK. |
| Leer velocidad, marcha o combustible de la moto | No disponible en el protocolo conocido. La app no dibuja indicadores falsos; los de la moto siguen en su franja. |
| Controles en la TFT | La pantalla no es táctil para la app y el protocolo no envía botones: la música se controla desde el iPhone. |
| Ampliar la imagen más allá de 800×400 | La resolución la pide la moto. |
| Nombre de la calle por la que vas | MapKit no lo da de forma continua; la tarjeta muestra la calle del próximo giro. |
| Idioma | Solo español. |

## No incluidas todavía

Varias paradas en una ruta, límites de velocidad, navegación en la pantalla de bloqueo del
iPhone y colores de tráfico sobre la propia ruta.
