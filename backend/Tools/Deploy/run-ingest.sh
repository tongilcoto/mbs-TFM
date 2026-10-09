#!/bin/bash
# Lo que ejecuta `launchd` en cada disparo (Plan launchd-001, L-L.1 · H-59).
#
# No se ejecuta desde el repositorio: `install.sh` lo copia del commit junto al
# binario, a `$TFM_HOME/releases/<sha>/`, por el mismo motivo que el binario
# (H-85): un cambio de rama no puede cambiar lo que dispara `launchd`.
#
# Hace tres cosas y ninguna más:
#
#   1. `Run ingest --fail-if-empty`, con los argumentos que se le pasen detrás.
#      El flag convierte el recorrido vacío en `exit 1` (DL-2), así que **lo que
#      decide si hay aviso es solo el código de salida**; la salida se lee
#      después, y únicamente para ponerle motivo al aviso.
#   2. Cada línea al log, con la hora y el commit delante.
#   3. Si el código no es 0, la señal de DL-1: una notificación de macOS y una
#      línea en ULTIMO_FALLO, que no se borra hasta que la borre una persona.
#      Las dos llevan **el motivo**, sacado de la salida de este disparo (ver
#      `reason`): con "exit 1" a secas, la base caída y el recorrido vacío avisan
#      igual y piden cosas distintas.
#
# Variables (todas opcionales):
#   TFM_HOME      ~/Library/Application Support/tfm
#   TFM_LOG_DIR   ~/Library/Logs/tfm
#   DB_*          las de `DatabaseConfig.swift`; por defecto, el Postgres de docker compose

set -uo pipefail

TFM_HOME="${TFM_HOME:-$HOME/Library/Application Support/tfm}"
LOG_DIR="${TFM_LOG_DIR:-$HOME/Library/Logs/tfm}"
LOG="$LOG_DIR/ingest.log"
FAILURES="$LOG_DIR/ULTIMO_FALLO"
mkdir -p "$LOG_DIR"

SHA="$(basename "$(readlink "$TFM_HOME/current" 2>/dev/null || echo sin-instalar)")"

stamp() {
    while IFS= read -r line; do
        printf '%s %s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$SHA" "$line"
    done
}

# El motivo, en una línea, a partir de la salida de este disparo. **Solo da
# forma al aviso**: lo que decide si hay aviso es el código de salida.
reason() {
    local status="$1" output="$2" line
    if [ "$status" -eq 127 ] || [ "$status" -eq 126 ]; then
        echo "no se pudo ejecutar el binario instalado: ¿falta Tools/Deploy/install.sh?"
    elif grep -q "connectionError" <<< "$output"; then
        echo "la base no responde: ¿está Docker parado?"
    # La línea de resumen de un club que no terminó bien: la de éxito es la
    # única que dice ", 0 con fallo,".
    elif line="$(grep '^→ ' <<< "$output" | grep -v ', 0 con fallo,' | head -1)" && [ -n "$line" ]; then
        echo "${line#→ }"
    else
        tail -1 <<< "$output"
    fi
}

echo "── disparo · ingest --fail-if-empty $*" | stamp >> "$LOG"
output="$("$TFM_HOME/current/Run" ingest --fail-if-empty "$@" 2>&1)"
status=$?
[ -n "$output" ] && printf '%s\n' "$output" | stamp >> "$LOG"
echo "── fin · exit $status" | stamp >> "$LOG"

if [ "$status" -ne 0 ]; then
    # Se añade, no se sobrescribe: si fallan dos fines de semana seguidos, que
    # se vean los dos.
    why="$(reason "$status" "$output" | cut -c1-200)"
    echo "$(date '+%Y-%m-%d %H:%M') · exit $status · $SHA · $why · detalle en $LOG" >> "$FAILURES"
    # El texto va como argumento y no dentro del guion de AppleScript: así una
    # comilla en el motivo no rompe la notificación.
    /usr/bin/osascript \
        -e 'on run argv' \
        -e 'display notification (item 1 of argv) with title "TFM · ingesta falló" subtitle (item 2 of argv)' \
        -e 'end run' \
        "$why" "exit $status · detalle en $LOG" \
        >/dev/null 2>&1 || true
fi
exit "$status"
