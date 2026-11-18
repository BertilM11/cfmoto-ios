# Instalación y primer uso (0.6.2)

## Lo que hace falta

- iPhone con iOS 16 o posterior.
- PC con [Sideloadly](https://sideloadly.io) y el cable del iPhone.
- Tu Apple ID (con una cuenta gratuita, la app caduca a los 7 días y hay que reinstalarla).
- Datos móviles activos en el iPhone: la red Wi-Fi de la moto no da internet.

## Instalar

1. Descarga `CFMotoLink.ipa` de la publicación de la 0.6.2 en GitHub (*Releases*) o usa el
   que viene en la entrega (`CFMotoLink_0.6.2/CFMotoLink.ipa`).
2. Conecta el iPhone al PC con el cable y desbloquéalo. Si pregunta, toca **Confiar**.
3. En Sideloadly: toca el icono del IPA, elige el archivo, comprueba tu Apple ID y pulsa
   **Start**. Escribe tu contraseña solo en la ventana de Sideloadly.
4. En el iPhone: *Ajustes > General > VPN y gestión de dispositivos* > tu Apple ID > **Confiar**.
5. Abre CFMoto Link y permite la ubicación (**Al usar la app**) y, si usas Apple Music, el
   acceso a la música.

La 0.6.2 se instala encima de la 0.6.1 (o de la 0.6.0) y conserva los ajustes.

## Usar con la moto

1. En la moto abre la pantalla del código QR y déjala abierta.
2. En el iPhone conéctate al Wi-Fi `DIRECT-…-CFMOTO` (clave `12345678`).
3. **Inicio > Conectar y enviar el panel**.
4. **Navegación**: busca el destino. En la tarjeta de la ruta, "Guiar con" elige CFMoto Link
   (giros en la moto), Mapas de Apple, Google Maps o Waze.
5. Con CFMoto Link, pulsa **Iniciar** y mira el aviso bajo la maniobra:
   - *Guardando el mapa: 3,2 de 25 km* → la app está fotografiando la ruta.
   - *Mapa guardado: 25 de 25 km* (en verde) → ya puedes bloquear el iPhone: la moto seguirá
     mostrando las calles de la ruta.
6. Si quieres que el mapa siga **en vivo** todo el viaje (también fuera de la ruta), usa el
   botón de la luna (**Pantalla negra**) en vez de bloquear: la app sigue al frente con la
   pantalla en negro y el brillo al mínimo. Se sale manteniendo pulsado.

## Spotify (opcional)

En **Música > Spotify**: pega el Client ID de tu app de Spotify (la que creamos en
developer.spotify.com) y toca **Conectar con Spotify**. La cuenta dueña necesita Premium.

## Si algo falla

**Más > Diagnóstico > Exportar informe** y mándalo. No incluye contraseñas, permisos de
Spotify ni el Client ID; la posición va redondeada.

Para volver a la 0.6.1 o a la 0.6.0: [ROLLBACK.md](ROLLBACK.md).
