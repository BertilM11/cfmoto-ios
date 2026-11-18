# Resultados de las pruebas — CFMoto Link 0.6.2 (y 0.6.1)

Hay tres niveles y no se mezclan:

1. **Pruebas automáticas** (`Tools/DashboardCheck`, en macOS de GitHub Actions): el mismo
   código del panel, del mapa guardado y de los colores, sin iPhone ni moto.
2. **Simulador de iPhone** (GitHub Actions): la app completa con un recorrido simulado y mapas
   reales de Apple. No tiene moto, GPS real, Spotify ni bloqueo de pantalla de verdad.
3. **Moto** (manual, con la 450NK): **ni la 0.6.1 ni la 0.6.2 se han probado todavía en la moto.**

## 0.6.2 — Diseño de la pantalla

| Nivel | Qué se hizo | Resultado |
| --- | --- | --- |
| Automáticas | 152 pruebas: las 132 de la 0.6.1 (se conservan todas) y 20 nuevas | **Todas pasan** (prueba 29) |
| Compilación para el simulador | Xcode en GitHub (macOS arm64) | **BUILD SUCCEEDED** |
| Simulador | Recorrido de demostración en los modos 1 a 4, de día y de noche, y prueba en segundo plano | Capturas de la app con mapas reales de Apple |
| Compilación para iPhone | Release sin firmar (`CFMotoLink.ipa`) | Ver la publicación de la versión |
| Moto | Ver el diseño nuevo en la TFT | **Pendiente** |

Pruebas nuevas de la 0.6.2:

| Prueba | Resultado | Detalle |
| --- | --- | --- |
| Hora actual: el mismo sitio en los modos con mapa y nada encima | Pasa | arriba a la derecha: x 672, y 12, 116×30 |
| La hora se ve en el mismo sitio en todos los modos, de día y de noche, con y sin ruta | Pasa | 32 composiciones |
| La llegada lleva la palabra «Llegada»; el tiempo y la distancia van aparte | Pasa | Llegada 7:22 p.m. \| 18 min \| 7.4 km |
| La hora de llegada y la hora actual son cosas distintas | Pasa | 7:22 y 7:04 |
| Sin ruta, abajo no aparece otra hora | Pasa | imagen idéntica a la que no tiene barra de viaje |
| Maniobra compacta un 30 % más pequeña por lado | Pasa | 200×96, 50 % del área de antes (284×136) |
| La tarjeta grande de la maniobra sigue igual | Pasa | 340×176 |
| Mapa + Música: el centro (por donde va la ruta) queda libre de tarjetas | Pasa | maniobra hasta x 212, música desde x 538 |
| La tarjeta de música no crece | Pasa | 250×84 |
| La calle se saca de la indicación | Pasa | 8 indicaciones, incluidas dos sin calle |
| Música completa: partes sin montarse ni tapar la hora | Pasa | tres tamaños de portada, con y sin ruta |
| Música completa: portada grande | Pasa | 274 px; con el próximo giro abajo, 209 px |
| Música completa: columna de texto ancha y barra casi a todo el ancho | Pasa | columna de 432 px, barra de 736 px |
| Música completa: texto legible sobre el degradado | Pasa | peor contraste 10,3:1 (mínimo 4,5) |
| Cambio de canción: fundido corto | Pasa | 0,45 s |
| Portada que llega tarde (Spotify): solo se funde la portada | Pasa | |
| Misma canción avanzando: sin transición | Pasa | |
| Fondo guardado entre fotogramas igual que dibujado cada vez | Pasa | diferencia máxima 3 de 255 |
| Música completa en plena transición | Pasa | 9,9 ms por fotograma (equipo de GitHub) |
| Música completa sin transición (fondo reutilizado) | Pasa | 4,5 ms por fotograma (equipo de GitHub) |

Capturas: `docs/laminas/cambio1-…`, `cambio2-…` y `cambio3-…` en el paquete y la carpeta
`CAPTURAS` de la entrega (con el antes y el después).

