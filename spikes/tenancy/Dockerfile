# Multi-stage al estilo del ADR: compilación de Swift en el builder, imagen final slim.
# El spike lo usa para medir dos cosas que el ADR da por neutralizadas y nadie había
# medido: la RAM que pide compilar Swift y el tamaño de la imagen resultante.

# ───────────────────────── build ─────────────────────────
FROM swift:6.0-jammy AS build

WORKDIR /build

# Capa de dependencias, cacheable por separado del código.
COPY Package.swift Package.resolved ./
RUN swift package resolve --skip-update

COPY . .
RUN swift build -c release --product Run \
    -Xswiftc -g \
    --static-swift-stdlib

RUN mkdir -p /staging \
    && cp "$(swift build --package-path /build -c release --show-bin-path)/Run" /staging/

# ───────────────────────── runtime ─────────────────────────
FROM ubuntu:jammy

RUN apt-get update -q \
    && DEBIAN_FRONTEND=noninteractive apt-get install -q -y \
        ca-certificates tzdata libcurl4 libxml2 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor
WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app
USER vapor:vapor

EXPOSE 8080
ENTRYPOINT ["./Run"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
