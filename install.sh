#!/usr/bin/env bash
# Instalador de hypr-wallpaper-picker
#
# Copia los scripts, añade los atajos y registra las acciones del launcher.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
HYPR_SCRIPTS="$HOME/.config/hypr/custom/scripts"
HYPR_KEYBINDS="$HOME/.config/hypr/custom/keybinds.lua"
LAUNCHER_ACTIONS="$HOME/.config/illogical-impulse/actions"

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m::\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m::\033[0m %s\n' "$*" >&2; }

# --- dependencias ----------------------------------------------------------
missing=()
for cmd in curl jq magick fuzzel; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Faltan comandos: ${missing[*]}"
    warn "Instalalos con: sudo pacman -S ${missing[*]}"
fi

if ! python3 -c "import gi; gi.require_version('Gtk','4.0')" >/dev/null 2>&1; then
    warn "Falta python-gobject con GTK4 (necesario para la galeria)"
    warn "Instalalo con: sudo pacman -S python-gobject gtk4"
fi

# --- scripts ---------------------------------------------------------------
mkdir -p "$HYPR_SCRIPTS"
for f in "$REPO_DIR"/scripts/*; do
    cp -f "$f" "$HYPR_SCRIPTS/"
    chmod +x "$HYPR_SCRIPTS/$(basename "$f")"
done
info "Scripts instalados en $HYPR_SCRIPTS"

# --- acciones del launcher -------------------------------------------------
mkdir -p "$LAUNCHER_ACTIONS"
for f in "$REPO_DIR"/hypr/actions/*; do
    cp -f "$f" "$LAUNCHER_ACTIONS/"
    chmod +x "$LAUNCHER_ACTIONS/$(basename "$f")"
done
info "Acciones del launcher instaladas en $LAUNCHER_ACTIONS"

# --- atajos ----------------------------------------------------------------
mkdir -p "$(dirname "$HYPR_KEYBINDS")"
touch "$HYPR_KEYBINDS"
added=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! grep -qF "$line" "$HYPR_KEYBINDS"; then
        printf '\n%s\n' "$line" >>"$HYPR_KEYBINDS"
        added=1
    fi
done < <(grep '^hl\.bind' "$REPO_DIR/hypr/keybinds.snippet.lua")
if [[ $added -eq 1 ]]; then
    info "Atajos añadidos a $HYPR_KEYBINDS"
else
    info "Los atajos ya estaban en $HYPR_KEYBINDS"
fi

# --- wallpaper config ------------------------------------------------------
mkdir -p "$HOME/.config/waypaper"
if [[ -f "$HOME/.config/waypaper/config.ini" ]]; then
    if ! grep -q "wallpaper_apply.sh" "$HOME/.config/waypaper/config.ini"; then
        warn "Para que waypaper tambien regenere el tema, en ~/.config/waypaper/config.ini usa:"
        warn "  backend = none"
        warn "  post_command = $HYPR_SCRIPTS/wallpaper_apply.sh \$wallpaper"
    fi
fi

# --- fin -------------------------------------------------------------------
if command -v hyprctl >/dev/null 2>&1 && hyprctl instances >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 && info "Config de Hyprland recargada"
fi

cat <<'EOF'

Listo. Atajos:
  SUPER + SHIFT + G   galeria con previews
  SUPER + SHIFT + W   menu de fuentes

Acciones del launcher: wallpaper-gallery, wallpaper
EOF
