# Limitaciones pendientes — CFMoto Link 0.6.1

Lo que la 0.6.1 no resuelve o no ha comprobado todavía, y qué haría falta.

## 1. Mapa con el iPhone bloqueado (prioridad crítica)

**Qué hace la 0.6.1:** con la app al frente fotografía la ruta por delante (toda la que quepa en
la memoria) y, con el iPhone bloqueado, la moto usa esas imágenes. En el simulador guardó unos
5 km en 80 s y en segundo plano usó lo guardado.

**Lo que no puede hacer:**

- **Imágenes nuevas de Apple con el iPhone bloqueado.** Apple solo entrega las imágenes de
  `MKMapSnapshotter` con la app en primer plano. No hay modo de segundo plano de iOS que lo
  cambie, y la app no usa trucos para saltarse esa regla.
- **Calles fuera de la ruta guardada.** Si te desvías, o la ruta se recalcula con el iPhone
  bloqueado, fuera de lo guardado la moto muestra el dibujo simple de la ruta (MAPA SIMPLE)
  hasta que desbloquees.
- **Guardar más que la ruta del viaje.** Descargar zonas enteras sería una descarga masiva, que
  los términos de Apple Maps prohíben.

**Cuánto se guarda:** hasta 400 imágenes, con 16–64 MB según la memoria libre del iPhone. Con
el tamaño de imagen del simulador (unos 70 KB) eso da del orden de 40–70 km de ruta con el
zoom por defecto. **No está medido en tu iPhone.** El aviso "Mapa guardado: X de Y km" dice lo
que hay en cada momento.

**Alternativas que funcionan hoy:**

1. Esperar el aviso **"Mapa guardado"** en verde antes de bloquear.
2. **Pantalla negra** (botón de la luna): la app sigue al frente con el brillo al mínimo y el
   mapa sigue en vivo todo el viaje, también fuera de la ruta. Falta medir batería y
   temperatura en un viaje real.

**Qué haría falta para tener calles nuevas con el iPhone bloqueado:** un sistema completo que
no dependa de Apple: datos de calles de OpenStreetMap (licencia ODbL, con atribución), un dibujo
propio de calles hecho solo con la CPU y rutas calculadas también con OpenStreetMap. No se
pueden mezclar las rutas de Apple con mapas de otro proveedor. Es un proyecto aparte (ver
`INTEGRATIONS.md`).

## 2. Sin comprobar en la moto

Nada de la 0.6.1 se ha probado todavía en la 450NK. Pruebas A–K en `TESTING.md`; con cada una,
**Más > Diagnóstico > Exportar informe**. En particular:

- Ubicación en segundo plano en la moto y ritmo de envío (~10 fps) con el iPhone bloqueado.
- Recálculo de ruta con el iPhone bloqueado (depende de que Apple responda en segundo plano).
- Reconexión sin límite al apagar y encender la moto.
- Cambio de día a noche en la TFT con el iPhone bloqueado.
- Consumo de batería y temperatura en un viaje largo.

## 3. Proveedores externos

- **Waze y Google Maps no envían su mapa ni sus giros a la moto.** Solo reciben el destino; la
  guía y la voz las dan ellas en el iPhone. La moto muestra el mapa de Apple, tu posición y la
  bandera del destino.
- El Navigation SDK de Google es de pago, con tu propio proyecto y clave, y sus términos no
  permiten llevar su mapa a otra pantalla. El SDK de Waze para socios ya no está disponible.
- Falta abrir Waze y Google Maps en tu iPhone con la 0.6.1 (el aviso si no se abren).

## 4. Spotify

- Necesita tu Client ID, la app de Spotify instalada y que la cuenta dueña tenga Premium.
- El permiso dura una hora y vive en memoria: después hay que volver a conectar.
- iOS puede cortar la conexión con Spotify en segundo plano; se reintenta dos veces y al abrir
  CFMoto Link.
- Falta probar con Spotify real (portadas, colores y controles).

## 5. Instalación

- El IPA va **sin firmar**: Sideloadly lo firma con tu Apple ID. Con una cuenta gratuita caduca
  a los 7 días y hay que reinstalarlo.
- Sideloadly necesita el iPhone conectado por cable al PC.

## 6. Compilación

- Se compila en GitHub Actions (macOS con Xcode). En este equipo no hay Xcode: las pruebas y la
  compilación se hicieron en GitHub, no en un Mac propio.
