# Dreamer's Space World

Juego 3D de mundo abierto (Godot 4) sobre multiversos y viajes en el tiempo. Todos empiezan como una persona común; la IA (Ollama Cloud) **genera contenido nuevo y persistente** según tus decisiones, así que cada copia del juego termina siendo un mundo distinto.

## Principio: la IA diseña, el motor construye
La IA devuelve **definiciones JSON** (PNJs, lugares, objetos…) que combinan piezas de [data/archetypes.json](data/archetypes.json). [ContentValidator](autoload/ContentValidator.gd) las valida, [WorldDB](autoload/WorldDB.gd) las guarda en `user://worlds/<id>/world.json` y el motor las construye.

| Autoload | Función |
|---|---|
| `Settings` | API key cifrada en `user://`, modelo, modo mock |
| `AIClient` | `POST https://ollama.com/api/chat` con JSON schema |
| `ContentValidator` | Esquemas de entidades → validación + JSON schema |
| `WorldDB` | El mundo único de cada jugador |
| `ContentGenerator` | IA → validar → autocorregir → respaldo → guardar |
| `NPCMemory` | Qué recuerda cada PNJ de ti (hechos, relación) |
| `PlayerProfile` | Tu carácter inferido de lo que dices y eliges |
| `StoryDirector` | Conversaciones turno a turno con los PNJs |

## Empezar
1. Instala Godot 4.3+ y abre `project.godot`.
2. En *Ajustes de IA* pega tu API key de Ollama Cloud y pulsa *Guardar ajustes* (o marca *Modo mock* para probar sin red).
3. Vuelve al menú, escribe tu nombre y pulsa **Nueva vida**.

**Acto 0 — Bahía de las Horas:** WASD para moverte, Shift para correr, Espacio para saltar, ratón para la cámara, **E** para hablar y Esc para soltar el ratón. Habla con Marina (faro), Teo (cafetería) y Samir (estación). Puedes elegir una respuesta o escribir la tuya.

Pruebas: `godot --headless --path . -s tests/test_validator.gd`
