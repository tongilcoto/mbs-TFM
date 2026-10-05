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
#      El flag convierte el recorrido vacío en `exit 1` (DL-2), así que aquí no
#      se lee la salida: **solo el código de salida**.
#   2. Cada línea al log, con la hora y el commit delante.
#   3. Si el código no es 0, la señal de DL-1: una notificación de macOS y una
#      línea en ULTIMO_FALLO, que no se borra hasta que la borre una persona.
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

echo "── disparo · ingest --fail-if-empty $*" | stamp >> "$LOG"
"$TFM_HOME/current/Run" ingest --fail-if-empty "$@" 2>&1 | stamp >> "$LOG"
status=${PIPESTATUS[0]}
echo "── fin · exit $status" | stamp >> "$LOG"

if [ "$status" -ne 0 ]; then
    # Se añade, no se sobrescribe: si fallan dos fines de semana seguidos, que
    # se vean los dos.
    echo "$(date '+%Y-%m-%d %H:%M') · exit $status · $SHA · detalle en $LOG" >> "$FAILURES"
    /usr/bin/osascript -e "display notification \"La ingesta falló (exit $status). Detalle en ~/Library/Logs/tfm/ingest.log\" with title \"TFM · ingesta\"" \
        >/dev/null 2>&1 || true
fi
exit "$status"
