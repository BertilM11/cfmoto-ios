# Limitaciones pendientes — CFMoto Link 0.6.4

Lo que la 0.6.4 no puede resolver (por iOS, Apple Maps o la moto) y lo que falta comprobar.

## 1. Mapa con el iPhone bloqueado

Informe completo, con fuentes: `MAPA_IPHONE_BLOQUEADO.md`.

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

**Alternativas:** esperar «Ruta completa guardada» antes de bloquear, o la **pantalla negra** (la
app sigue al frente con el brillo al mínimo y el mapa en vivo). Para tener calles nuevas con el
iPhone bloqueado haría falta un sistema propio con OpenStreetMap dibujado por la CPU (proyecto
aparte).

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
