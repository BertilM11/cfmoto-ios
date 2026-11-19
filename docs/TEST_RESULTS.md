# Resultados de las pruebas — MotoLink 0.7.1 (y anteriores)

Hay tres niveles y no se mezclan:

1. **Pruebas automáticas** (`Tools/DashboardCheck`, en macOS de GitHub Actions): el mismo
   código del panel, del mapa guardado y de los colores, sin iPhone ni moto.
2. **Simulador de iPhone** (GitHub Actions): la app completa con un recorrido simulado y mapas
   reales de Apple. No tiene moto, GPS real, Spotify ni bloqueo de pantalla de verdad.
3. **Moto** (manual, con la 450NK): ver «Prueba en la moto — 19 de noviembre de 2026» abajo. La 0.6.3,
   la 0.6.4 y la 0.6.5 no se probaron en la moto.
   Las fotos de la TFT que enviaste muestran el diseño de la 0.6.2 (Música + Avisos con ruta y
   Spotify) y otra pantalla con solo música.

## Prueba en la moto — 19 de noviembre de 2026 (mapa propio de OpenStreetMap)

Reporte de Bertil después de rodar con el mapa propio:

- El mapa **no desaparece** durante el recorrido.
- La guía **sigue al puntero** de la moto y **no se queda pegada**; va mejor que en versiones anteriores.

Sin reporte todavía de: Z1 (sin datos móviles), Z3 (recálculo al salirse), Z4 (ruta larga),
Z5 (cambio a Apple Maps) y Z6 (fluidez medida en Diagnóstico).

## 0.7 — Mapa propio de OpenStreetMap

### Resumen

| Nivel | Qué se probó | Resultado |
| --- | --- | --- |
| Automáticas | 246 pruebas: las 208 de la 0.6.5 y 38 del mapa propio (zona de prueba y mapa completo de Guatemala) | **Todas pasan** en un Mac con Apple M1 (prueba rápida 22), dentro de las pruebas en el simulador (40 y 41) y en la compilación que produjo el IPA (build-17) |
| Simulador | Compilación optimizada (como en el iPhone), recorridos con el mapa propio y con Apple Maps, búsqueda sin internet y segundo plano (pruebas 40 y 41, la 41 con el código de la entrega) | `BUILD SUCCEEDED`; capturas de la 41 en `CAPTURAS/2_SIMULADOR_IPHONE` |
| Moto | — | **Sin probar** (pruebas Z1 a Z6 de `TESTING.md`) |

### Mapa propio en la moto (Mac con Apple M1, mediana)

| Medida | Resultado |
| --- | --- |
| Fotograma completo con el mapa propio y las tarjetas | 10,3 ms (límite 25 ms; la moto recibe 10 por segundo) |
| Fondo, parques y calles | 3,5 ms desde la imagen guardada (7,5 ms dibujándolo cada vez) |
| Nombres de calles | 0,5 ms como imágenes (3,7 ms letra a letra) |
| Día y noche | Claridad media 0,93 de día y 0,14 de noche: el tema siempre coincide |
| Sin el archivo del mapa | Se usa el mapa simple, sin errores |
| Nombres sobre tarjetas | Ninguno: cada nombre se comprueba a lo largo de toda su línea |

### Rutas calculadas en el teléfono (mapa completo)

| Ruta | Resultado |
| --- | --- |
| Avenida Reforma → 11 Calle (zona 10) | 1,7 km, 3 rutas en 27 ms; indicaciones con nombre de calle; la vuelta respeta los sentidos |
| Zona 10 → Antigua Guatemala | 35,4 km, 40 min, en 0,12 s |
| Zona 10 → Quetzaltenango | 199,3 km, 3 h 7 min, en 0,50 s, por la Carretera Panamericana |
| Zona 10 → Flores (Petén) | 485,9 km, 7 h 35 min, entre 1,5 y 4,4 s según la prueba, por la Ruta al Atlántico y la CA-13 (grafo amplio) |
| Maniobras en su cruce (ruta de 200 km) | 10 maniobras, error máximo 0,0 m (sin el ajuste serían 73 m) |
| Recálculo en marcha (desvío de 120 m camino a Antigua) | 0,09 s |

