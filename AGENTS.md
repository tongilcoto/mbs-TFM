# AGENTS.md

Este fichero es la referencia principal para agentes (Claude Code y similares) que trabajen en este repositorio. `CLAUDE.md` redirige aquí.

## Qué es este proyecto

Proyecto (TFM) para la gestión técnica de pequeños clubs de fútbol españoles: gestión manual de estadísticas de sus distintos equipos, en todas las categorías (desde pre-benjamín a senior), pudiendo existir varios equipos por categoría.

El caso base es **un único club**. Como ampliación de alcance de negocio, el producto puede ofrecerse a **varios clubs** en modo **SaaS multi-tenant**, con dos modelos de propiedad: **gestionado por el proveedor** (instancia compartida con aislamiento por club) o **instancia dedicada del club** (sus propias claves). Esto no invalida el caso de un solo club.

## Documentación clave

**Transversal (todo el proyecto):**

- [docs/Project Seed.md](./docs/Project%20Seed.md) — origen y reglas del proyecto.
- [docs/Project HLD-001.md](./docs/Project%20HLD-001.md) — diseño de alto nivel (artefactos y relaciones).
- [docs/Plan de desarrollo-001.md](./docs/Plan%20de%20desarrollo-001.md) — **cómo se construye**: los dos
  bucles (alcance y TDD) y las fases **F0–F10**: andamiaje primero, después la ingesta.

**Por módulo** (ADR = decisiones; LLD = diseño de bajo nivel; Docs = material de apoyo):

| Módulo | ADR | LLD | Docs |
|--------|-----|-----|------|
| **API backend + Base de datos** | [ADR-API_y_BBDD-001](./docs/ADR-API_y_BBDD-001.md) — tecnología BD/API y despliegue (ver resumen abajo) | [API_y_BBDD LLD-001](./docs/API_y_BBDD%20LLD-001.md) — arquitectura Clean/Hexagonal/DDD, modelo de datos, ORM, contrato API · Anexos: [Decisiones de diseño — bitácora](./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) · [Federación de Madrid (RFFM)](./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md) · [Federación de Cataluña (FCF)](./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md) | [mockups móvil](./docs/design-assets/mobile/) · [OpenAPI](./backend/openapi/openapi.yaml) |
| **Web backoffice** | *(pendiente)* | *(pendiente)* | — |
| **App iOS** | *(pendiente)* | *(pendiente)* | — |
| **App Android** | *(pendiente)* | *(pendiente)* | — |

## Decisiones de diseño transversales (detalle en el LLD-001)

- **El backend son tres módulos sobre un modelo de datos común** (§2.1): **BFF** (REST para backoffice y
  apps), **ingesta** de la API de la federación, y **gestión de usuarios** (transversal).
- **Cada entidad tiene un solo dueño de escritura** (§5.1), en tres papeles: *entrada de la ingesta*
  (`Season`, `Competition` — las crea el administrador), *salida de la ingesta* (`OpponentClub`, `Match`,
  `Round`… — solo corregibles) y *dominio manual* (`Player`, `Goal`, `Card`…). Regla:
  **el BFF corrige lo que la ingesta trae; no crea ni borra filas *emparejadas* con la federación.**
  Al tocar el spec o el LLD, respetar esta frontera: no añadir `POST`/`DELETE` a entidades de salida.
- **`Team` es la excepción, y es deliberada** (`D-66`): el club forma el equipo, lo inscribe en la
  federación y **solo entonces** la federación publica calendario — es fuente de verdad del *calendario*,
  no del *equipo*. Así que `Team` tiene `POST` (sin ningún dato de federación) y `DELETE` **mientras no
  esté emparejado**; una fila con `federationTeamId` nulo no tiene segundo escritor. La otra mitad de la
  regla, sin la cual esto no se sostiene: **la ingesta no crea equipos propios**, así que todo lo que
  encuentra y no reconoce es de un `OpponentClub`. `gender` y `modality` pasan a ser identidad de alta:
  van en `CreateTeamRequest`, nunca en el `PATCH`.
- **El copia-pega de la URL de la federación vive en el equipo, no en la competición** (`D-67`):
  `POST /v1/teams/{id}/federation-link` (+ su `/preview`) engancha, crea en cascada `Season` y
  `Competition` si hacen falta y **encola** la primera ingesta → **202**, no 201. Es 202 porque la FCF
  cuesta ~34 peticiones (§5.6) y en línea daría *timeout*. `POST /v1/competitions` se conserva solo como
  vía para semillas, *scripts* y tests.
- **`modality` y `gender`, cuando el equipo lo crea la ingesta, los hereda de su `Competition`** (§3.2, `D-07`, `D-58`): los dos entran en la
  clave única de `Team` y **ninguno es campo de escritura de `Team`**. La federación no publica género por
  equipo —va en el nombre de la competición—, así que el `/preview` lo propone y el administrador lo confirma
  en el alta. No devolver `gender` a `UpdateTeamRequest`: una inferencia mal puesta ahí no da un dato feo, da
  un 409 de unicidad.
