# Instalación y primer uso (0.7)

## Lo que hace falta

- iPhone con iOS 16 o posterior.
- PC con [Sideloadly](https://sideloadly.io) y el cable del iPhone.
- Tu Apple ID (con una cuenta gratuita, la app caduca a los 7 días y hay que reinstalarla).
- Datos móviles: con el mapa propio (de serie en la 0.7) no hacen falta para el mapa, la búsqueda
  ni la ruta. Sí para Spotify, Apple Music en streaming y el modo Apple Maps (la red Wi-Fi de la
  moto no da internet).
- Unos 30 MB libres en el iPhone (la app trae el mapa de Guatemala).

## Instalar

1. Descarga `CFMotoLink.ipa` de la publicación de la 0.7 en GitHub (*Releases*) o usa el
   que viene en la entrega (`CFMotoLink_0.7.ipa`).
2. Conecta el iPhone al PC con el cable y desbloquéalo. Si pregunta, toca **Confiar**.
3. En Sideloadly: toca el icono del IPA, elige el archivo, comprueba tu Apple ID y pulsa
   **Start**. Escribe tu contraseña solo en la ventana de Sideloadly.
4. En el iPhone: *Ajustes > General > VPN y gestión de dispositivos* > tu Apple ID > **Confiar**.
5. Abre CFMoto Link y permite la ubicación (**Al usar la app**) y, si usas Apple Music, el
   acceso a la música.

La 0.7 se instala encima de la 0.6.5 (o de una anterior) y conserva los ajustes y perfiles. Al
abrirla por primera vez usa el mapa propio de OpenStreetMap; para volver a Apple Maps:
**Personalizar > Mapa y navegación > Apple Maps**.

## Usar con la moto

1. En la moto abre la pantalla del código QR y déjala abierta.
2. En el iPhone conéctate al Wi-Fi `DIRECT-…-CFMOTO` (clave `12345678`).
3. **Inicio > Conectar y enviar el panel**.
4. **Navegación**: busca el destino. En la tarjeta de la ruta, "Guiar con" elige CFMoto Link
   (giros en la moto), Mapas de Apple, Google Maps o Waze.
5. Con CFMoto Link, pulsa **Iniciar**.
   - **Mapa propio (OpenStreetMap)**: el aviso dice *Mapa de Guatemala en el iPhone · sin
     internet*. Puedes bloquear el iPhone cuando quieras: el mapa, los giros y los desvíos siguen
     en la moto.
   - **Apple Maps**: mira el aviso bajo la maniobra. *Guardando el mapa: 3,2 de 25 km* → la app
     está fotografiando la ruta; *Ruta completa guardada* (en verde) → ya puedes bloquear el
     iPhone. Para el mapa en vivo todo el viaje, usa el botón de la luna (**Pantalla negra**) en
     vez de bloquear.
6. La búsqueda del modo propio no usa internet: escribe el lugar, la zona o el tipo de lugar
   («gasolinera», «farmacia»…). También puedes mantener pulsado el mapa del iPhone para elegir
   un punto.

## Spotify (opcional)

En **Música > Spotify**: pega el Client ID de tu app de Spotify (la que creamos en
developer.spotify.com) y toca **Conectar con Spotify**. La cuenta dueña necesita Premium.

## Si algo falla

**Más > Diagnóstico > Exportar informe** y mándalo. No incluye contraseñas, permisos de
Spotify ni el Client ID; la posición va redondeada.

Para volver a la 0.6.5 o a una anterior: [ROLLBACK.md](ROLLBACK.md).