### Búsqueda sin internet (mapa completo)

- Índice de 48 471 lugares en 0,3 s; cada búsqueda unos 5 ms.
- Pasan las 15 búsquedas de referencia: «antigua» → Antigua Guatemala (Ciudad · Sacatepéquez);
  «zona 10» → Zona 10 · Ciudad de Guatemala; «14 calle zona 10»; «oakland»; «quetzaltenango»;
  «cayala» (sin tilde); «6 avenida» = 6a Avenida; «aeropuerto» y «la aurora» → Aeropuerto
  Internacional La Aurora; «gasolinera» → Texaco de la zona 10 (por tipo y cercanía); «farmacia»;
  «mixco»; «14» mientras se escribe; «zona 1» no da la 10 ni la 14; «xela» → Quetzaltenango.

### En el simulador (prueba 40, compilación optimizada)

- **Mapa propio**: ruta al aeropuerto La Aurora calculada en el iPhone en 0,18 a 0,24 s (8,1 km y
  dos alternativas), con indicaciones como «Gira ligeramente a la derecha por 6a Avenida». En el
  iPhone, «Mapa de Guatemala en el iPhone · sin internet». La moto mostró el mapa propio de día y
  de noche en los cinco modos.
- **Búsqueda**: el índice se armó en 0,6 a 0,8 s; «Oakland» dio seis resultados con su zona y
  municipio y el pie «Sin internet, en el mapa de Guatemala · © colaboradores de OpenStreetMap».
- **Segundo plano**: con otra app al frente, la moto siguió recibiendo el mapa propio y la ruta
  avanzando (6,0 → 5,3 → 5,0 km), sin imágenes de Apple.
- **Apple Maps**: elegido en los ajustes, la ruta se calculó con Apple y el guardado funcionó como
  en la 0.6.5 («Guardando el mapa: 2,5 km de 9,5 km»).

### Lo que no está comprobado

- Nada de la 0.7 se ha visto todavía en la moto ni en tu iPhone. Los tiempos del iPhone pueden
  ser distintos de los del Mac: Más > Diagnóstico > «Dibujo del panel» los muestra.

## 0.6.5 — Mapa guardado y tema

### Resumen

| Nivel | Qué se probó | Resultado |
| --- | --- | --- |
| Automáticas | 208 pruebas: las 200 de la 0.6.4 y 8 nuevas del guardado del mapa (huecos, curvas, pausa) | **Todas pasan** en un Mac con Apple M1 (prueba rápida 14). En la máquina Intel del simulador (prueba 37) pasan 207: la de «Música completa en plena transición» tardó 37,1 ms (en el M1, 17 ms) |
| Límite de tiempo | Desde esta versión, en las máquinas Intel de GitHub (unas dos veces más lentas) el límite por fotograma es 40 ms en vez de 25 ms, y la prueba lo dice | Cambio solo de las pruebas: el dibujo no cambió |
| Simulador | Compilación, recorrido de demostración en los modos, día y noche, y prueba en segundo plano (prueba 37) | `BUILD SUCCEEDED`; capturas en `CAPTURAS/4_SIMULADOR_IPHONE` |
| Moto | — | **Sin probar** (pruebas X e Y de `TESTING.md`) |

### Lo nuevo, en el simulador (prueba 37)

- Ruta de demostración de 8,8 km al aeropuerto La Aurora. Con la app al frente, el guardado pidió
  **dos imágenes extra para huecos** (a 3,3 km y a 5,9 km) y llegó a **«Ruta completa guardada:
  6,2 km»** 2 min 19 s después de calcular la ruta: no se quedó parado.
- En segundo plano la moto siguió con las imágenes guardadas (24 imágenes, 2,0 MB; mapa seguido
  para unos 3 km de los que quedaban) y al volver al frente siguió igual.
