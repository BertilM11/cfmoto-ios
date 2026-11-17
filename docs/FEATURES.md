# Estado real de cada función (0.4.0)

"Verificado en la moto" significa que el propietario lo vio funcionar en su CFMOTO 450NK.
"Verificado en pruebas" significa que pasa las pruebas automáticas o se vio en el simulador de
iPhone, pero no en la moto.

## Reales

| Función | Estado |
| --- | --- |
| Conexión con la moto y envío de vídeo | Verificado en la moto (versiones 0.1 a 0.3) |
| Navegación propia dibujada en la TFT | Verificado en la moto (0.3) |
| Franja inferior libre para velocidad, marcha y testigos | Verificado en la moto (0.3) |
| Mapa, búsqueda, rutas reales, guía giro a giro, voz | Verificado en simulador; guía vista en la moto |
| Siete modos y panel modular | Verificado en pruebas; **falta la moto** |
| Editor "Mi pantalla" (arrastrar, tamaños, temas) | Verificado en pruebas (lógica) y simulador |
| Perfiles y persistencia | Verificado en pruebas |
| Cambios automáticos de modo | Verificado en pruebas; falta en ruta real |
| Música de la app Música (Apple Music): canción, artista, portada, progreso, controles | Programado; **sin probar en un iPhone** |
| Avisos de navegación, conexión y batería | Programado; falta en uso real |
| Duplicar pantalla | Verificado en la moto (0.2) |

## Simuladas (y marcadas como tales)

- **Vista previa con datos de demostración** y miniaturas de los modos: llevan la etiqueta DEMO.
  Esos datos nunca se envían a la moto.
- **Recorrido simulado** en Navegación: la app y la moto muestran SIMULACIÓN.
- **Aviso de prueba**: se titula "Aviso de prueba".

## Limitadas por iOS o por el proveedor

| Función pedida | Qué pasa |
| --- | --- |
| Notificaciones de WhatsApp, Telegram, llamadas | **No es posible.** iOS no deja que una app lea las notificaciones de otras apps. El módulo de avisos existe y muestra solo fuentes propias. |
| Spotify | **No incluido.** Su SDK oficial exige registrar la app con una cuenta Premium y un identificador propio. La app no trae credenciales; `MusicService` es el punto donde se añadiría. |
| YouTube Music y otras apps de música | **No es posible** leer lo que suena en otra app; no ofrecen SDK para ello. |
| Mapa con calles en la TFT | La TFT muestra la **ruta** sobre fondo liso, no el mapa de calles. El mapa completo está en el iPhone. Dibujar calles exige la tarjeta gráfica, que iOS niega en segundo plano. |
| Leer velocidad, marcha o combustible de la moto | No disponible en el protocolo conocido. La app no dibuja indicadores falsos. |
| Controles en la TFT | La pantalla no es táctil para la app: la música se controla desde el iPhone. |
| Vídeo con el iPhone bloqueado | Sin comprobar (ver `CONNECTION.md`). |
| Idioma | Solo español. |

## No incluidas todavía

Varias paradas en una ruta, navegación en la pantalla de bloqueo del iPhone, límites de
velocidad y posición libre de módulos fuera de las tres plantillas.

## Diseño aprobado

La imagen "CFMOTO 450NK — Interfaz Inteligente de Navegación" no llegó con el pedido. El panel
sigue la organización descrita en el texto (mapa protagonista, tarjeta de giro, música y avisos
a la derecha) y debe revisarse contra esa imagen.
