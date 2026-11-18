# Diseño 0.6.4 — Acabado premium del reproductor

La 0.6.4 parte de la 0.6.3 y solo cambia el dibujo de la música. Ningún módulo cambia de sitio
ni de tamaño: las zonas y las tarjetas miden lo mismo que en la 0.6.3 (prueba automática).
No cambian la conexión Wi-Fi Direct, el vídeo H.264, el protocolo con la moto ni sus
indicadores, la navegación, la hora, el modo día/noche, el mapa guardado ni sus diagnósticos
(ningún archivo de `Shared/`, `Broadcast/`, `MapCorridor.swift`, `TFTMap.swift`,
`Diagnostics.swift` ni `DashMapRenderer.swift` cambió).

## Qué se tomó de las referencias

| Referencia | Qué se tomó |
| --- | --- |
| 02 · Reproductor con controles grandes | Tres botones debajo del título y el artista: anterior, un **círculo grande** de reproducir/pausar y siguiente, en blanco; la barra con el tiempo transcurrido a la izquierda y la duración a la derecha; la portada grande a la derecha; el fondo oscuro con la luz de la portada |
| 01 · Panel premium | En las tarjetas pequeñas: portada a la izquierda, título en negrita, artista, los tres botones en una fila y la barra fina |
| 05 · Foto de la TFT (solo música) | Lo que había que mejorar: sin botones y con un fondo plano |
| 06 · Foto de la TFT (distribución) | Las posiciones que no se mueven |

## Los botones en cada modo

Los botones van donde la 0.6.3 mostraba el estado («Reproduciendo»), así que caben sin agrandar
nada. El círculo central es proporcional al sitio:

| Modo | Forma del reproductor | Círculo | Detalles |
| --- | --- | --- | --- |
| Música completa | Escenario | 62 px | Centrados bajo el título, el artista y el álbum; portada de 274 px |
| Música completa con el próximo giro abajo | Escenario | 62 px | Portada de 209 px |
| Dividida | Columna | 44 px | Portada de 162 px arriba, textos y botones debajo |
| Música + Avisos | Columna | 44 px | Portada de 155 px |
| Música + Avisos con ruta | Fila | 40 px | Portada de 181 px a la izquierda |
| Nav + Música, Completo y Personalizado (tarjeta compacta, 250×84) | Fila | 22 px | Título y artista; debajo, los botones con el nombre del servicio a la derecha; barra fina al pie |
| Tarjeta grande (300×124) y zona lateral | Fila | 26 px | Servicio, título, artista, botones y barra con los tiempos |

- **Estado real**: ❚❚ mientras suena y ▶ en pausa. Al cambiar, el símbolo se funde en 0,25 s.
- **Sin música**: los botones se ven apagados, con ▶.
- **Noche**: iconos blancos y círculo blanco con el símbolo oscuro. **Día**: al revés (iconos y
  círculo oscuros con el símbolo claro), para que se vean sobre el fondo claro.
- **Solo dibujo**: la moto no envía toques ni teclas a la app, así que en la TFT no se pueden
  pulsar. No se tocó el protocolo. La música se controla igual que antes: con los botones del
  iPhone (Más > Música), con el intercomunicador o con la app de música.

## Acabado

- **Luz de la portada**: el fondo toma los colores de la portada, reducidos y difuminados, sobre
  el degradado de la 0.6.3, con el resplandor detrás de ella (como en CarPlay).
- **Portada**: sombra difuminada y un filo fino que la separa del fondo. Las portadas que no son
  cuadradas se ven enteras, sin estirarse.
- **Barra de progreso**: degradado del color de la barra y punto con halo.
- **Letra**: título en negrita y grande, artista algo menor y álbum (donde cabe) más tenue.
- **Cambio de canción**: el fondo de cada canción se dibuja una vez y se guarda; al cambiar, se
  funden el anterior y el nuevo, sin volver a dibujarlos.

## Pruebas

Las pruebas automáticas comprueban, en los 10 sitios donde aparece la música, de día y de noche,
sonando y en pausa: que los tres botones están dentro de su tarjeta o zona sin tocar textos ni la
hora, que el círculo es mayor que los laterales y están alineados, que el símbolo central
coincide con el estado, que los iconos contrastan con su fondo (≥ 3:1), que sin música se ven
apagados, que el cambio ▶/❚❚ se funde, que las tarjetas miden lo mismo que en la 0.6.3, que una
portada no cuadrada no se estira, que ningún texto se corta y que cada fotograma tarda menos de
25 ms. Resultados en `TEST_RESULTS.md`.

Falta verlo en la TFT (pruebas U y V de `TESTING.md`): que los botones se lean bien al sol y de
noche y que el símbolo cambie al pausar desde el iPhone.
