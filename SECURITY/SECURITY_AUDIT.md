# Revisión de seguridad — MotoLink 0.9.0

- **Fecha:** 25 de noviembre de 2026.
- **Alcance:** código de la app (`App/`, `Shared/`, `Broadcast/`, `LiveActivity/`), herramientas (`Tools/`),
  flujos de GitHub Actions e historial de Git.
- **Método:** revisión manual del código de red, enlaces, almacenamiento y servicios externos; búsqueda de
  secretos en el árbol y en todo el historial; revisión de los flujos de CI. Referencias: OWASP MASVS 2.0,
  OWASP Mobile Top 10 (2024) y CWE.

## Arquitectura

| Parte | Qué hace |
| --- | --- |
| App (SwiftUI, iOS 16+) | Navegación con mapa propio de OpenStreetMap, panel para la moto, música (Música y Spotify), viajes |
| Extensión de transmisión | Envía la pantalla del iPhone a la moto (H.264) |
| Conexión con la moto (`Shared/BikeLink.swift`) | Wi-Fi Direct: la moto se conecta a los puertos 10920–10922 del iPhone; saludo con RSA |
| Servicios externos (HTTPS) | Nominatim (búsqueda), Open-Meteo (lluvia), LRCLIB (letras), GitHub (mapa), Spotify (SDK oficial) |
| Mapa | Se descarga de Releases y se comprueba su huella SHA-256 antes de usarlo |

## Superficie de ataque y controles

| Entrada | Control | Estado |
| --- | --- | --- |
| Puertos de la moto (Wi-Fi) | Solo se aceptan conexiones de la IP de la moto (o de su red directa); tramas con tamaño máximo | Verificado (revisión) |
| Registro de diagnóstico de la extensión | Solo en 127.0.0.1 (antes, en todas las interfaces) | Implementado |
| Enlace `cfmotolink://` | Solo la vuelta de Spotify, y solo mientras se espera ese permiso | Implementado |
| Enlaces de mapas pegados | Solo dominios de mapas conocidos; se leen coordenadas, no se ejecuta nada | Verificado (revisión) |
| Descarga del mapa | HTTPS + huella SHA-256 fijada en el repositorio | Verificado (revisión) |
| Datos enviados a terceros | Lluvia: coordenadas con 2 decimales (~1 km); búsqueda: el texto que se escribe | Implementado |
| Permiso de Spotify | Solo en memoria (dura una hora); el Client ID no es secreto | Verificado (revisión) |
| Transporte | App Transport Security sin excepciones (solo HTTPS) | Verificado (revisión) |
| GitHub Actions | Acciones fijadas por SHA, CodeQL, Dependabot; escaneo de secretos y protección de push de GitHub activos | Implementado |

## Resultado

4 hallazgos de gravedad baja, corregidos, y 2 riesgos aceptados que impone el protocolo de la moto
(detalle en [VULNERABILITIES.md](VULNERABILITIES.md)). No se encontraron secretos en el código ni en el historial.
