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

set -euo pipefail

LABEL="com.tongilcoto.tfm.ingest"
TFM_HOME="${TFM_HOME:-$HOME/Library/Application Support/tfm}"
LOG_DIR="${TFM_LOG_DIR:-$HOME/Library/Logs/tfm}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/$LABEL.plist"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
install)
    if [ ! -x "$TFM_HOME/current/run-ingest.sh" ] || [ ! -x "$TFM_HOME/current/Run" ]; then
        echo "error: no hay nada instalado en $TFM_HOME/current. Primero: Tools/Deploy/install.sh" >&2
        exit 1
    fi
    mkdir -p "$LOG_DIR" "$(dirname "$PLIST")"
    # `|` como separador porque las rutas llevan `/`; y "Application Support"
    # lleva un espacio, que en un <string> de plist no necesita escaparse.
    sed -e "s|__TFM_HOME__|$TFM_HOME|g" -e "s|__LOG_DIR__|$LOG_DIR|g" "$TEMPLATE" > "$PLIST.tmp"
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
    launchctl print "$DOMAIN/$LABEL" | grep -E "state =|last exit code|runs =|path =" || {
        echo "$LABEL no está cargado" >&2
        exit 1
    }
    [ -s "$LOG_DIR/ULTIMO_FALLO" ] && { echo "── ULTIMO_FALLO:"; cat "$LOG_DIR/ULTIMO_FALLO"; }
    exit 0
    ;;
run)
    launchctl kickstart "$DOMAIN/$LABEL"
    echo "Disparado. Log: $LOG_DIR/ingest.log"
    ;;
*)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
