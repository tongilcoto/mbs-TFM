# AGENTS.md

Este fichero es la referencia principal para agentes (Claude Code y similares) que trabajen en este repositorio. `CLAUDE.md` redirige aquí.

## Qué es este proyecto

Proyecto (TFM) para la gestión técnica de pequeños clubs de fútbol españoles: gestión manual de estadísticas de sus distintos equipos, en todas las categorías (desde pre-benjamín a senior), pudiendo existir varios equipos por categoría.

El caso base es **un único club**. Como ampliación de alcance de negocio, el producto puede ofrecerse a **varios clubs** en modo **SaaS multi-tenant**, con dos modelos de propiedad: **gestionado por el proveedor** (instancia compartida con aislamiento por club) o **instancia dedicada del club** (sus propias claves). Esto no invalida el caso de un solo club.

## Documentación clave

**Transversal (todo el proyecto):**

- [docs/Project Seed.md](./docs/Project%20Seed.md) — origen y reglas del proyecto.
- [docs/Project HLD-001.md](./docs/Project%20HLD-001.md) — diseño de alto nivel (artefactos y relaciones).

**Por módulo** (ADR = decisiones; LLD = diseño de bajo nivel; Docs = material de apoyo):

| Módulo | ADR | LLD | Docs |
|--------|-----|-----|------|
| **API backend + Base de datos** | [ADR-API_y_BBDD-001](./docs/ADR-API_y_BBDD-001.md) — tecnología BD/API y despliegue (ver resumen abajo) | [API_y_BBDD LLD-001](./docs/API_y_BBDD%20LLD-001.md) — arquitectura Clean/Hexagonal/DDD, modelo de datos, ORM, contrato API · Anexos: [Decisiones de diseño — bitácora](./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) · [Federación de Madrid (RFFM) — API](./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md) | [mockups móvil](./docs/design-assets/mobile/) · [OpenAPI](./backend/openapi/openapi.yaml) |
| **Web backoffice** | *(pendiente)* | *(pendiente)* | — |
| **App iOS** | *(pendiente)* | *(pendiente)* | — |
| **App Android** | *(pendiente)* | *(pendiente)* | — |

## Decisiones de diseño transversales (detalle en el LLD-001)

- **El backend son tres módulos sobre un modelo de datos común** (§2.1): **BFF** (REST para backoffice y
  apps), **ingesta** de la API de la federación, y **gestión de usuarios** (transversal).
- **Cada entidad tiene un solo dueño de escritura** (§5.1), en tres papeles: *entrada de la ingesta*
  (`Season`, `Competition` — las crea el administrador), *salida de la ingesta* (`Team`, `OpponentClub`,
  `Match`, `Round`… — solo corregibles) y *dominio manual* (`Player`, `Goal`, `Card`…). Regla:
  **el BFF corrige lo que la ingesta trae; nunca lo crea ni lo borra.** Al tocar el spec o el LLD, respetar
  esta frontera: no añadir `POST`/`DELETE` a entidades de salida.
- **La federación es un catálogo en código, no una tabla** (§3.6): soportar una nueva exige un adaptador.
  Lo que sí es dato es cuál es la del club (`Club.federation`), una por tenant.

## Dónde va cada cosa al documentar

El LLD de API/BD se dividió en tres ficheros **por naturaleza del contenido**, no por tema (decisión `D-26`).
Al escribir documentación nueva, aplicar este criterio:

| Si el contenido… | Va a |
|------------------|------|
| lo necesita alguien **para escribir el código** | el **LLD** (normativo) |
| es la razón por la que se **descartó otra opción** | el **Anexo de Decisiones** (bitácora, entradas `D-nn`) |
| es una **observación sobre un sistema de terceros** (muestras, deducciones) | el **Anexo de la Federación** |

Tres señales de que algo **no** es LLD aunque lo parezca: una **tabla de opciones con veredicto**, una
narrativa **"antes pensábamos X, ahora Y"**, o un **volcado JSON**. El LLD enuncia el *qué* en una línea y
enlaza con `[D-nn]`. Detalle campo a campo de los DTOs: **solo** en el spec OpenAPI, nunca duplicado en el
LLD (`D-25`).

## Decisiones técnicas (resumen — detalle y razones en el ADR-API_y_BBDD-001)

- **Base de datos:** PostgreSQL gestionado en **Supabase** (BD + Auth + Storage), **región UE** (RGPD; datos de menores).
- **API backend:** **Swift — Vapor + Fluent** (ORM oficial), estilo **REST** con **OpenAPI**. API *tenant-aware*.
- **Autenticación:** **Supabase Auth** (`auth.users`), *pool* compartido; *claims* de tenant (`club_id`, `role`) hechos cumplir por la API/RLS.
- **Multi-tenancy:** **una sola base de código**; aislamiento por **_schema_ por club** (tier gestionado) o **proyecto por club** (tier dedicado). Modelo *pooled* (`club_id` en tablas compartidas) descartado.
- **Despliegue:** **PaaS con Docker**, **Fly.io** preferente para Vapor (compilación de Swift en *builder* remoto/CI, no en el host); Railway/Render como alternativas. Tope de coste **20 $/mes** en el tier gestionado.

## Idioma

El desarrollador es hispanohablante y toda la documentación del proyecto se escribe en español (es-ES). Responde y documenta en español salvo que se indique lo contrario.

## Artefactos previstos

El proyecto se compone de los siguientes artefactos, aún por construir:

- Base de datos
- API backend
- Web backoffice
- App iOS de consulta
- App Android de consulta

Los tres primeros artefactos (base de datos, API backend y web backoffice) se alojarán mediante servicios cloud contratados para tal fin.

## Estado actual

El repositorio está en fase inicial: las **decisiones tecnológicas de BD/API y despliegue ya están tomadas** (ver ADR y resumen arriba), pero **todavía no existe código**, esquema de base de datos, ni estructura de proyecto para ninguno de los artefactos.

Sí existe ya un **artefacto ejecutable**: el *spec* OpenAPI en [`backend/openapi/openapi.yaml`](./backend/openapi/openapi.yaml), que se construye **entidad a entidad** en paralelo al §5 del LLD (hoy: `Club`, `Season`, `Competition`, `OpponentClub` y `Team`). Validación:

```sh
npx @redocly/cli lint backend/openapi/openapi.yaml
```

Cuando se incorpore código a alguno de los artefactos, este fichero debe actualizarse con los comandos y la arquitectura correspondientes.

Próximos pasos de diseño pendientes (futuros ADRs/propuestas): modelo de datos detallado, contrato de la API, detalle fino de tenancy/auth (roles, provisión y automatización de migraciones por tenant) y estimación de costes cloud por *tier*.

## Equipo

El desarrollo cuenta con un único desarrollador humano, con la ayuda de Claude Code.
