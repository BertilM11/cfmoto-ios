# CFMoto Link 0.7 — Mapa propio de OpenStreetMap

La 0.7 añade un segundo mapa, propio, hecho con los datos de **OpenStreetMap** y guardado dentro
de la app. Con él, el mapa de la moto, la búsqueda, el cálculo de la ruta, las indicaciones y el
recálculo funcionan **en el iPhone, sin internet y con el iPhone bloqueado**. El modo Apple Maps
de la 0.6.5 sigue igual y se elige en **Personalizar > Mapa y navegación**.

No cambian la conexión Wi-Fi Direct, el vídeo H.264, el protocolo con la moto ni sus indicadores
(velocidad, RPM, marcha, combustible y testigos), la música, la distribución de los modos ni el
modo día/noche.

## 1. Por qué hace falta un mapa propio

- Apple solo entrega sus imágenes de mapa con la app al frente, y sus condiciones no permiten
  guardar mapas completos (ver `MAPA_IPHONE_BLOQUEADO.md`).
- Las condiciones de Apple Maps (anexo 6 del acuerdo de desarrolladores) solo permiten mostrar
  sus datos (rutas, indicaciones y resultados de búsqueda incluidos) sobre un mapa de Apple. Por
  eso, en el modo OpenStreetMap **todo** sale de OpenStreetMap: el mapa, la búsqueda, la ruta y
  las indicaciones. Una ruta de Apple nunca se dibuja sobre el mapa propio (si se cambia de mapa
  con una ruta en pantalla, se vuelve a calcular con el mapa nuevo y, mientras tanto, la moto usa
  el dibujo simple de la ruta).
- En el iPhone se sigue viendo el mapa de Apple (MapKit) con la ruta propia encima: mostrar datos
  propios sobre un mapa de Apple sí está permitido.

## 2. Los datos: `Guatemala.cfmap`

| | |
| --- | --- |
| Origen | Extracto de Guatemala de Geofabrik (`guatemala-latest.osm.pbf`, unos 131 MB) |
| Qué se guarda | Calles y carreteras (7 clases, sentido único, rotondas, enlaces, puentes y túneles), agua, ríos, parques y bosques, lugares con nombre (ciudades, pueblos, aldeas, zonas y colonias, gasolineras, hospitales, centros comerciales, supermercados, hoteles, aeropuertos…), otros nombres (`alt_name`, p. ej. «Xela»), departamentos y municipios |
| Formato | Propio (`Tools/OSM/build_cfmap.py`, versión 2): cuadros de 0,01° (unos 1,1 km) comprimidos uno por uno, puntos en millonésimas de grado, tabla de nombres y tabla de lugares con su municipio |
| Tamaño | Unos 25 MB (63 375 cuadros, 68 000 lugares, 338 departamentos y municipios) |
| Dónde se arma | En GitHub, con el flujo «Mapa de Guatemala (OpenStreetMap)» (`.github/workflows/mapa.yml`), que lo publica en la versión `mapa-guatemala` con su huella en el nombre (`Guatemala-<8 cifras>.cfmap`) y `FUENTE.txt` |
| Cómo entra en la app | Las compilaciones descargan el archivo cuya huella está en `Tools/OSM/Guatemala.cfmap.sha256`, comprueban el SHA-256 y lo copian a `App/Map/` antes de generar el proyecto |
| Actualizar el mapa | Ejecutar el flujo del mapa, copiar la huella nueva de `FUENTE.txt` a `Tools/OSM/Guatemala.cfmap.sha256` y compilar |

En el iPhone el archivo se abre «mapeado» en memoria (solo se lee lo que se usa) y cada cuadro se
descomprime cuando hace falta; se guardan los últimos 160 cuadros.

## 3. El mapa en la moto

- Se dibuja con la CPU (CoreGraphics), sin la tarjeta gráfica: funciona con el iPhone bloqueado.
- Colores, grosores y nombres como en el vídeo de muestra: calles con borde, más anchas según su
  clase; parques y agua; nombres de calles derechos y girados con la calle, sin taparse entre sí,
  sin ponerse encima de la ruta ni debajo de las tarjetas; «© OpenStreetMap» abajo a la izquierda.
- **Fondo guardado como imagen**: parques, agua y calles se dibujan una vez en una imagen con el
  norte arriba, más grande que la pantalla, que en cada fotograma solo se gira y se mueve. Se
  rehace en segundo plano antes de que la moto llegue a su borde o si cambia el zoom; si cambia el
  tema o se salta lejos, se rehace en el momento.
- **Nombres como imágenes**: cada nombre se dibuja una vez con su borde y luego solo se pega.
- Cuánto cuesta (Mac con Apple M1, mediana): 13 ms el fotograma completo con el mapa propio y las
  tarjetas; del mapa, 3,7 ms el fondo desde la imagen guardada (7,2 ms si se dibujara cada vez) y
  0,5 ms los nombres (4 ms letra a letra). La moto recibe 10 imágenes por segundo.
- 2D, con la ruta hacia arriba o el norte arriba (como esté elegido). La vista 3D es solo de
  Apple Maps.
- Día y noche según el tema elegido, siempre: no hay imágenes de otro tema que esperar.

## 4. La ruta, en el iPhone

- **Router propio** (`App/OSM/OSMRouter.swift`): búsqueda A* sobre las calles de los cuadros entre
  el origen y el destino, con el tiempo como coste (velocidad estimada por la clase de la calle:
  las de servicio y los caminos cuentan como lentos). Respeta los sentidos únicos. No penaliza los
  giros: entre dos caminos de tiempo parecido puede elegir el de más cruces.
