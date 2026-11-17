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
- **Modos A–D** y los tres modos de la 0.4.
- **Edición**: intercambiar zonas y tarjetas, mover, agrandar, ocultar, cambiar de plantilla.
- **Persistencia** y **actualización desde la 0.4**: se conservan el modo, los avisos y los
  perfiles del usuario; los de fábrica pasan al mapa completo.
- **Reglas automáticas**.
- **Proyección del mapa**: la homografía de 4 puntos reproduce una perspectiva exacta; con una
  cámara de prueba girada, la ruta cae a menos de 1 píxel de donde debe.
- **Dibujo sobre un mapa de prueba**: cada modo, en oscuro y claro, con contenido también en
  el 20 % inferior; la línea azul de la ruta cae sobre su calle.
- **Estados sin datos**, mapa simple sin imagen de calles, modo Música con el próximo giro abajo,
  otra resolución (640×320).
- **Rendimiento**: tiempo medio de dibujo por fotograma con mapa y tarjetas.

Además guarda una lámina PNG de cada modo.

```sh
swiftc -O Tools/DashboardCheck/main.swift App/HUD/HUDModel.swift App/HUD/HUDRenderer.swift \
       App/Dashboard/DashModel.swift App/Dashboard/DashRenderer.swift \
       App/Dashboard/MapBase.swift App/Dashboard/DashMapRenderer.swift -o dashcheck
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
| 0.5: imagen completa, sin franja negra | **Pendiente** (foto) |
| 0.5: mapa de calles legible en la TFT, de día y de noche | **Pendiente** |
| 0.5: mapa con el iPhone bloqueado (imágenes guardadas) | **Pendiente** |
| 0.5: Spotify en la TFT | **Pendiente** (necesita tu Client ID) |
| Vídeo con el iPhone bloqueado | **Pendiente** |
| Reconexión tras apagar y encender la moto | **Pendiente** |

### Cómo hacerlas

1. Conecta y envía el panel (Inicio). Foto de la TFT: ya no debe haber franja negra entre el
   panel y los indicadores de la moto.
2. Con datos móviles activos, elige un destino e inicia la ruta. Deja la app abierta unos
   segundos para que vea las calles y guarde las del recorrido.
3. Recorre los modos A–D desde Inicio y comprueba que la moto cambia sin reconectar.
4. Pon música (Apple Music, o Spotify si registraste tu app) y mira la tarjeta de música.
5. Más > Notificaciones > Enviar un aviso de prueba.
6. Bloquea el iPhone dos minutos con la ruta activa: deben seguir las calles mientras estés en
   la zona guardada.
7. Más > Conexión > Copiar registro, y fotos de la TFT de día y de noche.
