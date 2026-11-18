# Diseño de la 0.6.2: música, instrucciones y hora

Tres cambios en el dibujo de la pantalla de la moto. No cambian la conexión Wi-Fi Direct, el
vídeo H.264, el protocolo con la moto ni la imagen de 800×400 (los indicadores de la moto siguen
en su propia franja, debajo de la imagen). Referencias: las fotos de la TFT con la 0.6.1 y la
captura de un reproductor de CarPlay que mandó el propietario.

Las capturas están en `docs/laminas/` dentro del paquete (`cambio1-…`, `cambio2-…`,
`cambio3-…`) y, con el antes y el después, en la carpeta `CAPTURAS` de la entrega.

## 1. Modo «4 · Música completa»

| | 0.6.1 | 0.6.2 |
| --- | --- | --- |
| Portada | 267 px, a la izquierda | **274 px** (tamaño normal; 288 en grande), a la derecha, con sombra suave |
| Título | Arriba a la derecha, alineado a la izquierda | Centrado, en una línea si cabe con letra de 33 a 40 px; si no, en dos |
| Artista y álbum | Artista | Artista y **álbum** (Apple Music y Spotify), centrados |
| Controles | Icono pequeño de estado junto al servicio | **Estado centrado**: «Reproduciendo» o «En pausa» (ver abajo) |
| Barra de progreso | Bajo el texto, con los tiempos encima | **A todo el ancho**, con el tiempo transcurrido a la izquierda y la duración a la derecha |
| Fondo | Degradado de la portada | Degradado de la portada y un **resplandor** de su color detrás de ella |
| Cambio de canción | Solo se mezclaban los colores | **Fundido** de la portada y los textos (menos de medio segundo) |

**Por qué no hay botones.** La referencia de CarPlay tiene anterior, pausa y siguiente. En la
450NK la pantalla no es táctil para la app y el protocolo no envía teclas: unos botones
dibujados no harían nada. En su lugar se ve el estado (reproduciendo o en pausa), centrado
donde irían los controles. La música se sigue controlando desde el iPhone o desde el
intercomunicador.

**Rendimiento.** Nada se mueve salvo la barra de progreso. El fundido dura 0,45 s y se puede
apagar con «Animaciones» en Personalización. El fondo (dos degradados) se dibuja una vez por
canción y se reutiliza en cada fotograma.

**Marca de Spotify.** El nombre del servicio sigue las reglas de Spotify (verde solo sobre
negro; si no, blanco o negro) y la portada no se recorta ni lleva nada encima (esquinas de
8 px).

Con una ruta activa, el próximo giro sigue en la franja de abajo y la portada se ajusta
(209 px; en la 0.6.1, 220).

## 2. Modos con mapa: instrucciones compactas

| | 0.6.1 | 0.6.2 |
| --- | --- | --- |
| Tamaño de la tarjeta | 284×136 | **200×96** (un 30 % menos por lado; la mitad de área) |
| Flecha | 68 px | **50 px** |
| Texto | Distancia, «Luego» y la instrucción completa en dos líneas | Distancia y **nombre de la calle** («7a Avenida»); la maniobra siguiente, pequeña, en una esquina |
| Sin ruta | 284×92 | 200×66 |

- La calle se saca de la indicación de Apple («Da vuelta a la derecha por 7a Avenida» →
  «7a Avenida»): el giro ya lo dice la flecha. Si la indicación no nombra una calle («Gira a la
  izquierda»), se muestra la indicación.
- Con la tarjeta compacta, el centro del mapa (por donde va la ruta) queda libre: la maniobra
  llega hasta x = 212 y la música empieza en x = 538, de 800.
- La tarjeta de música no cambia (250×84). La tarjeta grande de la maniobra (340×176) sigue
  disponible en Mi pantalla para quien la prefiera.
- La instrucción completa sigue en la pantalla dividida y en la franja del modo Música.

## 3. Hora actual fija

- La hora actual va **siempre arriba a la derecha** (116×30, a 12 px del borde), en los ocho
  modos, de día y de noche, con y sin ruta. No se mueve ni desaparece al activar una ruta.
- La barra de viaje dice **«Llegada 7:22 p.m. | 18 min | 7.4 km»**: la palabra «Llegada», la
  hora de llegada, y separados por líneas, el tiempo restante y la distancia. Sin ruta, la
  barra no aparece (antes mostraba la hora actual en ese mismo sitio, y con ruta la hora de
  llegada: eso era lo que se confundía).
- Lo que queda debajo de la hora se aparta: en los modos con mapa, las tarjetas de arriba a la
  derecha (la música) bajan; en las pantallas por zonas, la brújula baja y la cabecera de la
  música se acorta.
- Las etiquetas de estado (SIMULACIÓN, MAPA SIMPLE) van a la izquierda de la hora.

## Comprobación

Ver `TEST_RESULTS.md`: pruebas automáticas de cada regla (sitio de la hora en 32
composiciones, tamaños, centro libre, calles, distribución de la música, contraste, fundido y
tiempo de dibujo) y capturas del simulador con mapas reales de Apple. **Falta verlo en la
TFT de la moto.**