- **Grafo normal**: una caja con hasta 25 km de margen alrededor del origen y el destino, con todas
  las calles a menos de 12 km de los extremos y, en medio, las terciarias o mayores.
- **Grafo amplio**: si en la caja no hay camino (la ruta da un rodeo: de la capital a Flores se va
  por Río Dulce) se prueba con casi todo el país y las carreteras principales en medio. Los
  recálculos hacia ese destino usan el grafo amplio directamente.
- **Rutas alternativas**: hasta dos más, que evitan en lo posible las calles de la principal.
- **Indicaciones en español** con el nombre de la calle: «Gira a la derecha por 12 Calle»,
  «Mantente a la izquierda hacia…», «En la rotonda, toma la 3.ª salida hacia…», «Has llegado a tu
  destino». Cada maniobra se sitúa en su cruce exacto de la ruta guiada.
- **Recálculo** al salirse de la ruta, también con el iPhone bloqueado, sin proponer dar la vuelta
  si se puede seguir de frente.
- El cálculo va en un hilo aparte: la interfaz y la moto no se detienen mientras tanto.

Tiempos medidos en el Mac con Apple M1 de las pruebas (ver `TEST_RESULTS.md`; en el iPhone
pueden ser algo distintos): 24 ms por la ciudad, 0,11 s a Antigua (35 km), 0,47 s a
Quetzaltenango (199 km), 1,5 s a Flores (486 km) y 0,08 s un recálculo en marcha.

## 5. La búsqueda sin internet

- Índice armado en el iPhone al abrir Navegación, en segundo plano (0,3 s en el Mac de las
  pruebas); cada búsqueda tarda unos 5 ms.
- Sin acentos ni mayúsculas, «6a Avenida» = «6 avenida», «z10» = «zona 10», abreviaturas (av,
  calz, blvd, col…) y otros nombres de OpenStreetMap («Xela» lleva a Quetzaltenango).
- Palabras de tipo de lugar: «gasolinera», «farmacia», «hospital», «hotel», «aeropuerto»… buscan
  por tipo y ordenan por cercanía, aunque el lugar se llame Texaco o Puma.
- Cada resultado dice qué es y dónde está: «Calle · Zona 10, Ciudad de Guatemala», «Ciudad ·
  Sacatepéquez» (zona, municipio y departamento de los límites de OpenStreetMap).
- Al pie de la lista: «Sin internet, en el mapa de Guatemala · © colaboradores de OpenStreetMap».
- En el modo OpenStreetMap no se usa el buscador de Apple (sus resultados no pueden ir sobre otro
  mapa). La pulsación larga en el mapa del iPhone sigue sirviendo para elegir un punto.

## 6. Licencias

- Datos: **© colaboradores de OpenStreetMap**, bajo la licencia **ODbL 1.0**. La app lo dice en el
  mapa de la moto, en la búsqueda y en Personalizar.
- `Guatemala.cfmap` es una base de datos derivada: se publica tal cual, con su origen y fecha, en
  la versión `mapa-guatemala` del repositorio, bajo la misma licencia ODbL, y el programa que la
  arma está en `Tools/OSM/`.
- El código de la app sigue bajo AGPL-3.0.

## 7. Lo que no hace

- **Tráfico en vivo**: los tiempos son estimados por el tipo de calle.
- **Calidad de los datos**: depende de lo que haya en OpenStreetMap para Guatemala (calles sin
  nombre, sentidos sin marcar o lugares que faltan). La app no inventa nada que no esté en los
  datos.
- **Carriles, límites de velocidad y señales**: no se usan.
- **Ferris**: no entran en las rutas (por ejemplo, el de Sayaxché).
- **Mapas de otros países**: solo Guatemala.
- **Actualizarse solo**: el mapa es el de la fecha en que se compiló la app; para uno más nuevo
  hay que volver a armarlo y compilar.

## 8. Archivos

| Archivo | Qué hace |
| --- | --- |
| `App/OSM/OSMMapData.swift` | Lee `Guatemala.cfmap` (cuadros, nombres y lugares) |
| `App/OSM/OSMRenderer.swift` | Dibuja el mapa de la moto, el fondo guardado como imagen y los nombres |
| `App/OSM/OSMRouter.swift` | Grafo, búsqueda de rutas e indicaciones en español |
| `App/OSM/OSMSearch.swift` | Búsqueda sin internet |
| `App/Nav/PlannedRoute.swift` | Una ruta de Apple o de OpenStreetMap, igual para la interfaz y la guía |
| `App/Nav/NavEngine.swift`, `GuidedRoute.swift`, `PlaceSearch.swift`, `NavScreen.swift`, `NavComponents.swift`, `NavMapView.swift`, `PocketScreen.swift` | La navegación con cualquiera de los dos mapas |
| `App/Dashboard/MapBase.swift`, `DashMapRenderer.swift`, `DashState.swift`, `Diagnostics.swift` | El mapa elegido, el dibujo en la moto y el diagnóstico |
| `App/UI/PersonalizationScreen.swift` | La elección del mapa |
| `Tools/OSM/build_cfmap.py`, `Tools/OSM/Guatemala.cfmap.sha256` | El conversor y la huella del mapa que entra en la app |
| `.github/workflows/mapa.yml` | Arma y publica el mapa |