- Apple no falló ninguna imagen en esta prueba, así que la pausa tras fallos (2, 4, 8… hasta 60 s)
  y el aviso «Apple no entregó la última imagen… Reintento en N s» no se vieron aquí; los cubren
  las pruebas automáticas.
- **Tema**: el arreglo (el tablero usa el tema de la imagen de mapa que muestra) está en el código
  del estado del tablero, que las pruebas automáticas no ejecutan, y en el simulador no se dio el
  caso de una imagen del otro tema. Se comprueba en la moto con la prueba Y.

### Lo que no está confirmado

- La causa de que el guardado se quedara en «10,0 km de 21 km» en tu ruta. La sospecha de las
  curvas cerradas se probó y no era. Si vuelve a pasar: Más > Diagnóstico > Exportar informe.

## 0.6.4 — Acabado premium del reproductor

### Resumen

| Nivel | Qué se probó | Resultado |
| --- | --- | --- |
| Automáticas | 200 pruebas: las 193 de la 0.6.3 y 7 nuevas de los botones, más las del reproductor ampliadas | **Todas pasan** (pruebas rápidas 10 y 11 y prueba 34 del simulador; se repiten en la compilación que produce el IPA) |
| Rendimiento | La 0.6.3 y la 0.6.4 en la **misma máquina** (Apple M1 de GitHub), mediana de 3 pasadas | Iguales: diferencias de ±1 ms, todo por debajo de 12 ms (tabla abajo) |
| Simulador | Compilación de la app, recorrido de demostración en los modos, día y noche, y prueba en segundo plano (prueba 34) | `BUILD SUCCEEDED`; capturas en `CAPTURAS/4_SIMULADOR_IPHONE` |
| Moto | — | **Sin probar** (pruebas U, V y W de `TESTING.md`) |

### Pruebas nuevas de los botones

| Prueba | Resultado |
| --- | --- |
| Anterior, reproducir/pausar y siguiente en todos los modos con música, dentro de su sitio y sin tocar textos ni la hora | Pasa: 10 sitios, día y noche, sonando y en pausa |
| Círculo central proporcional a cada sitio y laterales menores, alineados | Pasa: 62 px (Música completa, con y sin ruta), 44 (Dividida, Música + Avisos), 40 (Música + Avisos con ruta), 26 (tarjeta grande y zona lateral), 22 (Nav + Música, Completo, Personalizado) |
| El círculo muestra el estado real | Pasa: ❚❚ sonando, ▶ en pausa |
| Iconos con contraste sobre su fondo (≥ 3:1, día y noche) | Pasa: el peor, 4,9:1 (Nav + Música de día, en pausa) |
| Sin música, botones apagados | Pasa (con ▶) |
| El cambio ▶/❚❚ se funde | Pasa: centro del círculo 1,00 sonando, 0,25 a mitad, 0,01 en pausa |
| Las tarjetas de música miden lo mismo que en la 0.6.3 | Pasa: 250×84 y 300×124 |
| Portada que no es cuadrada | Pasa: se ve entera, sin estirarse |
| Ningún texto cortado, montado ni encima de la hora | Pasa: 68 composiciones (todos los modos, día y noche, con y sin ruta) |
| Portada proporcional al espacio | Pasa: Música completa 274 px (209 con el giro abajo), Dividida 162, Música + Avisos 155 (181 con ruta), tarjetas 64 y 100 |
| Título y artista legibles sobre el fondo de la portada (≥ 4,5:1) | Pasa: el peor, 8,3:1 |

### Rendimiento: 0.6.3 frente a 0.6.4 en la misma máquina

Milisegundos por fotograma (la moto pide uno cada 100 ms; el límite de las pruebas es 25 ms).

| Medida | 0.6.3 | 0.6.4 |
| --- | --- | --- |
| Música completa en plena transición de canción | 17,0 | 17,3 |
| Música completa sin transición | 10,1 | 9,8 |
| 1 · Navegación completa | 5,4 | 5,2 |
| 2 · Navegación + música compacta | 6,9 | 6,2 |
| 3 · Pantalla dividida | 11,6 | 10,6 |
| 4 · Música completa | 8,2 | 8,3 |
| 5 · Personalizado | 6,8 | 6,9 |
| Panel completo | 6,9 | 6,8 |
| Navegación + Avisos | 5,7 | 4,5 |
| Música + Avisos | 8,9 | 8,8 |

