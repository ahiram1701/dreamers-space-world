# Changelog

Todos los cambios relevantes del proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [0.5.0] - 2026-10-29

### Añadido
- **Tu personaje hace lo que escribes.** Con <kbd>F</kbd> se ve la acción (talar con un hacha, cavar con una pala, martillar, sentarse, dormir, pescar, beber, bailar…) y el mundo cambia de verdad: reparas o modificas tus objetos, gastas materiales, **talas árboles y rompes rocas** (no vuelven a crecer) y **construyes** balsas, botes, hogueras, tiendas, mesas, sillas, camas, vallas o carteles, que quedan en el mundo. Cada acción gasta el tiempo que tardaría de verdad.
- **Edificios por dentro**: tu casa, la cafetería (con Teo detrás de la barra), la estación con el taller de Samir, el faro y las casas de los mundos generados, con muebles. Puedes sentarte en sillas y sofás y **dormir** hasta la mañana para recuperarte.
- **Barcas**: súbete a las del muelle (o a las que construyas) y rema con WASD.
- **Nadar** en el mar.
- Los PNJs **gesticulan** según cómo se sienten, te **miran** cuando pasas cerca, te entregan las cosas con la mano y pueden arreglar tus objetos.
- Ajuste de **duración del día** (24 min, 1 h, 2 h, 4 h o tiempo real).

### Cambiado
- Animación de los personajes mucho más natural: respiran, cambian el peso, giran cadera y hombros al andar, corren inclinados, saltan y llevan herramientas en la mano.
- El día dura 2 horas por defecto (antes 24 minutos).
- Se puede pasar bajo las copas de los árboles.

### Corregido
- Tras varios turnos, algunos modelos no devolvían opciones y la respuesta del PNJ se perdía («dialogue_turn.choices: falta»).
- Un PNJ podía prestarte dos veces el mismo objeto.

## [0.4.0] - 2026-10-29

### Añadido
- **Lo que se dice, pasa.** Los PNJs pueden actuar de verdad en una conversación: dar o prestar objetos, aceptar los que les das, acompañarte, ir a un sitio, curarte, hablarte de lugares nuevos (que se convierten en destinos), pedirte favores y darlos por cumplidos, anotar pistas en tu diario o negarse a hablarte un rato si les enfadas. Deciden según su personalidad y su relación contigo.
- Botón **Dar objeto** en el diálogo, y objetos prestados que los PNJs recuerdan y te pueden pedir de vuelta.
- **Hacer algo** (tecla <kbd>F</kbd>): describe con tus palabras lo que haces en el mundo (buscar, examinar, descansar, construir…) y la IA narra qué ocurre; si encuentras algo o descubres una pista, pasa de verdad.
- **Diario** y **encargos** en el panel de inventario (<kbd>I</kbd>).
- **Ciclo de día y noche** (un día dura 24 minutos): el sol se mueve, salen las estrellas y se encienden farolas y ventanas. Los vecinos del pueblo siguen una **rutina** según la hora.
- **Gráficos nuevos**: personas, casas, árboles, rocas, farolas, barcas y equipamiento espacial con modelos 3D CC0 de Quaternius ([créditos](assets/CREDITS.md)), animados por código; terreno con playa y colinas, mar con olas y espuma, hierba con viento, iluminación con SSAO, glow y niebla.
- Ajustes de **calidad gráfica** (baja, media, alta) y de **aspecto de tu personaje**.

### Cambiado
- Los PNJs caminan, te siguen y se giran hacia ti al hablar.

## [0.3.1] - 2026-10-29

### Corregido
- Los PNJs repetían siempre la misma frase: los modelos de Ollama Cloud no respetan el esquema JSON (traducen valores al español, devuelven opciones como texto, decimales donde van enteros) y el validador rechazaba la respuesta entera. Ahora los detalles se reparan y solo se rechaza si falta lo esencial.
- Con DeepSeek, a partir del segundo turno de una conversación el modelo dejaba de responder en JSON.
- Nombres de lugares y objetos cortados a mitad de palabra.

### Añadido
- El formato esperado se describe en el prompt (claves y valores permitidos), generado del mismo esquema.
- Botón «Probar conexión con la IA» en Ajustes, con el modelo y el tiempo de respuesta.
- Si la IA no responde, el diálogo lo indica y explica por qué, y cada PNJ usa su propio saludo.

