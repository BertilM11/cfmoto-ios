# Estado real de cada función (0.6.4)

"Verificado en la moto" significa que el propietario lo vio funcionar en su CFMOTO 450NK.
"Verificado en pruebas" significa que pasa las pruebas automáticas o se vio en el simulador de
iPhone, pero no en la moto.

## Reales

| Función | Estado |
| --- | --- |
| Conexión con la moto y envío de vídeo | Verificado en la moto (0.1 a 0.5) |
| Navegación propia dibujada en la TFT | Verificado en la moto (0.3) |
| Imagen completa de 800×400, sin franja vacía | Verificado en la moto (foto de la 0.5) |
| Mapa de calles de Apple Maps en la TFT, con la app abierta | Verificado en la moto (foto de la 0.5, sin ruta) |
| **0.6.4** Botones del reproductor (anterior, reproducir/pausar grande, siguiente) en todos los modos con música, con el estado real; solo dibujo | Verificado en pruebas (10 sitios, día y noche, sonando y en pausa: dentro de su sitio, sin tocar textos ni la hora, proporciones, ❚❚/▶, contraste ≥ 3:1) y capturas; **falta verlo en la TFT** (pruebas U y V) |
| **0.6.4** Acabado premium: luz de la portada en el fondo, sombra difuminada, barra con degradado, portadas no cuadradas sin estirar, fundido entre canciones | Verificado en pruebas y capturas (el mismo tiempo por fotograma que la 0.6.3, medido en la misma máquina); **falta en la TFT** (pruebas U y W) |
| **0.6.3** Rediseño premium: tarjetas de vidrio con borde luminoso en todos los modos, maniobra con mosaico, bloques Distancia · Restante · Llegada, hora con reloj, avisos con remitente, ruta con resplandor y posición nueva, sin mover nada | Verificado en pruebas (posiciones iguales a la 0.6.2, mismo vidrio en todas las tarjetas, textos sin cortar, < 8 ms por fotograma) y capturas de los 8 modos; **falta verlo en la TFT** (prueba T) |
| **0.6.3** El mismo reproductor en todos los modos (completa, columna, zonas y tarjetas) | Verificado en pruebas (forma, contraste ≥ 4,5, fondo de la portada, estado) y capturas; **falta en la TFT** con Spotify y Apple Music |
| **0.6.3** Maniobra compacta en la Dividida y zonas con mapa, con tamaño y esquina del iPhone | Verificado en pruebas (20 combinaciones sin tapar hora, viaje, brújula ni ruta) y capturas; **falta en la TFT** |
| **0.6.3** Mapa guardado: 3 a la vez, 800 imágenes / 96 MB, aviso completa/guardando/parcial y MAPA GUARDADO en la moto | Verificado en pruebas (ruta de 15 km completa en 70 s con 2 s por imagen) y en el simulador; **falta en el iPhone y la moto** (pruebas P, Q y R) |
| **0.6.2** Música completa al estilo de CarPlay (portada grande, textos centrados, estado, barra con tiempos, fondo con los colores de la portada, fundido al cambiar de canción) | Verificado en pruebas y capturas; **falta verla en la TFT** |
| **0.6.2** Maniobra compacta (200×96) con flecha, distancia y calle | Verificado en pruebas y capturas; **falta verla en la TFT** con una ruta real |
| **0.6.2** Hora actual fija arriba a la derecha y «Llegada» en la barra de viaje | Verificado en pruebas (8 modos, día y noche, con y sin ruta) y capturas; **falta en la TFT** |
| **0.6.2** Botones de música en la TFT | **No se dibujan a propósito**: la pantalla no es táctil para la app y el protocolo no envía teclas. Se muestra el estado (reproduciendo / en pausa) |
| **0.6.1** Mapa de calles con el iPhone bloqueado: ruta entera guardada por delante (hasta el límite de memoria), imagen tras cada giro, tema según la hora de paso, conservado al recalcular | Verificado en pruebas (ruta de 15 km sin huecos; avanzando, sin repetir) y en el simulador (unos 5 km guardados en 80 s; en segundo plano se usa lo guardado); **falta la moto** (pruebas A–K de `TESTING.md`) |
| **0.6.1** Aviso "Guardando el mapa / Mapa guardado: X de Y km" en Navegación | Visto en el simulador; falta en el iPhone |
| **0.6.1** Pantalla negra (mapa en vivo sin bloquear el iPhone) | Programado; **falta probar** batería y temperatura en un viaje real |
| **0.6.1** Diagnóstico con informe exportable | Programado y compilado; **falta verlo en el iPhone** |
| **0.6.1** Reconexión con la moto sin límite de intentos | Programado; **falta la moto** (apagar y encender) |
| **0.6.1** Spotify: portadas y datos siempre de la canción que suena | Verificado en pruebas (lógica de la portada); falta con Spotify real |
| **0.6.1** Proveedores externos solo activos si iOS confirma que se abrieron | Programado; falta con Waze y Google Maps instalados |
| **0.6** Proveedor de navegación: CFMoto Link, Mapas de Apple, Google Maps, Waze | Verificado en pruebas (enlaces oficiales) y simulador; **falta abrir Waze y Google Maps en tu iPhone** |
| **0.6** Destino conservado al cambiar de proveedor (y recálculo al volver a CFMoto Link) | Programado; falta en uso real |
| **0.6** Tarjeta "Guía en Waze / Google Maps / Mapas de Apple" con flecha y distancia al destino | Verificado en pruebas (lámina) |
| **0.6** Día y noche automáticos por el sol; siempre claro; siempre oscuro | Verificado en pruebas (horas de Guatemala comparadas con una biblioteca astronómica); **falta verlo cambiar en la moto** |
| **0.6** Fundido al cambiar de estilo de mapa y al recalcular la ruta | Programado; falta verlo en la moto |
| **0.6** Colores de la portada en la tarjeta de música (contraste ≥ 4,5:1, transición de 0,3 s) | Verificado en pruebas (rojo, azul y portada clara, de día y de noche); falta con Spotify y Apple Music reales |
| **0.6** Rutas propuestas en la moto antes de empezar (la elegida en azul, las demás en gris) | Verificado en pruebas (lámina); falta en la moto |
| **0.6** Flecha blanca del próximo giro dibujada sobre la ruta | Verificado en pruebas |
| **0.6** Estilo de la ruta (normal, alto contraste, fina) y zoom automático sí/no | Verificado en pruebas |
| **0.6** Modos 1–5 (incluida Pantalla dividida) y los tres modos de la 0.4 | Verificado en pruebas; **falta la moto** |
| **0.6** Personalización del tablero (todo guardado al momento) | Verificado en pruebas (persistencia) y simulador |
| Ruta resaltada con borde, tramo recorrido atenuado, destino | Verificado en pruebas y simulador |
| Indicador de posición, brújula, vista 3D, norte arriba, zoom según velocidad y giros | Verificado en simulador; falta la moto |
| Tráfico en colores | Con iOS 17 o posterior, cuando Apple tiene datos de la zona (sobre las calles, no sobre la línea de la ruta) |
| Tarjetas flotantes semitransparentes (maniobra, música, viaje, avisos, reloj) | Verificado en pruebas (3000 combinaciones sin solapes) |
| Editor "Mi pantalla" | Verificado en pruebas (lógica) y simulador |
| Perfiles y persistencia; la configuración de la 0.4 y la 0.5 se conserva al actualizar | Verificado en pruebas |
| Cambios automáticos de modo | Verificado en pruebas; falta en ruta real |
| Apple Music (canción, artista, portada, progreso, controles en el iPhone) | Programado; **sin probar en un iPhone** |
| Spotify con su SDK oficial | Programado y compilado; tu app de Spotify ya está creada (Client ID); **falta verlo en la moto** |
| Avisos de navegación, conexión y batería | Programado; falta en uso real |
| Duplicar pantalla | Verificado en la moto (0.2) |