### Simulador (prueba 34)

- La app compila y recorre los modos de día y de noche con mapas reales de Apple.
- **Mapa guardado** (el código del mapa es el de la 0.6.3: ningún archivo del mapa cambió). Apple
  devolvió esta vez una ruta de 8,8 km con 8 giros (en la prueba 33, 8,2 km con 10 giros). Con la
  app al frente, en 73 s se guardaron 41 imágenes (0,56 por segundo; en la prueba 33, 0,55) y el
  mapa seguido llegaba a 3,3 de los 6,6 km que quedaban. En segundo plano la moto usó las imágenes
  guardadas y los km bajaron sin saltos (3,1 → 2,7 km).
- Lo que no prueba: el simulador no tiene moto (ritmo de envío 0), ni GPS real, ni bloquea la
  pantalla.

## 0.6.3 — Rediseño premium y correcciones

| Nivel | Qué se hizo | Resultado |
| --- | --- | --- |
| Automáticas | 193 pruebas: las 152 de la 0.6.2 (se conservan todas) y 41 nuevas | **193 pruebas, todas pasan** (prueba rápida 6; se repite al compilar la versión) |
| Compilación para el simulador | Xcode en GitHub (macOS arm64) | **BUILD SUCCEEDED** |
| Simulador | Recorrido de demostración en los modos, de día y de noche, y prueba en segundo plano (prueba 33) | Capturas en `CAPTURAS/4_SIMULADOR_IPHONE`. Ruta de Apple de 8,2 km; mapa guardado: 5,5 de los 6,0 km que quedaban en 68 s (37 imágenes); en segundo plano la moto usó las guardadas y los km bajaron sin saltos (5,6 → 5,1); al volver, «Ruta completa guardada» |
| Compilación para iPhone | Release sin firmar (`CFMotoLink.ipa`) | Ver la publicación de la versión |
| Moto | Ver el diseño nuevo en la TFT y el mapa con el iPhone bloqueado | **Pendiente** (pruebas L–T de `TESTING.md`) |

Pruebas nuevas de la 0.6.3 (resultado tal como lo escribió la prueba):

