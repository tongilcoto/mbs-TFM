#!/bin/bash
# Carga y descarga el agente de `launchd` (Plan launchd-001, L-L.2 y L-L.5).
#
#   Tools/Deploy/agent.sh install     escribe el .plist en ~/Library/LaunchAgents y lo carga
#   Tools/Deploy/agent.sh uninstall   lo descarga y lo borra (el binario y los logs se quedan)
#   Tools/Deploy/agent.sh status      lo que launchd sabe de él
#   Tools/Deploy/agent.sh run         dispara ya, sin esperar a la hora
#
# El binario lo instala `install.sh`; esto solo maneja el agente. Por eso
# `install` se niega si no hay nada instalado.
#
# Variables (todas opcionales):
#   TFM_AGENT_LABEL   nombre del agente en launchd; por defecto, local.tfm.ingest
#   TFM_HOME          ~/Library/Application Support/tfm
#   TFM_LOG_DIR       ~/Library/Logs/tfm

set -euo pipefail

LABEL="${TFM_AGENT_LABEL:-local.tfm.ingest}"
TFM_HOME="${TFM_HOME:-$HOME/Library/Application Support/tfm}"
LOG_DIR="${TFM_LOG_DIR:-$HOME/Library/Logs/tfm}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/ingest.plist"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
install)
    if [ ! -x "$TFM_HOME/current/run-ingest.sh" ] || [ ! -x "$TFM_HOME/current/Run" ]; then
        echo "error: no hay nada instalado en $TFM_HOME/current. Primero: Tools/Deploy/install.sh" >&2
        exit 1
    fi
    # Otro agente que ya lanza esta misma ingesta —p. ej., el de antes de
    # cambiar TFM_AGENT_LABEL— haría que cada disparo se ejecutase dos veces.
    others=0
    while IFS= read -r other; do
        [ "$other" = "$PLIST" ] && continue
        other_label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$other" 2>/dev/null || basename "$other" .plist)"
        echo "error: el agente $other_label ya lanza esta ingesta; con dos, cada disparo se ejecutaría dos veces." >&2
        echo "  Quítalo antes:  launchctl bootout $DOMAIN/$other_label; rm \"$other\"" >&2
        others=1
    done < <(grep -l -F "$TFM_HOME/current/run-ingest.sh" "$HOME/Library/LaunchAgents"/*.plist 2>/dev/null)
    [ "$others" -eq 0 ] || exit 1
    mkdir -p "$LOG_DIR" "$(dirname "$PLIST")"
    # `|` como separador porque las rutas llevan `/`; y "Application Support"
    # lleva un espacio, que en un <string> de plist no necesita escaparse.
    sed -e "s|__LABEL__|$LABEL|g" -e "s|__TFM_HOME__|$TFM_HOME|g" -e "s|__LOG_DIR__|$LOG_DIR|g" \
        "$TEMPLATE" > "$PLIST.tmp"
    plutil -lint "$PLIST.tmp" >/dev/null
    mv "$PLIST.tmp" "$PLIST"
    # `bootout` de lo que hubiera: `bootstrap` sobre un agente ya cargado falla.
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    # Un `bootstrap` que no se queja no prueba nada (§3, aviso 4 del plan).
    launchctl print "$DOMAIN/$LABEL" >/dev/null
    echo "Cargado: $LABEL → $TFM_HOME/current ($(basename "$(readlink "$TFM_HOME/current")"))"
    ;;
uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
        echo "error: $LABEL sigue cargado" >&2
        exit 1
    fi
    echo "Descargado y borrado: $LABEL. El binario ($TFM_HOME) y los logs ($LOG_DIR) se quedan."
    ;;
status)
    launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E "state =|last exit code|runs =|path =" || {
        echo "$LABEL no está cargado" >&2
        exit 1
    }
    # Los disparos **que launchd tiene cargados**, no los del fichero: si alguien
    # edita el .plist sin `agent.sh install`, son estos los que mandan.
    echo "── disparos programados (hora local):"
    launchctl print "$DOMAIN/$LABEL" | awk '
        BEGIN { split("domingo lunes martes miércoles jueves viernes sábado", day, " ") }
        /descriptor = \{/ { inside = 1; w = ""; h = 0; m = 0; next }
        inside && /"Weekday"/ { w = $3 }
        inside && /"Hour"/    { h = $3 }
        inside && /"Minute"/  { m = $3 }
        inside && /\}/ {
            printf "\t%02d:%02d  %s\n", h, m, (w == "" ? "cada día" : day[(w % 7) + 1])
            inside = 0
        }'
    echo "── binario: $(basename "$(readlink "$TFM_HOME/current")")"
    [ -s "$LOG_DIR/ULTIMO_FALLO" ] && { echo "── ULTIMO_FALLO:"; cat "$LOG_DIR/ULTIMO_FALLO"; }
    exit 0
    ;;
run)
    launchctl kickstart "$DOMAIN/$LABEL"
    echo "Disparado. Log: $LOG_DIR/ingest.log"
    ;;
*)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
