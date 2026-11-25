# Respuesta a incidentes — MotoLink

| Situación | Qué hacer |
| --- | --- |
| Una compilación falla con la moto o se comporta raro | Volver a la versión anterior ([docs/ROLLBACK.md](../docs/ROLLBACK.md)) y abrir un issue con el registro de Diagnóstico |
| Alguien reporta un problema de seguridad | Responder por el canal privado ([SECURITY.md](../SECURITY.md)), corregir en una rama y publicar una compilación nueva; documentar en `VULNERABILITIES.md` cuando esté corregido |
| Se subió un secreto al repositorio | Revocarlo primero en el servicio (Spotify Developer, GitHub…); después decidir si hace falta limpiar el historial |
| Permiso de Spotify en duda | En Spotify › Configuración › Apps, quitar el acceso de la app y volver a conectar desde MotoLink |
| El mapa descargado no coincide | La app lo rechaza por la huella SHA-256; revisar la versión «mapa-guatemala» en Releases |
| Teléfono perdido | Bloquearlo con Buscar (Find My); MotoLink no guarda contraseñas ni permisos permanentes |
