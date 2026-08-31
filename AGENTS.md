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
| **API backend + Base de datos** | [ADR-API_y_BBDD-001](./docs/ADR-API_y_BBDD-001.md) — tecnología BD/API y despliegue (ver resumen abajo) | [API_y_BBDD LLD-001](./docs/API_y_BBDD%20LLD-001.md) — arquitectura Clean/Hexagonal/DDD, modelo de datos, ORM, contrato API · Anexos: [Decisiones de diseño — bitácora](./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) · [Federación de Madrid (RFFM)](./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md) · [Federación de Cataluña (FCF)](./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md) | [mockups móvil](./docs/design-assets/mobile/) · [OpenAPI](./backend/Sources/APIContract/openapi.yaml) |
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
  `Competition` si hacen falta y **encola** la primera ingesta → **202**, no 201. Su razón escrita —que la
  FCF costaba ~34 peticiones— **caducó** (hoy cuesta una, `D-74`) y **está rehecha en F3**: el `202` se
  mantiene porque lo caro es lo que viene *detrás* del calendario —~240 partidos y **un escudo por club** que
  descargar y subir a Storage (`D-19`)— y porque encolar es lo que permite reintentar sin romper el enganche.
  F10 tiene que medirlo para cerrarlo del todo. `POST /v1/competitions` se conserva solo como vía para
  semillas, *scripts* y tests.
- **La cadena de emparejamiento tiene tres pasos, y los tres se escribieron en F4 con enmienda** (§3.7):
  el paso 2 de equipos compara **la clave única entera** —nombre normalizado, categoría, **letra**, género y
  modalidad—, porque *"nombre más categoría"* fusionaba el "Infantil A" y el "Infantil B" del mismo club
  (`D-77`); el *"si no"* que encadena los pasos significa **"si el anterior no resolvió"**, no *"si el dato no
  viene"*, o `D-76` no llega a ocurrir nunca (`D-78`); y cuando el paso inexacto encuentra dos, **no se
  decide: se reporta** (`D-79`). Al tocarla, dos cosas: la *"marca para revisión manual"* de §3.7 **no es una
  columna** —es el escalón que devuelve la cadena—, y el paso 2 **no puede alcanzar equipos propios sin
  enganchar**, que es el límite que `D-76` le dejó escrito.
- **`modality` y `gender`, cuando el equipo lo crea la ingesta, los hereda de su `Competition`** (§3.2, `D-07`, `D-58`): los dos entran en la
  clave única de `Team` y **ninguno es campo de escritura de `Team`**. La federación no publica género por
  equipo —va en el nombre de la competición—, así que el `/preview` lo propone y el administrador lo confirma
  en el alta. No devolver `gender` a `UpdateTeamRequest`: una inferencia mal puesta ahí no da un dato feo, da
  un 409 de unicidad.
- **La inscripción del equipo lleva la competición, y eso se decidió antes de que la tabla existiera**
  (`D-68` + enmienda): `TeamRegistration` es `(team_id, season_id, competition_id?)`. La razón no es
  rendimiento —derivar la pareja de `Match` cuesta milisegundos, medido en §9.12— sino que **hay un instante
  en que el sistema sabe que un equipo va con una competición y no lo puede leer**: entre el `202` del
  enganche (`D-67`) y la primera pasada no existe ni un `Match`. Es el mismo agujero que creó la entidad en
  el eje de la temporada, tapado ahora en el de la competición. **No es `Participation`** (`D-27`): la
  escribe el club, no la ingesta. Al tocarla: el `UNIQUE` de tres columnas va con **`NULLS NOT DISTINCT`**, y
  la coherencia con la temporada es una **FK compuesta**, no una guarda.
- **La federación es un catálogo en código, no una tabla** (§3.6): soportar una nueva exige un adaptador.
  Lo que sí es dato es cuál es la del club (`Club.federation`), una por tenant. El catálogo describe también
  **qué sabe hacer** cada proveedor, no solo sus coordenadas (`D-17`, `D-55`).
