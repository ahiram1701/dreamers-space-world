# Changelog

Todos los cambios relevantes del proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [0.8.0] - 2026-11-07

### Corregido
- **Los destellos blancos, por fin.** Eran píxeles NaN: en algunos puntos del suelo la normal quedaba a cero, al normalizarla salía NaN y el resplandor (glow) convertía ese único píxel en una mancha blanca enorme. Se veían en el campo de noche y en la orilla (el agua refleja lo que tiene debajo). El shader del suelo ya no puede dar NaN.
- Las estrellas eran una esfera fija en el centro del pueblo: lejos de él, algunas quedaban a ras de suelo, metidas en las colinas. Ahora el cielo va con la cámara y ninguna estrella baja de 8° sobre el horizonte. El agua refleja menos las farolas.
- **Tecla F:**
  - «Regreso al pueblo» funciona: desde otro planeta vas a tu nave, despegas y el piloto automático te deja en la plataforma del pueblo; sin nave, usas el Ancla si tiene energía. En el pueblo, te lleva caminando al sitio que digas, aunque esté lejos.
  - «Voy a dormir a mi casa» te lleva a casa, entras y te acuestas en tu cama. Antes te tumbabas en el suelo donde estabas.
  - «Súbete al auto» funciona aunque ya estés dentro del coche: la persona va hasta él y sube. Si no puede, lo dice.
  - F funciona también dentro de la nave y en el espacio (aterrizar, ir a un planeta, hablar con quien va a bordo).
- **La nave:**
  - Vas dentro, en la cabina, no sentado encima del casco. Quien te acompaña sube contigo, va dentro y baja contigo al aterrizar, en otro planeta o de vuelta en casa.
  - <kbd>V</kbd> cambia a la vista de cabina, con tablero, instrumentos y palanca.
- **El espacio ya no se traba:**
  - Shift es un crucero de 1,5 km/s; al soltarlo, la asistencia frena en unos segundos. Antes llegabas a 8 km/s y tardabas minutos en frenar.
  - Con algo delante, el crucero se corta solo. <kbd>X</kbd> frena en seco.
  - Un golpe ya no destroza el casco de una vez, y con el casco destrozado la nave sigue respondiendo a poca potencia para que puedas aterrizar.
  - Pulsar Esc mientras aterrizabas podía cerrar el juego.
- **El faro:** el techo tenía la escalera tapada y te dabas con la cabeza a media subida. Ahora tiene un hueco y un tubo hasta la trampilla de la linterna.
- **Edificios de dos plantas:** las tiendas, el café y la estación (y los edificios altos de los planetas) tienen escalera y planta de arriba, como las casas: mesas en el café, almacén en las tiendas y oficina en la estación.
- **Los coches del tráfico** ya no desaparecen a la vista: aparecen y se van cuando no los miras, aparcan al final de la calle y frenan ante otros coches. Hay hasta tres a la vez.
- Un coche rápido ya no cae del terreno por trozos: el suelo con colisión se prepara por delante y, si aún no está, el coche espera en vez de caer.

### Cambiado
- **Física de los coches:**
  - Más agarre (antes patinaban como en hielo) y tracción según el tipo: delantera los turismos, a las cuatro ruedas las camionetas y trasera los deportivos y camiones.
  - El motor pierde fuerza poco a poco cerca de la velocidad máxima, sin corte en seco.
  - Control de tracción, freno motor en las ruedas motrices, menos balanceo y sin trompos.
- **El espacio, más vivo:** lunas alrededor de los planetas, naves que van y vienen entre la estación y los planetas, polvo espacial que pasa a tu lado y el sol sólido y peligroso (calienta el casco). <kbd>G</kbd> activa el piloto automático al destino marcado.
- **Otros planetas:** al aterrizar hay un puesto avanzado con módulos, cajas, terminales y dos o tres personas, no solo naturaleza. Se ven sus lunas en el cielo y hay cosas que recoger según el planeta: cristales, obsidiana, fruta extraña…