## [0.3.0] - 2026-10-29

### Añadido
- **El Despertar**: el pulso de las 3:33, el campo de dilatación temporal y la brecha bajo el faro. La IA elige un origen científico (sonda del futuro, experimento fallido, transmisión de otra rama, artefacto no humano o anomalía natural) según cómo jugaste el Acto 0, diseña tu Ancla y fija hechos canónicos.
- Decisión del Despertar: saltar solo, con el vecino que más confía en ti como compañero, o sellar la brecha detrás de ti.
- Árbol de líneas temporales (`TimelineManager`), stats del viajero (`GameState`) y saltos (`Travel`).
- **Mundos generados**: cada salto a lo desconocido crea un lugar 3D nuevo con terreno procedural, cielo, gravedad, puntos de interés, recarga del Ancla y 2 habitantes generados por la IA.
- Panel del Ancla (tecla T), HUD de stats y pantalla de carga.
- Prueba de flujo completo sin red (`tests/test_awakening_flow.gd`).
- **Misiones** generadas por la IA en cada mundo (visitar, hablar, llevar un objeto), resueltas contra lo que existe en el lugar.
- **Hilo principal**: 5 fragmentos de coordenadas de la transmisión llevan a su origen.
- **El final**: revelación escrita para tu partida, 3 desenlaces (cerrar el bucle, volver a casa, seguir explorando), epílogo y créditos con el resumen de tu multiverso.
- **Inventario** (I) con objetos que curan, recargan, estabilizan, revelan secretos, dan saltos gratis o mejoran la confianza.
- **Mundos variados**: asentamientos según la época, estaciones espaciales con estrellas y planeta, ruinas, vegetación, cristales, lava, océano y anomalías.
- Túnel visual del salto y **pregeneración** del siguiente destino en segundo plano.
- Inestabilidad con **fallos visuales** (decoherencia), daño a nivel crítico y **desanclaje** con recuperación.
- **Pausa** (Esc), **ajustes** completos (IA, sensibilidad del ratón, volumen, actualizaciones) y **gestión de partidas** (cargar y borrar).
- **Sonido ambiental** sintetizado: viento, olas y zumbido de estación.
- Prueba de partida completa sin red (`tests/test_full_game.gd`).

### Cambiado
- Canon del multiverso reescrito como ciencia ficción (muchos mundos, brechas, inestabilidad, filtraciones de memoria). Los misterios del Acto 0 ahora tienen causas físicas.

## [0.2.1] - 2026-10-29

### Corregido
- En pantallas de 768 px de alto (p. ej. 1366×768) la ventana no cabía y la barra de título quedaba fuera de la pantalla. Ahora el juego abre maximizado y la interfaz escala a cualquier resolución.

## [0.2.0] - 2026-10-29

### Añadido
- Actualizador integrado: comprueba al arrancar si hay una versión estable nueva en GitHub Releases, la descarga, verifica su SHA-256, se reemplaza y se reinicia con un clic. Los mundos y ajustes se conservan.
- Versión del juego visible en el menú principal y opción «Buscar actualizaciones» en Ajustes.
- `SemVer`: comparación de versiones semánticas, con pruebas.
- Las Releases incluyen `SHA256SUMS.txt`.

### Cambiado
- El proyecto, la CI y el CD pasan de Godot 4.3 a **Godot 4.7.2**.
- Acciones de GitHub actualizadas (`checkout@v7`, `cache@v6`, ya en Node 24).

## [0.1.0] - 2026-10-29

### Añadido
- Cliente de Ollama Cloud con salida en JSON schema, reintentos y modo *mock*.
- Validador de entidades (PNJ, lugar, objeto, turno de diálogo) que también genera los JSON schema.
- `WorldDB`: el mundo persistente de cada jugador, con el origen de cada entidad.
- `ContentGenerator`: generación con autocorrección y contenido de respaldo.
- Acto 0 «Bahía de las Horas»: pueblo 3D, jugador en tercera persona y 3 vecinos.
- Conversaciones generadas por IA con opciones o texto libre, memoria de PNJs y perfil del jugador.
- Menú principal y generador de contenido para desarrollo.
- CI (pruebas unitarias y smoke test) y publicación automática de builds para Windows y Linux.