- **Los dos proveedores se parecen mucho más de lo que dicen los documentos antiguos, y eso es reciente.**
  El 2026-08-28 se descubrió que **la FCF ha rehecho su web y ahora publica una API JSON** ([D-74],
  [Anexo FCF §C.10]): coordenada de tres códigos numéricos como la de Madrid, calendario entero en **una**
  petición, identificador de partido (`CODACTA`) e identificador de club como campo propio. **§C.1–§C.9 del
  anexo FCF están obsoletas** — describen el sitio de raspado anterior. De las diferencias que ese anexo daba
  por medidas, **solo sobrevive una**: la FCF publica **únicamente la clasificación vigente** (`D-55`,
  reverificado), así que las jornadas anteriores al alta se calculan (`D-15`).
- **Esas dos razones caducadas se rehicieron en F3, y ninguna regla cambió: cambiaron de argumento.**
  `D-56` (*ausente o vacío nunca sobrescribe*) ya no se apoya en que la FCF borre nada —no lo hace: 240 de
  240— sino en que **los dos errores no cuestan lo mismo** (`D-75`): ignorar un vacío real se corrige solo en
  la pasada siguiente; escribir un silencio pierde el dato y `Match` no tiene `PATCH`. La cadencia semanal de
  §5.6 sigue siendo **requisito**, pero por `D-55` —la clasificación de la FCF no se puede pedir hacia
  atrás—, no por la fecha. Y el `202` de `D-67`, arriba. **La lección se repite: una regla puede sobrevivir a
  su ejemplo, pero hay que ir a comprobarlo.**
- **Una coordenada caducada no falla: devuelve el calendario de otra competición** (`D-84`). Se descubrió en
  F5 capturando un volcado que se pedía para otra cosa: **la RFFM reutiliza los códigos de competición y grupo
  entre temporadas**, así que `competicion=24037548&grupo=24037549` da PREFERENTE AFICIONADO con
  `temporada=22` y PRIMERA DIVISION AUTONOMICA CADETE con `temporada=21`. Y **no da 404 nunca** en esa ruta:
  con `competicion`/`grupo` inexistentes responde `200` con `calendar: null`, y con una `temporada`
  inexistente responde `200` con el calendario de otra e **ignora el parámetro**. Consecuencias: confirma con
  dato la regla de §3.5 (`Competition` se identifica por `season_id` **+** `federation_group_id`); obliga a la
  ingesta a **comparar el nombre contra `Competition.federation_name` antes de escribir**; y le da al canario
  de Plan §4.4 **cuatro** señales en vez de dos. Al tocar cualquier adaptador de federación: **una premisa
  sobre un sistema de terceros no se hereda, se mide** — ésta llevaba escrita desde F2 y era falsa.
- **El recorrido de la ingesta no se detiene en el primer fallo, y eso solo es seguro por dos cosas que ya
  estaban puestas** (`D-86`): la pasada es **atómica** (`D-83`) y **deja constancia** de su fallo (`D-85`). La
  unidad de aislamiento es la **competición**: abortar haría que una sola coordenada caducada —de las que
  `D-84` demuestra que existen y que no dan error— dejara sin sincronizar a todo lo que va detrás. Las dos
  mitades son inseparables: **se continúa y se apunta**, y el comando sale con código distinto de cero. Ojo al
  copiar esto a las migraciones por tenant (§9.3): **no es la misma pregunta** — una migración a medias deja
  *schemas* a distinta versión y nada que lo diga.
- **La cadencia de la ingesta vive fuera del proceso; lo que el código trae es un antirrebote** (`D-87`). No
  hay temporizador dentro del servidor: lo dispara un cron (§5.6 pide **lunes** + fin de semana). El
  `--min-interval-hours` (6 por defecto) es un **mínimo** que hace inofensivo un disparo de más — **no es el
  tope semanal**, que es un máximo y lo hace cumplir el calendario de disparos. Y **la competición que nunca
  se sincronizó entra siempre**: sin esa excepción, la recién dada de alta por el enganche de `D-67` esperaría
  para siempre. Lo encontró la comprobación de mutación, no un rojo.