Lo que no se probó: la TFT real (tamaño de letra, contraste al sol, la hora en la esquina),
Spotify y Apple Music reales con el diseño nuevo y el fundido en un iPhone.

---

# 0.6.1 — Estabilidad y navegación

## Resumen

| Nivel | Qué se hizo | Resultado |
| --- | --- | --- |
| Automáticas | 132 pruebas: las 105 de la 0.6.0 (se conservan todas) y 27 nuevas | **Todas pasan** |
| Compilación para el simulador | Xcode en GitHub (macOS arm64) | **BUILD SUCCEEDED** |
| Simulador: recorrido | 6 recorridos de demostración (día y noche, modos 1–5, Personalización) | Capturas generadas |
| Simulador: segundo plano | Ruta simulada, otra app al frente 50 s y vuelta | Ver abajo (antes y después de la corrección) |
| Compilación para iPhone | Release sin firmar (`CFMotoLink.ipa`) | Ver la publicación de la versión |
| Moto | Pruebas A–K de `TESTING.md` | **Pendientes** |

## 1. Pruebas automáticas

Lista completa con el detalle de cada una en `docs/RESULTADOS.txt` dentro del paquete (la
genera la compilación de la versión). Las de la 0.6.1:

| Prueba | Resultado | Detalle |
| --- | --- | --- |
| Ruta de prueba medida bien (15 km) | Pasa | 15 000 m |
| Se detectan los dos giros de la ruta | Pasa | 5990 m y 9990 m |
| Situar un punto en la ruta (a lo largo y de lado) | Pasa | 7300 m / 30 m |
| Ruta de 15 km guardada entera, sin huecos | Pasa | 15 km seguidos, 87 imágenes, 0 huecos |
| Las curvas tienen su imagen orientada a la calle nueva | Pasa | |
| No se vuelve a pedir lo que ya está guardado | Pasa | 0 repetidas |
| Lo ya pedido no se pide dos veces; primero lo más cercano | Pasa | |
| Memoria del mapa guardado acotada | Pasa | 15 km en 7,5 MB |
| Con memoria para 20 imágenes se guarda el tramo más cercano | Pasa | 20 imágenes |
| Lo recorrido y lo más lejano se sueltan con poca memoria | Pasa | |
| Se detecta un tramo sin imagen | Pasa | 4,1 km seguidos, 1 hueco |
| Al recalcular se conserva el tramo común | Pasa | 34 de 87 |
| Tras recalcular solo se pide el tramo nuevo | Pasa | 30 nuevas |
| Recalculando desde la posición actual no se vuelve a pedir lo que ya se tiene | Pasa | 75 conservadas, 0 pedidas de nuevo |
| Decidir qué pedir tarda poco | Pasa | 0,3 ms |
| Avanzando, cada imagen nueva amplía el mapa (60 s como el simulador) | Pasa | 4,1 km seguidos con 28 peticiones, 0 repetidas |
| Avanzando 4 minutos se guarda toda la ruta que queda | Pasa | 12,1 de 12,1 km, 83 peticiones, 0 repetidas |
| La separación no cambia por pequeñas variaciones de calibración | Pasa | |
| iPhone bloqueado: se usa una imagen guardada | Pasa | |
| Lo que se recorrerá de noche se guarda en oscuro | Pasa | |
| Con las dos versiones guardadas gana el tema correcto | Pasa | |
| Si solo hay del otro tema se usa y se marca | Pasa | |
| Sin imagen que sirva: mapa simple, sin inventar calles | Pasa | |
| La imagen en vivo reciente manda; una vieja solo como último recurso | Pasa | |
| Portadas de Spotify: solo vale la de la canción que suena | Pasa | |
| Revisar la cobertura de 15 km tarda poco | Pasa | 1,1 ms |
| Recta larga sin puntos intermedios: la ruta se ve por delante de la moto | Pasa | |
| Dibujar un fotograma con mapa y tarjetas | Pasa | 3,8 ms de media (equipo de GitHub, no el iPhone) |