### Añadido
- **El campo alrededor del pueblo:**
  - Caminos de tierra, hierba alta y praderas con flores.
  - Sitios a los que ir, que la IA conoce: la granja con ovejas y vacas en su corral, el lago con embarcadero y barca, el campamento con hoguera, las ruinas, el mirador de la montaña, la cabaña del pescador y el cruce de caminos con su poste de letreros.
  - Pájaros que vuelan en bandada de día.
- **Cosas que hacer:**
  - Pescar en el muelle o en el lago: coge la caña vieja de la cabaña del pescador y pulsa <kbd>E</kbd> cuando pique.
  - Recoger moras, setas, conchas o chatarra; vuelven a salir al día siguiente.
- **Música de verdad** (CC0, de OpenGameArt) que cambia con fundido según dónde estés: menú, pueblo de día y de noche, campo, cafetería, otros planetas, espacio y peligro. Sustituye a los acordes sintetizados. El volumen se ajusta en Ajustes → Música.

### Créditos
- Música: pistas CC0 de OpenGameArt (polosik, beardalaxy, Pro Sensory, isaiah658, congusbongus, yd, Centurion_of_war y otros); la lista completa está en `assets/CREDITS.md`.

## [0.7.2] - 2026-11-07

La v0.7.1 no llegó a publicarse con instalador: esta versión la incluye entera, con un arreglo.

### Corregido
- El terreno sin fin creaba la malla de cada trozo en un hilo de trabajo. Si la escena se cerraba mientras se generaba, podía dar errores y dejar memoria sin liberar. Ahora el hilo solo calcula los datos y la malla se crea en el hilo principal.

## [0.7.1] - 2026-11-06

### Añadido
- **El mundo no tiene borde.** Ya no caes al vacío al llegar al final del mapa: el terreno se genera por trozos a tu alrededor mientras caminas, conduces o vuelas, y se suelta al alejarte.
  - Más allá del pueblo hay colinas con pinos y, lejos tierra adentro, montañas con roca y nieve.
  - Al este, el mar no se acaba y aparecen islas con palmeras.
  - En los planetas pasa lo mismo: el relieve crece hasta montañas y, en los planetas océano, hay mar abierto con islas.
- **Coches de verdad:** modelos del Car Kit de Kenney (CC0) con ruedas que giran, suspensión y volante.
  - Sedán, camioneta, furgoneta, taxi y SUV en el pueblo; la IA puede usar también deportivo, compacto, patrulla, ambulancia, bomberos, camión de reparto, de la basura, tractor y coche de carreras.
  - El tráfico de la calle usa los mismos modelos y frena ante cualquiera que tenga delante.
- **Conducir se siente mejor:**
  - Cámara de persecución que sigue al vehículo, no choca con él y da sensación de velocidad.
  - Marchas automáticas, freno de mano (<kbd>Espacio</kbd>) para derrapar, volante que vuelve solo al centro y gatillos del mando para acelerar y frenar.
  - Faros que se encienden de noche y con lluvia.
- **Los vehículos suenan:** el motor se sintetiza en tiempo real y sube de vueltas al acelerar; ruido de neumáticos, derrape, claxon (<kbd>H</kbd>) y golpes según su fuerza. Las naves zumban como una turbina.
- **Choques y atropellos con consecuencias:**
  - Contra algo duro, el coche se abolla, echa humo y, muy dañado, deja de arrancar. Si el golpe es fuerte, saltan piezas.
  - Si atropellas a alguien, sale despedido, cae, se queda en el suelo y se levanta cojeando. Lo recuerda y quien lo vea lo cuenta; un golpe muy fuerte lo manda unos días a la clínica.
  - Con el claxon, la gente que tienes delante se aparta.