- **El módulo de ingesta asoma exactamente dos endpoints, y el `POST` no crea filas** (`D-88`).
  `GET /v1/ingestion-runs` lee el registro; `POST /v1/ingestion-runs` **pide que el job pase** —el cuerpo no
  lleva ni un campo de la pasada, lleva qué sincronizar, igual que `Competition` como entrada (`D-16`)—, y
  responde **200** con una competición (cabe en la respuesta) o **202** con una temporada (decenas de
  competiciones y ~240 partidos cada una: es `D-67` un nivel más abajo). El `202` **planifica antes de
  responder**, para que una `seasonId` inexistente dé 404 y no un 202 con un fallo invisible detrás. El cuerpo
  lleva **lista** de competiciones porque la pantalla que lo usa son equipos con una casilla al lado: marcar
  tres es **una** acción del usuario. Y diseñarlo destapó §9.12 — **ninguna lectura sirve la terna *(equipo,
  temporada, competición)***, que es lo que el backoffice llama *"un equipo"*; hoy costaría N+1 peticiones.
  No es fallo del modelo (la participación se deriva por diseño, `D-27`/`D-28`): es una vista derivada que
  falta.
- **Ojo con el atajo "RFFM = JSON, FCF = *scraping*": ya no vale por partida doble.** La FCF es JSON puro; y
  en la RFFM el **calendario sigue siendo HTML** con el JSON dentro de un `__NEXT_DATA__` embebido
  ([Anexo RFFM §F.7, §F.15]) — solo sus rutas `/api/…` son JSON directo. Evidencia campo a campo en los
  anexos y en `docs/Federation APIs examples/`; **no deducir nada de memoria, y revalidar el anexo antes de
  escribir su adaptador** — es la lección de `D-74`.

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

Las **decisiones tecnológicas de BD/API y despliegue están tomadas** (ver ADR y resumen arriba) y el
**backend camina**: del [Plan de desarrollo](./docs/Plan%20de%20desarrollo-001.md) están entregadas **F0**
—`GET /v1/club` responde de HTTP a Postgres contra tenants aislados—, **F1**, que añade `Season` y
`Competition` en dominio y persistencia, **F2**, el puerto `FederationClient` con el adaptador del
calendario de la RFFM contra volcados reales (Plan §4.3), **F3**, la **política de *upsert*** de §3.7
—`UpsertPolicy`, `Kickoff` y `MatchResult` en el Dominio, sin una sola bandera nueva en el esquema (Plan
§4.5)—, **F4**, la **cadena de emparejamiento** —`MatchingChain`, `MatchOutcome` y `NormalizedName`, también
sin columnas nuevas (Plan §4.6)—, **F5**, la **ingesta del calendario de punta a punta** —las cuatro
entidades de salida contra Postgres real, el transporte HTTP y el canario (Plan §4.7)—, y **F6**, el **job**:
el `AsyncCommand`, el recorrido por tenant, la cadencia y **los dos primeros endpoints desde F0** (Plan §4.8).
**246 tests.** **Web backoffice, app iOS y app Android siguen sin empezar.**

**F5 es la fase que junta lo que F3 y F4 entregaron sueltos**: la cadena decide qué fila es, `UpsertPolicy`
decide qué se le escribe. El volcado real de una temporada jugada entra entero —30 jornadas, 240 partidos, 16
equipos— y la segunda pasada no duplica nada contra los `UNIQUE` de verdad. Trae además **la entidad 21 del
modelo**, `IngestionRun` (`D-85`): el registro de cada pasada, escrito **fuera** de su transacción para que
sobreviva al `rollback` de la que falla — que es la única que nadie ve, porque la ingesta no tiene usuario
delante.

