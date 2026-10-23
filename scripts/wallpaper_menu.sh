#!/usr/bin/env bash
# Menu de wallpapers online con previews.
#
# Flujo: eliges la fuente -> se descargan candidatos -> se abre el selector
# con miniaturas -> eliges uno -> se aplica el fondo y se regenera el tema.
#
# Uso:
#   wallpaper_menu.sh              -> menu
#   wallpaper_menu.sh <etiquetas>  -> busca esos tags y va directo al selector

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
FETCH="$SCRIPT_DIR/wallpaper_fetch.sh"
PICK="$SCRIPT_DIR/wallpaper_pick.sh"
WALLPAPER_DIR="$HOME/Pictures/Wallpapers"

notify() {
    command -v notify-send >/dev/null 2>&1 &&
        timeout 5 notify-send -a "Wallpapers" "$@" >/dev/null 2>&1
    return 0
}

# Con argumentos: busca y va directo al selector de previews
if [[ $# -gt 0 ]]; then
    "$FETCH" candidates all "$*" 16 >/dev/null 2>&1
    "$PICK" "$WALLPAPER_DIR"
    exit $?
fi

MENU=(
    "Galeria con previews (elige sin descargar)"
    "Wallhaven - general (paisajes, arte, 3D...)"
    "Wallhaven - anime"
    "Wallhaven - personas"
    "Wallhaven - toplist de la semana"
    "Wallhaven - buscar por etiquetas..."
    "Bing - imagen del dia"
    "Waypaper - visor de la carpeta"
)

menu() {
    printf '%s\n' "${MENU[@]}" |
        fuzzel --dmenu --prompt="Wallpaper > " --lines=10 2>/dev/null
}

# Descarga los candidatos y abre el selector con previews
pick_from() {
    local desc="$1"; shift
    notify "Descargando wallpapers..." "$desc"
    if ! "$FETCH" candidates "$@" >/dev/null 2>&1; then
        notify "No se pudieron descargar" "Revisa la conexion o prueba otra fuente"
        return 1
    fi
    "$PICK" "$WALLPAPER_DIR"
}

while true; do
    choice=$(menu)
    [[ -z "$choice" ]] && exit 0

    case "$choice" in
        "Galeria con previews (elige sin descargar)")
            "$SCRIPT_DIR/wallpaper_gallery.py" >/dev/null 2>&1 &
            ;;
        "Wallhaven - general (paisajes, arte, 3D...)")
            pick_from "general" general "" 16 ;;
        "Wallhaven - anime")
            pick_from "anime" anime "" 16 ;;
        "Wallhaven - personas")
            pick_from "personas" people "" 16 ;;
        "Wallhaven - toplist de la semana")
            pick_from "toplist" top "" 16 ;;
        "Wallhaven - buscar por etiquetas...")
            tags=$(printf '' | fuzzel --dmenu --prompt="Etiquetas > " 2>/dev/null)
            [[ -z "$tags" ]] && continue
            pick_from "buscando $tags" all "$tags" 16
            ;;
        "Bing - imagen del dia")
            notify "Descargando..." "Bing"
            if out=$("$FETCH" bing 2>/dev/null); then
                "$PICK" "$WALLPAPER_DIR"
            else
                notify "No se pudo descargar" "Bing"
            fi
            ;;
        "Waypaper - visor de la carpeta")
            waypaper >/dev/null 2>&1 &
            ;;
        *) exit 0 ;;
    esac

    exit 0
done