- **Pasajeros:** quien te acompaña se sube contigo al coche y baja contigo. Puedes decirle a alguien «súbete al auto», y lo hace si hay un coche cerca con sitio.
- **Naves de Quaternius (CC0):** la lanzadera vieja es ahora una nave de verdad.
  - En un planeta se pilota apuntando con el ratón y tiene gravedad: sin combustible, cae.
  - En el espacio, el ratón cabecea y gira, <kbd>A</kbd>/<kbd>D</kbd> alabean y <kbd>Z</kbd> enciende o apaga la asistencia de vuelo.
  - <kbd>Tab</kbd> elige destino y una flecha en pantalla te lleva hasta él.
- **Casas ajenas de verdad:**
  - Se puede comer de la nevera, beber y ducharse. Si te invitaron, bien. Si te ven sin permiso, no les gusta y lo cuentan. Si no te ve nadie, al volver notan que falta comida, sin saber quién fue.
  - Dormir en la cama de otro tiene consecuencias. Si su dueño llega a acostarse, te despierta y reacciona según cómo os llevéis. Si te vio alguien de la casa, se lo cuenta. Si no, encuentra la cama deshecha.
- **Te atienden en la cafetería:** hay un mesero o mesera que viene a tu mesa cuando te sientas, te toma nota, va a la barra y te trae el pedido en una bandeja. Teo sigue detrás de la barra.
- **El faro, rehecho:**
  - Puerta de madera con marco de piedra y escalones para subir al zócalo.
  - Dentro, la escalera de caracol tiene barandilla y sube por una trampilla hasta el balcón de la linterna, a 19 m sobre el mar, que antes no llevaba a ningún sitio.
  - Marina tiene cocina.
- **La gente lleva en la mano lo que usa:** si barre, una escoba; si limpia, un trapo; si lee, un libro; si toma café, una taza; si sirve, una bandeja.

### Cambiado
- **Los puntos de interés de los planetas son cosas reales,** según lo que son: una antena con luz roja, restos de una nave medio enterrada, un cráter, un campamento, ruinas, un monolito o un mojón de piedras. Antes eran pilares naranjas y azules brillantes. Cada uno tiene un letrero de madera que se lee de cerca; el punto de recarga del Ancla es una terminal.
- **Al aterrizar** la nave se posa en un claro (en casa, en la plataforma de despegue) y apareces a su lado. Antes podías aparecer lejos o atorado.
- **La IA no inventa lo que no hay:**
  - Con <kbd>F</kbd> y al hablar, sabe dónde está cada persona, qué hace, qué lleva en la mano, su ropa y qué vehículos hay cerca.
  - Una narración que le pone a alguien un objeto que no lleva, o lo sitúa donde no está, se corrige antes de mostrarse.
- Los vehículos ya no llevan su nombre flotando encima, y los letreros de las tiendas no se ven cuando la cámara pasa pegada a ellos.

### Corregido
- La nave tenía una pared invisible alrededor: chocaba como una caja enorme que incluía las alas. Ahora choca con su forma (fuselaje y alas) y se puede pasar junto a ella y bajo las alas.
- En el espacio se atravesaban los asteroides, los planetas y la estación. Ahora son sólidos y los golpes dañan el casco.
- Marina decía que te había pillado dentro del faro aunque estaba en la playa. Ahora solo te pilla quien está dentro de verdad.
- Destellos blancos de día: los faros de los vehículos brillaban siempre y el resplandor de la imagen los convertía en manchas. Ahora solo se encienden de noche o con lluvia, y el resplandor es menos sensible.

