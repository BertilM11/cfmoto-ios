# Mantenimiento de seguridad — MotoLink

## Automático (GitHub)

| Qué | Cuándo |
| --- | --- |
| CodeQL (Swift) | Pull requests a `main`, cada push a `main`, lunes 08:41 y a mano |
| Escaneo de secretos y protección de push | Siempre (ajuste del repositorio) |
| Dependabot: acciones de GitHub | Cada mes |

## Manual

| Frecuencia | Tarea |
| --- | --- |
| Cada versión | Revisar [DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md) |
| Mensual | Revisar alertas en Security; fusionar o cerrar los pull requests de Dependabot |
| Cada 3 meses | Revisar si el SDK de Spotify (`project.yml`) tiene versión nueva; revisar qué datos se envían a servicios externos |
| Al cambiar la conexión con la moto | Mantener la validación de la IP de la moto y los límites de tamaño de las tramas |
