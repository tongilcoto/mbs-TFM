#!/bin/bash
# Instala el binario que dispara `launchd` (Plan launchd-001, bloque I · H-85).
#
#   Tools/Deploy/install.sh            # el commit de HEAD
#   Tools/Deploy/install.sh <ref>      # cualquier commit, rama o etiqueta
#
# **Compila un commit, no el árbol de trabajo.** Extrae `backend/` del commit con
# `git archive` y lo compila en su propio directorio, fuera de `.build`. Por eso:
#
#   - `swift build`, `swift test` y `Tools/Mutate` reescriben `.build` y no tocan
#     lo instalado (H-85: un disparo a mitad de una mutación ejecutaba código roto
#     a propósito contra `club_atleti`);
#   - no hay carrera entre "comprobar que está limpio" y "compilar": lo que se
#     compila es el commit, aunque el árbol cambie mientras;
#   - lo que no está commiteado NO se instala, y el guion lo avisa.
#
# Deja:
#   $TFM_HOME/releases/<sha>/Run       el binario
#   $TFM_HOME/releases/<sha>/VERSION   de qué commit y rama salió, y cuándo
#   $TFM_HOME/current                  enlace a la versión que ejecuta `launchd`
#
# `TFM_HOME` por defecto: ~/Library/Application Support/tfm

set -euo pipefail

REF="${1:-HEAD}"
TFM_HOME="${TFM_HOME:-$HOME/Library/Application Support/tfm}"
KEEP_RELEASES=5

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
SHA="$(git -C "$REPO" rev-parse --verify --short=12 "$REF^{commit}")" || {
    echo "error: '$REF' no es un commit de este repositorio" >&2
    exit 1
}
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"

# Avisos, no errores: el guion instala igual, pero conviene saber qué se queda fuera.
if [ "$REF" = "HEAD" ] && [ -n "$(git -C "$REPO" status --porcelain -- backend/Sources backend/Package.swift backend/Package.resolved)" ]; then
    echo "aviso: hay cambios sin commitear en Sources/ o Package.* — NO entran en el binario." >&2
fi
if [ "$REF" = "HEAD" ] && [ "$BRANCH" != "main" ]; then
    echo "aviso: instalando desde '$BRANCH', no desde main." >&2
fi

DEST="$TFM_HOME/releases/$SHA"
if [ -x "$DEST/Run" ]; then
    echo "$SHA ya estaba instalado; solo se mueve 'current'."
else
    SRC="$TFM_HOME/src"
    rm -rf "$SRC"
    mkdir -p "$SRC"
    git -C "$REPO" archive --format=tar "$SHA" backend | tar -x -C "$SRC"

    # El directorio de compilación se reutiliza entre instalaciones: las
    # dependencias no se recompilan cada vez, y sigue estando fuera de `.build`.
    echo "Compilando $SHA en release…"
    swift build -c release --product Run \
        --package-path "$SRC/backend" --scratch-path "$TFM_HOME/build"
    BIN="$(swift build -c release --package-path "$SRC/backend" \
        --scratch-path "$TFM_HOME/build" --show-bin-path)/Run"

    mkdir -p "$DEST"
    cp "$BIN" "$DEST/Run.tmp"
    mv "$DEST/Run.tmp" "$DEST/Run"
    {
        echo "commit=$(git -C "$REPO" rev-parse "$SHA")"
        echo "ref=$REF"
        echo "branch=$BRANCH"
        echo "installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$DEST/VERSION"
    rm -rf "$SRC"
fi

# Atómico: `launchd` nunca ve un `current` a medio cambiar.
ln -sfn "releases/$SHA" "$TFM_HOME/current.tmp"
mv -fh "$TFM_HOME/current.tmp" "$TFM_HOME/current"

# Las más recientes se quedan para poder volver atrás (`install.sh <sha>`).
# `current` no se borra nunca, aunque sea antigua.
ls -1t "$TFM_HOME/releases" | tail -n +$((KEEP_RELEASES + 1)) | while read -r old; do
    [ "$old" = "$SHA" ] || rm -rf "$TFM_HOME/releases/$old"
done

echo "Instalado: $TFM_HOME/current -> releases/$SHA"
cat "$DEST/VERSION"
