#!/bin/bash
# Lo que ejecuta `launchd` en cada disparo (Plan launchd-001, L-L.1 · H-59).
#
# No se ejecuta desde el repositorio: `install.sh` lo copia del commit junto al
# binario, a `$TFM_HOME/releases/<sha>/`, por el mismo motivo que el binario
# (H-85): un cambio de rama no puede cambiar lo que dispara `launchd`.
#
# Hace cuatro cosas y ninguna más:
#
#   0. Esperar a que haya red (L-L.6). Con el portátil cerrado, `launchd` no
#      espera a que alguien lo abra: lanza el disparo en uno de los despertares
#      en segundo plano que macOS hace cada ~15 min (DarkWake), que duran unos
#      segundos y **no tienen red**. Medido en L-L.4: el disparo del sábado salió
#      a las 23:42 con la tapa cerrada y las dos competiciones fallaron con
#      `Network is down`; al abrir el portátil no se repitió, porque para
#      `launchd` ya estaba hecho. Así que la espera va aquí: el guion se queda
#      esperando dentro del mismo disparo y la ingesta corre cuando vuelve la red.
#      El plazo se mide con el reloj de pared (`date +%s`), que sí avanza
#      mientras el Mac duerme; `sleep` no, y con él solo el plazo podría
#      alargarse días.
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
#   TFM_NET_WAIT_HOURS    plazo para que vuelva la red (12); si vence, aviso y exit 75
#   TFM_NET_POLL_SECONDS  cada cuánto se vuelve a mirar (60)
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
    if [ "$status" -eq 75 ]; then
        echo "sin red durante ${NET_WAIT_HOURS} h: no se lanzó la ingesta"
    elif [ "$status" -eq 127 ] || [ "$status" -eq 126 ]; then
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

NET_WAIT_HOURS="${TFM_NET_WAIT_HOURS:-12}"
NET_POLL_SECONDS="${TFM_NET_POLL_SECONDS:-60}"

# "Hay red" = hay ruta por defecto. No pregunta a la federación a propósito: el
# host es conocimiento del adaptador (D-97), y si la fuente falla, eso lo
# registra la pasada en su fila; aquí solo se evita lanzarla sin red.
has_network() {
    route -n get default >/dev/null 2>&1
}

# MEDIDA, no decisión (L-L.6 reabierto, 2026-10-12). La ruta por defecto
# resultó no bastar: el disparo del lunes 08:00 la vio en un DarkWake y falló
# con `Network is down`. Antes de cambiar la señal se apunta qué ve el Mac en
# cada disparo: si en un despertar en segundo plano falta `Graphics` en
# `pmset -g systemstate`, ésa será la señal de "despierto de verdad".
power_state() {
    local caps route
    caps="$(pmset -g systemstate 2>/dev/null | sed -n 's/^Current System Capabilities are: *//p' | sed 's/ *$//')"
    if has_network; then route="sí"; else route="no"; fi
    echo "capacidades: ${caps:-?} · ruta por defecto: $route"
}

# Devuelve 0 en cuanto hay red y 1 si vence el plazo.
wait_for_network() {
    has_network && return 0
    local start deadline
    start="$(date +%s)"
    deadline=$(( start + NET_WAIT_HOURS * 3600 ))
    echo "── sin red: espero hasta ${NET_WAIT_HOURS} h, mirando cada ${NET_POLL_SECONDS} s" | stamp >> "$LOG"
    while [ "$(date +%s)" -lt "$deadline" ]; do
        sleep "$NET_POLL_SECONDS"
        if has_network; then
            echo "── red de vuelta tras $(( ($(date +%s) - start) / 60 )) min" | stamp >> "$LOG"
            return 0
        fi
    done
    return 1
}

echo "── disparo · ingest --fail-if-empty $*" | stamp >> "$LOG"
echo "── estado al disparar · $(power_state)" | stamp >> "$LOG"
if wait_for_network; then
    output="$("$TFM_HOME/current/Run" ingest --fail-if-empty "$@" 2>&1)"
    status=$?
else
    # 75 = EX_TEMPFAIL: no se intentó nada, así que no hay filas en
    # `ingestion_runs` y la competición entra entera en el disparo siguiente.
    output=""
    status=75
fi
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
