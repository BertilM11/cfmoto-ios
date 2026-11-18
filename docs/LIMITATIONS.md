# Limitaciones pendientes — CFMoto Link 0.7

Lo que la 0.7 no puede resolver (por iOS, los mapas o la moto) y lo que falta comprobar.

## 0. Mapa propio de OpenStreetMap (0.7)

Con el mapa propio no hay que guardar nada antes de bloquear: el mapa, la búsqueda, la ruta y el
recálculo funcionan sin internet y con el iPhone bloqueado. Lo que no hace:

- **Tráfico en vivo**: los tiempos son estimados por el tipo de calle.
- **Datos incompletos**: lo que falte o esté mal en OpenStreetMap para Guatemala (calles sin
  nombre, sentidos sin marcar, lugares que no están) falta o está mal en la app. Una dirección
  exacta («6a avenida 12-34») no se puede buscar: se busca la calle y la zona.
- **Giros**: la ruta no penaliza los giros; entre dos caminos de tiempo parecido puede elegir el de
  más cruces.
- **Ferris** (Sayaxché, por ejemplo) no entran en las rutas.
- **3D, carriles, límites de velocidad y señales**: no.
- **Solo Guatemala**, con la fecha de los datos de cuando se compiló la app.
- **Sin probar en la moto todavía** (ver `TESTING.md`, sección 8).

## 1. Mapa con el iPhone bloqueado (modo Apple Maps)

Informe completo, con fuentes: `MAPA_IPHONE_BLOQUEADO.md`. Desde la 0.7 esto solo afecta al modo
Apple Maps.

**Qué hace:** al elegir el destino guarda la ruta entera por delante (hasta 800 imágenes de Apple
Maps y 96 MB de memoria, unos 140 km con el zoom por defecto), tres imágenes a la vez, de cerca a
lejos y con el tema de día o de noche que tocará en cada tramo. En Navegación dice **«Ruta completa
guardada»**, **«Guardando el mapa: X de Y km»** o **«Mapa parcial: X de Y km (límite de
memoria)»**; en la moto, con el iPhone bloqueado y menos de 2 km guardados, **MAPA GUARDADO: X KM**.

**Lo que no se puede:**

- **Imágenes nuevas de Apple con el iPhone bloqueado.** `MKMapSnapshotter` solo entrega con la app
  en primer plano, y la tarjeta gráfica no se puede usar en segundo plano. La app no usa trucos
  para saltarse esas reglas.
- **Descargar mapas completos o zonas enteras de Apple**: lo prohíben sus condiciones (solo se
  permite guardar de forma temporal para que funcione mejor, y hay que borrarlo después).
- **Usar los mapas sin conexión de la app Mapas**: no hay forma para otras apps.
- **Desvíos con el iPhone bloqueado**: fuera de la ruta guardada, MAPA SIMPLE hasta desbloquear.

**Alternativas:** esperar «Ruta completa guardada» antes de bloquear, la **pantalla negra** (la
app sigue al frente con el brillo al mínimo y el mapa en vivo) o, desde la 0.7, el **mapa propio
de OpenStreetMap**, que dibuja la CPU y no necesita a Apple.

## 2. Diseño de la referencia que no se puede llevar a la moto

- **Pulsar los botones de reproducción en la TFT**: desde la 0.6.4 la moto **muestra** anterior,
  reproducir/pausar y siguiente, como en la referencia, pero son solo dibujo: la moto no envía
  toques ni teclas a la app y no se tocó el protocolo. La música se controla desde el iPhone
  (Más > Música), el intercomunicador o la app de música. El botón central sí muestra el estado
  real (❚❚ o ▶).
- **Aleatorio, repetir y botones del mapa** (+, −, capas): no se dibujan; tampoco funcionarían en
  la moto. El zoom es automático y se elige en el iPhone.
- **Avisos de WhatsApp u otras apps**: iOS no deja que una app lea las notificaciones de otras. La
  moto muestra los avisos de CFMoto Link (ruta, conexión con la moto, batería del iPhone).
- **Colores propios del mapa** (el azul de la referencia): MapKit solo ofrece sus estilos (claro,
  oscuro, apagado, híbrido, satélite).
- **Logotipo de Spotify**: no está en el proyecto el recurso oficial; se escribe el nombre del
  servicio con sus reglas de color.

## 3. Sin comprobar en la moto

Nada de la 0.6.3 se ha probado todavía en la 450NK. Pruebas en `TESTING.md` (A–K de la 0.6.1 y
L–T de la 0.6.3); con cada una, **Más > Diagnóstico > Exportar informe**. En particular:

- **Q:** con el iPhone bloqueado, que la TFT **siga recibiendo imagen** (no basta con que el GPS
  funcione): ritmo de envío cerca de 10 por segundo y última imagen de hace menos de 1 s.
- **T:** el diseño nuevo en la TFT al sol y de noche (la foto 09 muestra que la TFT aclara los
  azules oscuros).
- Cuánto tarda de verdad en guardar una ruta en tu iPhone (en las pruebas se supusieron 2 s por
  imagen) y la memoria que deja iOS.
- Batería y temperatura en un viaje largo (sobre todo con la pantalla negra).

## 4. Proveedores externos

- **Waze y Google Maps no envían su mapa ni sus giros a la moto.** Solo reciben el destino; la
  guía y la voz las dan ellas en el iPhone. La moto muestra el mapa de Apple, tu posición y el
  destino.
- El Navigation SDK de Google es de pago, con tu propio proyecto y clave, y sus términos no
  permiten llevar su mapa a otra pantalla. El SDK de Waze para socios ya no está disponible.

## 5. Spotify

- Necesita tu Client ID, la app de Spotify instalada y que la cuenta dueña tenga Premium.
- El permiso dura una hora y vive en memoria: después hay que volver a conectar.
- iOS puede cortar la conexión con Spotify en segundo plano; se reintenta dos veces y al abrir
  CFMoto Link.

## 6. Instalación y compilación

- El IPA va **sin firmar**: Sideloadly lo firma con tu Apple ID. Con una cuenta gratuita caduca a
  los 7 días y hay que reinstalarlo; Sideloadly necesita el iPhone conectado por cable al PC.
- Se compila en GitHub Actions (macOS con Xcode). Las pruebas del panel y del simulador se hacen
  allí, no en un Mac propio.