## Simuladas (y marcadas como tales)

- **Vista previa con datos de demostración** y miniaturas de los modos: llevan la etiqueta DEMO
  y una portada de ejemplo dibujada por la app (degradado rojo y negro). Esos datos nunca se
  envían a la moto.
- **Recorrido simulado** en Navegación: la app y la moto muestran SIMULACIÓN.
- **Aviso de prueba**: se titula "Aviso de prueba".
- **Mapa de prueba** de las pruebas automáticas: una cuadrícula dibujada por el programa de
  pruebas, solo para comprobar la proyección; no existe en la app.

## Limitadas por iOS o por el proveedor

| Función pedida | Qué pasa |
| --- | --- |
| Giros de Waze o Google Maps en la moto | **No es posible.** No comparten su ruta ni sus giros con otras apps. El SDK de Waze que los daba era solo para empresas de transporte y terminó el 1 de noviembre de 2026; el de Google es de pago con tu propia clave (ver `INTEGRATIONS.md`). La moto muestra mapa, posición y destino, y la tarjeta lo dice. |
| Ver la interfaz de Waze o Google Maps en la moto | Solo con Duplicar pantalla y el iPhone desbloqueado. |
| Mapa de calles con el iPhone bloqueado | Apple no entrega imágenes nuevas con la app en segundo plano. Se usan las guardadas de la ruta (toda la que quepa en la memoria). Fuera de la ruta guardada (desvío o recálculo con el iPhone bloqueado): dibujo simple de la ruta, con la etiqueta MAPA SIMPLE. Para mapa en vivo todo el viaje: Pantalla negra. Calles nuevas con el iPhone bloqueado solo serían posibles con un sistema completo sin Apple (ver `INTEGRATIONS.md`). |
| Recálculo con el iPhone bloqueado | Depende de que Apple responda en segundo plano; si no responde en 20 s se pide otra vez y la tarjeta dice a cuánto está la ruta. Se verá en el registro. |
| Cambio de día a noche con el iPhone bloqueado | Apple no entrega imágenes nuevas en segundo plano. Los tramos que se recorrerán de noche ya se guardan en oscuro (por la hora prevista de paso) y al anochecer se eligen esas. Si un tramo solo tiene imagen clara (por ejemplo, si el viaje se retrasa mucho), se usa la clara hasta abrir la app. Falta verlo en la moto. |
| Tráfico sobre la línea de la ruta | MapKit no da el tráfico por tramo de la ruta: se ve en las calles del mapa. |
| Spotify | Exige que la cuenta dueña de la app de desarrollo tenga Premium y limita a 5 usuarios. El permiso dura una hora. Spotify puede cortar la conexión en segundo plano o tras un rato en pausa. La app no trae ninguna credencial ni el logotipo oficial (la atribución es el nombre en texto). |
| Notificaciones de WhatsApp, Telegram, llamadas | **No es posible.** iOS no deja que una app lea las notificaciones de otras apps. |
| YouTube Music y otras apps de música | **No es posible** leer lo que suena en otra app; no ofrecen SDK. |
| Leer velocidad, marcha o combustible de la moto | No disponible en el protocolo conocido. La app no dibuja indicadores falsos; los de la moto siguen en su franja. |
| Controles en la TFT | La pantalla no es táctil para la app y el protocolo no envía botones: la música se controla desde el iPhone (o el intercomunicador). Desde la 0.6.4 la moto **muestra** los botones (solo dibujo). |
| Ampliar la imagen más allá de 800×400 | La resolución la pide la moto. |
| Nombre de la calle por la que vas | MapKit no lo da de forma continua; la tarjeta muestra la calle del próximo giro. |
| Idioma | Solo español. |

## No incluidas todavía

Varias paradas en una ruta, límites de velocidad, navegación en la pantalla de bloqueo del
iPhone, colores de tráfico sobre la propia ruta y el logotipo oficial de Spotify.