### Créditos
- Coches: [Car Kit](https://kenney.nl/assets/car-kit) de Kenney (CC0).
- Naves: [Ultimate Spaceships](https://quaternius.com/packs/ultimatespaceships.html) de Quaternius (CC0).

## [0.7.0] - 2026-11-06

### Añadido
- **Agente creador: la IA programa el mundo mientras juegas.** Con <kbd>F</kbd> («construyo un carrito con ruedas», «hago una caseta con puerta», «pongo un farol junto a la banca») la IA ya no responde de una vez: trabaja paso a paso con herramientas, como un programador dentro del juego.
  - Mira alrededor, busca entre 299 modelos 3D (muebles, plantas, barcos, herramientas, edificios, sci-fi…) y crea piezas a escala real (caja, cilindro, esfera, cápsula, cono, toro, rampa, rueda) con material: madera, metal, vidrio, tela, piedra, plástico, goma, pintura o luz.
  - Les da comportamientos: asiento, cama, baúl, luz, fuego, puerta que abre, letrero, máquina (entra algo y sale otra cosa), física, flotar, sonido, ruedas, motor, pedales, propulsor y cabina.
  - Revisa cómo quedó y corrige. Si se equivoca, la herramienta le dice qué está mal.
  - Gasta los materiales que lleves, y si falta algo lo dice.
  - Todo se guarda y sigue ahí cuando vuelves.
  - No puede romper la partida ni tocar nada fuera del juego.
- **Reglas** para lo que creas, sin código: «si llueve, enciende la luz del porche», «de noche, cierra la puerta», «cuando me acerque, suena».
- **Vehículos con física real:** sedán, camioneta, furgoneta, moto, bici y lancha.
  - Aceleran como un coche de verdad, giran, frenan, gastan gasolina, chocan y se quedan donde los dejas.
  - En el pueblo hay coches aparcados de los vecinos; llevarte uno ajeno es robo y el dueño se entera.
  - Tienes tu propia bici junto a casa, y Marina tiene una lancha en el muelle.
  - De vez en cuando pasa un coche por la calle, por su carril, y frena si estás delante.
  - Lo que inventa la IA con ruedas y motor (o pedales) también se conduce; con flotador y motor, es una lancha.
- **Naves y espacio:**
  - En la plataforma de despegue, al oeste del pueblo, hay una lanzadera vieja.
  - Despega en vertical (<kbd>Espacio</kbd> sube, <kbd>Ctrl</kbd>/<kbd>Q</kbd> baja) y, al salir de la atmósfera, estás en el espacio.
  - Tu sistema solar tiene sol, 5–7 planetas (templados, desiertos, hielo, selva, océano, volcanes, cristal, gigantes gaseosos con anillos), un cinturón de asteroides y una estación orbital.
  - <kbd>Shift</kbd> activa el modo crucero.
  - Al acercarte, <kbd>E</kbd> para aterrizar: la superficie de cada planeta se genera la primera vez, con su gravedad, y tu nave queda aparcada a tu lado.
  - La IA también puede construir naves (propulsor + cabina).
- **Ropa por prendas:** impermeable, abrigo, chamarra, suéter, chaleco, delantal, bufanda, gorra, sombrero, gorro, mochila y lentes, encima de la ropa de siempre y moviéndose con el cuerpo.
  - La gente se viste según el tiempo: con lluvia, impermeable; de noche, abrigo. Dentro de casa se lo quita.
  - Cada quien lleva la de su oficio (el barista, delantal).
  - En los abarrotes venden prendas, que te pones y te quitas desde el inventario.
- **El pueblo se conoce:** cada vecino sabe quién vive y trabaja en el pueblo, si es hombre o mujer, su edad y su oficio. Recuerda de qué ha charlado con los demás. Teo ya sabe quién es Samir.

### Cambiado
- **Lo que un PNJ narra que hace, lo hace:** «da un sorbo al café» bebe, «señala el faro» señala hacia el faro, «se acerca a la ventana» da unos pasos, «se pone el abrigo» se lo pone. Lo que no se puede hacer en el juego ya no se muestra.
- **La IA solo menciona lo que existe:**
  - Sabe qué ropa lleva cada uno (y tú). Ya no se ajusta un impermeable que no lleva ni te pide dejar un abrigo que no traes.
  - Sabe qué hay alrededor (farolas, toldos, macetas, buzones, bancas, el mar) y qué no: la cafetería no tiene toldo.
- **Nombres y oficios coherentes:** el oficio va en el género de la persona y la edad casa con el oficio. Nadie es «maestra jubilada» llamándose Joaquín ni jubilado con 30 años.

## [0.6.6] - 2026-11-05

### Añadido
- **Instalador de Windows:** `DreamersSpaceWorld-Setup-vX.Y.Z.exe` con el logo del juego.
  - Se instala solo para tu usuario, sin pedir permisos de administrador.
  - Crea accesos en el menú Inicio (y, si quieres, en el escritorio) y al terminar ofrece abrir el juego.
  - Se desinstala desde *Aplicaciones instaladas*. Tus partidas solo se borran si lo marcas.
  - El juego instalado se sigue actualizando solo desde el menú.
- **Logo propio:** un faro bajo la luna y una órbita. Lo lleva el .exe, la ventana y la pantalla de arranque, en lugar del logo de Godot. Ya hay un solo ejecutable (sin el `.console.exe`).
- **Tocar la puerta:**
  - En una casa ajena ya no se entra como si nada: tocas y sale a abrir quien esté despierto.
  - Te invita a pasar según cómo le caes, la hora y lo que le digas; si no, te atiende en el umbral.
  - Si nadie abre, «No abre nadie». Si estaban dormidos, alguien puede despertarse de mal humor.
  - Los negocios cerrados no dejan entrar, aunque a veces el dueño, que aún anda dentro, te deja pasar un momento.
- **Forzar la puerta o colarse por una ventana** (de noche), con E después de tocar o con F:
  - Hace ruido: quienes están dentro o pasan cerca pueden oírte, y lo cuentan.
  - El dueño no te deja volver a entrar durante días.
  - Con una barreta o un martillo es más rápido y más silencioso.
- **Subir al techo con F** («subo al techo de mi casa») y bajar («me bajo del techo»).
  - Hasta unos 7 m se trepa; más alto hace falta una escalera de mano, que se vende en la ferretería (igual que la barreta).
  - Con F también puedes subirte encima de una banca o una roca.
- **Los PNJ caminan por una malla de navegación:** buscan un camino que rodea paredes, muebles y árboles en vez de ir en línea recta y chocar.

### Cambiado
- **En el diálogo, lo que el PNJ hace va aparte**, en cursiva y en tercera persona: *(Da un sorbo al café y mira hacia la escalera.)*. Su frase es solo lo que dice. Lo que escribes entre asteriscos cuenta como lo que haces.
- **La IA sabe qué ropa llevas** (prenda, colores y que no llevas abrigo ni sombrero) **y cómo es cada sitio por dentro** (el faro tiene una sola puerta). Ya no se inventa ropa ni puertas.

### Arreglado
- **Las bolas blancas de noche:** la luz de cada farola estaba dentro de su propio farol y quemaba el cristal a blanco. Ahora la luz va debajo del farol y el cristal brilla suave.
- **La orilla parpadeaba al moverte:** la espuma latía según la posición de la cámara. Ahora late según su sitio en el mundo, y el agua refleja menos como un espejo.
- **La estación cerrada tenía las ventanas encendidas;** ahora está a oscuras.
- **Comprar café y galletas solo daba el café:** el juego los tomaba por el mismo objeto. Ahora se compara el nombre entero, y lo que compras siempre llega aunque ya tengas otro igual.
- **El celular contaba lo que ya habíais hablado:** Samir te escribía «alguien entró en mi casa» aunque eras tú y charlasteis.
- **Un PNJ se sentaba en el aire:** ahora solo se sienta si hay una silla o una banca cerca; si no, se queda de pie.
- **Los PNJ chocaban sin parar con lo que tenían delante:** además de seguir el camino de la malla, cuando chocan rodean el obstáculo por el lado que acerca al destino, no al azar.

## [0.6.5] - 2026-11-03

### Añadido
- **Locales de verdad:** abarrotes, fonda, farmacia y ferretería en el centro del pueblo, con quien atiende en su horario y una lista de precios.
  - Lo que compras es un objeto real: el pan se come, el agua se bebe, las vendas curan, y el hacha o la pala hacen que las veas en tu mano al usarlas.
  - **En la fonda y en la cafetería pides de la carta**, te sientas, te traen el plato a la mesa, comes y se te quita el hambre.
  - En los mundos generados hay negocios propios de su época: taberna y mercado en la Antigüedad, botica en el siglo XIX, cantina en el futuro… Los sitios que crea la IA también tienen quien atienda y algo que comprar.
- **Edificios más realistas:**
  - **Interiores por cuartos:** recámara, baño, sala-comedor y cocina separados por tabiques.
  - **Casas de dos plantas** con escalera (se sube andando) y las recámaras arriba.
  - **Fachadas con detalle:** escalón, macetas con flores, buzones, y en los negocios toldo de rayas y letrero colgante.
  - **Ventanas con vida:** de noche se encienden solo si hay alguien despierto dentro o el negocio está abierto, y se apagan cuando se acuestan.
  - La puerta queda donde el edificio tiene la suya.
- **Dormir o esperar hasta una hora con F:** «duermo hasta las 3:30», «espero hasta las 7 de la tarde», «echo una siesta de 2 horas». En una cama descansas del todo; en el suelo, la mitad, y te levantas entumecido/a. Funciona aunque la IA no responda.
- **La linterna se ve en tu mano**, y la luz sale de ella y alumbra hacia donde apuntas.
- **Paso a nivel** donde la calle cruza las vías, con cruces de San Andrés y señales.

### Cambiado
- **El faro está apagado**, como dice la historia: solo a las 3:33 un pulso lo enciende unos segundos (más fuerte cuando se acerca el Despertar).
- **El objetivo dice a quién buscar:** «Habla con Marina, Teo y Samir (1/3) · falta: Samir».
- **Lo que les cuentan otros es un rumor:** los PNJ ya no confunden algo que le pasó a otro con algo que vivieron ellos.
- **Si le dices a alguien que no notaste nada**, te cree y no habla como si lo hubieras vivido.
- Cuando dos personas charlan contigo delante (o en la misma habitación), te hablan a ti o cambian de tema, en vez de hablar de ti como si no estuvieras.
- Al cansarte, el personaje se estira y bosteza con la cabeza hacia atrás, en vez de quedarse cabizbajo. Agacharse con F ya no te deja agachado, y al colgar el celular el otro también deja de hablar por teléfono.

### Corregido
- **Las vías del tren pasaban por debajo de casas:** ya no se construye nada encima. El resto del pueblo y el número de cada casa no cambian.
- **Luces blancas que aparecían y desaparecían de noche:** eran bocadillos de texto de gente lejana. Ahora no se ven a más de 22 m, y los letreros se desvanecen a lo lejos sin brillar.
- Al dormir, el descanso ya no se gastaba mientras dormías.

## [0.6.4] - 2026-10-31

### Añadido
- **La gente vive en sus casas.** Cada casa tiene su hogar: una persona sola, una pareja, una familia con hijos o una pareja mayor, siempre los mismos. Al entrar los ves haciendo lo que toca por la hora: de noche duermen en sus camas, por la mañana desayunan, a mediodía cocinan y comen, por la tarde leen o ven la tele. Quien trabaja fuera no está en su horario, y los niños están en la escuela.
- **Lo que ves entrar, está dentro.** La gente de paso que entra en una casa o en la cafetería ya no desaparece: la encuentras dentro, de visita o tomando algo.
- Los vecinos **se van a dormir a su casa** caminando, y si llegas antes que ellos, entran y se acuestan. Si a alguien se le acaba su rato dentro estando tú, se despide y sale por la puerta.
- Si entras en una casa ajena, quien vive ahí reacciona según la hora y si te conoce («¿Quién eres? ¿Qué haces en mi casa?»). Si duermen, no se enteran… salvo que les hables.
- **Más opciones de aspecto:** tono de piel, peinado (13 entre hombre y mujer), color de pelo, altura (de 1,55 a 1,95 m) y complexión baja. La gente del pueblo también tiene ahora tonos de piel variados.
- **La ropa es tuya:** empiezas con la que elegiste y una muda en el armario de casa. Te cambias en el armario, y en la nueva **tienda de ropa** del centro compras y te pruebas conjuntos (cambian cada día).
- **Peluquería:** te cortas el pelo o te lo tiñes, pagando.
- **Tu cuerpo se nota:** la lluvia te moja y luego te secas (la ropa mojada se oscurece y brilla); talar, cavar o trabajar te ensucian, y la ducha te limpia. Con las semanas, según comas y te muevas, tu complexión cambia un poco. La gente lo ve y lo comenta.

### Cambiado
- Las herramientas **se agarran por el mango**: el hacha, la pala o el remo ya no atraviesan el brazo. Con las dos manos (talar, cavar, remar), la otra mano va al mango, y los dedos se cierran alrededor de lo que sujetas. Al beber, la botella llega a la boca, y el celular a la oreja al llamar.
- Solo se ve la herramienta si la tienes: sin hacha, talas con las manos vacías (en el trabajo te dan las suyas).
- «Tu aspecto» en la pausa ahora solo corrige rasgos del cuerpo; la ropa y el pelo se cambian en el mundo.

### Corregido
- **Quedarse atrapado al salir de una casa:** ahora apareces siempre en un hueco libre, ningún arbusto tapa una puerta y, si te quedas metido dentro de algo, te despegas al intentar moverte.
- «Me voy a mi casa» llevaba a cualquiera a la primera casa del pueblo; ahora cada uno va a la suya.
- El objetivo «Habla con tus vecinos» ya no cuenta a la gente que conoces por el camino.

## [0.6.3] - 2026-10-31

### Añadido
- **Crea tu personaje** antes de empezar una vida nueva: nombre, hombre o mujer, complexión, ropa y colores, con una vista previa en 3D que gira. Ya no apareces con un aspecto al azar.
- **Tu aspecto** en el menú de pausa: cambia cómo te ves sin salir de la partida. Cada vida guarda su propio aspecto.

### Cambiado
- **Los ajustes se aplican al momento**, en plena partida: la calidad gráfica (efectos, hierba, lluvia, sombras de las luces) y el tamaño del texto, también en los textos con tamaño propio.
- **Conversaciones que dejan ver**: el panel es más bajo y algo transparente, las respuestas van en dos columnas, el historial se pliega tras un botón y la cámara encuadra la cara de quien te habla por encima del panel.

### Corregido
- **Al correr parecía que cruzabas los brazos**: ahora los brazos van hacia delante y hacia atrás junto al cuerpo. Los gestos (celular, beber, pensar) conservan su postura.
- «Tu personaje» ya no está en Ajustes: se elige al crear la vida o en la pausa.

## [0.6.2] - 2026-10-31

### Añadido
- **«Llévame a…»**: la gente te lleva de verdad a un sitio. Te dice «Sígueme», camina delante, te espera si te quedas atrás («¿Vienes?») y te lo señala al llegar. Si no existe, te lo dice.
- La gente **sale y entra por las puertas** al moverse: ya no se queda atascada dentro de un edificio.
- Con lluvia, los vecinos que estaban fuera **se resguardan** bajo un alero.
- Si llamas a alguien que está en la escena, se le ve con el celular en la oreja.

### Corregido
- **Te escribían al celular estando a tu lado**, o justo después de hablar. Ahora no te escriben ni te llaman si estás con esa persona (te lo dice en persona), ni se inventan encuentros.
- Al volver a hablar con alguien poco después, ya no te saluda como si no te hubiera visto: recuerda lo que acaban de hablar.
- **Posturas de los brazos**: el codo se doblaba hacia fuera. Al mirar el celular ya no levantas los brazos, y beber, pensar, cruzar los brazos o caminar se ven naturales.

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
