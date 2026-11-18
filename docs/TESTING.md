# Pruebas

Hay tres niveles. Solo el tercero prueba la moto de verdad.

## 1. Pruebas automáticas del panel (sin iPhone ni moto)

`Tools/DashboardCheck` compila en macOS el mismo modelo y el mismo dibujo de la app y comprueba:

- **Imagen completa**: por defecto se usa toda la imagen de 800×400; la parte vacía de abajo
  solo aparece si el usuario la pide, y entonces queda lisa.
- **Distribución por zonas**: 2000 diseños al azar (con valores inválidos) sin salirse ni solaparse.
- **Tarjetas sobre el mapa**: en cada modo y en 3000 combinaciones al azar de tarjetas, lugares,
  tamaños y escalas, ninguna se sale, ninguna se monta sobre otra, la maniobra siempre está y
  las tarjetas no tapan más de la mitad del mapa.
- **Modos 1–5** (con la Pantalla dividida: mapa a la izquierda, música a la derecha) y los
  tres modos de la 0.4.
- **Edición**: intercambiar zonas y tarjetas, mover, agrandar, ocultar, cambiar de plantilla.
- **Persistencia** y **actualización desde la 0.4 y la 0.5**: se conservan el modo, los avisos
  y los perfiles del usuario; los de fábrica pasan al mapa completo; el tema oscuro fijo de
  antes pasa a automático y el claro elegido se respeta.
- **Día y noche (0.6)**: amanecer y atardecer en Ciudad de Guatemala el 17 de noviembre de 2026
  (6:04 y 17:30, comprobados con la biblioteca *astral*); día a las 9:00, 12:00 y 16:30; noche a
  las 5:00, 18:30 y 23:00; sin posición, por la hora.
- **Colores de la portada (0.6)**: una portada roja y negra da tonos rojos; una azul, azules;
  con portadas rojas, azules y muy claras, de día y de noche y a tres intensidades, el texto
  siempre tiene contraste de al menos 4,5:1; los fondos fijos no dependen de la portada; la
  transición entre canciones mezcla los colores.
- **Proveedores (0.6)**: enlaces oficiales de Waze (`waze://ul` y `https://waze.com/ul`) y
  Google Maps (app y web); CFMoto Link no abre nada; ningún proveedor externo dice dar giros.
- **Mapa guardado para el iPhone bloqueado (0.6.1)**, con una ruta de prueba de 15 km y dos
  giros: se detectan los giros; la ruta queda guardada entera y sin huecos; cada curva tiene su
  imagen orientada a la calle nueva; nada se pide dos veces; con poca memoria se guarda lo más
  cercano; lo recorrido y lo lejano se sueltan; se detecta un tramo sin imagen; al recalcular se
  conserva el tramo común y solo se pide el nuevo; lo que se recorrerá de noche se guarda en
  oscuro; el tema correcto gana; sin imagen que sirva, mapa simple; la imagen en vivo reciente
  manda y una vieja solo como último recurso; tiempo de revisar la cobertura.
  Con la **moto avanzando** (como en la app: cada 0,25 s se mira qué falta, dos imágenes a la
  vez, imágenes que tardan 4,5 s o 2 s en llegar y una calibración que varía ±8 %): cada imagen
  nueva amplía el mapa por delante, no se repite ningún punto y en 4 minutos queda guardada
  toda la ruta. **Recálculo desde la posición actual** (la ruta nueva empieza donde está la
  moto, con otra rejilla): no se vuelve a pedir lo que ya se tiene. Tiempo de decidir qué pedir.