Las pruebas usan imágenes de mapa de prueba con la misma geometría que pide la app; no
descargan mapas de Apple.

## 2. Simulador: la app en segundo plano

Con la ruta simulada en marcha (unos 9 km), la app al frente 60 s, otra app al frente 50 s
(CFMoto Link pasa a segundo plano, como con el iPhone bloqueado) y vuelta. El registro guarda
una línea `[DIAG]` cada 10 s.

| Con la ruta y la app al frente | Antes de la corrección (prueba 22) | Después (prueba 23) |
| --- | --- | --- |
| ~15 s | 0,4 km seguidos (7 imágenes) | 1,0 km (9 imágenes) |
| ~30 s | 0,4 km (13) | 2,1 km (15) |
| ~40 s | 0,5 km (18) | 2,9 km (19) |
| ~50 s | 0,7 km (22) | 3,3 km (23) |
| ~60 s | 0,8 km (25) | 4,2 km (26) |
| Al pasar a segundo plano | 0,8 de 6,7 km (24 imágenes) | 4,7 de 8,6 km (29 imágenes, 2,1 MB) |
| En segundo plano (50 s) | Imagen usada: guardada | Imagen usada: guardada |
| Al volver | 0,2 de 5,5 km (quedaban 4 imágenes) | 4,1 de 7,9 km (30 imágenes) |

Las dos pruebas usan rutas de Apple entre los mismos puntos, pero Apple devolvió rutas algo
distintas (8,8 km con 7 giros y 9,6 km con 9 giros).

Lo que muestra: con la app al frente, el mapa guardado ahora avanza por la ruta (antes se
repetía cerca de la posición); en segundo plano no llegan imágenes nuevas de Apple y se usan
las guardadas.

Lo que **no** muestra: el simulador no bloquea la pantalla ni aplica todas las reglas de un
iPhone real en segundo plano; no hay moto (ritmo de envío 0), ni GPS real (la posición la da el
recorrido simulado), ni datos móviles.

**Prueba 24** (con el tema, el avance y la cobertura al día en segundo plano): 5,0 km seguidos
al pasar a segundo plano (34 imágenes en 80 s, 2,3 MB); en segundo plano la cobertura se siguió
actualizando mientras avanzaba la ruta simulada (5,5 → 5,0 km) y se usó la imagen guardada; al
volver, 4,9 de 8,8 km. En su captura en segundo plano faltaba la línea de la ruta por delante de
la moto en una recta larga (error 9 del informe): corregido después.

**Prueba 25** (con esa corrección; es la del código que se publica): 132 pruebas automáticas,
todas pasan. Con la app al frente, 4,6 km seguidos al pasar a segundo plano (30 imágenes,
2,1 MB); en segundo plano, imagen guardada y cobertura al día (4,2 → 4,1 km); en la captura en
segundo plano la línea de la ruta ya se ve por delante de la moto en la avenida recta.

## 3. Lo que falta: pruebas en la moto

Ninguna de las pruebas A–K de `TESTING.md` está hecha. En particular, sin ellas **no se puede
afirmar** que:

- el mapa se vea sin huecos con el iPhone bloqueado durante 2, 5 o 10 minutos;
- la ubicación siga llegando en segundo plano en la moto (`fijos=…bg`);
- el vídeo mantenga ~10 fotogramas por segundo con el iPhone bloqueado;
- el recálculo con el iPhone bloqueado responda (depende de Apple);
- la reconexión sin límite funcione al apagar y encender la moto;
- el cambio de día a noche se vea bien en la TFT con el iPhone bloqueado;
- Spotify, Waze y Google Maps se comporten igual en un iPhone real.

Con cada prueba en la moto: **Más > Diagnóstico > Exportar informe** y una foto de la TFT.