**De F0 a F5 no se añadió un solo endpoint, y no fue un descuido: era el plan.** F1 entrega entidades,
*Value Objects*, puertos, `Record`s y migraciones **sin ningún caso de uso**; F3 y F4, dos reglas puras sin
llamante; y F5, la pasada entera, cuyo adaptador primario es un `AsyncCommand` y **no un Controller**
(§2.3-b). **F6 es la primera que mueve el `filter`**, con las dos operaciones que el módulo de ingesta sí
necesita asomar (`D-88`): `GET /v1/ingestion-runs` —el registro de `D-85`, que si no no lo lee nadie— y
`POST /v1/ingestion-runs`, el disparador manual del job. Las siguientes llegan en **F10**
(`POST /teams/{id}/federation-link` + `/preview`). El `filter` de `openapi-generator-config.yaml` **es**
literalmente el alcance entregado (`D-69`): al añadir un endpoint, se añade ahí primero — y el compilador
para el *build* hasta que el *handler* exista.

Sí existe ya un **artefacto ejecutable**: el *spec* OpenAPI en [`backend/Sources/APIContract/openapi.yaml`](./backend/Sources/APIContract/openapi.yaml), que se construye **entidad a entidad** en paralelo al §5 del LLD (hoy: `Club`, `Season`, `Competition`, `OpponentClub`, `Team`, `Round`, `Match`, `StandingRow`, `LeagueScorer` — con la que queda **cerrada toda la superficie de salida de la ingesta**— y, del **dominio manual**, `Player`, `Absence`, `Appearance`, `Card` y `Goal` con CRUD completo, más `CompetitionSanctionBracket`, que es **configuración** y se escribe como conjunto con un `PUT` (`D-50`). más las cuatro de **roles y permisos** (`StaffMember`, `StaffPosition`, `PositionPermission`,
`StaffAssignment`), más `TeamRegistration`, la inscripción del equipo en la temporada (`D-68`). **El contrato queda completo: las 20 entidades que §3.2 tenía cuando se cerró tienen sus endpoints**).
**La 21ª, `IngestionRun`, ya también**: la añadió F5 al modelo y F6 le dio su recurso, con el job delante
(`D-85`, `D-88`). Validación:

```sh
npx @redocly/cli lint backend/Sources/APIContract/openapi.yaml
```

### El backend: cómo está montado y cómo se trabaja

> **Para levantarlo, hablarle con `curl`, mirar la BD con TablePlus o ver los cuerpos que cruzan la frontera
> en los tests: [`backend/README.md`](./backend/README.md)** — el manual de a bordo, verificado comando a
> comando. Lo de aquí abajo es el mapa; ése es el manual.

Paquete SwiftPM en `backend/`, **Swift 6** en todos los *targets* (modo de lenguaje `.v6` + *upcoming
features*; **sin** `defaultIsolation: MainActor`, que es recomendación de apps, no de un backend).

**Un *target* por capa, y el grafo de `Package.swift` ES la Regla de dependencia de §2.2** — no una
convención de carpetas. Comprobado: `import Vapor` desde `Domain` o `Application` **no compila**.

```
Run ─► App ─┬─► HTTPAdapter ─┬─► APIContract   (tipos generados del spec)
            │                └─► Application
            ├─► Persistence ────► Application
            ├─► Federation ─────► Application   (adaptadores RFFM / FCF)
            ├─► Tenancy
            └─► Application ────► Domain        (Domain no depende de nada)
```

**`Federation` cuelga de `App` desde F6**, y hasta entonces no colgaba: de F2 a F5 lo mantuvo en el grafo de
*build* su *target* de tests, porque el adaptador no tenía llamante. Ese llamante es el job de ingesta
(§2.3-b), y la raíz de composición es el único sitio donde el puerto y su implementación se conocen.