- **Spotify (0.6.1)**: una portada que llega tarde no se queda con otra canción.
- **Diseño de la 0.6.2**:
  - **Hora actual**: el mismo sitio (arriba a la derecha) en todos los modos con mapa y en las
    3000 combinaciones al azar, sin ninguna tarjeta encima; y se ve (píxeles del color del
    texto en ese sitio) en los 8 modos, de día y de noche, con y sin ruta (32 composiciones).
  - **Llegada**: la barra de viaje separa «Llegada» + hora de llegada, el tiempo restante y la
    distancia; la hora de llegada no es la hora actual; sin ruta, la barra no dibuja nada
    (la imagen es idéntica a la que no tiene barra).
  - **Maniobra compacta**: 200×96 (un 30 % menos por lado que 284×136); la grande no cambia; en
    Mapa + Música el centro (de 250 a 530 px de ancho) queda libre de tarjetas; la tarjeta de
    música sigue en 250×84; la calle se saca bien de 8 indicaciones de Apple (y no se inventa
    cuando no hay calle).
  - **Música completa**: portada, textos, barra y cabecera sin montarse ni tapar la hora, con
    los tres tamaños de portada y con el próximo giro abajo; portada de más del 60 % del alto;
    columna de texto ancha y barra casi a todo el ancho; texto legible (contraste ≥ 4,5:1)
    sobre el degradado con tres portadas, de día y de noche; fundido al cambiar de canción
    (menos de medio segundo), solo de la portada si llega tarde, y nada si es la misma
    canción; tiempo de dibujo en plena transición.
  - Capturas de los tres cambios (`cambio1-…`, `cambio2-…`, `cambio3-…`).
- **Reglas automáticas**.
- **Proyección del mapa**: la homografía de 4 puntos reproduce una perspectiva exacta; con una
  cámara de prueba girada, la ruta cae a menos de 1 píxel de donde debe.
- **Dibujo sobre un mapa de prueba**: cada modo, en oscuro y claro, con contenido también en
  el 20 % inferior; la línea azul de la ruta cae sobre su calle.
- **Estados sin datos**, mapa simple sin imagen de calles, modo Música con el próximo giro abajo,
  otra resolución (640×320).
- **Rendimiento**: tiempo medio de dibujo por fotograma con mapa y tarjetas.

Además guarda una lámina PNG de cada modo y, desde la 0.6: tarjeta con colores de la portada
de noche, pantalla dividida de día, guía en Waze, ruta de alto contraste y rutas propuestas.

```sh
swiftc -O Tools/DashboardCheck/main.swift App/HUD/HUDModel.swift App/HUD/HUDRenderer.swift \
       App/Dashboard/DashModel.swift App/Dashboard/DashRenderer.swift \
       App/Dashboard/MapBase.swift App/Dashboard/DashMapRenderer.swift \
       App/Dashboard/Appearance.swift App/Dashboard/MapCorridor.swift -o dashcheck
./dashcheck salida
```

El resultado de la última ejecución en GitHub Actions está en `docs/RESULTADOS.txt` dentro del
paquete.

## 2. Simulador de iPhone (sin moto)

GitHub Actions compila la app, la instala en un simulador de iPhone, lanza un recorrido
simulado por Ciudad de Guatemala con rutas reales de Apple y guarda capturas de las pantallas y
de la imagen que se enviaría a la moto en cada modo, **con el mapa de calles real de Apple**
(`tft-night-*.png`, `tft-light-*.png`).

Desde la 0.6.1 hay además una prueba con la app en **segundo plano**: con la ruta simulada en
marcha, se abre otra app 50 s y se vuelve; se guardan la imagen para la moto en cada momento
(`bg-1-al-frente.png`, `bg-2-segundo-plano.png`, `bg-3-de-vuelta.png`) y el registro
(`log-segundo-plano.txt`). El simulador no bloquea la pantalla ni aplica todas las reglas de
segundo plano de un iPhone real: sirve de indicio, no de prueba.

Esto **no** prueba: GPS real, sonido, música (el simulador no tiene app Música), permisos en un
iPhone real ni nada de la conexión con la moto.

## 3. Pruebas en la moto (manuales)