| Prueba | Resultado | Detalle |
| --- | --- | --- |
| Cobertura estable: al avanzar, el final del mapa guardado no salta | Pasa | el final se mueve 0 m en 31 posiciones (antes saltaba según el instante) |
| Música: el mismo reproductor en cada modo, con la forma que cabe | Pasa | Música sola: stage, Dividida: column, Música + Avisos: column, Música + Avisos con ruta: row, Nav + Música: row, Completo: row, Tarjeta grande: row, Principal + 2 (zona lateral): row |
| Música: portada, textos y barra dentro de su sitio, sin montarse ni tapar la hora | Pasa |  |
| Música: portada proporcional al espacio (Dividida al menos 167 px como en la 0.6.2) | Pasa | Dividida 174 px, Música + Avisos 163 (con ruta 181), tarjeta compacta 64, grande 100 |
| Música: en todas las formas el fondo es el degradado con los colores de la portada | Pasa | 7 formas, 3 portadas, día y noche |
| Música: de noche se ve el resplandor de la portada en todas las formas | Pasa |  |
| Música: título y artista legibles en todas las formas (contraste ≥ 4,5) | Pasa | peor 7.6:1 (Dividida light neón «Reproduciendo») |
| Música: álbum y tiempos legibles (contraste ≥ 3) | Pasa | peor 3.9:1 |
| Música: el estado (Reproduciendo / En pausa) está en la música completa y en la columna | Pasa |  |
| Música en pausa: «En pausa» en la columna y sin texto cortado en la tarjeta | Pasa |  |
| Ningún texto cortado, montado ni encima de la hora (todos los modos, día y noche, con y sin ruta) | Pasa | 68 composiciones |
| Con datos normales ningún texto necesita «…» | Pasa |  |
| Títulos y artistas largos: se acortan con «…» sin salirse de su sitio | Pasa |  |
| Sin música: el mismo aviso en todas las formas, sin cortes | Pasa |  |
| A 640×320 tampoco hay textos cortados ni montados | Pasa |  |
| La vista previa del iPhone y la imagen de la moto salen del mismo dibujo (idénticas) | Pasa | diferencia máxima 0 |
| Dividida: la tarjeta de la maniobra es la misma que en el mapa completo (200×96; antes 426×155) | Pasa | 200×96 |
| Dividida: se ve más mapa (al menos el 80 % de la zona libre de tarjetas) | Pasa | mapa libre: 82 % (antes 53 %) |
| Dividida: si se elige la tarjeta grande, es más grande pero proporcional a la zona | Pasa | 318×151 |
| Dividida: la maniobra va donde se eligió en el iPhone, sin tapar la hora, el viaje, la brújula ni la ruta por delante | Pasa | 20 combinaciones |
| Nav + Música, Completo y Nav + Avisos usan la misma maniobra compacta que Navegación (200×96) | Pasa | mapa libre: 1 · Navegación completa 87 %, 2 · Navegación + música compacta 81 %, Panel completo 76 %, Navegación + Avisos 82 % |
| Cobertura: ruta completa, guardando y parcial (por memoria) se distinguen | Pasa | Ruta completa guardada: 12 km \| Guardando el mapa: 3.2 km de 12 km \| Mapa parcial: 141 km de 160 km (límite de memoria) |
| Cobertura: se informan los kilómetros que de verdad tienen mapa seguido | Pasa |  |
| Moto: aviso «MAPA GUARDADO» solo con el mapa guardado en uso y menos de 2 km | Pasa | MAPA GUARDADO: 1.4 KM |
| Moto: el aviso se dibuja sin tapar nada (mapa completo y pantalla dividida) | Pasa |  |
| Precarga antes de salir: con 3 imágenes a la vez se guarda más ruta en el mismo tiempo | Pasa | en 40 s (2 s por imagen): 10.4 km; antes 6.9 km |
| Ruta de 15 km: «Ruta completa guardada» en poco más de un minuto con el iPhone desbloqueado | Pasa | Ruta completa guardada: 15 km (82 imágenes) |
| Con 800 imágenes cabe una ruta de 120 km entera (antes, unos 70 km) | Pasa | 71 km → 120 km |
| Memoria del mapa guardado: hasta 96 MB y nunca más de la quinta parte de la libre | Pasa |  |
| Dividida: «Llegada», hora de llegada, tiempo y distancia por separado, y la hora actual arriba | Pasa |  |
| Rediseño: tarjetas y zonas en el mismo sitio y del mismo tamaño que en la 0.6.2 (y la hora fija) | Pasa | 9 tarjetas y 5 zonas |
| Rediseño: maniobra, viaje, avisos, hora y zonas usan el mismo vidrio con borde luminoso | Pasa | 6 tarjetas |
| Rediseño: las tarjetas guardadas ya dibujadas se ven igual que dibujadas cada vez | Pasa | diferencia máxima 3 de 255 (caso 3, x 786, y 56, canal 1: 75 / 78) |
| Rediseño: datos del viaje en tres bloques (Distancia, Restante, Llegada), cada cifra sobre su nombre | Pasa | 267 < 400 < 533 |
| Rediseño: la hora actual (con su reloj, arriba) y la de llegada (con «Llegada», abajo) no se confunden | Pasa | arriba: 7:04 p.m.; llegada: 7:22 |
| Rediseño: cada aviso con su remitente, título, mensaje y hora | Pasa |  |
| Rediseño: sin avisos se ve un estado vacío centrado, no la zona en blanco | Pasa |  |
| Rediseño: la ruta lleva un resplandor azul a los lados (más contraste sobre el mapa) | Pasa | 0.13,0.24,0.38 \| 0.23,0.36,0.53 |
| Rediseño: la posición se marca con la flecha azul en su disco de vidrio | Pasa | flecha 302 px, disco 630 px |
| Rediseño: ningún modo tarda más de 25 ms por fotograma (la moto recibe 10 por segundo) | Pasa | 1 · Navegación completa 3.7, 2 · Navegación + música compacta 3.8, 3 · Pantalla dividida 9.1, 4 · Música completa 7.0, 5 · Personalizado 5.9, Panel completo 4.9, Navegación + Avisos 3.7, Música + Avisos 6.8 ms |
| Las formas nuevas del reproductor se dibujan en menos de 25 ms por fotograma | Pasa | Dividida 7.0 ms, Nav + Música en transición 4.4 ms, Música + Avisos 6.4 ms |

