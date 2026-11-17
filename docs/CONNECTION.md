# Comunicación con la moto

La app habla el protocolo EasyConn / Carbit PXC que usa la app oficial de CFMOTO. La
implementación de iOS (`Shared/BikeLink.swift`) se escribió a partir de la documentación y el
comportamiento de [OpenCfMoto](https://github.com/zanderp/open-cfmoto). **Las versiones 0.4,
0.5 y 0.6 no cambian nada de este protocolo**: solo cambia la imagen que se le entrega. La
conexión es por **Wi-Fi Direct**, no por Bluetooth; el Bluetooth del iPhone queda libre para el
intercomunicador.

## Cómo funciona (verificado en una CFMOTO 450NK)

1. El iPhone se une al Wi-Fi Direct de la moto (`DIRECT-…-CFMOTO`).
2. El iPhone abre tres servidores TCP: 10920 (datos de vídeo), 10921 (control de vídeo) y
   10922 (control PXC).
3. El iPhone envía un aviso a la moto en el puerto 10930 (comando `0x70000010`, JSON). La moto
   responde `{"status":true}`.
4. La moto se conecta de vuelta a los tres puertos y dirige el saludo (intercambio de claves RSA).
5. La moto pide vídeo de 800×400 y solicita los fotogramas H.264 de uno en uno.
6. Hay latidos en los dos sentidos cada pocos segundos.

La app se presenta con el identificador de la app oficial de Android, porque es el único que
la moto reconoce.

## Qué está verificado y con qué

| Comportamiento | Estado | Evidencia |
| --- | --- | --- |
| Saludo, negociación y vídeo H.264 800×400 | Verificado | Registro y foto del propietario (0.1 y 0.2) |
| Imagen dibujada por la app en la TFT | Verificado | Foto del propietario con la navegación de la 0.3 |
| La moto muestra la imagen entera y pone sus indicadores **debajo**, en su propia franja | Verificado | Misma foto: la fila inferior de la 0.3 y el hueco vacío de la app se ven completos; velocidad, marcha y rpm están fuera de la imagen (corrige lo que decía la 0.4) |
| Panel modular con tarjetas sobre el mapa en la TFT | Verificado | Foto del propietario con la 0.5 |
| Mapa de calles de Apple Maps en la TFT | Verificado | Misma foto: calles con nombre, posición, brújula y tarjetas, imagen completa |
| Panel de la 0.6 (proveedores, colores, modos 1–5) | **Pendiente** | Misma vía de vídeo; solo cambia el dibujo |
| Cambiar de modo sin reconectar | **Pendiente** | El cambio solo altera el dibujo del siguiente fotograma |
| Reconexión tras perder el enlace | Parcial | Programada (`Enlace perdido; reintentando…`); sin prueba sistemática |
| Vídeo con el iPhone bloqueado | **Pendiente** | Ver más abajo |
| Otros modelos de CFMOTO | Sin probar | |

## Con el iPhone bloqueado

- **Duplicar pantalla**: iOS corta la transmisión de pantalla al bloquear. No tiene arreglo.
- **Panel de CFMoto Link**: la app sigue viva por la sesión de ubicación y dibuja sin tarjeta
  gráfica. El riesgo es el codificador de vídeo, que iOS invalida al pasar a segundo plano; la
  app lo vuelve a crear, prueba el codificador por software y, si no hay imagen nueva, repite la
  última. Si eso basta está **sin comprobar**: el registro anota cada cinco segundos el estado
  de la app, las imágenes enviadas y el codificador usado.

Desde la 0.5, con el iPhone bloqueado el mapa de calles sale de las imágenes que la app
guardó al iniciar la ruta (Apple no genera imágenes nuevas en segundo plano). El registro
anota `[MAPA]` cuando llegan o fallan las imágenes.

## Lo que la app no hace

No lee datos de la moto (velocidad, marcha, rpm): el protocolo conocido solo lleva vídeo hacia
la pantalla. No modifica el firmware ni envía comandos fuera de los descritos.

## Diagnóstico

**Más > Conexión** muestra el estado, permite fijar la IP de la moto y copia el registro
completo. Si la moto no responde en el puerto 10930, la app anota qué puertos encontró abiertos.