- **La federación es un catálogo en código, no una tabla** (§3.6): soportar una nueva exige un adaptador.
  Lo que sí es dato es cuál es la del club (`Club.federation`), una por tenant. El catálogo describe también
  **qué sabe hacer** cada proveedor, no solo sus coordenadas (`D-17`, `D-55`).
- **Los dos proveedores no son intercambiables** y sus diferencias están medidas: la RFFM sirve
  clasificación por **cualquier** jornada y el calendario entero en **una** petición; la **FCF** cuesta una
  petición **por jornada**, solo da la clasificación **vigente**, no tiene identificador de partido y
  **borra la fecha del partido al jugarse**. Ojo con el atajo "RFFM = JSON, FCF = *scraping*": **los dos
  devuelven HTML en el calendario** — la RFFM lo trae en un `__NEXT_DATA__` embebido ([Anexo RFFM §F.7]) y
  solo sus rutas `/api/…` (clasificación, competiciones, grupos) son JSON puro. De ahí que en la ingesta un campo
  **ausente o vacío nunca sobrescriba** (`D-56`) y que la cadencia semanal sea un requisito, no una
  recomendación (§5.6). Evidencia campo a campo en los anexos de federación; no deducir nada de memoria.

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
- **Contrato de la API: *design-first*** (`D-65`). El *spec* es la **fuente de verdad** y de él se generan los tipos
  y el `APIProtocol` con `swift-openapi-generator` + `vapor/swift-openapi-vapor`. **Al tocar el *spec*, tenerlo
  presente: el generador emite tipos, no validación** — ignora `readOnly`, `pattern`, longitudes, rangos,
  `minProperties`, `default`, `tags` y `security`. Esas reglas las hace cumplir el **Dominio** (Value Objects) o el
  *handler*, según la tabla de reparto del LLD §5.5. No dar por hecho que declararlo en el YAML lo hace cumplir.
- **Autenticación:** **Supabase Auth** (`auth.users`), *pool* compartido; *claims* de tenant (`club_id`, `role`) hechos cumplir por la API/RLS.
- **Multi-tenancy:** **una sola base de código**; aislamiento por **_schema_ por club** (tier gestionado) o **proyecto por club** (tier dedicado). Modelo *pooled* (`club_id` en tablas compartidas) descartado.
- **Despliegue:** **PaaS con Docker**, **Fly.io** preferente para Vapor (compilación de Swift en *builder* remoto/CI, no en el host); Railway/Render como alternativas. Tope de coste **20 $/mes** en el tier gestionado.

## Licencia

Repositorio **propietario** — ver [LICENSE](./LICENSE) (`LicenseRef-Proprietary`, declarada también en
`info.license` del *spec*). No es código abierto: no publicar fragmentos fuera del repositorio ni añadir
cabeceras de licencias permisivas a ficheros nuevos.

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

Sí existe ya un **artefacto ejecutable**: el *spec* OpenAPI en [`backend/openapi/openapi.yaml`](./backend/openapi/openapi.yaml), que se construye **entidad a entidad** en paralelo al §5 del LLD (hoy: `Club`, `Season`, `Competition`, `OpponentClub`, `Team`, `Round`, `Match`, `StandingRow`, `LeagueScorer` — con la que queda **cerrada toda la superficie de salida de la ingesta**— y, del **dominio manual**, `Player`, `Absence`, `Appearance`, `Card` y `Goal` con CRUD completo, más `CompetitionSanctionBracket`, que es **configuración** y se escribe como conjunto con un `PUT` (`D-50`). más las cuatro de **roles y permisos** (`StaffMember`, `StaffPosition`, `PositionPermission`,
`StaffAssignment`), más `TeamRegistration`, la inscripción del equipo en la temporada (`D-68`). **El contrato queda completo: las 20 entidades del §3.2 tienen sus endpoints**). Validación:

```sh
npx @redocly/cli lint backend/openapi/openapi.yaml
```

Cuando se incorpore código a alguno de los artefactos, este fichero debe actualizarse con los comandos y la arquitectura correspondientes.

Próximos pasos: **el orden y el método los fija ahora el [Plan de desarrollo-001](./docs/Plan%20de%20desarrollo-001.md)**
(**F0** = esqueleto que camina con `GET /v1/club`; después, **F1–F10**, la ingesta).
El diseño de API/BD está cerrado en lo esencial (modelo de datos, contrato, tenancy —**medida**
contra Postgres real— y roles). Lo inmediato es el **esqueleto del backend**: un *target* SwiftPM por capa (LLD
§2.2) para que la regla de dependencia la imponga el compilador, la fontanería de tenancy levantada del
[spike](./spikes/tenancy/README.md), el plugin de generación del *spec*, y los *targets* de test por nivel (§8.1).
Sigue pendiente de diseño: forma del *tier* dedicado (§9.2), fallo parcial y paralelismo de las migraciones por
tenant (§9.3), política de retención RGPD (§9.4) y estimación de costes cloud por *tier*.

## Equipo

El desarrollo cuenta con un único desarrollador humano, con la ayuda de Claude Code.
