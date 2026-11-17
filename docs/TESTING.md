# Pruebas

Hay tres niveles. Solo el tercero prueba la moto de verdad.

## 1. Pruebas automáticas del panel (sin iPhone ni moto)

`Tools/DashboardCheck` compila en macOS el mismo modelo y el mismo dibujo de la app y comprueba:

- **Distribución**: en cada modo y en 2000 diseños al azar (con valores inválidos), las zonas
  quedan dentro del área útil, no se solapan y no repiten módulo.
- **Modos**: cada modo contiene los módulos esperados.
- **Edición**: intercambiar zonas, colocar y ocultar módulos, cambiar de plantilla.
- **Persistencia**: la configuración se guarda y se recupera igual; datos dañados no rompen la carga.
- **Reglas automáticas**: inicio y fin de ruta, música sin ruta, giro próximo, reglas apagadas.
- **Composición**: cada modo, en oscuro y claro, dibuja contenido.
- **Franja de la moto**: en todos los modos el 22 % inferior queda intacto.
- **Estados sin datos**, otra resolución (640×320) y sin franja reservada.
- **Rendimiento**: tiempo medio de dibujo por fotograma.

Además guarda una lámina PNG de cada modo.

```sh
swiftc -O Tools/DashboardCheck/main.swift App/HUD/HUDModel.swift App/HUD/HUDRenderer.swift \
       App/Dashboard/DashModel.swift App/Dashboard/DashRenderer.swift -o dashcheck
./dashcheck salida
```

El resultado de la última ejecución en GitHub Actions está en `docs/RESULTADOS.txt` dentro del
paquete.

## 2. Simulador de iPhone (sin moto)

GitHub Actions compila la app, la instala en un simulador de iPhone, lanza un recorrido
simulado por Ciudad de Guatemala con rutas reales de Apple y guarda capturas de las pantallas y
de la imagen que se enviaría a la moto.

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
| Vídeo con el iPhone bloqueado | **Pendiente** |
| Reconexión tras apagar y encender la moto | **Pendiente** |

### Cómo hacerlas

1. Conecta y envía el panel (Inicio).
2. Recorre los siete modos desde Inicio o Mi pantalla y comprueba que la moto cambia sin reconectar.
3. Pon música en la app Música y mira la tarjeta de música.
4. Más > Notificaciones > Enviar un aviso de prueba.
5. Bloquea el iPhone dos minutos con una ruta activa.
6. Más > Conexión > Copiar registro.