| Prueba | Resultado |
| --- | --- |
| 0.1: saludo y vídeo de prueba | Hecha por el propietario: funciona |
| 0.2: duplicar pantalla | Hecha: funciona |
| 0.3: navegación propia en la TFT | Hecha: funciona (foto) |
| 0.4: panel modular en la TFT | **Pendiente** |
| 0.4: cambiar de modo sin reconectar | **Pendiente** |
| 0.4: música de Apple Music en la TFT | **Pendiente** |
| 0.4: avisos en la TFT | **Pendiente** |
| 0.5: imagen completa, sin franja negra | Hecha: funciona (foto) |
| 0.5: mapa de calles en la TFT con la app abierta | Hecha: funciona (foto, sin ruta, estilo oscuro) |
| 0.6: mapa claro de día y oscuro de noche (automático) | **Pendiente** |
| 0.6: Waze / Google Maps abiertos con el destino; tarjeta "Guía en …" en la moto | **Pendiente** |
| 0.6: volver a CFMoto Link con el mismo destino (recálculo) | **Pendiente** |
| 0.6: colores de la portada con Spotify y Apple Music | **Pendiente** |
| 0.6: modos 1–5, incluida la Pantalla dividida | **Pendiente** |
| 0.6: voz de la guía por el intercomunicador con Spotify sonando | **Pendiente** |
| 0.5: mapa con el iPhone bloqueado (imágenes guardadas) | **Pendiente** |
| 0.5: Spotify en la TFT | **Pendiente** (necesita tu Client ID) |
| Vídeo con el iPhone bloqueado | **Pendiente** |
| Reconexión tras apagar y encender la moto | **Pendiente** |

### Cómo hacerlas

1. Conecta y envía el panel (Inicio). Foto de la TFT: ya no debe haber franja negra entre el
   panel y los indicadores de la moto.
2. Con datos móviles activos, elige un destino e inicia la ruta. Deja la app abierta unos
   segundos para que vea las calles y guarde las del recorrido.
3. Recorre los modos 1–5 desde Inicio y comprueba que la moto cambia sin reconectar.
4. Pon música (Apple Music, o Spotify si registraste tu app) y mira la tarjeta de música.
5. Más > Notificaciones > Enviar un aviso de prueba.
6. Bloquea el iPhone dos minutos con la ruta activa: deben seguir las calles mientras estés en
   la zona guardada.
7. Más > Conexión > Copiar registro, y fotos de la TFT de día y de noche.
8. (0.6) En la tarjeta de la ruta elige "Guiar con: Waze" y pulsa "Abrir en Waze": Waze debe
   abrir con el destino y la moto mostrar "Guía en Waze" con la bandera del destino. Vuelve a
   CFMoto Link y pulsa "Guiar aquí": la ruta se recalcula con el mismo destino.
9. (0.6) Con Spotify conectado, cambia de canción: la tarjeta de la moto cambia de color en
   menos de medio segundo. Prueba los fondos fijos en Más > Personalización del tablero.
10. (0.6) Con el tema en Automático, mira la moto antes y después del atardecer (17:30 en
    Guatemala en noviembre): el mapa pasa de claro a oscuro con un fundido.


## 4. Pruebas en la moto de la 0.6.1 (iPhone bloqueado)

Antes de cada prueba: ruta con CFMoto Link, moto conectada, datos móviles activos. Al terminar:
**Más > Diagnóstico > Exportar informe** (el registro guarda una línea `[DIAG]` cada 10 s con
posición, edad de la imagen, cobertura, imágenes guardadas, ritmo de envío, memoria, red y
temperatura).

