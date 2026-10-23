#!/usr/bin/env bash
# Desinstalador de hypr-wallpaper-picker

set -uo pipefail

HYPR_SCRIPTS="$HOME/.config/hypr/custom/scripts"
HYPR_KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
LAUNCHER_ACTIONS="$HOME/.config/illogical-impulse/actions"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }

for f in wallpaper_fetch.sh wallpaper_pick.sh wallpaper_apply.sh wallpaper_menu.sh wallpaper_gallery.py; do
    rm -f "$HYPR_SCRIPTS/$f"
done
info "Scripts eliminados"

rm -f "$LAUNCHER_ACTIONS/wallpaper" "$LAUNCHER_ACTIONS/wallpaper-gallery"
info "Acciones del launcher eliminadas"

if [[ -f "$HYPR_KEYBINDS" ]]; then
    sed -i '/Wallpaper: galeria con previews/d; /Wallpaper: elegir fondo online/d' "$HYPR_KEYBINDS"
    info "Atajos eliminados de $HYPR_KEYBINDS"
fi

command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1
info "Hecho"
