<div align="center">

# 🌌 Dreamer's Space World

**Todos empiezan igual. Nadie termina en el mismo universo.**

Juego 3D de mundo abierto sobre multiversos y viajes en el tiempo, donde una IA genera,<br>
a partir de tus decisiones, un mundo **único y persistente** para cada jugador.

[![CI](https://github.com/ahiram1701/dreamers-space-world/actions/workflows/ci.yml/badge.svg)](https://github.com/ahiram1701/dreamers-space-world/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ahiram1701/dreamers-space-world?include_prereleases&label=release)](https://github.com/ahiram1701/dreamers-space-world/releases)
[![Godot](https://img.shields.io/badge/Godot-4.3-478cbf?logo=godotengine&logoColor=white)](https://godotengine.org)
[![IA](https://img.shields.io/badge/IA-Ollama%20Cloud-black)](https://ollama.com)
[![Licencia](https://img.shields.io/badge/licencia-todos%20los%20derechos%20reservados-lightgrey)](LICENSE)

</div>

---

## ✨ La idea

Todos los jugadores descargan el mismo juego y empiezan con la misma vida: una **persona común** en un pueblo costero del presente. Pero cada conversación, cada decisión y cada palabra que escribes queda registrada. A partir de ahí, la IA **crea contenido nuevo y permanente**: personas, lugares, objetos y, más adelante, épocas y universos enteros.

Tras unas horas de juego, tu copia del juego ya no se parece a la de nadie más.

## 🧠 Principio de diseño: *la IA diseña, el motor construye*

Un modelo de lenguaje no puede generar en tiempo real modelos 3D ni código fiable, pero sí puede **diseñar contenido como datos**:

1. El juego trae una **biblioteca de piezas** ([`data/archetypes.json`](data/archetypes.json)): biomas, tipos de cuerpo, emociones, efectos de objetos…
2. La IA devuelve **definiciones JSON** que combinan esas piezas, limitadas por un *JSON schema*.
3. Un **validador** comprueba cada definición y, si algo falla, se lo devuelve a la IA para que se corrija sola.
4. El motor la construye y la guarda en el **mundo persistente del jugador**.

```mermaid
flowchart LR
    J([Jugador]) -->|elige o escribe| SD[StoryDirector]
    SD -->|prompt + memoria + perfil| AI[AIClient<br/>Ollama Cloud]
    AI -->|JSON| V{ContentValidator}
    V -->|errores| AI
    V -->|válido| DB[(WorldDB<br/>mundo del jugador)]
    V -.->|2 fallos| FB[Contenido de respaldo]
    DB --> M[NPCMemory · PlayerProfile]
    M --> SD
```

Si la IA no está disponible, el juego usa contenido de respaldo y **nunca se queda bloqueado**.

## 🎮 Estado actual

| | Funcionalidad |
|---|---|
| ✅ | Cliente de Ollama Cloud con salida estructurada, reintentos y modo *mock* sin red |
| ✅ | Validación de entidades (PNJs, lugares, objetos, turnos de diálogo) con autocorrección |
| ✅ | Mundo persistente por jugador, con el origen de cada entidad registrado |
| ✅ | **Acto 0 — Bahía de las Horas**: pueblo 3D, jugador en tercera persona, 3 vecinos |
| ✅ | Conversaciones generadas por IA con opciones **o texto libre** |
| ✅ | Memoria de PNJs (hechos, relación) y perfil del jugador inferido de sus decisiones |
| 🔜 | El Despertar, árbol de líneas temporales y primer salto |
| 🔜 | Generación procedural de lugares, planetas y PNJs a partir de las definiciones de la IA |
| 🔜 | Nave, espacio, pregeneración en segundo plano y efectos de paradoja |

## 🚀 Jugar

### Descargar
Descarga la última versión para **Windows** o **Linux** desde [Releases](https://github.com/ahiram1701/dreamers-space-world/releases), descomprímela y ejecútala.

### Desde el código
1. Instala [Godot 4.3+](https://godotengine.org/download) (versión estándar).
2. Clona el repositorio y abre `project.godot`.
3. Pulsa <kbd>F5</kbd>.

### Configurar la IA
1. Crea una API key en [ollama.com](https://ollama.com) (Ollama Cloud).
2. En el menú, abre **Ajustes de IA**, pega la key y pulsa *Guardar ajustes*.
3. Si no tienes key, marca **Modo mock** para jugar con respuestas predefinidas.

> 🔒 La key se guarda **cifrada y ligada a tu equipo** en la carpeta de usuario de Godot (`user://`). Nunca entra en el repositorio.

### Controles
| Acción | Tecla |
|---|---|
| Moverse / correr | <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> / <kbd>Shift</kbd> |
| Saltar | <kbd>Espacio</kbd> |
| Cámara | Ratón |
| Hablar | <kbd>E</kbd> |
| Soltar el ratón | <kbd>Esc</kbd> |

## 🏗️ Arquitectura

| Autoload | Responsabilidad |
|---|---|
| [`Settings`](autoload/Settings.gd) | API key cifrada, modelo, idioma y modo mock |
| [`AIClient`](autoload/AIClient.gd) | `POST /api/chat` a Ollama Cloud con *JSON schema* y reintentos |
| [`ContentValidator`](autoload/ContentValidator.gd) | Única fuente de verdad del formato de cada entidad: valida y genera el schema |
| [`WorldDB`](autoload/WorldDB.gd) | El mundo único de cada jugador (`user://worlds/<id>/`) |
| [`ContentGenerator`](autoload/ContentGenerator.gd) | IA → validar → autocorregir → respaldo → guardar |
| [`StoryDirector`](autoload/StoryDirector.gd) | Conversaciones turno a turno con los PNJs |
| [`NPCMemory`](autoload/NPCMemory.gd) | Lo que cada PNJ recuerda del jugador |
| [`PlayerProfile`](autoload/PlayerProfile.gd) | Carácter del jugador inferido de cómo juega |

```
autoload/      Sistemas globales (IA, mundo, memoria, narrativa)
data/          Reglas del multiverso, piezas, PNJs base y contenido de respaldo
scenes/        Menú principal, Acto 0, UI y herramientas de desarrollo
scripts/       Jugador y PNJs
tests/         Pruebas unitarias y smoke test
.github/       CI y publicación automática
```

## 🧪 Pruebas

```bash
godot --headless --import --path .
godot --headless --path . -s tests/test_validator.gd   # pruebas unitarias
bash tests/smoke.sh                                    # arranca las escenas y busca errores de script
```

La [CI](.github/workflows/ci.yml) ejecuta todo esto en cada push y en cada pull request.

## 📦 Publicar una versión

```bash
git tag v0.2.0
git push origin v0.2.0
```

El workflow de [release](.github/workflows/release.yml) pasa las pruebas, exporta las builds de Windows y Linux con Godot y publica una Release en GitHub. Los tags con sufijo (`-alpha`, `-beta`, `-rc`) se publican como *pre-release*.

## 📄 Licencia

© 2026 ahiram1701. **Todos los derechos reservados.** El código se publica solo para consulta; consulta [LICENSE](LICENSE).
