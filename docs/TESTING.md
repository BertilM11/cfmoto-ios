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
       App/Dashboard/Appearance.swift -o dashcheck
./dashcheck salida
```

El resultado de la última ejecución en GitHub Actions está en `docs/RESULTADOS.txt` dentro del
paquete.

## 2. Simulador de iPhone (sin moto)

GitHub Actions compila la app, la instala en un simulador de iPhone, lanza un recorrido
simulado por Ciudad de Guatemala con rutas reales de Apple y guarda capturas de las pantallas y
de la imagen que se enviaría a la moto en cada modo, **con el mapa de calles real de Apple**
(`tft-night-*.png`, `tft-light-*.png`).

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
