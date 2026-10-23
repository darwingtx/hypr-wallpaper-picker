#!/usr/bin/env bash
# Descargador de wallpapers online para el shell de illogical-impulse.
#
# Fuentes:
#   wallhaven.cc  -> API publica, solo SFW (purity=100), no necesita API key
#   bing.com      -> wallpaper del dia (JSON, sin key)
#
# Uso:
#   wallpaper_fetch.sh random [general|anime|people|all]
#   wallpaper_fetch.sh search <etiquetas...>
#   wallpaper_fetch.sh top
#   wallpaper_fetch.sh bing
#   wallpaper_fetch.sh candidates <general|anime|people|all|top> [query] [cuantos]
#        Descarga un lote de candidatos (por defecto 16) en paralelo y muestra
#        sus rutas. Es lo que usa el menu para luego elegir con previews.
#
# Opciones:
#   --apply   Ademas de descargar, aplica el fondo y regenera el tema (matugen)
#
# Los ficheros se guardan en ~/Pictures/Wallpapers para que el selector de
# wallpapers del shell y waypaper los vean directamente.

set -uo pipefail

DEST_DIR="${WALLPAPER_DEST_DIR:-$HOME/Pictures/Wallpapers}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wallpaper-fetch"
LAST_FILE="$STATE_DIR/last-used"
BATCH_FILE="$STATE_DIR/last-batch"
MIN_RES="${WALLPAPER_MIN_RES:-1920x1200}"
PURITY="100"   # 100 = SFW. Sin API key no hay acceso a sketchy/nsfw.
CATEGORIES="111" # 100=general 010=anime 001=people 111=todo
API="https://wallhaven.cc/api/v1/search"
BING_API="https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8"
TIMEOUT=30
APPLY=0

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
APPLY_SCRIPT="$SCRIPT_DIR/wallpaper_apply.sh"

log() { printf '%s\n' "$*" >&2; }