| Target | Capa (§2.2) | Qué contiene |
|---|---|---|
| `Domain` | Dominio | Entidades, *Value Objects*, catálogo de federaciones y **las dos mitades de §3.7**: la política de *upsert* (F3) y la **cadena de emparejamiento** (F4). F5 añade las cuatro entidades de la **salida** de la ingesta —`Round`, `OpponentClub`, `Team`, `Match`— y `IngestionRun`. **Sin** `import Vapor/Fluent` |
| `Application` | Aplicación | Casos de uso y **puertos** (`ClubRepository`, `TenantUnitOfWork`, `FederationClientProvider`). F6 añade `IngestClubCalendars`: **el recorrido de un club**, con sus reglas de alcance y de fallo |
| `APIContract` | — | Generado del *spec* por el plugin. **No se edita a mano** |
| `HTTPAdapter` | Adaptador primario | Conforma el `APIProtocol` generado; mapea DTO ↔ dominio |
| `Persistence` | Adaptador secundario | `…Record` de Fluent, repositorios, migraciones |
| `Federation` | Adaptador secundario | Adaptadores de las APIs de federación. **Sin Vapor ni Fluent**: lo que hace es parsear texto ajeno |
| `Tenancy` | Infraestructura | Plano de control, `SET LOCAL search_path`, middleware |
| `App` | — | **Raíz de composición**: el único sitio que cablea las capas. Y los `AsyncCommand`: `migrate-tenants`, `provision-tenant` e `ingest` (F6) |

```sh
cd backend
docker compose up -d                      # Postgres 16 efímero en :5434
swift build
swift test                                # 4 niveles (§8.1); los 2 primeros sin I/O
swift test --filter FederationTests       # los adaptadores de federación: sin red y sin Docker
                                          # (sus volcados: Tests/FederationTests/Fixtures/README.md —
                                          #  son copias de docs/, y en Xcode no se leen: una sola línea)
swift run Run migrate --yes               # plano de control (public.tenants)
swift run Run provision-tenant atleti     # alta de club: schema + registro + migraciones
swift run Run migrate-tenants             # recorre todos los clubes (§4.7)
                                          # hoy: clubs -> seasons -> competitions
swift run Run ingest                      # LA PASADA DE INGESTA (§2.3-b, F6)
                                          #   -t <slug[,slug]>  solo esos clubes
                                          #   -c <uuid>         solo esa competición
                                          #   --season <uuid>   esa temporada, aunque no sea la vigente
                                          #   --force           ignora el antirrebote de 6 h
                                          # Sale con código != 0 si algo falló: es la
                                          # única señal que ve el cron (`D-86`)
swift run Run serve
curl http://atleti.localhost:8080/v1/club   # el club va en el subdominio (§6.1)
curl "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<uuid>"   # el registro (D-85)
HTTP_TRACE=1 swift test --filter APITests --no-parallel   # ver los cuerpos HTTP
FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests     # el CANARIO: pasa el parser por
                                          # encima de la respuesta VIVA (Plan §4.4). Fuera de
                                          # `swift test`, y con red. Coordenada configurable por
                                          # FEDERATION_LIVE_SEASON/_COMPETITION/_GROUP/_NAME
docker compose down -v
```

**Cinco cosas que hay que saber antes de tocar este código:**

- **El *spec* se genera *filtrado*** (`D-69`). `APIProtocol` obliga a implementar **todas** las operaciones
  generadas, así que el `filter` de `openapi-generator-config.yaml` lista solo las implementadas — esa lista
  **es** el alcance entregado. Al añadir un endpoint, **se añade ahí primero**. El *spec* no se toca: sigue
  completo.
- **Todo acceso a datos de tenant entra por `TenantUnitOfWork`** (§6.2). No se pasan `Database` por ahí: el
  aislamiento depende de que haya **un** punto de paso.
