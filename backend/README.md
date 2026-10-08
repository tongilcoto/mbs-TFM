# Backend · Manual de a bordo

> **Qué teclear** para levantar esto, hablarle y ver qué pasa por dentro.
> **El porqué no está aquí**: está en [`docs/`](../docs/), y este fichero enlaza en vez de repetirlo.

| Si buscas… | Está en |
|---|---|
| cómo se arranca, qué comando hay, por qué falla algo | **este fichero** |
| qué hace cada capa y por qué | [AGENTS.md](../AGENTS.md) · [LLD-001](../docs/API_y_BBDD%20LLD-001.md) |
| por qué se decidió así | [bitácora `D-nn`](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) |
| qué entregó cada fase y qué midió | [Plan de desarrollo](../docs/Plan%20de%20desarrollo-001.md) §4 |

Convención: **`§x` remite al LLD** y `D-nn` a la bitácora. Las remisiones a *este* fichero van como enlace,
porque los números chocan.

| | |
|---|---|
| [0 · Qué hay montado](#0-qué-hay-montado) | [1 · Arranque](#1-arranque-en-60-segundos) |
| [2 · Ejecución y entorno](#2-ejecución-y-entorno) | [3 · La base de datos](#3-la-base-de-datos) |
| [4 · La API con `curl`](#4-la-api-con-curl) | [5 · Los tests](#5-los-tests) |
| [6 · Los comandos](#6-los-comandos) | [7 · El *spec*](#7-el-spec) |
| [8 · Cuando algo falla](#8-cuando-algo-falla) | |

---

## 0. Qué hay montado

Entregadas **F0 a F8** y **F10**, más F6-bis, F6-ter, F9-bis, F10-bis y F10-ter; **F9 aplazada sin código**
(`D-95`). **591 tests.** Qué trajo cada una: [Plan §4](../docs/Plan%20de%20desarrollo-001.md). La
[auditoría 002](./Plan%20de%20auditor%C3%ADa-002.md) está **cerrada** (2026-10-04). Para conectar una
federación nueva: [la guía de alta](../docs/API_y_BBDD%20Guia-Alta-Federacion-001.md).

| Operación HTTP                                                                        |                                   |
| ------------------------------------------------------------------------------------- | --------------------------------- |
| `GET /v1/club` · `PATCH /v1/club`                                                     | F0                                |
| `GET /v1/ingestion-runs` · `POST /v1/ingestion-runs`                                  | F6                                |
| `POST /v1/teams/{id}/federation-link/preview` · `POST /v1/teams/{id}/federation-link` | F10 — [§4.1](#enganche)           |
| Las otras 77 del *spec*                                                               | ⛔ no generadas — [§7](#7-el-spec) |

**Esa lista no dice lo que hay montado, solo lo que se toca con `curl`.** De F1 a F5 no se añadió un endpoint
y era el plan: el adaptador primario de la ingesta es un `AsyncCommand`, no un Controller (§2.3-b). Lo demás
se mira por [la base de datos](#3-la-base-de-datos), por [los comandos](#6-los-comandos) o por
[los tests](#5-los-tests).

---

## 1. Arranque en 60 segundos

```sh
cd backend
docker compose up -d db            # Postgres 16 en localhost:5434
swift run Run migrate --yes        # crea public.tenants (plano de control)

swift run Run provision-tenant atleti \
  --federation rffm --name "Club Atlético de Ejemplo" --short-name "CD Atleti"

swift run Run serve                # la API en :8080 (otro puerto: --port 8765)
```

```sh
curl -s http://atleti.localhost:8080/v1/club | jq     # en otra terminal
```

**`provision-tenant` da de alta un club**: crea su *schema*, lo registra en `public.tenants`, le pasa las
migraciones y escribe su fila en `clubs`. Es idempotente: repetirlo no duplica nada.

| Parámetro | ¿Obligatorio? | Qué es |
|---|---|---|
| `<slug>` (`atleti`) | **sí** | El identificador del club. Va sin guion delante y es **lo que se teclea en el subdominio** para hablarle (`atleti.localhost`), y de él sale el nombre del *schema* |
| `--federation`, `-f` | **sí** | De qué federación se sincroniza el club entero. No hay valor por defecto que no sea inventárselo (§3.6). Hoy solo vale **`rffm`**: `fcf` está en el catálogo pero no tiene adaptador, y se rechaza (H-93) |
| `--name` | no | El nombre oficial. Por defecto, el *slug*. **No tiene forma corta**: `-n` la reserva ConsoleKit |
| `--short-name` | no | El nombre corto. Por defecto, el nombre |
| `--schema`, `-s` | no | El nombre del *schema*. Por defecto, `club_<slug>`; no hace falta cambiarlo |

**`serve` levanta la API.** Sin parámetros escucha en `127.0.0.1:8080`:

| Parámetro | Por defecto | Qué es |
|---|---|---|
| `--port`, `-p` | `8080` | El puerto. Si lo cambias, cambia en todos los `curl`: `http://atleti.localhost:8765/…` |
| `--hostname`, `-H` | `127.0.0.1` | La interfaz donde escucha |
| `--bind`, `-b` | — | Las dos cosas juntas: `-b 127.0.0.1:8765` |

- **`*.localhost` resuelve a 127.0.0.1 sin configurar nada**, así que desarrollo usa la misma vía que
  producción: el club va en el subdominio (§6.1). No hace falta ninguna cabecera.
- Para parar: `Ctrl-C`, y `docker compose down` (conserva datos) o `down -v` (los borra).

---

## 2. Ejecución y entorno

```sh
docker compose up -d db && swift run Run serve   # modo normal: API nativa, BD en Docker
docker compose --profile full up --build         # todo en Docker, release, ~3 min
```

El segundo no sirve para desarrollar; sirve para contestar *"¿esto seguiría funcionando desplegado?"*. Dentro
de compose la API usa `DB_HOST=db` y el puerto **interno** `5432`; desde el Mac es `localhost:5434`. **Es la
misma base de datos.**

| Variable | Por defecto | Para qué |
|---|---|---|
| `DB_HOST` / `DB_PORT` | `localhost` / `5434` | `db` / `5432` dentro de compose |
| `DB_USER` / `DB_PASSWORD` / `DB_NAME` | `tfm` | |
| `DOMAIN_SUFFIX` | `localhost` | El sufijo que se recorta del `Host` (§6.1) |
| `LOG_LEVEL` | `info` | `debug` muestra cada petición y cada SQL. Vale también en `swift test` |
| `HTTP_TRACE` | apagado | `1` vuelca los **cuerpos** HTTP. Solo en `.development` / `.testing` |
| `REQUIRE_DB` | apagado | `1` hace **fallar** los tests de BD en vez de omitirlos ([§5](#5-los-tests)). `CI` la activa sola |
| `KEEP_TEST_DATA` | apagado | `1` conserva los *schemas* de test. **Solo la mira `swift test`** |

> **`--log debug` NO enseña los cuerpos, y ninguna combinación de niveles lo hará.** Vapor registra la línea
> de petición, las cabeceras y el SQL, nunca el cuerpo. Para eso está `HTTP_TRACE=1`, que es una variable
> aparte y no un nivel de log. Está restringida a `.development`/`.testing` porque estos cuerpos llevan datos
> **de menores** (§3.2): un volcado completo en producción es una fuga, no un log verboso.

```sh
HTTP_TRACE=1 swift run Run serve --log debug     # cuerpos + SQL
```

---

## 3. La base de datos

**TablePlus / psql** — host `127.0.0.1`, puerto **5434**, usuario y contraseña `tfm`, SSL desactivado.

| | `tfm` | `tfm_test` |
|---|---|---|
| Quién escribe | tú, y `swift run Run …` | `swift test` |
| *Schemas* de club | `club_<slug>` | `test_<slug>` y `e2e_<slug>` |
| Si la borras | pierdes tu trabajo | nada: se recrea sola |

```
tfm
├── public          ← plano de control: tenants   (+ su _fluent_migrations)
├── club_atleti     ← un club: sus ONCE tablas    (+ su _fluent_migrations)
└── club_celtic     ← otro club: las mismas tablas, datos distintos
```

Las once de hoy, en el orden en que se crean — **no son las 21 entidades de §3.2**, solo las que las
fases entregadas han necesitado:

```
clubs · seasons · opponent_clubs · teams · competitions · rounds · matches
      · standing_rows · league_scorers · ingestion_runs · team_registrations
```

**Cada *schema* tiene su propia `_fluent_migrations`**: el progreso se rastrea por club, y revertir uno no
toca a los demás (§4.7). La API no filtra por `club_id` — fija `search_path` y el mismo SQL lee de uno o de
otro (§6.2), y por eso ninguna tabla lleva columna de club ni ninguna ruta `clubId`.

```sh
docker compose exec db psql -U tfm -d tfm
\dn                        -- los schemas: ahí están los clubes
\dt club_atleti.*          -- las tablas de un club
```

---

## 4. La API con `curl`

**A qué club le hablas lo dice el subdominio**: `atleti.localhost` es el club con *slug* `atleti`. La ruta
no lleva el club en ningún sitio.

```sh
curl -s http://atleti.localhost:8080/v1/club | jq

curl -s -X PATCH http://atleti.localhost:8080/v1/club \
  -H 'Content-Type: application/json' -d '{"name":"Renombrado"}' | jq
```

`PATCH` es **parcial**: lo que no mandas no se toca (§5.5).

**Dos campos del `GET` no se guardan en la base**: `federationProvidesRoundStandings` (la federación publica
la clasificación de cada jornada) y `federationProvidesScorers` (publica goleadores). Dicen **qué puede
traer la ingesta para este club** y dependen solo de su federación, así que se calculan al responder a
partir del catálogo de federaciones que vive en el código (`Sources/Domain/FederationCode.swift`, `D-17`).
Cambiar lo que publica una federación es tocar ese fichero, no un dato.

**Los errores llegan como `application/problem+json`** (§5.4): el `code` es para que un programa decida, y el
`title` es para leerlo. Los que salen al montar o al llamar están en [§8](#8-cuando-algo-falla).

**Si no puedes usar el subdominio**, hay una alternativa en desarrollo: llamar a `localhost` sin subdominio
y decir el club en la cabecera `X-Club`. Sirve para herramientas que no resuelven `*.localhost` o que no
permiten tocar el `Host`:

```sh
curl -s -H 'X-Club: atleti' http://localhost:8080/v1/club | jq
```

`X-Club` **solo funciona en `.development` y `.testing`**: cualquier cliente puede poner la cabecera que
quiera, así que en producción serviría para leer otro club con solo cambiarla (§6.1).

<a id="enganche"></a>

### 4.1 El enganche — dar de alta lo que la ingesta va a sincronizar

La ingesta ([§4.2](#42-la-ingesta)) no busca sola qué sincronizar: recorre **las competiciones que el club
ya tiene dadas de alta**. Con el club recién creado no hay ninguna, y una ingesta no hace nada. Esto va
primero.

**Una competición se da de alta enganchando un equipo del club**: se pega en la ficha del equipo la URL de
su calendario en la web de la federación (`D-67`). Con eso se crean de una vez la temporada (si no existía),
la competición y la inscripción del equipo, y se encola su primera ingesta.

> **Cuando exista la web**, esto se hace desde la ficha del equipo y los `curl` de aquí sobran. Hasta
> entonces, este es el camino, y son tres pasos.

**Paso 0 — el equipo.** `POST /v1/teams` es del *backoffice* y no está hecho, así que el equipo se crea con
un comando ([§6.2](#62-seed-team--el-equipo-propio-para-poder-engancharlo)):

```sh
TEAM=$(swift run Run seed-team -t atleti -c cadete -g masculino -m futbol_11 -l A | grep -o '[0-9a-f-]\{36\}')
```

| Parámetro | ¿Obligatorio? | Qué es |
|---|---|---|
| `--tenant`, `-t` | **sí** | El *slug* del club |
| `--category`, `-c` | **sí** | Edad: `prebenjamin`, `benjamin`, `alevin`, `infantil`, `cadete`, `juvenil`, `senior` |
| `--gender`, `-g` | **sí** | `masculino`, `femenino`, `mixto` |
| `--modality`, `-m` | **sí** | `futbol_11`, `futbol_7`, `futbol_5`, `futbol_sala`, `futbol_playa` |
| `--letter`, `-l` | no | Distingue equipos de la misma edad, género y modalidad (`A`, `B`…). **Sin `-l` es otro equipo, no "cualquiera"**: el que no lleva letra porque es el único |

**Las cuatro primeras no se pueden cambiar después** (`D-58`), y equivocarse no da un error al crear el
equipo, sino un **409** al engancharlo, si la competición es de otra edad, género o modalidad. El comando
imprime el UUID del equipo; la línea de arriba lo guarda en `$TEAM`.

**Paso 1 — verificar.** Se manda la URL del calendario, copiada tal cual de la web de la federación. El
servidor **consulta a la federación en ese momento y no guarda nada**: devuelve lo que hay en esa URL para
que lo mire una persona.

```sh
URL="https://www.rffm.es/competicion/calendario?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549"

curl -s -X POST http://atleti.localhost:8080/v1/teams/$TEAM/federation-link/preview \
  -H 'Content-Type: application/json' -d "{\"federationCalendarUrl\":\"$URL\"}" | jq
```

La respuesta tiene esta forma (recortada):

```json
{
  "season":      { "federationSeasonId": "21", "label": "2025/26", "exists": false },
  "competition": {
    "ageCategory": "cadete", "gender": "masculino", "modality": "futbol_11",
    "divisionLabel": "Primera", "groupLabel": "Grupo 1", "roundCount": 30,
    "alreadyRegistered": false,
    "teams": [
      { "federationTeamId": "3349086", "rawName": "CELTIC CASTILLA C.F. 'A'" },
      { "federationTeamId": null,      "rawName": "OTRO EQUIPO" }
    ]
  },
  "identityMatches": true,
  "ageCategoryChecked": true
}
```

**Qué mirar, en este orden:**

| Campo | Qué dice | Qué hacer |
|---|---|---|
| `competition.teams[]` | Los equipos del grupo, con el nombre tal cual lo publica la federación | **Buscar el tuyo y apuntar su `federationTeamId`**: es el `ownTeamFederationId` del paso 2. Es la comprobación importante: un dígito mal en la URL **no da error**, devuelve el calendario de otra liga (`D-84`), y solo una persona que no encuentra su club en la lista lo detecta (`D-16`) |
| `teams[].federationTeamId: null` | La federación publica ese equipo sin código | Se ve, pero **no se puede elegir**. Si es el tuyo, no se puede enganchar con esta URL |
| `competition.ageCategory` · `gender` · `modality` | Edad, género y modalidad de la competición | Comprobar que son las del equipo. `gender` es una **propuesta**: se deduce de si el nombre dice `FEMENINO`, y en el paso 2 se confirma o se corrige |
| `identityMatches` | `true` si las tres de arriba coinciden con las del equipo | En `false`, **el paso 2 dará 409**. O la URL no es de este equipo, o el equipo se creó con algo mal |
| `ageCategoryChecked` | `false` si la edad **no se ha podido comprobar** | Pasa cuando la competición es nueva y su nombre no dice edad (*"TERCERA FEDERACIÓN RFEF"*): entonces se usa la del equipo y `identityMatches` sale `true` sin saberlo. **Compruébalo tú**: si no es su edad, la competición se crea mal y todos los rivales la heredan (A-12·H-75) |
| `season.label` · `season.exists` | La temporada que dice la federación, y si ya está en la base | En `false`, el paso 2 **la creará**. Su `label` es lo que se manda como `seasonLabel` |
| `competition.alreadyRegistered` | `true` si ese grupo ya está dado de alta en esa temporada | Avisa de que ese grupo ya existe. Puede ser normal (otro equipo del club en el mismo grupo) o un enganche repetido |

**Paso 2 — confirmar.** Se vuelve a mandar la URL (el paso 1 no guardó nada), con lo que has comprobado:

```sh
curl -s -i -X POST http://atleti.localhost:8080/v1/teams/$TEAM/federation-link \
  -H 'Content-Type: application/json' \
  -d "{\"federationCalendarUrl\":\"$URL\",\"ownTeamFederationId\":\"3349086\",\"gender\":\"masculino\",\"seasonLabel\":\"2025/26\"}"
```

| Campo | ¿Obligatorio? | Qué va |
|---|---|---|
| `federationCalendarUrl` | **sí** | La misma URL del paso 1 |
| `ownTeamFederationId` | **sí** | El `federationTeamId` de tu equipo en `teams[]`. Si no está en esa lista, **409** |
| `gender` | **sí** | El `competition.gender` del paso 1, o el corregido |
| `seasonLabel` | solo si `season.exists` era `false` | El `season.label` del paso 1 |

**El `202` deja fila desde que se acepta** (`D-96`): el `jobId` que devuelve es una `ingestion_runs` con
`outcome: accepted`, y **la pasada que va detrás cierra ESA fila**, no abre otra. Se sigue leyendo:

```sh
curl -s "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<el competitionId del 202>" | jq
```

**Los códigos que estrena el enganche, y qué significa cada uno:**

| Caso | Código | `code` |
|---|---|---|
| URL que no es de la federación **del club** | **400** | `UNREADABLE_FEDERATION_URL` |
| Temporada nueva y la fuente no la rotula | **400** | `SEASON_LABEL_UNAVAILABLE` |
| Equipo inexistente | **404** | `TEAM_NOT_FOUND` |
| Equipo ya emparejado | **409** | `ALREADY_LINKED_TO_FEDERATION` |
| Ese código ya es de otro equipo | **409** | `FEDERATION_TEAM_ID_TAKEN` |
| Ese código no es de ningún equipo del calendario | **409** | `OWN_TEAM_NOT_IN_CALENDAR` |
| La competición dice otra edad, género o modalidad | **409** | `COMPETITION_IDENTITY_MISMATCH` |
| Club de una federación sin adaptador (FCF, `D-95`) | **501** | `FEDERATION_ADAPTER_MISSING` |
| La federación no responde | **504** | `FEDERATION_UNREACHABLE` |
| La federación responde mal, con error, o sin calendario | **502** | `FEDERATION_*` |

**El 409 del código ocupado es el que más se ve en una base que ya sincronizó**, y conviene saber por qué: la
ingesta **no crea equipos propios** (`D-66`), así que el equipo del club que nadie enganchó antes de la
primera pasada **ya existe como rival, con su código**. Engancharlo entonces choca contra
`uq:teams.federation_team_id`, y la respuesta dice **qué equipo lo tiene** para poder ir a `/ownership`
(`D-20`). Fundir las dos filas es §9.5 y está sin diseñar: el camino bueno es **enganchar antes de la primera
ingesta**.

Los **502/504** existen porque ésta es la única ruta síncrona con latencia de terceros: *"la RFFM está
caída"* y *"la RFFM cambió de formato"* merecen respuestas distintas, y hasta F10 las cuatro señales caían
en el mismo 500 (`A-6`/H-15).

### 4.2 La ingesta

**Una ingesta es una pasada que descarga de la federación los datos de las competiciones del club** —
calendario y resultados, clasificaciones y goleadores— y los escribe en la base. Normalmente no la lanza
nadie a mano: la lanza `launchd` tras los partidos del fin de semana con el comando `ingest` ([§6.3](#ingest),
[§6.4](#64-la-ingesta-programada--launchd)), que se salta lo sincronizado hace menos de 6 h.

Este endpoint es **el disparador manual**, el botón de *"sincroniza ahora"*: **no** respeta esas 6 h, porque
quien lo pulsa quiere los datos ya. Solo recorre competiciones que existan, así que antes hay que haber
enganchado algún equipo ([§4.1](#enganche)).

```sh
# Una competición: síncrona, 200, con el resultado dentro
curl -s -X POST http://atleti.localhost:8080/v1/ingestion-runs \
  -H 'Content-Type: application/json' -d '{"competitionIds":["<uuid>"]}' | jq

# La temporada vigente entera: 202, y dice qué ha aceptado
curl -s -i -X POST http://atleti.localhost:8080/v1/ingestion-runs \
  -H 'Content-Type: application/json' -d '{}'

# Qué pasó: las últimas pasadas de una competición, de la más reciente hacia atrás
curl -s "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<uuid>&limit=5" | jq
```

**Qué se recorre lo decide el cuerpo del `POST`**, que tiene dos campos, los dos opcionales:

| Cuerpo | Recorre | Respuesta |
|---|---|---|
| `{}` | Todas las competiciones de la **temporada vigente** | **202** con la lista de lo aceptado |
| `{"seasonId":"<uuid>"}` | Todas las de **esa** temporada, aunque no sea la vigente. Si no existe, **404**: no cae a la vigente | **202** |
| `{"competitionIds":["<uuid>"]}` | **Solo esa** competición, y espera a que termine | **200** con la pasada hecha |
| `{"competitionIds":["<a>","<b>"]}` | Solo esas, sin mirar de qué temporada son | **202** |

- **Si van los dos campos, gana `competitionIds`**, por ser más concreto.
- **200 o 202 lo decide la petición, no los datos.** Con `{}` sale 202 aunque el club tenga una sola
  competición (`D-88`): un cliente que recibiera una cosa u otra según cuántos equipos tiene el club no
  podría programarse.
- **`competitionIds` vacía es 400**, no *"todas"*. Para la temporada entera, se omite el campo.
- **Un campo mal escrito no da error, se ignora.** `{"competitionId":"…"}` (en singular) se lee como `{}` y
  recorre la temporada entera con un 202. Si esperabas un 200 y llega un 202, revisa el nombre.
- **El cuerpo no se puede omitir**: un `POST` sin cuerpo da **400**, porque el servidor generado lo intenta
  leer igual (`D-65`). Para "todo", `{}`.
- **Las pasadas que fallan también quedan registradas**: el `POST` da **502** y el `GET` enseña la fila con
  su `outcome` y su motivo, con el `sqlState` y la restricción si el fallo vino de Postgres (`D-85`).

---

## 5. Los tests

```sh
REQUIRE_DB=1 swift test                 # 591 tests, ~30 s — LA FORMA BUENA
swift test                              # igual, pero OMITE los de BD si Docker está parado
swift test --filter DomainTests         # nivel 1 · sin Docker
swift test --filter ApplicationTests    # nivel 2 · sin Docker
swift test --filter FederationTests     # nivel 1 · federación, sin red
swift test --filter PersistenceTests    # nivel 3 · Postgres
swift test --filter APITests            # nivel 4 · Postgres
swift test --no-parallel --disable-xctest                 # para LEER la salida
HTTP_TRACE=1 swift test --filter APITests --no-parallel   # los cuerpos HTTP
LOG_LEVEL=debug swift test --filter PersistenceTests      # el SQL de Fluent
KEEP_TEST_DATA=1 swift test --filter ClubUpdateTests      # conserva los schemas
```

> ⚠️ **`REQUIRE_DB=1`, no `swift test` a secas** (`A-7`/H-07). Sin la variable, con Docker parado los tests de
> BD **se omiten** y la salida es **idéntica en texto y en recuento** a la de una pasada de verdad — el total
> sale de la lista, no de lo ejecutado. Lo único que cambia es la duración: **23 s contra 0,002 s**. Omitir
> está bien para el bucle rápido y es el diseño; para saber si algo está roto, la variable.

**Para revisar una fase, sus tests** (Plan §9). Las comillas simples **no son decorativas**: sin ellas `zsh`
se come el `|`.

| Fase | Filtro | Docker |
|---|---|---|
| F3 · política de *upsert* | `'UpsertPolicyTests\|KickoffTests\|KickoffMergeTests\|MatchResultTests'` | no |
| F4 · cadena de emparejamiento | `'MatchingChainTests\|NormalizedNameTests'` | no |
| F5 · entidades de la ingesta | `'RoundTests\|OpponentClubTests\|TeamTests\|MatchTests\|IngestionRunTests'` | no |
| F5 · la pasada, con dobles | `IngestCalendarTests` | no |
| F5 · las tablas y la pasada real | `'IngestionPersistenceTests\|CalendarIngestionEndToEndTests'` | **sí** |
| F6 · el recorrido y sus argumentos | `'IngestClubCalendars\|IngestArguments'` | no |
| F6 · el recorrido por tenant · los endpoints | `TenantTraversal` · `IngestionEndpoint` | **sí** |
| F6-ter · el freno del recorrido | `IngestTraversalStop` | no |
| F7 · la fila, el cálculo y la PREV | `'StandingRowTests\|StandingTable\|StandingPrevious'` | no |
| F7 · parser · plan · pasada | `RFFMStandingsParser` · `StandingsSyncPlan` · `IngestStandingsTests` | no |
| F7 · la tabla · los dos volcados | `StandingPersistence` · `StandingIngestionEndToEnd` | **sí** |
| F8 · el goleador y su clave de *upsert* | `LeagueScorerTests` | no |
| F8 · parser · pasada | `RFFMScorersParser` · `IngestScorersTests` | no |
| F8 · la tabla, el `UNIQUE` y la retirada | `LeagueScorerPersistence` | **sí** |
| F8 · que el `CHECK` de un enumerado siga vivo | `MigrationIntegrity` | **sí** |
| F10 · el Dominio del enganche | `'TeamRegistrationTests\|GenderProposal'` | no |
| F10 · la cascada y el `/preview`, con dobles | `'FederationLinkTests\|FederationLinkPreview'` | no |
| F10 · la inscripción y sus invariantes en el esquema | `TeamRegistrationPersistence` | **sí** |
| F10 · las dos puertas en HTTP · los enumerados espejo | `FederationLinkEndpoint` · `ContractEnum` | **sí** |
| F10-ter · el identificador en minúscula | `IdentifierText` | no |

> **`--filter` es una expresión regular sobre identificadores de Swift** —el tipo de la *suite* y la función
> del `@Test`—, y de ahí tres sorpresas. **Arrastra suites que no esperas**: `Standing` trae 75 y `Scorer` 58,
> frente a los 31 y 23 de los filtros de arriba. **`Season` coge también `SeasonLabel`.** Y la que más
> despista: **el rótulo del `@Test` no se filtra** — `--filter reconoce` devuelve **0** aunque esté en seis
> rótulos; para eso, `grep` sobre `Tests/`. **Y mídelo con `REQUIRE_DB=1`**, o el filtro parece traer la mitad.

**Tus datos no se tocan.** Los tests corren contra `tfm_test`, que crean solos, y borran su *schema* al
acabar; `swift test` **barre al arrancar** lo que dejara una pasada que murió lanzando —al entrar y no en un
`defer`, para que la limpieza no dependa del camino de error—. Con `KEEP_TEST_DATA=1` se conservan y se miran
en TablePlus sobre `tfm_test`: es la alternativa barata al *breakpoint*, que dentro de un test de integración
te deja mirando **una transacción sin confirmar**.

> ⚠️ **`KEEP_TEST_DATA=1` es para un test, o para una *suite* que no repita *slug*** (`A-15`·H-88). Lo que se
> conserva se conserva también **entre los tests de la misma pasada**, y las *suites* que reutilizan su club
> de un test a otro chocan con lo que dejó el anterior (`23505 … uq:seasons.label`). Con la batería entera
> salen **42 rojos que no son del código**. Para mirar un fallo, filtra hasta ese test.

```sh
docker compose exec db psql -U tfm -d tfm_test -c '\dn'   # lo que dejan los tests
```

### 5.1 El canario — **no** corre con `swift test`

```sh
FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests
```

Es la única prueba que **habla con internet**, y vive fuera de la batería a propósito: los volcados contestan
*"¿he roto yo el parser?"* y esto contesta *"¿han cambiado ellos?"*. Fusionarlas las estropea las dos — con
red dentro de `swift test`, un rojo puede significar que la federación está caída.

**Tres tests, uno por lectura de la ingesta**: calendario, clasificación y goleadores (estos dos desde
`A-15`·H-86). **No compara bytes** (el calendario cambia cada semana por diseño): pasa nuestro parser por
encima de la respuesta viva, exige que no falle y comprueba invariantes que solo se rompen si cambia la
fuente. Por ejemplo, posiciones de 1 a N, G + E + P = J, el código de competición que devuelve
`/api/standings` es el pedido, y los goles bajan al bajar por el ranking. **Sabe decir cuatro cosas y solo una
es un hallazgo:**

| Lo que sale | ¿Hay que hacer algo? |
|---|---|
| *"No se pudo hablar con la RFFM"* · *"Respondió 500"* | no |
| *"La coordenada no designa nada"* | **repetirlo primero**: la RFFM sirve `null` pasajero en clasificación y goleadores (H-61, 2 de 5 pasadas el 2026-10-03). Si se repite, pasarle otra coordenada por variable |
| **⚠️ *"El parser ya no traga"*** | **sí**: recapturar volcado, revalidar el anexo, y solo entonces tocar el parser |

**Solo `FEDERATION_LIVE=1` es obligatoria**; la coordenada por defecto **envejece** —seguirá sirviendo su
temporada para siempre—, así que las otras seis se configuran. Son las de los volcados, para que el canario y
el *fixture* hablen de lo mismo:

| Variable | Por defecto |
|---|---|
| `FEDERATION_LIVE_SEASON` | `21` |
| `FEDERATION_LIVE_COMPETITION` | `24037548` |
| `FEDERATION_LIVE_GROUP` | `24037549` |
| `FEDERATION_LIVE_MODALITY` | `futbol_11` — es el `tipojuego` de la URL |
| `FEDERATION_LIVE_NAME` | `PRIMERA DIVISION AUTONOMICA CADETE` |
| `FEDERATION_LIVE_ROUND` | `30` — la jornada de la clasificación, la del volcado de F7 |

Una modalidad fuera del catálogo **falla diciendo cuáles hay**, en vez de caer a `futbol_11`: elegir por quien
llama es lo que haría que el canario mirase otra modalidad y lo llamase verde.

> **El filtro es `RFFMCanaryTests`, el nombre del tipo.** `--filter FederationCanary` —el rótulo del *suite*—
> no casa con nada y da `0 tests … passed`, que **se lee como verde**.

### 5.2 La comprobación de mutación — `Tools/Mutate`

```sh
swift build -c release --package-path Tools/Mutate
Tools/Mutate/.build/release/mutate Tools/Mutate/Catalogs/A-13.json --dry-run   # ¿casan los cambios?
Tools/Mutate/.build/release/mutate Tools/Mutate/Catalogs/A-13.json             # 6 mutaciones, 6 cazadas
swift test --package-path Tools/Mutate                                         # los tests del guion
```

Rompe una línea a propósito y exige que caiga el test que dice cubrirla. **Una cifra de mutación se afirma con
su catálogo** en `Tools/Mutate/Catalogs/` (`A-15`·H-52). Hace falta Docker para las mutaciones de base de datos.
El resumen queda en `.build/mutation-reports/`. Las reglas, el formato del catálogo y los cuatro desenlaces
(cazada, sobrevive, equivalente, **inválida**) están en [su README](./Tools/Mutate/README.md).

### 5.3 El censo del contrato — `Tools/Census`

```sh
swift build --package-path Tools/Census
Tools/Census/.build/debug/census          # códigos Problem y campos del contrato sin test que los nombre
swift test --package-path Tools/Census    # los tests del censo
```

**Al añadir un endpoint, pásalo.** Sale con `1` si hay un código o un campo nuevo que ningún test nombra, o si
un hueco de `Tools/Census/known-gaps.json` ya no lo es. **Nombrar no es afirmar** (H-47): encuentra huecos, no
certifica cobertura; eso lo hace la mutación. El método y sus límites, en [su README](./Tools/Census/README.md).

---

## 6. Los comandos

```sh
swift run Run --help
swift run Run migrate --yes                           # plano de control (public.tenants)
swift run Run migrate-tenants                         # migraciones nuevas a TODOS los clubes
swift run Run migrate-tenants -t atleti               # solo a uno
swift run Run migrate-tenants --revert --yes          # revierte TODOS: pide --yes
swift run Run provision-tenant atleti -f rffm --name "Nombre Largo" --short-name "Corto"
```

- **Trabajan siempre sobre `tfm`**, tu base manual. Los tenants de los tests los crean y borran ellos.
- **Cuando una fase añade tablas, vuelve a pasar `migrate-tenants`.** Fluent aplica solo las que faltan.
- **`--revert` exige `--yes`**: borra las tablas de todos los clubes y sus datos. Si uno falla a mitad, el
  comando **se para** diciendo de qué club era (`D-86`); reanudar es volver a pasarlo.
- **`--name` no tiene forma corta**: `-n` lo reserva ConsoleKit y el valor acabaría en `.unknownInput`. `-f`
  y `-s` sí funcionan.
- **`provision-tenant` hace cuatro cosas**, y la cuarta es la que se olvida: *schema*, registro en
  `public.tenants`, migraciones **y la fila de `clubs`**. Sin ella, `500 TENANT_NOT_PROVISIONED`. Es
  idempotente.

> ⚠️ **`migrate-tenants` va siempre por conexión directa, nunca por un *pooler*** (§6.4). Se apoya en un `SET`
> de sesión, y detrás de un *pooler* en modo transacción eso deja de significar lo que parece: el precio no es
> leer mal, es **crear la tabla en el *schema* de otro club**.

> ⚠️ **Dos cosas que NO se editan nunca, y las dos fallan en silencio** (`D-90`): una **migración ya aplicada**
> —`_fluent_migrations` guarda el nombre y no el contenido, así que tu base la recibe al recrearla y un club
> en producción no— y el **`CHECK` de un enumerado**, que se deriva de `sqlValueList` **una sola vez**, al
> migrar. Un caso nuevo del `enum` **no llega** a un *schema* que ya existe: hace falta una migración que lo
> **rehaga** (`replaceCheckConstraint`), o un alta limpia lo acepta y un club vivo lo rechaza con un `23514`.
> Lo encontró F8 y lo vigila `MigrationIntegrityTests`.
>
> ```sh
> docker exec backend-db-1 psql -U tfm -d tfm \
>   -c "SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE conname LIKE 'chk_%';"
> ```

### 6.1 `seed-competition` — la *entrada* de la ingesta

La ingesta necesita una `Season` y una `Competition` **antes** de poder pasar (`D-16`). El camino de verdad es
pegar la URL en la ficha del equipo (`D-67`), y **ya existe**: es [§4.1](#enganche). Esto se conserva como vía para
semillas, *scripts* y tests, que no deberían depender del formato de URL de un tercero:

```sh
swift run Run seed-competition -t atleti \
  -u "https://www.rffm.es/competicion/calendario?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549" \
  -c cadete -g masculino
```

Imprime los rótulos que dice la federación y te deja el `ingest` y el `curl` listos para pegar. **Es una
herramienta, no contrato** (`POST /v1/competitions` del *spec* es otra cosa). Hace cuatro cosas que un
`INSERT` a mano no: **se pega la URL entera** —la mitigación de `D-22` contra el dígito mal tecleado, que no
da error sino que sincroniza otro calendario—, los **rótulos los dice la fuente**, **pasa por el Dominio**, y
**valida antes de escribir**: coordenada mala o URL incompleta → falla **sin dejar fila**.

### 6.2 `seed-team` — el equipo propio, para poder engancharlo

`seed-competition` da de alta la **entrada** de la ingesta; esto da de alta el **equipo del club**, que es la
otra mitad que hace falta para probar el enganche de `D-67`. `POST /v1/teams` es del backoffice y no existe,
así que sin esta herramienta la base de trabajo **no puede tener un equipo propio**.

```sh
swift run Run seed-team -t atleti -c cadete -g masculino -m futbol_11 -l A
```

El equipo nace en el **único estado desde el que se puede enganchar**: propio (`opponent_club_id` nulo ⇒ se
deriva, no hay columna `is_own`) y **sin emparejar** (`federation_team_id` nulo). Esa fila **no tiene segundo
escritor**, que es la mitad de `D-66` sin la cual el enganche no se sostiene.

**Las tres que son identidad se teclean y ninguna tiene defecto honesto**: `category`, `gender` y `modality`
forman la clave única con la letra (§3.5) y quedan congeladas tras el alta (`D-58`). Equivocar una no da un
rótulo feo, da un **409** el día que la ingesta cree el equipo que éste tenía que haber sido. La hermana puede
derivar la modalidad de la URL; aquí no hay URL.

**Valida antes de escribir**, igual que `seed-competition`: si ya existe un equipo propio con esa identidad lo
dice con su UUID en vez de dejar que reviente el `UNIQUE` — un `23505` en crudo no dice cuál de las cinco
columnas repetiste, y la violación abortaría el ámbito entero (`25P02`). **La letra nula ES un valor**
—«el único equipo»—, no un comodín: sin `-l` se da de alta **otro** equipo distinto del "A".

> **Lo que no hace, y ya no es porque falte la tabla:** no escribe `TeamRegistration` (`D-68`). La tabla
> existe desde el bloque D de F10 y quien la escribe es **la cascada del enganche** ([§4.1](#enganche)), que es la que
> sabe en qué competición queda inscrito el equipo. Recién sembrado, el equipo existe y se puede enganchar
> pero **no está inscrito en ninguna temporada** — el estado que el *spec* evita exigiendo `seasonId` en el
> alta, porque es **invisible en toda pantalla que filtre por temporada**. Engancharlo lo arregla.

<a id="ingest"></a>

### 6.3 `ingest` — la pasada de la federación

```sh
swift run Run ingest                        # todos los clubes, temporada vigente
swift run Run ingest -t atleti              # un club (o varios: -t "atleti,otro")
swift run Run ingest -c "<uuid>,<uuid>"     # competiciones concretas, en el orden pedido
swift run Run ingest --season <uuid>        # una temporada aunque no sea la vigente
swift run Run ingest --force                # ignora el antirrebote de 6 h
swift run Run ingest --min-interval-hours 24   # o cámbialo en vez de ignorarlo
swift run Run ingest --fail-if-empty          # un club sin nada que recorrer sale con 1 (lo usa launchd)
```

**Un disparo son TRES pasadas por competición**, y hay que saberlo antes de mirar `ingestion_runs`:

| `kind` | Qué escribe | Unidad | Filas por competición |
|---|---|---|---|
| `calendar` | `Round`, `Match`, `Team`, `OpponentClub` | la competición | **1** |
| `standings` | `StandingRow` — ingerida o calculada (`D-15`) | **la jornada** | **una por jornada** que toque |
| `scorers` | `LeagueScorer` | la competición | **1** |

El calendario va primero porque crea los `Team` con los que la clasificación empareja y los `Match` desde los
que calcula. Por eso **un alta a mitad de temporada deja muchas más filas de las que uno espera**. La de
goleadores **no siempre existe**: si la federación del club no los publica no se intenta, y no hay *fallback*
posible (`D-48`).

```sh
docker exec backend-db-1 psql -U tfm -d tfm -c "
SELECT kind, outcome, round_id IS NULL AS sin_jornada, league_scorers_retired AS retirados,
       round((extract(epoch from finished_at - started_at))::numeric, 3) AS seg
FROM club_atleti.ingestion_runs ORDER BY finished_at DESC LIMIT 10;"
```

- **Sale con código `1` si algo falló**, que es la única señal que ve un cron (`D-86`). Un fallo **no detiene
  el recorrido**: la unidad de aislamiento es la competición.
- **`round_id` solo lo lleva la clasificación**, y el esquema lo hace cumplir.
- **El antirrebote de 6 h no es el tope semanal.** Aquél es un mínimo que evita repetir trabajo; el tope lo
  hace cumplir el calendario de disparos (`D-87`). Una competición **que nunca se sincronizó entra siempre**.
- **Sin `--fail-if-empty`, un recorrido vacío sale en verde**: *"nada que recorrer"* es un aviso, no un fallo,
  porque quien lanza `ingest` a mano sobre un club recién dado de alta no ha hecho nada mal. Con el *flag*
  sale con `1`, y es lo que pasa el disparo desatendido ([§6.4](#ingesta-programada)). Lo
  saltado por el antirrebote **no** es vacío: es un disparo de más, y la línea dice cuántas saltó.
- **El tope semanal de §5.6 lo pone `launchd`** ([§6.4](#ingesta-programada)): lunes y fin de
  semana. El código sigue sin hacerlo cumplir; `ingestion_runs` permite comprobarlo a posteriori.

<a id="ingesta-programada"></a>

### 6.4 La ingesta programada — `launchd`

**`ingest` se dispara solo en el Mac**, contra esta misma base (`tfm`), los **sábados y domingos a las 23:30 y
los lunes a las 08:00**, en hora local (`D-87`; las horas, `DL-3` del
[Plan launchd-001](./Plan%20launchd-001.md)). Un disparo que caiga con el portátil **dormido** se ejecuta al
despertar. Es un montaje **local**, para que la base acumule semanas reales mientras se construye el
backoffice: en Fly.io se dispara de otra forma, y lo que se lleva y lo que se tira está en el §1.6 del plan.

**Son tres piezas, y ninguna se ejecuta desde el repositorio:**

```
~/Library/LaunchAgents/com.tongilcoto.tfm.ingest.plist      ← CUÁNDO   (lo copia agent.sh install)
        │  launchd, a esa hora, ejecuta…
        ▼
~/Library/Application Support/tfm/current/run-ingest.sh     ← QUÉ PASA EN CADA DISPARO
        │                                                       (lo copia install.sh, del commit)
        ▼
~/Library/Application Support/tfm/current/Run ingest --fail-if-empty
                                                              (lo compila install.sh, del commit)
```

- **`run-ingest.sh` no programa nada**: es el envoltorio. Lanza `ingest`, escribe cada línea en el log con la
  hora y el commit delante y, si el código de salida no es `0`, **avisa**.
- **El binario y el envoltorio salen de un commit, nunca de tu árbol de trabajo** (A-15·H-85). `swift build`,
  `swift test` y `Tools/Mutate` reescriben `.build`; si `launchd` ejecutara `.build/debug/Run`, un disparo a
  mitad de una mutación correría código roto a propósito contra tu base. Por eso **lo que no está commiteado
  no se instala**, y cambiar de rama no cambia lo que se dispara.

Los dos guiones, desde `backend/`:

| Para                                                                  | Comando                                                                       |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| **Instalar** o **actualizar** el binario y el envoltorio | `Tools/Deploy/install.sh`: instala **lo último commiteado en tu rama** (lo no commiteado no entra). `install.sh main` o `install.sh <sha>` instala otra rama o un commit concreto |
| **Cargar** el agente en `launchd` (una vez, o si cambia el `.plist`)  | `Tools/Deploy/agent.sh install`                                               |
| **Ver** el estado: disparos, último código de salida, binario, fallos | `Tools/Deploy/agent.sh status`                                                |
| **Disparar ya**, sin esperar a la hora                                | `Tools/Deploy/agent.sh run`                                                   |
| **Quitarlo** (el binario y los logs se quedan)                        | `Tools/Deploy/agent.sh uninstall`                                             |

**Montarlo desde cero son dos comandos**, en este orden, porque `agent.sh install` se niega si no hay nada
instalado:

```sh
Tools/Deploy/install.sh          # ~3 min la primera vez (release, dependencias incluidas); ~20 s después
Tools/Deploy/agent.sh install
```

**Para que `launchd` ejecute un cambio**: commit y `Tools/Deploy/install.sh`. **No hay que recargar el
agente**: el `.plist` apunta a `current/`, e `install.sh` mueve ese enlace de forma atómica. Guarda las cinco
últimas versiones en `releases/`, y volver a una es `install.sh <sha>` (instantáneo si sigue ahí). El guion
**avisa** si instalas desde una rama que no es `main`, o con cambios sin commitear en `Sources/` (que no entran).

#### Dónde mirar

| Qué | Dónde |
|---|---|
| La salida de cada disparo, con hora y commit | `~/Library/Logs/tfm/ingest.log` |
| **Los fallos, uno por línea con su motivo. No se borra solo** | `~/Library/Logs/tfm/ULTIMO_FALLO` — bórralo cuando lo hayas visto |
| Lo que falle **antes** de que arranque el envoltorio (p. ej., que no exista) | `~/Library/Logs/tfm/launchd.log` — normalmente vacío |
| Lo que escribió cada pasada | `ingestion_runs`, igual que con `ingest` a mano ([§6.3](#ingest)) |
| Qué versión está instalada | `agent.sh status`, o `~/Library/Application Support/tfm/current/VERSION` |

**Cuándo avisa**: solo si el código de salida no es `0`. Entonces sale una **notificación de macOS** («TFM ·
ingesta falló») y una línea en `ULTIMO_FALLO`, las dos con el motivo:

| El motivo dice | Qué pasa | Qué hacer |
|---|---|---|
| *"la base no responde: ¿está Docker parado?"* | Postgres no estaba a la hora del disparo. La pasada se detuvo sin dejar nada a medias (`D-86`) | Levantar Docker; entra en el disparo siguiente, o `agent.sh run` |
| *"<club>: nada que recorrer…"* | **No hay temporada vigente con competiciones**: el disparo no habría acumulado nada (H-59) | Dar de alta la temporada y enganchar los equipos ([§4.1](#enganche)) |
| *"<club>: N competición(es) sincronizada(s), M con fallo…"* | Alguna pasada falló; las demás siguieron (`D-86`) | Su fila de `ingestion_runs` dice cuál y por qué. Un `null` de la RFFM suele ser pasajero (H-61) |
| *"no se pudo ejecutar el binario instalado"* | No hay nada en `current/` | `Tools/Deploy/install.sh` |

> **Lo que no cubre:** el portátil **apagado** a la hora del disparo (se está midiendo: `L-L.4` del plan), y
> que nadie mire las notificaciones. Un disparo **de más** no avisa ni repite trabajo: el antirrebote lo salta
> y la línea lo dice (*"N saltada(s) por el antirrebote"*).

---

## 7. El *spec*

`Sources/APIContract/openapi.yaml` — **6.739 líneas, 83 operaciones en 45 rutas y las 21 entidades de §3.2**.
Es la **fuente de verdad** (`D-25`): de él se generan los tipos y el `APIProtocol` (`D-65`).

```sh
npx @redocly/cli lint Sources/APIContract/openapi.yaml
ls .build/plugins/outputs/backend/APIContract/destination/OpenAPIGenerator/GeneratedSources/
```

**Para añadir un endpoint**, se añade a `filter.operations` de `openapi-generator-config.yaml` → compila → **no
compila**, porque falta su método → se implementa. Esa lista **es, literalmente, el alcance entregado**
(`D-69`), y ese *"no compila"* es la garantía entera de *design-first*.

- **El generador emite tipos, no validación** (`D-65`): ignora `pattern`, `minLength`, `readOnly`,
  `minProperties`, `default`, `tags` y `security`. Que algo esté en el YAML **no** significa que se compruebe.
- **Los errores se devuelven, no se lanzan**: lo que lance un *handler* se convierte en 500 antes de que
  ningún middleware lo vea. La consecuencia es buena: **un código que el *spec* no declara no se puede
  devolver**, porque no existe como caso del enum.
- **`ProblemMiddleware` es para lo de fuera del transporte**: tenancy, 404 de ruta y lo que el transporte
  rechaza antes del *handler* — un parámetro obligatorio que falta ni llega a tu código.

**El grafo de capas y qué hay en cada *target*: [AGENTS.md](../AGENTS.md).** Compruébalo tú mismo:

```sh
swift package clean
echo "import Vapor" > Sources/Domain/Prueba.swift
swift build --target Domain      # error: no such module 'Vapor'
rm Sources/Domain/Prueba.swift
```

El `swift package clean` no sobra: con `.build` caliente falla igual —la regla se sostiene— pero con un
mensaje desconcertante (`missing required module '_NumericsShims'`).

---

## 8. Cuando algo falla

| Síntoma | Causa casi segura |
|---|---|
| `Cannot find type 'Components' in scope` en Xcode | Los tipos del contrato no existen hasta que corre el plugin. Acepta el aviso de confianza y ⌘B. **La CLI es la fuente de verdad**, no el índice |
| `connection refused` al 5434 | `docker compose up -d db` |
| Verde sospechosamente rápido (0,002 s) | Corriste sin `REQUIRE_DB=1` y Docker estaba parado: **no se probó nada que toque la base** |
| `400 TENANT_NOT_RESOLVED` | Llamaste a `localhost:8080` sin subdominio ni `X-Club` |
| `404 UNKNOWN_TENANT` | Falta `swift run Run provision-tenant <slug>` |
| `500 TENANT_NOT_PROVISIONED` | El *schema* existe pero `clubs` está vacío. Repite `provision-tenant`: es idempotente |
| `23514` al ingerir | Un `CHECK` del *schema* que se quedó atrás — ver el aviso de [§6](#6-los-comandos) |
| Los tests petan con **señal 5** | Una `Application` destruida sin esperar a su cierre. Usa `TestEnvironment.withApp` |
| Los tests fallan **la primera vez** y pasan a la segunda | Arranque compartido en carrera entre suites paralelas. Va en `TestEnvironment.bootstrap()` |
| `PSQLError – Generic description…` | PostgresNIO esconde el detalle. Se reexpone con `String(reflecting:)` |
| `Address already in use` (errno 48) al hacer `serve` | Ya hay un `Run serve` vivo: `lsof -nP -iTCP:8080 -sTCP:LISTEN` y `kill <PID>` |
| `Test Suite … Executed 0 tests` de XCTest | No hay XCTest en el proyecto (`D-70`): SwiftPM ejecuta las dos bibliotecas. `--disable-xctest` lo quita |
| Docker no arranca | Suele ser disco lleno |

```sh
LOG_LEVEL=debug swift run Run serve    # cada petición y cada SQL
swift package clean && swift build     # cuando el build se comporta raro
```
