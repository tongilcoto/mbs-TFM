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
  `Competition` si hacen falta y **encola** la primera ingesta → **202**, no 201. ⚠️ **La razón escrita de ese
  202 —que la FCF costaba ~34 peticiones— ha caducado**: hoy cuesta una (ver más abajo y `D-74`). El `202`
  puede seguir siendo lo correcto por desacoplamiento, pero **no se da por bueno sin rehacerle el
  argumento**. `POST /v1/competitions` se conserva solo como vía para semillas, *scripts* y tests.
- **`modality` y `gender`, cuando el equipo lo crea la ingesta, los hereda de su `Competition`** (§3.2, `D-07`, `D-58`): los dos entran en la
  clave única de `Team` y **ninguno es campo de escritura de `Team`**. La federación no publica género por
  equipo —va en el nombre de la competición—, así que el `/preview` lo propone y el administrador lo confirma
  en el alta. No devolver `gender` a `UpdateTeamRequest`: una inferencia mal puesta ahí no da un dato feo, da
  un 409 de unicidad.
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
- **Dos consecuencias de eso que están sin resolver, y tocan en F3.** `D-56` (*ausente o vacío nunca
  sobrescribe*) y la cadencia semanal de §5.6 se apoyan en que *"la FCF borra la fecha al jugarse el
  partido"* — una temporada entera ya jugada las **conserva en 240 de 240**. Y `D-67` justifica su `202` con
  las *"~34 peticiones"* de la FCF, que ahora es **1**. Las reglas pueden seguir siendo buenas; **sus razones
  escritas han caducado**, y hay que rehacerlas al implementarlas, no darlas por buenas.
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
`Competition` en dominio y persistencia, y **F2**, el puerto `FederationClient` con el adaptador del
calendario de la RFFM contra volcados reales (Plan §4.3). **102 tests.** **Web backoffice, app iOS y app
Android siguen sin empezar.**

**F1 no tiene superficie HTTP, y es deliberado** (Plan §4.1): entrega entidades, *Value Objects*, puertos,
`Record`s y migraciones, y **ningún caso de uso** — su llamante es la cascada de `D-67`, que es F10. La lista
de operaciones del `filter` sigue siendo la de F0, que es como se lee el alcance entregado (`D-69`).

Sí existe ya un **artefacto ejecutable**: el *spec* OpenAPI en [`backend/Sources/APIContract/openapi.yaml`](./backend/Sources/APIContract/openapi.yaml), que se construye **entidad a entidad** en paralelo al §5 del LLD (hoy: `Club`, `Season`, `Competition`, `OpponentClub`, `Team`, `Round`, `Match`, `StandingRow`, `LeagueScorer` — con la que queda **cerrada toda la superficie de salida de la ingesta**— y, del **dominio manual**, `Player`, `Absence`, `Appearance`, `Card` y `Goal` con CRUD completo, más `CompetitionSanctionBracket`, que es **configuración** y se escribe como conjunto con un `PUT` (`D-50`). más las cuatro de **roles y permisos** (`StaffMember`, `StaffPosition`, `PositionPermission`,
`StaffAssignment`), más `TeamRegistration`, la inscripción del equipo en la temporada (`D-68`). **El contrato queda completo: las 20 entidades del §3.2 tienen sus endpoints**). Validación:

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
            ├─► Tenancy
            └─► Application ────► Domain        (Domain no depende de nada)

            Federation ────────► Application    (adaptadores RFFM / FCF)
```

`Federation` **todavía no cuelga de `App`**, y no es un olvido: su primer llamante es el job de ingesta (F6)
y el `/preview` (F10). Hoy lo mantiene en el grafo de *build* su *target* de tests.

| Target | Capa (§2.2) | Qué contiene |
|---|---|---|
| `Domain` | Dominio | Entidades, *Value Objects*, catálogo de federaciones. **Sin** `import Vapor/Fluent` |
| `Application` | Aplicación | Casos de uso y **puertos** (`ClubRepository`, `TenantUnitOfWork`) |
| `APIContract` | — | Generado del *spec* por el plugin. **No se edita a mano** |
| `HTTPAdapter` | Adaptador primario | Conforma el `APIProtocol` generado; mapea DTO ↔ dominio |
| `Persistence` | Adaptador secundario | `…Record` de Fluent, repositorios, migraciones |
| `Federation` | Adaptador secundario | Adaptadores de las APIs de federación. **Sin Vapor ni Fluent**: lo que hace es parsear texto ajeno |
| `Tenancy` | Infraestructura | Plano de control, `SET LOCAL search_path`, middleware |
| `App` | — | **Raíz de composición**: el único sitio que cablea las capas |

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
swift run Run serve
curl http://atleti.localhost:8080/v1/club   # el club va en el subdominio (§6.1)
HTTP_TRACE=1 swift test --filter APITests --no-parallel   # ver los cuerpos HTTP
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
Con F0, F1 y F2 entregadas, lo inmediato es **F3: la política de *upsert*** —descriptivo, volátil, propiedad
y emparejamiento (§3.7, `D-56`)—, que es **unit puro y cero I/O**. Es además donde el bucle de Plan §5.1 se
aplica en serio: si la función es `merge(existing:incoming:)`, el esqueleto es **devolver `incoming`** —pisar
siempre, la implementación ingenua que `D-56` existe para prohibir—, y contra él cada test de la fase falla
por su aserción y con el dato delante. Llega con un deber apuntado: **la
justificación de `D-56` hay que rehacerla**, porque su ejemplo estrella —que la FCF borra la fecha al jugarse
el partido— es falso desde el rediseño de esa web (`D-74`). La regla puede seguir siendo buena; su argumento
no se da por bueno.

Y un aviso para **F5**: el volcado de calendario que tenemos es de una **temporada sin arrancar**, así que la
rama de "partido jugado" no la ejercita ningún dato real. Hace falta **un volcado de temporada en curso**
antes de estrenar la ingesta de resultados (Plan §4.3). Ojo al montar ese puerto: hay ingesta ya escrita en la app iOS
`rffm-agenda-ios`, de la que se hereda la forma y las coordenadas, pero **no** su estado mutable entre
llamadas ni su modelo de pantalla sin identificadores de federación (Plan §7).
Sigue pendiente de diseño: forma del *tier* dedicado (§9.2), fallo parcial y paralelismo de las migraciones por
tenant (§9.3), política de retención RGPD (§9.4) y estimación de costes cloud por *tier*.

## Equipo

El desarrollo cuenta con un único desarrollador humano, con la ayuda de Claude Code.

[Anexo FCF §C.10]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo RFFM §F.7, §F.15]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
