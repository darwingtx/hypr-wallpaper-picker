#!/usr/bin/env bash
# Aplica un wallpaper al shell (Noctalia / illogical-impulse) y regenera el tema
# Material You.
#
# Delega en switchwall.sh (el script de illogical-impulse) que:
#   - fija el fondo del shell
#   - ejecuta matugen para derivar la paleta de la imagen
#   - aplica los colores a terminal, apps Qt y shell
#
# Uso: wallpaper_apply.sh /ruta/a/imagen.jpg

set -uo pipefail

img="${1:-}"
if [[ -z "$img" ]]; then
    echo "uso: wallpaper_apply.sh <imagen>" >&2
    exit 1
fi
if [[ ! -f "$img" ]]; then
    echo "no existe el fichero: $img" >&2
    exit 1
fi

# El script de los dotfiles vive en ~/.config/quickshell/<config>/scripts/colors/
switchwall=$(ls -1 "$HOME"/.config/quickshell/*/scripts/colors/switchwall.sh 2>/dev/null | head -1)
if [[ -z "$switchwall" ]]; then
    echo "No se encontro switchwall.sh" >&2
    exit 1
fi

# switchwall.sh usa el venv del shell para generar los colores
export ILLOGICAL_IMPULSE_VIRTUAL_ENV="${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"

# Respeta el modo claro/oscuro actual
mode="light"
if gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -q "dark"; then
    mode="dark"
fi

# Solo una aplicacion a la vez: varias en paralelo saturan el servidor de
# notificaciones del shell y se quedan colgadas.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/wallpaper-apply.lock"
exec 9>"$LOCK" 2>/dev/null
if command -v flock >/dev/null 2>&1; then
    flock 9
fi

"$switchwall" --image "$img" --mode "$mode"
