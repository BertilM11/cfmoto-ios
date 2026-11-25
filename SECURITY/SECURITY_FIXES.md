# Correcciones de seguridad — MotoLink

Rama `seguridad/protocolo`. No cambian el diseño ni quitan funciones.

| Hallazgo | Cambio | Archivos |
| --- | --- | --- |
| MOTO-01 | `TcpListener` recibe la dirección donde escucha (por defecto `0.0.0.0`, como antes, para la moto); el servidor del registro usa `127.0.0.1`. La app lo sigue leyendo igual desde el propio iPhone | `Shared/Sock.swift`, `Shared/LogServer.swift` |
| MOTO-02 | Coordenadas del pronóstico con 2 decimales | `App/Nav/RainForecast.swift` |
| MOTO-03 | La vuelta de Spotify exige el destino `spotify-login` y que MotoLink esté esperando ese permiso | `App/Dashboard/SpotifyService.swift` |
| MOTO-04 | `actions/checkout` fijada por SHA en los cuatro flujos; Dependabot para mantenerla al día | `.github/workflows/*.yml`, `.github/dependabot.yml` |
| Continuo | Análisis de código con CodeQL (Swift) en pull requests, en `main` y cada lunes | `.github/workflows/codeql.yml` |
| Documentación | Política de seguridad y esta carpeta | `SECURITY.md`, `SECURITY/` |