Lo que no se probó: la TFT real (contraste al sol y de noche, tamaño de letra), Spotify y Apple
Music reales con el diseño nuevo, el tiempo real de guardado de una ruta en tu iPhone y que la
TFT siga recibiendo imagen con el iPhone bloqueado (prueba Q).

---

## 0.6.2 — Diseño de la pantalla

| Nivel | Qué se hizo | Resultado |
| --- | --- | --- |
| Automáticas | 152 pruebas: las 132 de la 0.6.1 (se conservan todas) y 20 nuevas | **Todas pasan** (prueba 29) |
| Compilación para el simulador | Xcode en GitHub (macOS arm64) | **BUILD SUCCEEDED** |
| Simulador | Recorrido de demostración en los modos 1 a 4, de día y de noche, y prueba en segundo plano | Capturas de la app con mapas reales de Apple |
| Compilación para iPhone | Release sin firmar (`CFMotoLink.ipa`) | Ver la publicación de la versión |
| Moto | Ver el diseño nuevo en la TFT | **Pendiente** |

Pruebas nuevas de la 0.6.2:

| Prueba | Resultado | Detalle |
| --- | --- | --- |
| Hora actual: el mismo sitio en los modos con mapa y nada encima | Pasa | arriba a la derecha: x 672, y 12, 116×30 |
| La hora se ve en el mismo sitio en todos los modos, de día y de noche, con y sin ruta | Pasa | 32 composiciones |
| La llegada lleva la palabra «Llegada»; el tiempo y la distancia van aparte | Pasa | Llegada 7:22 p.m. \| 18 min \| 7.4 km |
| La hora de llegada y la hora actual son cosas distintas | Pasa | 7:22 y 7:04 |
| Sin ruta, abajo no aparece otra hora | Pasa | imagen idéntica a la que no tiene barra de viaje |
| Maniobra compacta un 30 % más pequeña por lado | Pasa | 200×96, 50 % del área de antes (284×136) |
| La tarjeta grande de la maniobra sigue igual | Pasa | 340×176 |
| Mapa + Música: el centro (por donde va la ruta) queda libre de tarjetas | Pasa | maniobra hasta x 212, música desde x 538 |
| La tarjeta de música no crece | Pasa | 250×84 |
| La calle se saca de la indicación | Pasa | 8 indicaciones, incluidas dos sin calle |
| Música completa: partes sin montarse ni tapar la hora | Pasa | tres tamaños de portada, con y sin ruta |
| Música completa: portada grande | Pasa | 274 px; con el próximo giro abajo, 209 px |
| Música completa: columna de texto ancha y barra casi a todo el ancho | Pasa | columna de 432 px, barra de 736 px |
| Música completa: texto legible sobre el degradado | Pasa | peor contraste 10,3:1 (mínimo 4,5) |
| Cambio de canción: fundido corto | Pasa | 0,45 s |
| Portada que llega tarde (Spotify): solo se funde la portada | Pasa | |
| Misma canción avanzando: sin transición | Pasa | |
| Fondo guardado entre fotogramas igual que dibujado cada vez | Pasa | diferencia máxima 3 de 255 |
| Música completa en plena transición | Pasa | 9,9 ms por fotograma (equipo de GitHub) |
| Música completa sin transición (fondo reutilizado) | Pasa | 4,5 ms por fotograma (equipo de GitHub) |

