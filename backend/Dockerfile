# Multi-stage al estilo del ADR: compilación en el builder, imagen final slim.
# Sirve además para **remedir** el build con el plugin de generación dentro,
# que es lo que D-65 dejó pendiente y §8.2 pide repetir.
#
# Swift 6.2 (no 6.0 como el spike): el paquete usa modo de lenguaje v6 y varias
# upcoming features que la 6.0 no conoce.

# ───────────────────────── build ─────────────────────────
FROM swift:6.2-noble AS build

WORKDIR /build

# Capa de dependencias, cacheable por separado del código.
COPY Package.swift Package.resolved* ./
RUN swift package resolve --skip-update

COPY Sources ./Sources
COPY Tests ./Tests

# El plugin de swift-openapi-generator corre **aquí dentro**, en tiempo de
# compilación: es exactamente el coste que había que medir.
RUN swift build -c release --product Run \
    -Xswiftc -g \
    --static-swift-stdlib

RUN mkdir -p /staging \
    && cp "$(swift build --package-path /build -c release --show-bin-path)/Run" /staging/

# ───────────────────────── runtime ─────────────────────────
FROM ubuntu:noble

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
