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
)
status=0

for scene in "${SCENES[@]}"; do
	echo "::group::$scene"
	log="$("$GODOT" --headless --path . "$scene" --quit-after 300 2>&1)"
	echo "$log"
	echo "::endgroup::"
	if grep -qE 'SCRIPT ERROR|Parse Error|ERROR:' <<<"$log"; then
		echo "::error::Errores al ejecutar $scene"
		status=1
	else
		echo "✔ $scene"
	fi
done

exit $status
