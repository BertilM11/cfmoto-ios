# Lista de verificación de una compilación — MotoLink

Cada push a `main` compila y publica una versión en Releases. Antes de fusionar a `main`:

- [ ] El pull request tiene CodeQL en verde y sin alertas nuevas (Security › Code scanning).
- [ ] Sin secretos en el diff (GitHub los bloquea al hacer push, pero revisa también a ojo).
- [ ] Ningún servidor nuevo escucha en `0.0.0.0` salvo los puertos de la moto.
- [ ] Datos nuevos que salgan del iPhone: solo los necesarios y por HTTPS.
- [ ] Si cambió el mapa: huella SHA-256 actualizada en `Tools/OSM/Guatemala.cfmap.sha256`.
- [ ] `CHANGELOG.md` actualizado y respaldo de la versión anterior (rama `backup/vX` y etiqueta).

Después de publicar:

- [ ] El flujo «Compilar app iOS» terminó y las pruebas del panel pasaron.
- [ ] Instalar el `.ipa` con Sideloadly y probar con la moto: conexión, Diagnóstico, música y navegación.
- [ ] Si algo falla, volver a la versión anterior con [docs/ROLLBACK.md](../docs/ROLLBACK.md).
