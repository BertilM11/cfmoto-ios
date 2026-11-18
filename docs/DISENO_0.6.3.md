# Diseño de la pantalla — CFMoto Link 0.6.3

Referencias: **01_REFERENCIA_DISENO_PREMIUM** (tablero con tarjetas de vidrio; referencia
principal), **10_REFERENCIA_REPRODUCTOR_OPCIONAL** (reproductor al estilo de CarPlay) y
**09_TABLERO_REAL** (foto de la TFT con la 0.6.2). Las capturas «antes» son las de la 0.6.2 en
*Mi pantalla* (02 a 08).

**Regla de la 0.6.3: el aspecto de la referencia sin tocar la estructura.** Ninguna tarjeta ni zona
cambia de sitio ni de tamaño respecto a la 0.6.2 (lo comprueba una prueba automática con las
medidas exactas). Lo único que cambia de tamaño es la tarjeta del giro dentro de las zonas con mapa
(pantalla Dividida y diseños por zonas), que se pidió compacta: es la misma tarjeta del mapa
completo, en la misma esquina (arriba a la izquierda).

Todo se dibuja con CoreGraphics en la CPU (como antes): así la imagen de la moto se sigue generando
con el iPhone bloqueado. La vista previa del iPhone es el mismo dibujo (prueba automática: imagen
idéntica).

## 1. Qué se tomó de la referencia y qué no

| En la referencia | En la 0.6.3 |
| --- | --- |
| Tarjetas de vidrio azul oscuro, borde luminoso, sombra y brillo | **Todas** las tarjetas y zonas: maniobra, viaje, música, avisos, hora, brújula, franja del giro, guía externa y zonas del panel |
| Mosaico azul con la flecha del giro | Maniobra compacta, grande, en zonas y en la franja; también los iconos de los avisos |
| «70 m» grande y la instrucción | Distancia grande con su unidad; la calle (tarjeta compacta) o la instrucción completa y «Luego» (tarjeta grande) |
| Bloques «15 km Distancia · 33 min Restante · 7:04 p. m. Llegada» | Igual, en ese orden, con cada cifra sobre su nombre: mapa completo, Dividida y zona «Viaje» |
| Reproductor: portada, título, artista, barra con punto | En **todos** los tamaños (música completa, columna, zonas, tarjeta compacta y grande) con los colores de la portada |
| Botones anterior / pausa / siguiente (y aleatorio / repetir) | **No.** La moto no envía a la app ni toques ni teclas, así que no funcionarían. Se muestra el estado («Reproduciendo» / «En pausa» o el símbolo en las tarjetas); la música se controla desde el iPhone o el intercomunicador |
| Aviso de WhatsApp | El mismo formato para los avisos de CFMoto Link (icono, remitente, título, mensaje y hora). iOS no deja que una app lea las notificaciones de otras apps |
| Ruta azul con resplandor, posición en un disco, destino rojo | Sí, en el mapa de Apple y en el mapa simple |
| Botones «+», «−» y capas en el mapa | **No** (no funcionarían en la TFT). El zoom es automático y se ajusta en el iPhone; la brújula sí está |
| Mapa azul oscuro con las calles en otro tono | El mapa es la imagen de Apple Maps tal cual: MapKit solo ofrece sus estilos (estándar, apagado, híbrido, satélite; claro u oscuro), no colores a medida, y la ruta de Apple solo puede ir sobre un mapa de Apple. El contraste se gana con la ruta, la marca de posición y el destino |
| Distribución (columna de tarjetas a la izquierda) | **No se copió**: se mantiene la distribución de cada modo |

## 2. Sistema visual

Una sola pieza, la **tarjeta de vidrio**, para todo:

| Parte | Noche | Día |
| --- | --- | --- |
| Cuerpo (degradado vertical) | `#182740` 93 % → `#0A1222` 94 % | `#FFFFFF` 95 % → `#EDF2F9` 95 % |
| Borde luminoso (1,25 px, más claro arriba) | `#7DB8FF` 80 % → `#3567C4` 36 % | blanco 95 % → `#8FA6CC` 55 % |
| Brillo interior junto al borde | 2 px, 28 % del borde | ídem |
| Halo exterior | azul `#3D8BFF` 17 % (dos trazos) | sin halo |
| Sombra | negra, desenfoque 9 px, 3 px hacia abajo | azul oscuro suave |
| Radio | 16 px maniobra, 14 px viaje/avisos/zonas, píldora en la hora | ídem |

