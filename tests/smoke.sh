#!/usr/bin/env bash
# Arranca las escenas principales sin ventana y falla si Godot imprime errores.
# Godot no cambia el código de salida ante errores de GDScript, así que hay que leer la salida.
#   bash tests/smoke.sh        (requiere `godot` en el PATH, o GODOT=/ruta/al/binario)
set -uo pipefail

GODOT="${GODOT:-godot}"
SCENES=(
	"res://scenes/main_menu/MainMenu.tscn"
	"res://scenes/act0_town/Act0Town.tscn"
	"res://scenes/dev/AITestScene.tscn"
	"res://scenes/generated_location/GeneratedLocation.tscn"
)
IGNORE='Parameter "m" is null'  # mesh_get_surface_count en servers/rendering/dummy
status=0

for scene in "${SCENES[@]}"; do
	echo "::group::$scene"
	log="$("$GODOT" --headless --path . "$scene" --quit-after 300 2>&1)"
	echo "$log"
	echo "::endgroup::"
	# Ruido conocido del renderizador "dummy" de --headless: no son errores del juego
	errors="$(grep -E 'SCRIPT ERROR|Parse Error|ERROR:' <<<"$log" | grep -vE "$IGNORE" || true)"
	if [[ -n "$errors" ]]; then
		echo "$errors" | sort | uniq -c
		echo "::error::Errores al ejecutar $scene"
		status=1
	else
		echo "✔ $scene"
	fi
done

exit $status
