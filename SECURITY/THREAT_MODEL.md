# Modelo de amenazas — MotoLink

## Qué se protege

| Activo | Por qué |
| --- | --- |
| Ubicación y rutas | Revelan dónde vive y por dónde se mueve quien maneja |
| Conexión con la moto | Lo que ve quien maneja en la pantalla mientras conduce |
| Permiso de Spotify | Control de la música de la cuenta |
| Destinos guardados y viajes | Lugares personales (Casa, Trabajo, favoritos) |
| Compilaciones publicadas | Lo que se instala en el iPhone |

## De quién

| Actor | Puede |
| --- | --- |
| Alguien en la misma red Wi-Fi | Conectarse a puertos abiertos del iPhone |
| Otra app del iPhone | Abrir enlaces `cfmotolink://` |
| Un servicio externo (búsqueda, lluvia, letras) | Ver lo que la app le envía |
| Quien altere el repositorio o una acción de GitHub | Cambiar lo que se compila y publica |

## Controles (STRIDE)

| Amenaza | Ejemplo | Control |
| --- | --- | --- |
| Suplantación | Un equipo se hace pasar por la moto | Solo se acepta la IP de la moto o su red directa |
| Alteración | Mapa modificado | Huella SHA-256 fijada antes de usarlo |
| Alteración | Acción de GitHub alterada | Acciones fijadas por SHA; permisos mínimos en CodeQL |
| Divulgación | Leer el registro desde la red | Registro solo en 127.0.0.1 |
| Divulgación | Ubicación exacta a terceros | Lluvia con ~1 km de precisión; la búsqueda solo envía lo escrito |
| Divulgación | Secretos en el repositorio | No hay secretos; escaneo de secretos y protección de push de GitHub |
| Denegación de servicio | Tramas enormes de la moto | Tamaño máximo por trama |
| Elevación | Permiso de Spotify colado por otra app | Solo se acepta la vuelta que la app pidió |

## Supuestos

- La red Wi-Fi Direct de la moto es solo entre la moto y el iPhone.
- iOS aísla los datos de cada app; el iPhone tiene código de bloqueo.
