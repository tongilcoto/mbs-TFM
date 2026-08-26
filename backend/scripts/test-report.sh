#!/usr/bin/env bash
# `swift test` agrupando cada test bajo el nombre de su suite.
#
# swift-testing imprime el nombre del test pero no el de su suite, así que con
# varias suites en marcha no se sabe qué está pasando. Este script pide su flujo
# de eventos en JSON —que sí trae la jerarquía— y lo reimprime agrupado.
#
#   ./scripts/test-report.sh                       # todo
#   ./scripts/test-report.sh --filter DomainTests  # se pasan los argumentos tal cual
set -uo pipefail
cd "$(dirname "$0")/.."

EVENTS="$(mktemp -t test-events).jsonl"
trap 'rm -f "$EVENTS"' EXIT

# --no-parallel para que el orden sea el del código fuente, y --disable-xctest
# para no arrastrar el "Executed 0 tests" de un XCTest que no existe.
swift test --disable-xctest --no-parallel \
  --experimental-event-stream-output "$EVENTS" "$@" > /dev/null 2>&1

# El codigo de salida es el del informe, no el de `swift test`: si un test falla,
# este script tiene que fallar tambien o CI lo daria por bueno.
swift scripts/test-report.swift "$EVENTS"