usage() {
    sed -n '2,/^set /{/^set /q;p;}' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

# Ajusta la imagen a la resolucion de la pantalla (recorte centrado) para que
# quede nitida y no aparezca el aviso de "Upscale?" del shell.
optimize_image() {
    local file="$1"
    command -v magick >/dev/null 2>&1 || return 0
    local ext="${file##*.}"
    local tmp="${file}.tmp.${ext}"
    local args=("$file" -resize "${MIN_RES}^" -gravity center -extent "${MIN_RES}")
    [[ "$ext" =~ ^(jpg|jpeg)$ ]] && args+=(-quality 90)
    if magick "${args[@]}" "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$file"
    else
        rm -f "$tmp"
    fi
}

save_last() {
    mkdir -p "$STATE_DIR"
    printf '%s' "$1" >"$LAST_FILE"
}

# --- wallhaven -------------------------------------------------------------
# $1 = query (vacio = cualquiera)  $2 = sorting  $3 = categories  $4 = topRange
fetch_wallhaven() {
    local query="$1" sorting="$2" cats="$3" toprange="${4:-}"
    local url="${API}?purity=${PURITY}&categories=${cats}&atleast=${MIN_RES}&sorting=${sorting}"

    [[ -n "$query" ]] && url+="&q=$(printf '%s' "$query" | jq -sRr @uri)"
    [[ -n "$toprange" ]] && url+="&topRange=${toprange}"

    log "Consultando wallhaven..."
    local json
    json=$(curl -fsSL --max-time "$TIMEOUT" "$url" 2>/dev/null) || {
        log "No se pudo contactar con wallhaven.cc"; return 1
    }

    local last
    last=$(cat "$LAST_FILE" 2>/dev/null || true)

    # Descarta el ultimo usado para no repetir fondo
    local entry
    entry=$(printf '%s' "$json" | jq -r --arg last "$last" '
        [.data[] | select(.id != $last)] | .[0] // empty
        | [.id, .path] | @tsv' 2>/dev/null)

    [[ -z "$entry" ]] && {
        log "wallhaven no devolvio resultados"; return 1
    }

    local id url_img
    id="${entry%%$'\t'*}"
    url_img="${entry#*$'\t'}"

    local ext="${url_img##*.}"
    [[ "$ext" == "$url_img" || -z "$ext" ]] && ext="jpg"

    mkdir -p "$DEST_DIR"
    local dest="${DEST_DIR}/wallhaven-${id}.${ext}"

    log "Descargando ${id}..."
    curl -fsSL --max-time 120 -o "$dest" "$url_img" || {
        log "Fallo la descarga"; rm -f "$dest"; return 1
    }

    optimize_image "$dest"
    save_last "$id"
    printf '%s\n' "$dest"
}

# --- bing ------------------------------------------------------------------
fetch_bing() {
    log "Consultando bing..."
    local json
    json=$(curl -fsSL --max-time "$TIMEOUT" "$BING_API" 2>/dev/null) || {
        log "No se pudo contactar con bing.com"; return 1
    }

    local base
    base=$(printf '%s' "$json" | jq -r '.images[].urlbase' 2>/dev/null | shuf -n1)
    [[ -z "$base" || "$base" == "null" ]] && { log "bing no devolvio imagenes"; return 1; }

    mkdir -p "$DEST_DIR"
    local dest="${DEST_DIR}/bing-$(date +%Y%m%d-%H%M%S).jpg"

    log "Descargando imagen del dia..."
    curl -fsSL --max-time 120 -o "$dest" "https://www.bing.com${base}_1920x1080.jpg" || {
        log "Fallo la descarga"; rm -f "$dest"; return 1
    }

    optimize_image "$dest"
    printf '%s\n' "$dest"
}

# --- wallhaven por lotes ---------------------------------------------------
# Descarga varios candidatos en paralelo y muestra sus rutas.
# $1 = categorias  $2 = query  $3 = sorting  $4 = topRange  $5 = cuantos
fetch_candidates() {
    local cats="$1" query="$2" sorting="$3" toprange="$4" count="${5:-16}"
    local url="${API}?purity=${PURITY}&categories=${cats}&atleast=${MIN_RES}&sorting=${sorting}"

    [[ -n "$query" ]] && url+="&q=$(printf '%s' "$query" | jq -sRr @uri)"
    [[ -n "$toprange" ]] && url+="&topRange=${toprange}"

    log "Buscando $count wallpapers en wallhaven..."
    local json
    json=$(curl -fsSL --max-time "$TIMEOUT" "$url" 2>/dev/null) || {
        log "No se pudo contactar con wallhaven.cc"; return 1
    }

    local entries
    entries=$(printf '%s' "$json" | jq -r '.data[] | [.id, .path] | @tsv' 2>/dev/null | head -"$count")
    [[ -z "$entries" ]] && { log "wallhaven no devolvio resultados"; return 1; }

    mkdir -p "$DEST_DIR"

    clean_previous_batch

    log "Descargando ${count} candidatos..."
    local downloaded
    downloaded=$(printf '%s\n' "$entries" | xargs -P 4 -n 2 bash -c '
        id="$1"; url="$2"
        ext="${url##*.}"
        [[ "$ext" == "$url" || -z "$ext" ]] && ext="jpg"
        dest="'"$DEST_DIR"'/wallhaven-${id}.${ext}"
        curl -fsSL --max-time 120 -o "$dest" "$url" 2>/dev/null || { rm -f "$dest"; exit 0; }
        if command -v magick >/dev/null 2>&1; then
            tmp="${dest}.tmp.${ext}"
            args=("$dest" -resize "'"$MIN_RES"'^" -gravity center -extent "'"$MIN_RES"'")
            case "$ext" in jpg|jpeg) args+=(-quality 90) ;; esac
            if magick "${args[@]}" "$tmp" 2>/dev/null; then
                mv -f "$tmp" "$dest"
            else
                rm -f "$tmp"
            fi
        fi
        echo "$dest"
    ' _)

    # Guarda el lote para poder limpiarlo la proxima vez
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$downloaded" >"$BATCH_FILE"

    printf '%s\n' "$downloaded"
}

# Borra el lote anterior (nunca el wallpaper que este en uso)
clean_previous_batch() {
    [[ -f "$BATCH_FILE" ]] || return 0
    local current
    current=$(current_wallpaper)
    local f
    while IFS= read -r f; do
        [[ -z "$f" || "$f" == "$current" ]] && continue
        rm -f "$f"
    done <"$BATCH_FILE"
    rm -f "$BATCH_FILE"
}

# Wallpaper que tiene puesto el shell ahora mismo
current_wallpaper() {
    local cfg="$HOME/.config/illogical-impulse/config.json"
    [[ -f "$cfg" ]] || return 0
    python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['background']['wallpaperPath'])" \
        "$cfg" 2>/dev/null
}

# --- main ------------------------------------------------------------------
[[ $# -eq 0 ]] && usage

# Las opciones pueden ir en cualquier posicion
ARGS=()
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        *) ARGS+=("$arg") ;;
    esac
done
set -- ${ARGS[@]+"${ARGS[@]}"}

ACTION="${1:-}"
[[ $# -gt 0 ]] && shift

case "$ACTION" in
    random)
        cat="${1:-all}"
        case "$cat" in
            general) CATS="100" ;;
            anime)   CATS="010" ;;
            people)  CATS="001" ;;
            all)     CATS="111" ;;
            *) log "Categoria desconocida: $cat (general|anime|people|all)"; exit 1 ;;
        esac
        path=$(fetch_wallhaven "" random "$CATS") || exit 1
        ;;
    search)
        query="$*"
        [[ -z "$query" ]] && { log "Falta la busqueda"; exit 1; }
        path=$(fetch_wallhaven "$query" relevance "111") || exit 1
        ;;
    top)
        path=$(fetch_wallhaven "" toplist "111" "1w") || exit 1
        ;;
    bing)
        path=$(fetch_bing) || exit 1
        ;;
    candidates)
        # candidates <categoria|top> [query] [count]
        cat="${1:-all}"
        case "$cat" in
            general) CATS="100" ;;
            anime)   CATS="010" ;;
            people)  CATS="001" ;;
            all)     CATS="111" ;;
            top)     CATS="111" ;;
            *) log "Categoria desconocida: $cat"; exit 1 ;;
        esac
        query="${2:-}"
        count="${3:-16}"
        if [[ "$cat" == "top" ]]; then
            fetch_candidates "$CATS" "" toplist "1w" "$count" || exit 1
        elif [[ -n "$query" ]]; then
            fetch_candidates "$CATS" "$query" relevance "" "$count" || exit 1
        else
            fetch_candidates "$CATS" "" random "" "$count" || exit 1
        fi
        exit 0
        ;;
    *)
        usage
        ;;
esac

[[ -z "${path:-}" ]] && exit 1

echo "$path"

if [[ $APPLY -eq 1 ]]; then
    "$APPLY_SCRIPT" "$path"
fi
