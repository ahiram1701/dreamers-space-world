# Changelog

Todos los cambios relevantes del proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [versionado semántico](https://semver.org/lang/es/).

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
