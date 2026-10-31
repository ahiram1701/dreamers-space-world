# Changelog

Todos los cambios relevantes del proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [0.6.1] - 2026-10-30

### Añadido
- **Modo de pantalla**: ventana maximizada, pantalla completa o ventana (Ajustes → Imagen). **F11** o **Alt+Enter** alternan la pantalla completa.
- Ajustes de **límite de FPS**, **VSync** y **mostrar FPS**, y tamaño de la interfaz en «Automático».
- **Registro** en el Cuaderno: todo lo que te pasó y lo que te dijeron, con su hora, aunque el aviso ya se haya ido.
- Con mando: los menús empiezan con un botón seleccionado y **B** cierra el panel abierto.

### Cambiado
- La partida se guarda **agrupando los cambios** (como mucho una vez cada 2 s, y siempre al pausar o salir): menos tirones.
- La gente lejana o fuera de cámara se anima con menos detalle: más fluidez con mucha gente.

### Corregido
- **La ventana no cabía en algunas pantallas**: ahora siempre se ajusta a la zona útil (sin taparse con la barra de tareas).
- Los paneles (celular, ajustes, controles, conversación) se salían en pantallas bajas; ahora se adaptan y se desplazan.
- Si el juego se cerraba a mitad de guardar, la partida podía dañarse: ahora se escribe en una copia y, si el archivo se daña, se recupera la anterior.

## [0.6.0] - 2026-10-30

### Añadido
- **Celular** (<kbd>C</kbd>):
  - **Mensajes**: la gente te contesta como en un chat y a veces te escribe por iniciativa propia.
  - **Llamadas**: de madrugada o si te odian, no contestan.
  - **Contactos**: se consiguen pidiendo el número.
  - **Banco** con tus movimientos.
  - **Mapa** que marca un destino y te guía con una flecha.
  Si lo pierdes o lo das, no hay llamadas.
- **Trabajo**: pide trabajo y alguien puede contratarte con puesto, horario y sueldo. En tu turno, en tu sitio, pulsa E para trabajar: pasan las horas, cobras y te cuentan cómo fue. Si llegas tarde cobras menos, y a la tercera falta seguida te despiden.
- **Crear e inventar** con realismo (la ciencia ficción vale si tiene base):
  - Los objetos tienen uso real: linternas que alumbran, comida, bebida, radios, abrigo y herramientas.
  - Lo que construyes toma la forma que describes (una antena, un generador…) y sirve para algo: luz, asiento, cama, calor, radio o **baúl para guardar cosas**.
  - En el Cuaderno puedes **combinar** objetos.
- **Más vida**:
  - **Transeúntes** que van y vienen según la hora; si le hablas a uno, pasa a ser alguien de verdad.
  - Los vecinos **vuelven a casa de noche**, y si te metes en una casa ajena se nota.
  - **Sonido ambiente**: pájaros, grillos, murmullo en la cafetería y **música** suave, con su propio volumen.
  - Con mucho sueño bostezas y se te nubla la vista.
- **Una vida de verdad** (en **dólares**):
  - **Hambre, sed, descanso e higiene**: se notan, te ralentizan si los descuidas (nunca te matan) y la gente lo nota. En casa puedes comer de la nevera, beber del grifo, ducharte y dormir.
  - **Dinero**: empiezas con $40. Teo te cobra el café ($3), puedes pagar (botón **Pagar** o diciéndolo), te pagan por trabajos y encargos, y sin dinero no se compra.
- **La IA crea gente y sitios que se quedan**: «llamo a un fontanero» y llega alguien nuevo andando, con nombre, oficio y carácter. «Abro una panadería» y, si es creíble, aparece en un solar con su letrero, su puerta y su interior.
- **El pueblo vive**:
  - Cada vecino hace lo suyo en su sitio: Teo limpia la barra, Samir repara radios.
  - Quien ve lo que haces se entera, y luego **se lo cuenta a otros**.
  - Los vecinos **charlan entre ellos**.
  - La cafetería **cierra de noche**.
- **Tiempo y calendario**: despejado, nublado, lluvia (con sonido), niebla o viento, y días de la semana. La IA lo tiene en cuenta.
- **Cuaderno** (<kbd>I</kbd>) con pestañas Objetos, Encargos, Diario y **Personas** (cómo te trata cada uno y lo último que pasó). Los objetos se usan, examinan, dan o sueltan.
- **Consejos la primera vez** que algo es posible, y la **lista completa de controles en la pausa** (teclado y mando).
- **Hacer algo** (<kbd>F</kbd>) sugiere ideas según lo que tienes cerca y cómo estás, y recuerda lo que escribiste (↑ ↓).
- **Lo que escribes con <kbd>F</kbd> pasa de verdad, paso a paso.** Tu personaje camina hasta lo que nombras, hace el gesto (talar, golpear, abrazar, dar la mano, empujar, arrodillarse, escribir, escuchar la radio…), usa sillas, camas, puertas y barcas, y la gente de alrededor **reacciona en el momento**: se enfada, se asusta, te devuelve el golpe, huye, se acerca o se encierra en casa. Lo vives con subtítulos y puedes cancelarlo moviéndote.
- **Cámara**: acerca y aleja con la **rueda del ratón**; al máximo, **primera persona**. En las conversaciones la cámara encuadra a la otra persona por encima de tu hombro.
- **Mando**: se puede jugar con mando (sticks, A saltar, X interactuar, Y hacer algo).
- **Sonido**: pasos según el suelo (hierba, arena, madera, agua), puertas, golpes, hacha y chapoteo.
- Ajustes de **campo de visión** e **invertir el eje vertical**.
- Las respuestas del diálogo se pueden elegir con las teclas **1 a 4**.

### Cambiado
- La gente y los textos hablan **español latino neutro** (ustedes, celular, carro…).
- **Interfaz nueva**:
  - Tipografía, colores, botones, paneles y animaciones nuevos.
  - HUD limpio: lugar y objetivo arriba a la izquierda, hora, tiempo y dinero arriba a la derecha, avisos en tarjetas, y la salud y las necesidades solo cuando importan.
  - **Ya no están los controles en pantalla.**
- **Conversaciones** con bandas de cine, la ocupación y el trato de la persona, lo dicho antes a la vista, texto que se escribe solo (se salta con clic o Espacio) y Esc para despedirse.
- Menú principal con el faro de fondo, pantallas de carga con consejos y ajustes por pestañas (tamaño de la interfaz y del texto, velocidad del texto).
- **E elige bien con qué interactúas**: lo que tienes delante y a la vista, con una sola indicación abajo en pantalla («[E] Hablar con Marina»). Una persona a la que miras gana a la silla de al lado, y una pared tapa lo que hay detrás.
- **Los PNJs hacen lo que dicen**: si alguien dice que se va o se encierra, la conversación termina y le ves marcharse y entrar en el edificio. Si echó el pestillo, la puerta no se abre hasta que se le pase. Solo recuerdan lo que pasó de verdad.
- El faro por dentro es más grande y Marina ya no tapa la salida. Samir ya no está encima de su silla.
- Los nombres de los PNJs se ven pequeños, solo de cerca y no a través de las paredes.

### Corregido
- Se podían atravesar sillas, sofás, camas, arbustos, barcas y lo que construías.
- Había agua dentro de las barcas.
- E a veces no hacía nada al hablar con alguien, o te sentaba en una silla cercana.
- La barra de controles se dibujaba debajo del diálogo.

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
