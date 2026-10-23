#!/usr/bin/env bash
# Muestra las previews de los wallpapers descargados y aplica el que elijas.
#
# Usa el selector de ficheros de KDE (el mismo que usa el shell) que muestra
# miniaturas, y al elegir se aplica el fondo + se regenera el tema.
#
# Uso: wallpaper_pick.sh [carpeta]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DIR="${1:-$HOME/Pictures/Wallpapers}"

command -v kdialog >/dev/null 2>&1 || {
    echo "kdialog no esta instalado" >&2
    exit 1
}

[[ -d "$DIR" ]] || { echo "No existe el directorio: $DIR" >&2; exit 1; }

# El selector se abre dentro de la carpeta para que muestre sus miniaturas
img=$(cd "$DIR" && kdialog --getopenfilename . --title "Elige wallpaper" 2>/dev/null)

[[ -z "$img" ]] && exit 0
[[ "$img" != /* ]] && img="$DIR/${img#./}"

"$SCRIPT_DIR/wallpaper_apply.sh" "$img"
