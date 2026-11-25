# Hallazgos — MotoLink

Revisión del 25 de noviembre de 2026 sobre la versión 0.9.0.

| ID | Hallazgo | Gravedad | CWE | Estado |
| --- | --- | --- | --- | --- |
| MOTO-01 | La extensión de transmisión servía su registro de diagnóstico (identificador de la moto, direcciones IP y eventos) en el puerto 10950 de **todas** las interfaces y sin clave: otro equipo en la misma red Wi-Fi podía leerlo mientras se transmitía la pantalla | Baja | CWE-200, CWE-306 | Corregida: solo 127.0.0.1 · Implementado, no verificado en la moto |
| MOTO-02 | El aviso de lluvia enviaba a Open-Meteo los puntos de la ruta (incluida la salida) con 4 decimales (~11 m) | Baja | CWE-359 | Corregida: 2 decimales (~1 km), suficiente para el pronóstico · Implementado |
| MOTO-03 | El enlace `cfmotolink://` aceptaba un permiso de Spotify con cualquier ruta y en cualquier momento: otra app del iPhone podía abrirlo con un permiso ajeno | Baja | CWE-939 | Corregida: solo `cfmotolink://spotify-login` mientras se espera el permiso · Implementado |
| MOTO-04 | Los flujos de GitHub Actions, con permiso de escritura, usaban `actions/checkout@v4` sin fijar por SHA | Baja | CWE-829 | Corregida: fijada por SHA + Dependabot mensual · Implementado |

## Riesgos aceptados

| ID | Tema | Motivo |
| --- | --- | --- |
| MOTO-R1 | El saludo con la moto usa una clave RSA de 1024 bits (nueva en cada sesión, no se guarda) | Lo impone el protocolo de la moto; usar 2048 bits podría impedir la conexión. Se puede probar con la moto en una versión futura |
| MOTO-R2 | La imagen y el control con la moto viajan sin cifrar por Wi-Fi Direct | Lo define el firmware de la moto; la red es directa entre la moto y el iPhone |

## Revisado sin hallazgos

Validación de quién se conecta a los puertos de la moto, límites de tamaño de las tramas, lectura de JSON,
enlaces de mapas pegados, descarga e integridad del mapa, App Transport Security, almacenamiento del permiso
de Spotify y secretos en el repositorio (árbol e historial completo).