| Prueba | Qué hacer | Qué mirar en la moto | Qué mirar en el informe |
| --- | --- | --- | --- |
| A | Ruta con el iPhone desbloqueado | Calles en vivo | `mapa=en vivo`, edad < 3 s |
| B | Esperar "Mapa guardado" en verde y bloquear 2 min | Calles sin huecos | `mapa=guardada`, `fijos=…bg` subiendo, `envio≈10fps` |
| C | Igual, 5 min | Igual | Cobertura que baja según avanzas |
| D | Igual, 10 min | Igual | Que no aparezca `ninguna: mapa simple` dentro de la ruta guardada |
| E | Desviarse por calles fuera de la ruta con el iPhone bloqueado | Mapa simple fuera de lo guardado (esperado) | `[RUTA] fuera de la ruta`, tiempo del recálculo |
| F | Bloquear antes de que termine de guardar | Calles hasta donde llegó; después, mapa simple | `cobertura=` al bloquear y cuándo se acaba |
| G | Bloquear con datos móviles activos | — | `[RED] … datos móviles` |
| H | Moto conectada y abrir una web en el iPhone | La moto sigue recibiendo | `[RED] con salida por datos móviles` |
| I | Desbloquear tras una interrupción | Calles en vivo en segundos | `[MAPA] la app vuelve al frente`, llegadas tardías descartadas |
| J | Ruta larga (> 20 km), bloquear y recorrerla | Calles todo lo guardado | Cobertura inicial, memoria (`mem=`) y temperatura (`temp=`) |
| K | Pantalla negra (botón de la luna) en vez de bloquear | Calles en vivo todo el viaje | `mapa=en vivo`, batería y temperatura |

Ninguna de estas pruebas está hecha todavía: dependen de la moto y del iPhone real.

## 5. Pruebas en la moto de la 0.6.3

Igual que antes: al terminar cada una, **Más > Diagnóstico > Exportar informe**.

| Prueba | Qué hacer | Qué mirar en la moto | Qué mirar en el informe |
| --- | --- | --- | --- |
| L | Modo 3 · Dividida con una ruta | Tarjeta del giro pequeña (como en el mapa completo) arriba a la izquierda; se ve el mapa por delante; los bloques «Distancia · Restante · Llegada» abajo a la derecha | — |
| M | En Personalización, «Tarjeta de maniobra: Grande» y «Lugar de la maniobra: Arriba der.» con la Dividida | La moto cambia al momento (pasa a modo 5) y nada tapa la hora | — |
| N | Música en Música sola, Nav + Música, Dividida, Completo y Música + Avisos (Spotify y Apple Music) | El mismo reproductor en todos: fondo con los colores de la portada, portada, título, artista, estado y barra; nada cortado; legible de día y de noche | — |
| O | Cambiar de canción varias veces con la ruta activa | Fundido corto, sin tirones en el mapa | `envio≈10fps` |
| P | Ruta de 15–30 km: cronometrar desde que eliges el destino hasta «Ruta completa guardada»; luego bloquear y recorrerla | Calles en toda la ruta, sin MAPA SIMPLE dentro de ella | `[MAPA] Ruta completa guardada`, `cobertura=` |
| Q | Moto encendida y el iPhone bloqueado 10 minutos (con y sin ruta) | **La TFT sigue recibiendo imagen** (la hora avanza cada minuto). Que el GPS siga no basta | `envio≈10fps` y edad del último fotograma < 1 s durante todo el bloqueo |
| R | Ruta muy larga (> 140 km) | En el iPhone, aviso naranja «Mapa parcial»; en la moto, al final de lo guardado, «MAPA GUARDADO: x KM» y después MAPA SIMPLE | `[MAPA] Mapa parcial…`, memoria (`mem=`) |
| S | Vista previa de Mi pantalla y Personalización frente a la moto | Lo mismo en el iPhone y en la TFT | — |
| T | Rediseño premium en la TFT, de día (al sol) y de noche, en los 8 modos | Tarjetas de vidrio legibles, bordes visibles sin deslumbrar, hora y «Llegada» claras; nada fuera de su sitio respecto a la 0.6.2 | Foto de la TFT en cada modo |

Ninguna de estas pruebas está hecha todavía: dependen de la moto y del iPhone real.