- **Mosaicos de icono**: degradado vertical (maniobra `#52A3FF → #1A58DC`; recalculando ámbar;
  llegada verde; sin ruta gris), brillo de vidrio en la mitad de arriba y borde claro.
- **Texto**: cifras y títulos en negrita blanca (de día casi negra); nombres y mensajes en gris
  azulado; remitentes en versalitas pequeñas.
- **Ruta**: resplandor azul alrededor, borde azul, la línea y un brillo en el centro (efecto de
  tubo de luz). Con «Alto contraste» se mantiene el halo blanco/negro de antes.
- **Posición**: halo azul, disco de vidrio con borde claro y la flecha con degradado azul y borde
  blanco (igual en el mapa de Apple y en el simple).
- **Destino**: marcador rojo con punto blanco y su sombra en el suelo.
- **Etiquetas** (DEMO, SIMULACIÓN, MAPA SIMPLE, MAPA GUARDADO): píldora ámbar con degradado.
- **Rendimiento**: el fondo de cada tarjeta (sombra, degradado y bordes) se dibuja una vez por
  tamaño y se reutiliza; cada fotograma solo dibuja los textos y los datos. La prueba compara la
  imagen guardada con el dibujo directo (diferencia máxima 3 de 255).

## 3. Cada modo

| Modo | Qué cambia (las posiciones son las de la 0.6.2) |
| --- | --- |
| 1 · Navegación | Maniobra 200×96 arriba izquierda, viaje 400×46 abajo centro, hora 116×30 arriba derecha y brújula: todo con el vidrio nuevo; ruta con resplandor y posición nueva |
| 2 · Nav + Música | Además, la tarjeta de música 250×84 (debajo de la hora) con los colores de la portada, la sombra y el borde luminoso del sistema, punto en la barra |
| 3 · Dividida | Zona del mapa: maniobra 200×96 (antes 426×155) y bloques del viaje 300×44 abajo a la derecha. Zona de música: columna (portada, título, artista, estado, barra con tiempos) |
| 4 · Música completa | Diseño CarPlay de la 0.6.2 con el nombre del servicio y su punto de color, borde del panel, píldora del estado de vidrio y punto en la barra |
| Completo | Como Nav + Música, más el aviso 262×58 debajo de la música |
| Nav + Avisos | El aviso 262×58 debajo de la hora |
| Música + Avisos | Música en columna (o en fila si hay ruta y abajo va la franja del giro). Avisos con campana, contador, tarjetas con remitente, título, mensaje y hora; **sin avisos, un estado vacío centrado** (antes la zona se veía vacía, como en la foto 09) |
| 5 · Personalizado | Las mismas piezas en cualquier plantilla (mapa completo, 1 zona, 2 columnas, principal + 2) |

Tarjeta del giro:

- **Compacta (200×96)**: mosaico de 52 px con la flecha, distancia en grande (36 px), la maniobra
  siguiente en un chip y la calle debajo. Sin ruta: tarjeta baja con «Sin ruta» y el consejo en dos
  líneas.
- **Grande** (sobre el mapa 340×176; en las zonas, proporcional): mosaico de hasta 100 px, la
  distancia y la instrucción completa a su derecha (hasta tres líneas) y «Luego» con la maniobra
  siguiente debajo de la flecha, como en la referencia.

## 4. Textos

- Ninguno se corta por el borde ni se monta con otro (prueba en todos los modos, día y noche, con y
  sin ruta, a 800×400 y a 640×320).
- Si un título no cabe, primero se reduce un poco la letra; después, en la tarjeta compacta, pasa
  a dos líneas sin el artista. Solo si ni así cabe (títulos muy largos) termina en «…».
- La guía en otra app (Waze o Google Maps) pone el destino en dos líneas si hace falta.

## 5. La foto de la TFT (09)

En la foto, el azul muy oscuro del panel se ve bastante más claro que en el iPhone: la pantalla de
la moto realza los tonos oscuros. Por eso el vidrio nuevo es oscuro y los bordes y textos son
claros: el contraste no depende de ese azul. **Falta verlo en la moto** de día y de noche (prueba T
de `TESTING.md`).

## 6. Pruebas

Ver `TEST_RESULTS.md` (sección 0.6.3): posiciones iguales a la 0.6.2, mismo vidrio en todas las
tarjetas, bloques del viaje en orden, hora actual distinta de la llegada, avisos con remitente,
estado vacío, resplandor de la ruta, marca de posición, imagen guardada = dibujo directo, ningún
texto cortado y menos de 25 ms por fotograma en todos los modos.