- **El contexto de actor (`ActorContext`) ya cruza la frontera de los casos de uso** (§7.4), aunque hoy solo
  lleve el club. Un caso de uso nuevo lo recibe **desde el principio**, no cuando llegue §7.
- **El ámbito de tenant *es* una transacción, y eso condiciona cómo se escribe un test** (§6.2). Lo que se
  escriba dentro de un `withRepositories` **no lo ve otra conexión** hasta que cierra, así que un `SELECT` en
  crudo para comprobar una columna no encuentra nada; y una violación de restricción **aborta la transacción
  entera** (`25P02`), de modo que dos intentos que deban fallar en el mismo ámbito hacen que el segundo pase
  por el motivo equivocado. `TenantFixture` (nivel 3) obliga a declarar cada ámbito justo por eso.
- **El `CHECK` de un enumerado se deriva, nunca se teclea** (§4.6, `D-02`): `sqlValueList` es genérico sobre
  `CaseIterable where RawValue == String`, así que un enumerado nuevo lo hereda solo. Y el `switch` sobre
  `DomainError` en `ProblemMiddleware` es **exhaustivo** a propósito — un caso de error nuevo no compila hasta
  que alguien decida su código HTTP.
- **Los tests citan el diseño.** Cada `@Test` lleva su `§x` o su `D-nn`: es lo que permite revisar una fase
  leyendo los tests en vez del código (Plan §9). `swift-testing`, no XCTest (`D-70`).
- **Y se escriben con esqueleto: el rojo tiene que ser de aserción, no de compilación** (Plan §5.1). Escribir
  el test primero compra la presión de diseño, pero un `cannot find 'X' in scope` **no** demuestra que la
  aserción cace nada, porque no llegó a ejecutarse. Antes de implementar, la función existe con su firma
  definitiva y **devuelve mal a propósito** — un valor válido pero equivocado, nunca `fatalError()`, que
  trapea y se lleva la ejecución entera. Y una regla por ciclo: con un *suite* entero el esqueleto no dice
  nada. Es lo que F2 se saltó (Plan §4.3).

**Si abres el proyecto en Xcode y ves `Cannot find type 'Components' in scope`, no está roto.** `Components`
y el resto del contrato **no existen en disco hasta que el plugin corre** (`D-69`), así que el índice de Xcode
no los conoce **antes de la primera compilación exitosa**. Además, Xcode pide **confiar y habilitar** los
plugins de *build* de paquetes externos: si ese aviso no se acepta, el plugin no corre nunca y el error no se
va. Orden: aceptar el aviso → ⌘B → si persiste, *File ▸ Packages ▸ Reset Package Caches* y volver a compilar.
**La CLI es la fuente de verdad**, no el índice de Xcode: si `swift build` pasa, el código está bien.
*(Comprobado con Swift 6.3.2 y con la 6.4 de Xcode 27 Beta: el paquete compila con las dos.)*

**El club viaja en el subdominio, nunca en una cabecera que ponga el cliente.** `*.localhost` resuelve a
127.0.0.1 sin configurar nada, así que **desarrollo usa la misma vía que producción**:
`http://atleti.localhost:8080/v1/club`. La cabecera `X-Club` existe solo como andamiaje y está **restringida
por lista blanca a `.development` y `.testing`** — aceptarla en producción sería dejar abierto un conmutador
de tenant, porque es un dato que controla el cliente por completo.

**Deuda declarada de F0**, para que nadie la confunda con diseño: el tenant se resuelve por `Host`, **no** por
*claim* firmado. §6.1 dice que el *claim* es autoritativo, el subdominio solo enrutado, y que una discrepancia
**se rechaza**; `TenantResolutionMiddleware` es el sitio donde eso se corregirá.

