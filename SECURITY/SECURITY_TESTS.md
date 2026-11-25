# Pruebas de seguridad — MotoLink

Revisión del 25 de noviembre de 2026.

| Prueba | Estado |
| --- | --- |
| Búsqueda de secretos en el árbol y en todo el historial de Git (patrones de claves, tokens, llaves privadas, URLs con contraseña) | **Verificado** — sin secretos |
| Escaneo de secretos y protección de push de GitHub | **Verificado** — activos en el repositorio |
| Revisión del código de red: IP de la moto, límites de tramas, lectura de JSON | **Verificado** (revisión manual) |
| Revisión de enlaces `cfmotolink://` y enlaces de mapas pegados | **Verificado** (revisión manual) |
| Compilación completa con los cambios (CodeQL en el pull request) | Se comprueba en el pull request |
| Pruebas del panel (`Tools/DashboardCheck`) | Se ejecutan al compilar la versión en `main` |
| En la moto: pantalla de Diagnóstico muestra el registro de la extensión; Spotify se conecta; aviso de lluvia | **Pendiente** (requiere el iPhone y la moto) |
| Clave RSA de 2048 bits con la moto | **Pendiente** (riesgo aceptado MOTO-R1) |