Capturas: `docs/laminas/cambio1-…`, `cambio2-…` y `cambio3-…` en el paquete y la carpeta
`CAPTURAS` de la entrega (con el antes y el después).

Lo que no se probó: la TFT real (tamaño de letra, contraste al sol, la hora en la esquina),
Spotify y Apple Music reales con el diseño nuevo y el fundido en un iPhone.

---

# 0.6.1 — Estabilidad y navegación

## Resumen

| Nivel | Qué se hizo | Resultado |
| --- | --- | --- |
| Automáticas | 132 pruebas: las 105 de la 0.6.0 (se conservan todas) y 27 nuevas | **Todas pasan** |
| Compilación para el simulador | Xcode en GitHub (macOS arm64) | **BUILD SUCCEEDED** |
| Simulador: recorrido | 6 recorridos de demostración (día y noche, modos 1–5, Personalización) | Capturas generadas |
| Simulador: segundo plano | Ruta simulada, otra app al frente 50 s y vuelta | Ver abajo (antes y después de la corrección) |
| Compilación para iPhone | Release sin firmar (`CFMotoLink.ipa`) | Ver la publicación de la versión |
| Moto | Pruebas A–K de `TESTING.md` | **Pendientes** |

## 1. Pruebas automáticas

Lista completa con el detalle de cada una en `docs/RESULTADOS.txt` dentro del paquete (la
genera la compilación de la versión). Las de la 0.6.1:

| Prueba | Resultado | Detalle |
| --- | --- | --- |
| Ruta de prueba medida bien (15 km) | Pasa | 15 000 m |
| Se detectan los dos giros de la ruta | Pasa | 5990 m y 9990 m |
| Situar un punto en la ruta (a lo largo y de lado) | Pasa | 7300 m / 30 m |
| Ruta de 15 km guardada entera, sin huecos | Pasa | 15 km seguidos, 87 imágenes, 0 huecos |
| Las curvas tienen su imagen orientada a la calle nueva | Pasa | |
| No se vuelve a pedir lo que ya está guardado | Pasa | 0 repetidas |
| Lo ya pedido no se pide dos veces; primero lo más cercano | Pasa | |
| Memoria del mapa guardado acotada | Pasa | 15 km en 7,5 MB |
| Con memoria para 20 imágenes se guarda el tramo más cercano | Pasa | 20 imágenes |
| Lo recorrido y lo más lejano se sueltan con poca memoria | Pasa | |
| Se detecta un tramo sin imagen | Pasa | 4,1 km seguidos, 1 hueco |
| Al recalcular se conserva el tramo común | Pasa | 34 de 87 |
| Tras recalcular solo se pide el tramo nuevo | Pasa | 30 nuevas |
| Recalculando desde la posición actual no se vuelve a pedir lo que ya se tiene | Pasa | 75 conservadas, 0 pedidas de nuevo |
| Decidir qué pedir tarda poco | Pasa | 0,3 ms |
| Avanzando, cada imagen nueva amplía el mapa (60 s como el simulador) | Pasa | 4,1 km seguidos con 28 peticiones, 0 repetidas |
| Avanzando 4 minutos se guarda toda la ruta que queda | Pasa | 12,1 de 12,1 km, 83 peticiones, 0 repetidas |
| La separación no cambia por pequeñas variaciones de calibración | Pasa | |
| iPhone bloqueado: se usa una imagen guardada | Pasa | |
| Lo que se recorrerá de noche se guarda en oscuro | Pasa | |
| Con las dos versiones guardadas gana el tema correcto | Pasa | |
| Si solo hay del otro tema se usa y se marca | Pasa | |
| Sin imagen que sirva: mapa simple, sin inventar calles | Pasa | |
| La imagen en vivo reciente manda; una vieja solo como último recurso | Pasa | |
| Portadas de Spotify: solo vale la de la canción que suena | Pasa | |
| Revisar la cobertura de 15 km tarda poco | Pasa | 1,1 ms |
| Recta larga sin puntos intermedios: la ruta se ve por delante de la moto | Pasa | |
| Dibujar un fotograma con mapa y tarjetas | Pasa | 3,8 ms de media (equipo de GitHub, no el iPhone) |