Próximos pasos: **el orden y el método los fija ahora el [Plan de desarrollo-001](./docs/Plan%20de%20desarrollo-001.md)**
(**F0** = esqueleto que camina con `GET /v1/club`; **F1** = `Season` y `Competition`, la *entrada* de la
ingesta; **F2–F10** = la ingesta propiamente dicha).
Con F0–F6 entregadas, lo inmediato es **F7: `StandingRow`, con la clasificación histórica de la RFFM y el
*fallback* calculado desde `Match`** (`D-15`, `D-55`). **Los tres deberes que F6 arrastraba están hechos**: el
recorrido continúa tras un fallo y la unidad de aislamiento es la competición (`D-86`), la cadencia vive fuera
del proceso y el código trae un antirrebote que no es el tope semanal (`D-87`), y el registro tiene su `GET`
—más un `POST` que dispara la pasada, que no estaba previsto y lo pidió el desarrollador para controlarlo
desde la web (`D-88`)—.

**Queda un deber que no es de código y conviene no perderlo**: **montar el cron**. F6 entrega el comando, pero
quién lo llama los lunes y los fines de semana es una decisión de despliegue; hasta que exista, el tope semanal
de §5.6 **no lo garantiza nada**.

**La vara de medir sigue siendo la misma, y va subiendo**: F3 hizo el bucle de Plan §5.1 entero (doce ciclos,
11/11 mutaciones), F4 lo repitió con **16/16**, F5 con **35 mutaciones, 34 cazadas y 1 equivalente** sobre
**35 ciclos**, y F6 con **23/23** — pero **cinco sobrevivieron a la primera pasada y las cinco eran "falta un
test"**, una de ellas seria: *"la competición que nunca se sincronizó no entra"* pasaba toda la batería, y
significaba que una competición recién dada de alta se quedaría esperando para siempre. Ningún rojo la habría
encontrado, porque ningún test tenía motivo para existir hasta que la mutación preguntó. F5 aportó una lectura que no se había dado: una mutación superviviente son *"falta un test"* o
*"sobra el código"* — **y a veces ninguna de las dos**, porque el programa mutado es el mismo programa
(cruzar los dos marcadores que `Match` le pasa a `Kickoff` no es observable: `Kickoff` solo pregunta *"¿hay
marcador?"*, y esa pregunta es simétrica).

**Y una lección de arnés nueva, de F6: un test de nivel 3 puede romper los de otras suites.** El primer test
del recorrido enumeraba **todos** los tenants de `public.tenants`, y las suites corren en paralelo — así que
se puso a ingerir los clubes de las demás y a escribirles filas en sus *schemas*. **Probar una regla global
con efectos globales, en una batería paralela, no es un test: es una carrera.** Se parte en dos: la regla
*"sin filtro son todos"* se afirma sobre una consulta **sin efectos**, y el recorrido de verdad se lanza sobre
una lista explícita de clubes. Al escribir un test que enumere algo compartido, mirar esto primero.

**Los dos deberes que F5 arrastraba están hechos** (Plan §4.3 y §4.4). El **volcado de temporada en curso**
existe —de hecho es de una temporada **jugada**, la 2025-26 entera: 240 partidos con marcador y con hora, así
que la rama de "partido jugado" ya la ejercita dato real—. Y el ***canario*** está escrito y verificado en
vivo: `FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests`. **No compara bytes** —el calendario cambia cada
semana por diseño—: pasa el parser por encima de la respuesta viva y exige que no falle. Al tocarlo, saber que
tiene **cuatro** señales y no dos, porque `D-84` obligó: sin red · coordenada mala · código HTTP raro ·
formato cambiado. Solo la última es para lo que existe.

Sigue pendiente de diseño: forma del *tier* dedicado (§9.2), fallo parcial y paralelismo de las migraciones por
tenant (§9.3), política de retención RGPD (§9.4) y estimación de costes cloud por *tier*.

## Equipo

El desarrollo cuenta con un único desarrollador humano, con la ayuda de Claude Code.

[Anexo FCF §C.10]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[D-74]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[Anexo RFFM §F.7, §F.15]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