Las pruebas usan imágenes de mapa de prueba con la misma geometría que pide la app; no
descargan mapas de Apple.

## 2. Simulador: la app en segundo plano

Con la ruta simulada en marcha (unos 9 km), la app al frente 60 s, otra app al frente 50 s
(CFMoto Link pasa a segundo plano, como con el iPhone bloqueado) y vuelta. El registro guarda
una línea `[DIAG]` cada 10 s.

| Con la ruta y la app al frente | Antes de la corrección (prueba 22) | Después (prueba 23) |
| --- | --- | --- |
| ~15 s | 0,4 km seguidos (7 imágenes) | 1,0 km (9 imágenes) |
| ~30 s | 0,4 km (13) | 2,1 km (15) |
| ~40 s | 0,5 km (18) | 2,9 km (19) |
| ~50 s | 0,7 km (22) | 3,3 km (23) |
| ~60 s | 0,8 km (25) | 4,2 km (26) |
| Al pasar a segundo plano | 0,8 de 6,7 km (24 imágenes) | 4,7 de 8,6 km (29 imágenes, 2,1 MB) |
| En segundo plano (50 s) | Imagen usada: guardada | Imagen usada: guardada |
| Al volver | 0,2 de 5,5 km (quedaban 4 imágenes) | 4,1 de 7,9 km (30 imágenes) |

Las dos pruebas usan rutas de Apple entre los mismos puntos, pero Apple devolvió rutas algo
distintas (8,8 km con 7 giros y 9,6 km con 9 giros).

Lo que muestra: con la app al frente, el mapa guardado ahora avanza por la ruta (antes se
repetía cerca de la posición); en segundo plano no llegan imágenes nuevas de Apple y se usan
las guardadas.

Lo que **no** muestra: el simulador no bloquea la pantalla ni aplica todas las reglas de un
iPhone real en segundo plano; no hay moto (ritmo de envío 0), ni GPS real (la posición la da el
recorrido simulado), ni datos móviles.

**Prueba 24** (con el tema, el avance y la cobertura al día en segundo plano): 5,0 km seguidos
al pasar a segundo plano (34 imágenes en 80 s, 2,3 MB); en segundo plano la cobertura se siguió
actualizando mientras avanzaba la ruta simulada (5,5 → 5,0 km) y se usó la imagen guardada; al
volver, 4,9 de 8,8 km. En su captura en segundo plano faltaba la línea de la ruta por delante de
la moto en una recta larga (error 9 del informe): corregido después.

**Prueba 25** (con esa corrección; es la del código que se publica): 132 pruebas automáticas,
todas pasan. Con la app al frente, 4,6 km seguidos al pasar a segundo plano (30 imágenes,
2,1 MB); en segundo plano, imagen guardada y cobertura al día (4,2 → 4,1 km); en la captura en
segundo plano la línea de la ruta ya se ve por delante de la moto en la avenida recta.

## 3. Lo que falta: pruebas en la moto

Ninguna de las pruebas A–K de `TESTING.md` está hecha. En particular, sin ellas **no se puede
afirmar** que:

- el mapa se vea sin huecos con el iPhone bloqueado durante 2, 5 o 10 minutos;
- la ubicación siga llegando en segundo plano en la moto (`fijos=…bg`);
- el vídeo mantenga ~10 fotogramas por segundo con el iPhone bloqueado;
- el recálculo con el iPhone bloqueado responda (depende de Apple);
- la reconexión sin límite funcione al apagar y encender la moto;
- el cambio de día a noche se vea bien en la TFT con el iPhone bloqueado;
- Spotify, Waze y Google Maps se comporten igual en un iPhone real.

Con cada prueba en la moto: **Más > Diagnóstico > Exportar informe** y una foto de la TFT.
