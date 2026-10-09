# Backend · Manual de a bordo

> **Cómo arrancar el backend**, usar la API y los comandos, y ver qué pasa por dentro.
> **El porqué de cada decisión no está aquí**: está en [`docs/`](../docs/), y este fichero enlaza en vez de
> repetirlo.

| Si buscas… | Está en |
|---|---|
| cómo se arranca, qué comando hay, por qué falla algo | **este fichero** |
| qué hace cada capa y por qué | [AGENTS.md](../AGENTS.md) · [LLD-001](../docs/API_y_BBDD%20LLD-001.md) |
| por qué se decidió así | [bitácora `D-nn`](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) |
| qué entregó cada fase y qué midió | [Plan de desarrollo](../docs/Plan%20de%20desarrollo-001.md) §4 |

Convención: **`§x` sin enlace se refiere al LLD**, y `D-nn` a la bitácora de decisiones. Las referencias a
secciones de *este* fichero van siempre como enlace, para no confundirlas con las del LLD.

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
(`D-95`). **603 tests.** Qué trajo cada una: [Plan §4](../docs/Plan%20de%20desarrollo-001.md). La
[auditoría 002](./Plan%20de%20auditor%C3%ADa-002.md) está **cerrada** (2026-10-04). Para conectar una
federación nueva: [la guía de alta](../docs/API_y_BBDD%20Guia-Alta-Federacion-001.md).

| Operación HTTP                                                                        |                                   |
| ------------------------------------------------------------------------------------- | --------------------------------- |
| `GET /v1/club` · `PATCH /v1/club`                                                     | F0                                |
| `GET /v1/ingestion-runs` · `POST /v1/ingestion-runs`                                  | F6                                |
| `POST /v1/teams/{id}/federation-link/preview` · `POST /v1/teams/{id}/federation-link` | F10 — [§4.1](#enganche)           |
| Las otras 77 del *spec*                                                               | ⛔ no generadas — [§7](#7-el-spec) |

**La tabla solo recoge lo que se puede llamar por HTTP, no todo lo que está hecho.** De F1 a F5 no se añadió
ningún endpoint, y era lo previsto: la ingesta se lanza con un comando (`ingest`), no desde la API (§2.3-b).
El resto se ve en [la base de datos](#3-la-base-de-datos), en [los comandos](#6-los-comandos) o en
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
| `--federation`, `-f` | **sí** | De qué federación se sincroniza el club entero. No tiene valor por defecto: hay que decirla siempre (§3.6). Hoy solo vale **`rffm`**: `fcf` está en el catálogo pero todavía no se puede sincronizar, y se rechaza (H-93) |
| `--name` | no | El nombre oficial. Por defecto, el *slug*. **No tiene forma corta**: `-n` ya lo usa la librería de comandos (ConsoleKit) |
| `--short-name` | no | El nombre corto. Por defecto, el nombre |
| `--schema`, `-s` | no | El nombre del *schema*. Por defecto, `club_<slug>`; no hace falta cambiarlo |

**`serve` levanta la API.** Sin parámetros escucha en `127.0.0.1:8080`:

| Parámetro | Por defecto | Qué es |
|---|---|---|
| `--port`, `-p` | `8080`, o `API_PORT` | El puerto. Si lo cambias, cambia en todos los `curl`: `http://atleti.localhost:8765/…` |
| `--hostname`, `-H` | `127.0.0.1` | La interfaz donde escucha |
| `--bind`, `-b` | — | Las dos cosas juntas: `-b 127.0.0.1:8765` |

- **Para usar otro puerto siempre, mejor `export API_PORT=8765` que `--port`**: `serve` lo toma como puerto
  por defecto, y `provision-tenant`, `seed-team` y `seed-competition` lo usan en los `curl` que imprimen
  para pegar. Con `--port` solo se entera `serve`, y esos `curl` siguen diciendo `8080`.
- **`*.localhost` apunta a 127.0.0.1 sin configurar nada**, así que en local el club se indica igual que en
  producción: en el subdominio (§6.1). No hace falta ninguna cabecera.
- Para parar: `Ctrl-C`, y `docker compose down` (conserva datos) o `down -v` (los borra).

---

## 2. Ejecución y entorno

```sh
docker compose up -d db && swift run Run serve   # modo normal: API nativa, BD en Docker
docker compose --profile full up --build         # todo en Docker, release, ~3 min
```

El segundo no es para desarrollar: sirve para comprobar que todo seguiría funcionando desplegado. Dentro de
Docker la API se conecta a `db:5432`, y desde el Mac la misma base está en `localhost:5434`. **Es la misma
base de datos.**

| Variable | Por defecto | Para qué |
|---|---|---|
| `DB_HOST` / `DB_PORT` | `localhost` / `5434` | `db` / `5432` dentro de compose |
| `DB_USER` / `DB_PASSWORD` / `DB_NAME` | `tfm` | |
| `DOMAIN_SUFFIX` | `localhost` | El sufijo que se recorta del `Host` (§6.1) |
| `API_PORT` | `8080` | Puerto por defecto de `serve` (`--port` gana) y el de los `curl` que imprimen los comandos |
| `LOG_LEVEL` | `info` | `debug` muestra cada petición y cada SQL. Vale también en `swift test` |
| `HTTP_TRACE` | apagado | `1` vuelca los **cuerpos** HTTP. Solo en `.development` / `.testing` |
| `REQUIRE_DB` | apagado | `1` hace **fallar** los tests de BD en vez de omitirlos ([§5](#5-los-tests)). `CI` la activa sola |
| `KEEP_TEST_DATA` | apagado | `1` conserva los *schemas* de test. **Solo la mira `swift test`** |

> **`--log debug` no muestra el cuerpo de las peticiones ni de las respuestas**, con ningún nivel de log:
> Vapor registra la petición, las cabeceras y el SQL, pero nunca el cuerpo. Para eso está `HTTP_TRACE=1`, que
> es una variable aparte. Solo funciona en desarrollo y en los tests, porque esos cuerpos llevan **datos de
> menores** (§3.2): volcarlos en producción sería una fuga de datos.

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
├── public          ← lo común: la lista de clubes, tenants   (+ su _fluent_migrations)
├── club_atleti     ← un club: sus ONCE tablas    (+ su _fluent_migrations)
└── club_celtic     ← otro club: las mismas tablas, datos distintos
```

Las once tablas de hoy, en el orden en que se crean. **No son las 21 entidades de §3.2**, solo las que han
necesitado las fases entregadas:

```
clubs · seasons · opponent_clubs · teams · competitions · rounds · matches
      · standing_rows · league_scorers · ingestion_runs · team_registrations
```

**Cada *schema* tiene su propia `_fluent_migrations`**: las migraciones se llevan club a club, y revertir
uno no toca a los demás (§4.7). **La API no filtra por club**: antes de cada consulta elige el *schema* del
club (`search_path`), y la misma consulta lee de uno o de otro (§6.2). Por eso ninguna tabla tiene columna
de club ni ninguna ruta lleva `clubId`.

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
un comando ([§6.3](#seed-team)):

```sh
swift run Run seed-team -t atleti -c cadete -g masculino -m futbol_11 -l A
```

| Parámetro | ¿Obligatorio? | Qué es |
|---|---|---|
| `--tenant`, `-t` | **sí** | El *slug* del club |
| `--category`, `-c` | **sí** | Edad: `prebenjamin`, `benjamin`, `alevin`, `infantil`, `cadete`, `juvenil`, `senior` |
| `--gender`, `-g` | **sí** | `masculino`, `femenino`, `mixto` |
| `--modality`, `-m` | **sí** | `futbol_11`, `futbol_7`, `futbol_5`, `futbol_sala`, `futbol_playa` |
| `--letter`, `-l` | no | Distingue equipos de la misma edad, género y modalidad (`A`, `B`…). **Sin `-l` es otro equipo, no "cualquiera"**: el que no lleva letra porque es el único |

**Las cuatro primeras no se pueden cambiar después** (`D-58`), y equivocarse no da un error al crear el
equipo, sino un **409** al engancharlo, si la competición es de otra edad, género o modalidad.

La salida empieza así:

```
Equipo listo: 3f2a9c1e-…
  cadete A · masculino · futbol_11
  propio, SIN enganchar y SIN inscribir (la inscribe la cascada de D-67)
```

Debajo imprime además el `curl` del paso 1 con el UUID ya puesto, **solo como recordatorio: no lo ejecuta**.
Puedes pegarlo desde ahí o seguir con el paso 1 de aquí, que es el mismo.

**Copia el UUID de `Equipo listo` a una variable**, que es la que usan los `curl` de abajo:

```sh
TEAM=3f2a9c1e-…
```

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

**El `202` ya deja una fila en `ingestion_runs`** (`D-96`), con `outcome: accepted`; su id es el `jobId` de
la respuesta. Cuando la ingesta termina, actualiza esa misma fila, no crea otra. Para ver cómo va:

```sh
curl -s "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<el competitionId del 202>" | jq
```

**Los errores del enganche:**

| Caso | Código | `code` |
|---|---|---|
| URL que no es de la federación **del club** | **400** | `UNREADABLE_FEDERATION_URL` |
| La temporada es nueva y la federación no publica su nombre | **400** | `SEASON_LABEL_UNAVAILABLE` |
| Equipo inexistente | **404** | `TEAM_NOT_FOUND` |
| El equipo ya está enganchado | **409** | `ALREADY_LINKED_TO_FEDERATION` |
| Ese código ya es de otro equipo | **409** | `FEDERATION_TEAM_ID_TAKEN` |
| Ese código no es de ningún equipo del calendario | **409** | `OWN_TEAM_NOT_IN_CALENDAR` |
| La competición dice otra edad, género o modalidad | **409** | `COMPETITION_IDENTITY_MISMATCH` |
| El club es de una federación que todavía no se puede sincronizar (FCF, `D-95`) | **501** | `FEDERATION_ADAPTER_MISSING` |
| La federación no responde | **504** | `FEDERATION_UNREACHABLE` |
| La federación responde mal, con error, o sin calendario | **502** | `FEDERATION_*` |

**`FEDERATION_TEAM_ID_TAKEN` es el 409 más probable si ya ha pasado alguna ingesta.** La ingesta no crea
equipos del club (`D-66`): si en un calendario encuentra un equipo del club que nadie ha enganchado, lo da
de alta como **rival**, con su código de la federación. Al intentar engancharlo después, ese código ya lo
tiene el rival. La respuesta dice qué equipo lo tiene, para resolverlo con `/ownership` cuando exista
(`D-20`); unir las dos filas en una está sin diseñar (§9.5). Por eso conviene **enganchar los equipos antes
de la primera ingesta**.

**Hay dos códigos para los fallos de la federación** porque piden cosas distintas: **504** es «la RFFM no
contesta» (reintentar más tarde) y **502** es «contesta algo que no entendemos» (puede haber cambiado su
formato). El enganche es la única ruta que espera a la federación dentro de la propia petición. Antes de F10
todos estos casos salían como un 500 (`A-6`/H-15).

### 4.2 La ingesta

**Una ingesta es una pasada que descarga de la federación los datos de las competiciones del club** —
calendario y resultados, clasificaciones y goleadores— y los escribe en la base. Normalmente no la lanza
nadie a mano: la lanza `launchd` tras los partidos del fin de semana con el comando `ingest` ([§6.4](#ingest),
[§6.5](#ingesta-programada)), que se salta lo sincronizado hace menos de 6 h.

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
- **200 o 202 depende de lo que se pide, no de los datos.** Con `{}` sale 202 aunque el club tenga una sola
  competición (`D-88`): así quien llama sabe qué respuesta le llega sin saber cuántas competiciones hay.
- **`competitionIds` vacía es 400**, no *"todas"*. Para la temporada entera, se omite el campo.
- **Un campo mal escrito no da error, se ignora.** `{"competitionId":"…"}` (en singular) se lee como `{}` y
  recorre la temporada entera con un 202. Si esperabas un 200 y llega un 202, revisa el nombre.
- **El cuerpo no se puede omitir**: un `POST` sin cuerpo da **400**, porque el código generado a partir del
  *spec* lo lee siempre (`D-65`). Para «todo», `{}`.
- **Las pasadas que fallan también quedan registradas**: el `POST` da **502** y el `GET` enseña la fila con
  su `outcome` y su motivo, con el `sqlState` y la restricción si el fallo vino de Postgres (`D-85`).

---

## 5. Los tests

```sh
REQUIRE_DB=1 swift test                 # 603 tests, ~30 s — la forma recomendada
swift test                              # igual, pero se SALTA los de BD si Docker está parado
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

> ⚠️ **Usa `REQUIRE_DB=1`, no `swift test` a secas** (`A-7`/H-07). Sin la variable, si Docker está parado,
> los tests que usan la base **se saltan sin avisar**: la salida dice lo mismo y cuenta los mismos tests que
> una pasada completa. Solo se nota en el tiempo: **23 s frente a 0,002 s**. Saltarlos está bien para ir
> rápido mientras programas; para saber si algo está roto, usa la variable.

**Los tests de cada fase** (Plan §9). Las comillas simples **hacen falta**: sin ellas, `zsh` interpreta el
`|` como una tubería.

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

> **`--filter` busca por los nombres en Swift** (el tipo de la *suite* y la función del `@Test`), como
> expresión regular. Eso tiene tres consecuencias:
>
> - **Trae más de lo que parece**: `Standing` encuentra 75 tests y `Scorer` 58, frente a los 31 y 23 de los
>   filtros de la tabla. `Season` también coge `SeasonLabel`.
> - **No busca en la descripción del `@Test`**: `--filter reconoce` da 0 tests aunque esa palabra aparezca en
>   seis descripciones. Para buscar por descripción, `grep` en `Tests/`.
> - **Pásalo con `REQUIRE_DB=1`**, o parecerá que el filtro trae la mitad.

**Los tests no tocan tus datos.** Usan la base `tfm_test`, que crean ellos, y borran su *schema* al
terminar. Si una pasada anterior se cortó a medias, `swift test` limpia lo que quedó al arrancar. Con
`KEEP_TEST_DATA=1` los datos se conservan y se pueden mirar en TablePlus sobre `tfm_test`. Es más práctico
que un *breakpoint*, que en un test de integración te deja delante de **una transacción sin confirmar**.

> ⚠️ **`KEEP_TEST_DATA=1`, solo con un test o con una *suite* que no repita club** (`A-15`·H-88). Los datos
> conservados siguen ahí **para el test siguiente de la misma pasada**, y las *suites* que reutilizan su club
> entre tests chocan con lo que dejó el anterior (`23505 … uq:seasons.label`). Con todos los tests salen
> **42 fallos que no son del código**. Para investigar un fallo, filtra hasta ese test.

```sh
docker compose exec db psql -U tfm -d tfm_test -c '\dn'   # lo que dejan los tests
```

### 5.1 El canario — **no** corre con `swift test`

```sh
FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests
```

Es la única prueba que **se conecta a internet**, y por eso va aparte. Los tests normales usan respuestas de
la federación guardadas en ficheros, y contestan «¿he roto yo el parser?». El canario consulta la web real y
contesta «¿ha cambiado la federación?». Si fuera dentro de `swift test`, un fallo podría deberse simplemente a
que la RFFM está caída.

**Son tres tests**, uno por cada cosa que lee la ingesta: calendario, clasificación y goleadores (estos dos
desde `A-15`·H-86). **No compara con una respuesta guardada**, porque el calendario cambia cada semana. Pasa
nuestro parser por la respuesta real, comprueba que no falla y que se cumplen reglas que solo se romperían
si la federación cambia algo: posiciones de 1 a N, ganados + empatados + perdidos = jugados, la competición
que devuelve `/api/standings` es la pedida, y los goles bajan al bajar en la tabla de goleadores. **Puede
dar cuatro resultados, y solo uno pide trabajo:**

| Lo que sale | ¿Hay que hacer algo? |
|---|---|
| *"No se pudo hablar con la RFFM"* · *"Respondió 500"* | no |
| *"La coordenada no designa nada"*: la competición pedida vino vacía | **repetirlo primero**: la RFFM a veces devuelve vacíos pasajeros en clasificación y goleadores (H-61, 2 de 5 pasadas el 2026-10-03). Si se repite, probar con otra competición por variable |
| **⚠️ El parser falla con la respuesta real** | **sí**: guardar una respuesta nueva, revisar el anexo de la RFFM, y solo entonces cambiar el parser |

**Solo hace falta `FEDERATION_LIVE=1`.** Las otras seis variables eligen qué competición consultar. Por defecto
es la misma de las respuestas guardadas, para que el canario y los tests normales hablen de lo mismo; es de
una temporada pasada, así que sigue funcionando, pero ya no refleja la actual:

| Variable | Por defecto |
|---|---|
| `FEDERATION_LIVE_SEASON` | `21` |
| `FEDERATION_LIVE_COMPETITION` | `24037548` |
| `FEDERATION_LIVE_GROUP` | `24037549` |
| `FEDERATION_LIVE_MODALITY` | `futbol_11` — es el `tipojuego` de la URL |
| `FEDERATION_LIVE_NAME` | `PRIMERA DIVISION AUTONOMICA CADETE` |
| `FEDERATION_LIVE_ROUND` | `30` — la jornada de la clasificación, la del volcado de F7 |

Si la modalidad no existe, **falla y dice cuáles valen**, en vez de usar `futbol_11` sin avisar: el canario
daría verde mirando otra modalidad.

> **El filtro es `RFFMCanaryTests`, el nombre del tipo.** Con `--filter FederationCanary`, que es la
> descripción de la *suite*, no encuentra nada y da `0 tests … passed`, que **parece un verde**.

### 5.2 La comprobación de mutación — `Tools/Mutate`

```sh
swift build -c release --package-path Tools/Mutate
Tools/Mutate/.build/release/mutate Tools/Mutate/Catalogs/A-13.json --dry-run   # ¿casan los cambios?
Tools/Mutate/.build/release/mutate Tools/Mutate/Catalogs/A-13.json             # 6 mutaciones, 6 cazadas
swift test --package-path Tools/Mutate                                         # los tests del guion
```

Cambia a propósito una línea del código y comprueba que algún test falla. Si ninguno falla, esa línea no
está probada de verdad. Cada lista de cambios es un **catálogo** en `Tools/Mutate/Catalogs/`, y un resultado
de mutación se cita siempre con el suyo (`A-15`·H-52). Las mutaciones que tocan la base de datos necesitan
Docker. El resumen se guarda en `.build/mutation-reports/`. Las reglas, el formato del catálogo y los cuatro
resultados posibles (cazada, sobrevive, equivalente, **inválida**) están en [su README](./Tools/Mutate/README.md).

### 5.3 El censo del contrato — `Tools/Census`

```sh
swift build --package-path Tools/Census
Tools/Census/.build/debug/census          # códigos Problem y campos del contrato sin test que los nombre
swift test --package-path Tools/Census    # los tests del censo
```

**Pásalo al añadir un endpoint.** Busca en el *spec* los códigos de error y los campos que ningún test
menciona, y sale con `1` si aparece alguno nuevo, o si alguno de los apuntados en
`Tools/Census/known-gaps.json` ya tiene test. **Que un test mencione algo no significa que lo compruebe**
(H-47): el censo encuentra huecos, pero no garantiza cobertura; para eso está la mutación. El método y sus
límites, en [su README](./Tools/Census/README.md).

---

## 6. Los comandos

Todos se lanzan con `swift run Run <comando>` y **trabajan siempre sobre `tfm`**, tu base manual; los tenants
de los tests los crean y borran los propios tests. `swift run Run --help` los lista, y
`swift run Run <comando> --help` da los parámetros de cada uno.

| Comando | Para qué | Dónde |
|---|---|---|
| `migrate` · `migrate-tenants` · `provision-tenant` | Crear las tablas y dar de alta clubes | [§6.1](#provision) |
| `seed-competition` | Dar de alta una competición sin equipo: semillas, *scripts* y tests | [§6.2](#seed-competition) |
| `seed-team` | Dar de alta un equipo del club, para engancharlo | [§6.3](#seed-team) |
| `ingest` | La pasada de la federación | [§6.4](#ingest) |
| — (`launchd`) | `ingest` programado en el Mac | [§6.5](#ingesta-programada) |

<a id="provision"></a>

### 6.1 `migrate`, `migrate-tenants` y `provision-tenant` — las tablas y los clubes

```sh
swift run Run migrate --yes                           # lo común: la tabla de clubes (public.tenants)
swift run Run migrate-tenants                         # migraciones nuevas a TODOS los clubes
swift run Run migrate-tenants -t atleti               # solo a uno
swift run Run migrate-tenants --revert --yes          # revierte TODOS: pide --yes
swift run Run provision-tenant atleti -f rffm --name "Nombre Largo" --short-name "Corto"
```

- **Cuando una fase añade tablas, vuelve a pasar `migrate-tenants`.** Fluent aplica solo las que faltan.
- **`--revert` exige `--yes`**: borra las tablas de todos los clubes, con sus datos. Si falla en un club, el
  comando **se para** y dice en cuál (`D-86`); para seguir, se vuelve a lanzar.
- **`--name` no tiene forma corta**: `-n` ya lo usa la librería de comandos (ConsoleKit). `-f` y `-s` sí
  funcionan.
- **`provision-tenant` hace cuatro cosas**: crea el *schema*, registra el club en `public.tenants`, pasa las
  migraciones y escribe la fila del club en `clubs`. Si falta esta última, la API responde
  `500 TENANT_NOT_PROVISIONED`. Se puede repetir sin miedo: no duplica nada.

> ⚠️ **`migrate-tenants` necesita una conexión directa a Postgres, nunca a través de un *pooler*** (§6.4).
> Elige el *schema* de cada club con un `SET` que dura toda la conexión, y un *pooler* en modo transacción
> puede repartir esas órdenes entre conexiones distintas. El resultado no sería un error, sino **tablas
> creadas en el *schema* de otro club**.

> ⚠️ **Dos cosas que no se deben editar nunca, porque fallan sin avisar** (`D-90`):
>
> - **Una migración ya aplicada.** Fluent apunta en `_fluent_migrations` el nombre de cada migración, no su
>   contenido: una base nueva recibiría la versión editada, y un club que ya la tenía, no.
> - **El `CHECK` de un enumerado.** Se genera a partir de `sqlValueList` una sola vez, al migrar. Si añades un
>   caso al `enum`, los *schemas* que ya existen no se enteran: hace falta una migración nueva que rehaga el
>   `CHECK` (`replaceCheckConstraint`). Si no, un club nuevo acepta el valor y uno existente lo rechaza con un
>   error `23514`. Lo encontró F8 y lo vigila `MigrationIntegrityTests`.
>
> Para ver los `CHECK` que hay ahora:
>
> ```sh
> docker exec backend-db-1 psql -U tfm -d tfm \
>   -c "SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE conname LIKE 'chk_%';"
> ```

<a id="seed-competition"></a>

### 6.2 `seed-competition` — la *entrada* de la ingesta

La ingesta solo recorre temporadas y competiciones que ya existan en la base (`D-16`). La forma normal de
darlas de alta es el enganche ([§4.1](#enganche)). Este comando da de alta **solo la competición, sin
equipo**, y se mantiene para semillas, *scripts* y tests:

```sh
swift run Run seed-competition -t atleti \
  -u "https://www.rffm.es/competicion/calendario?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549" \
  -c cadete -g masculino
```

Muestra los nombres que da la federación para la temporada, la competición y el grupo, y deja preparados el
`ingest` y el `curl` para lanzar la primera ingesta. **Es una herramienta de apoyo, no parte de la API**: el
`POST /v1/competitions` del *spec* es otra cosa. Frente a meter la fila a mano en la base:

- **Se pega la URL entera** en vez de teclear los códigos: un dígito mal no da error, sincroniza otro
  calendario (`D-22`).
- **Los nombres los pone la federación**, no quien teclea.
- **Pasa por las reglas del Dominio**, como el resto del código.
- **Comprueba antes de escribir**: si la URL está incompleta o no lleva a ninguna competición, falla sin
  dejar nada a medias.

**Qué escribe, comparado con el enganche:**

| | Escribe |
|---|---|
| `/preview` ([§4.1](#enganche), paso 1) | **Nada**: consulta a la federación y enseña lo que hay |
| `federation-link` ([§4.1](#enganche), paso 2) | Temporada, competición, **el equipo emparejado y su inscripción**, y encola la primera ingesta |
| `seed-competition` | Temporada y competición. **Nada del equipo** |

> ⚠️ **Para los equipos del club, engancha; no uses esto.** Si la competición entra por aquí y pasa una
> ingesta antes del enganche —y `launchd` la pasa solo—, la ingesta crea al equipo del club **como rival**,
> con su código. Engancharlo después da `409 FEDERATION_TEAM_ID_TAKEN`, y fundir las dos filas está sin
> diseñar (§9.5).

<a id="seed-team"></a>

### 6.3 `seed-team` — el equipo propio, para poder engancharlo

Da de alta un equipo del club. Hace falta para el enganche ([§4.1](#enganche)), que se hace sobre un equipo
que ya existe: crear equipos desde la API (`POST /v1/teams`) le toca al *backoffice*, que todavía no está
hecho.

```sh
swift run Run seed-team -t atleti -c cadete -g masculino -m futbol_11 -l A
```

Los parámetros están explicados en el paso 0 de [§4.1](#enganche).

**El equipo queda como equipo del club, no como rival, y sin emparejar con la federación.** Es el único
estado desde el que se puede enganchar.

**Edad, género y modalidad tienen que estar bien, porque después no se pueden cambiar** (`D-58`). Junto con
la letra, son lo que identifica al equipo. Si alguno está mal, el comando no lo detecta. El error aparece
al enganchar, como un **409**, cuando la competición no coincide con el equipo.

**Comprueba antes de escribir.** Si el club ya tiene un equipo con esa edad, género, modalidad y letra, lo
dice y da su UUID, en vez de crear otro o fallar con un error de base de datos difícil de leer.

**Sin `-l` es un equipo distinto**: el que no lleva letra porque es el único de su edad, género y
modalidad. No significa «cualquier letra»: `cadete` sin letra y `cadete A` son dos equipos.

> **No inscribe al equipo en ninguna temporada** (`D-68`): `team_registrations` queda vacía. Lo hace el
> enganche, porque es el que sabe en qué temporada y competición juega. Mientras tanto, el equipo existe pero
> no aparece en las pantallas que filtran por temporada.

<a id="ingest"></a>

### 6.4 `ingest` — la pasada de la federación

```sh
swift run Run ingest                        # todos los clubes, temporada vigente
swift run Run ingest -t atleti              # un club (o varios: -t "atleti,otro")
swift run Run ingest -c "<uuid>,<uuid>"     # competiciones concretas, en el orden pedido
swift run Run ingest --season <uuid>        # una temporada aunque no sea la vigente
swift run Run ingest --force                # no se salta nada (ver «antirrebote» abajo)
swift run Run ingest --min-interval-hours 24   # cambia las 6 h del antirrebote
swift run Run ingest --fail-if-empty          # un club sin nada que recorrer sale con 1 (lo usa launchd)
```

**Cada competición se sincroniza en tres pasadas**, y cada una deja sus propias filas en `ingestion_runs`:

| `kind` | Qué escribe | Filas por competición |
|---|---|---|
| `calendar` | Jornadas, partidos, equipos y clubes rivales (`Round`, `Match`, `Team`, `OpponentClub`) | **1** |
| `standings` | La clasificación (`StandingRow`): la que publica la federación o, si no la publica, calculada con los resultados (`D-15`) | **una por jornada** que haya que actualizar |
| `scorers` | Los goleadores (`LeagueScorer`) | **1** |

El calendario va primero porque crea los equipos y los partidos que necesitan las otras dos. Como la
clasificación deja una fila por jornada, **una competición dada de alta a mitad de temporada deja muchas
filas en su primera ingesta**. Los goleadores **no siempre se piden**: si la federación del club no los
publica, no hay de dónde sacarlos (`D-48`).

```sh
docker exec backend-db-1 psql -U tfm -d tfm -c "
SELECT kind, outcome, round_id IS NULL AS sin_jornada, league_scorers_retired AS retirados,
       round((extract(epoch from finished_at - started_at))::numeric, 3) AS seg
FROM club_atleti.ingestion_runs ORDER BY finished_at DESC LIMIT 10;"
```

- **Sale con código `1` si algo falló**, que es lo único que ve un programador de tareas (`D-86`). Un fallo en
  una competición **no para las demás**.
- **`round_id` solo lo tienen las filas de clasificación**, y la base de datos lo obliga.
- **El antirrebote**: por defecto, `ingest` se salta las competiciones sincronizadas hace menos de 6 h, para
  no repetir trabajo. Una competición **que nunca se ha sincronizado entra siempre**.
- **Cuántas veces por semana se sincroniza no lo decide el antirrebote**, sino los disparos programados de
  `launchd`: fin de semana y lunes (`D-87`, §5.6, [§6.5](#ingesta-programada)). El código no lo limita; se
  puede comprobar después en `ingestion_runs`.
- **Sin `--fail-if-empty`, no tener nada que sincronizar no es un fallo**: sale con `0` y un aviso
  (*"nada que recorrer"*), porque es lo normal en un club recién dado de alta. Con el *flag* sale con `1`, y
  así lo lanza `launchd` ([§6.5](#ingesta-programada)): ahí no mira nadie, y una ingesta que no sincroniza
  nada tiene que avisar. Lo que se salta el antirrebote **no** cuenta como «nada»: es un disparo de más, y la
  salida dice cuántas se saltó.

<a id="ingesta-programada"></a>

### 6.5 La ingesta programada en macOS — `launchd`

**Opcional.** Programa `ingest` con `launchd`, el programador de tareas de macOS, para que tu base local vaya
acumulando datos reales sin lanzarla a mano. Por defecto se dispara los **sábados y domingos a las 23:30 y
los lunes a las 08:00**, en hora local (`D-87`; las horas, `DL-3` del
[Plan launchd-001](./Plan%20launchd-001.md)). Si a esa hora el Mac está **dormido**, se ejecuta al
despertar. Es solo para macOS y para la base local; en producción (Fly.io) se programará de otra forma (§1.6
del plan).

**Antes de montarlo:**

- **Postgres tiene que estar levantado a la hora de los disparos** (`docker compose up -d db`). Si no, el
  disparo falla y avisa.
- **El club tiene que tener equipos enganchados** ([§4.1](#enganche)). Si no, no hay nada que sincronizar y
  cada disparo avisa de ello.
- **Usa la base de `docker compose`** (`localhost:5434`, usuario `tfm`). `launchd` no hereda las variables de
  tu terminal: si tu base es otra, añade las `DB_*` ([§2](#2-ejecución-y-entorno)) en `EnvironmentVariables`
  de la plantilla `Tools/Deploy/ingest.plist`.

**Montarlo son dos comandos**, desde `backend/` y en este orden, porque `agent.sh install` se niega si no hay
nada instalado:

```sh
Tools/Deploy/install.sh          # compila e instala; ~3 min la primera vez, ~20 s después
Tools/Deploy/agent.sh install    # da de alta el agente en launchd
Tools/Deploy/agent.sh status     # comprobarlo: disparos programados y binario instalado
```

**Son tres piezas, y ninguna se ejecuta desde el repositorio:**

```
~/Library/LaunchAgents/local.tfm.ingest.plist               ← CUÁNDO   (lo escribe agent.sh install)
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
- **El binario y el envoltorio se instalan desde un commit, no desde tus ficheros de trabajo** (A-15·H-85).
  `swift build`, `swift test` y `Tools/Mutate` reescriben `.build`; si `launchd` usara `.build/debug/Run`, un
  disparo en mitad de una prueba de mutación ejecutaría contra tu base código roto a propósito. Por eso **lo
  que no está en un commit no se instala**, y cambiar de rama no cambia lo que se ejecuta.

**Los dos guiones**, desde `backend/`:

| Para | Comando |
|---|---|
| **Instalar** o **actualizar** el binario y el envoltorio | `Tools/Deploy/install.sh`: instala **lo último que hay en un commit de tu rama** (lo no commiteado no entra). `install.sh main` o `install.sh <sha>` instala otra rama o un commit concreto |
| **Dar de alta** el agente en `launchd` (una vez, o si cambias la plantilla) | `Tools/Deploy/agent.sh install` |
| **Ver** el estado: disparos, último código de salida, binario, fallos | `Tools/Deploy/agent.sh status` |
| **Disparar ya**, sin esperar a la hora | `Tools/Deploy/agent.sh run` |
| **Quitarlo** (el binario y los logs se quedan) | `Tools/Deploy/agent.sh uninstall` |

**Para que `launchd` ejecute un cambio del código**: commit y `Tools/Deploy/install.sh`. **No hay que volver
a dar de alta el agente**: apunta a `current/`, e `install.sh` cambia ese enlace de una vez. Guarda las cinco
últimas versiones en `releases/`, y volver a una es `install.sh <sha>` (instantáneo si sigue ahí). El guion
**avisa** si instalas desde una rama que no es `main`, o con cambios sin commitear en `Sources/` (que no
entran).

**Para personalizarlo:**

| Qué | Cómo |
|---|---|
| **Las horas** | Edita `StartCalendarInterval` en `Tools/Deploy/ingest.plist` (`Weekday`: 0 = domingo, 1 = lunes… 6 = sábado) y vuelve a pasar `agent.sh install` |
| **El nombre del agente** en `launchd` (por defecto, `local.tfm.ingest`) | `export TFM_AGENT_LABEL=com.<tu-usuario>.tfm.ingest` antes de `agent.sh install`, y déjala puesta en tu perfil de shell: `status`, `run` y `uninstall` lo buscan por ese nombre |
| **Dónde se instala** (por defecto, `~/Library/Application Support/tfm`) | `TFM_HOME`, puesta igual para `install.sh` y para `agent.sh install` |
| **Dónde van los logs** (por defecto, `~/Library/Logs/tfm`) | `TFM_LOG_DIR`, antes de `agent.sh install` |

> **Al cambiar el nombre, quita antes el agente viejo.** Si no, habría dos agentes y cada disparo se
> ejecutaría dos veces. `agent.sh install` lo comprueba: si otro agente ya lanza esta ingesta, se para y
> dice cómo quitarlo (`launchctl bootout gui/<uid>/<nombre-viejo>` y borrar su `.plist`).

#### Dónde mirar

Con las rutas por defecto; si cambiaste `TFM_LOG_DIR` o `TFM_HOME`, en las tuyas.

| Qué | Dónde |
|---|---|
| La salida de cada disparo, con hora y commit | `~/Library/Logs/tfm/ingest.log` |
| **Los fallos, uno por línea con su motivo. No se borra solo** | `~/Library/Logs/tfm/ULTIMO_FALLO` — bórralo cuando lo hayas visto |
| Lo que falle **antes** de que arranque el envoltorio (p. ej., que no exista) | `~/Library/Logs/tfm/launchd.log` — normalmente vacío |
| Lo que escribió cada pasada | `ingestion_runs`, igual que con `ingest` a mano ([§6.4](#ingest)) |
| Qué versión está instalada | `agent.sh status`, o `~/Library/Application Support/tfm/current/VERSION` |

**Cuándo avisa**: solo si el código de salida no es `0`. Entonces sale una **notificación de macOS** («TFM ·
ingesta falló») y una línea en `ULTIMO_FALLO`, las dos con el motivo:

| El motivo dice | Qué pasa | Qué hacer |
|---|---|---|
| *"la base no responde: ¿está Docker parado?"* | Postgres no estaba a la hora del disparo. La pasada se detuvo sin dejar nada a medias (`D-86`) | Levantar Docker; entra en el disparo siguiente, o `agent.sh run` |
| *"<club>: nada que recorrer…"* | **No hay temporada vigente con competiciones**: el disparo no habría acumulado nada (H-59) | Dar de alta la temporada y enganchar los equipos ([§4.1](#enganche)) |
| *"<club>: N competición(es) sincronizada(s), M con fallo…"* | Alguna pasada falló; las demás siguieron (`D-86`) | Su fila de `ingestion_runs` dice cuál y por qué. Un `null` de la RFFM suele ser pasajero (H-61) |
| *"no se pudo ejecutar el binario instalado"* | No hay nada en `current/` | `Tools/Deploy/install.sh` |

> **Lo que no cubre:** el Mac **apagado** a la hora del disparo (está por comprobar si se recupera: `L-L.4`
> del plan), y que nadie mire las notificaciones. Un disparo **de más** no avisa ni repite trabajo: el antirrebote lo salta
> y la línea lo dice (*"N saltada(s) por el antirrebote"*).

---

## 7. El *spec*

`Sources/APIContract/openapi.yaml` — **6.860 líneas, 83 operaciones en 45 rutas y las 21 entidades de §3.2**.
Es la **fuente de verdad** (`D-25`): de él se generan los tipos y el `APIProtocol` (`D-65`).

```sh
npx @redocly/cli lint Sources/APIContract/openapi.yaml
ls .build/plugins/outputs/backend/APIContract/destination/OpenAPIGenerator/GeneratedSources/
```

**Para añadir un endpoint**: se añade su operación a `filter.operations` en `openapi-generator-config.yaml`
y se compila. **No compilará**, porque falta su método; se implementa y ya compila. Esa lista es exactamente
lo que está entregado de la API (`D-69`), y ese error de compilación es lo que garantiza que el código sigue
al *spec* y no al revés.

- **El generador crea los tipos, pero no valida** (`D-65`): ignora `pattern`, `minLength`, `readOnly`,
  `minProperties`, `default`, `tags` y `security`. Que algo esté en el YAML **no** significa que se compruebe.
- **Los errores se traducen a HTTP en un solo sitio: `ProblemMiddleware`.** También los que se escapan de un
  *handler* (H-40): le llegan envueltos en un `ServerError`, y los desenvuelve. Por eso un tipo de error nuevo
  hay que añadirlo **también** a su lista de desenvoltorio, o se queda en 500. Además traduce lo que pasa
  antes de llegar al *handler*: el club que no existe, la ruta que no existe o un parámetro obligatorio que
  falta.
- **Un *handler* solo atrapa un error si quiere devolverlo como una respuesta del *spec***. Y lo que
  devuelve tiene que ser una de las respuestas que el *spec* declara: el tipo generado no tiene otras.

**Las capas, qué hay en cada *target* y quién puede depender de quién: [AGENTS.md](../AGENTS.md).** Para
comprobar que una capa no puede usar lo que no le toca:

```sh
swift package clean
echo "import Vapor" > Sources/Domain/Prueba.swift
swift build --target Domain      # error: no such module 'Vapor'
rm Sources/Domain/Prueba.swift
```

El `swift package clean` hace falta: sin él, también falla (la regla se cumple), pero con un mensaje que
despista (`missing required module '_NumericsShims'`).

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
| `23514` al ingerir | Un `CHECK` del *schema* que se quedó atrás — ver el aviso de [§6.1](#provision) |
| Los tests se caen con **señal 5** | Una `Application` destruida sin esperar a que se cierre. Usa `TestEnvironment.withApp` |
| Los tests fallan **la primera vez** y pasan a la segunda | Dos *suites* en paralelo inicializando lo mismo a la vez. Esa inicialización va en `TestEnvironment.bootstrap()` |
| `PSQLError – Generic description…` | PostgresNIO oculta el detalle; `String(reflecting:)` lo muestra |
| `Address already in use` (errno 48) al hacer `serve` | Ya hay un `Run serve` vivo: `lsof -nP -iTCP:8080 -sTCP:LISTEN` y `kill <PID>` |
| `Test Suite … Executed 0 tests` de XCTest | No hay tests de XCTest en el proyecto (`D-70`), pero SwiftPM lanza también su ejecutor, que no encuentra nada. `--disable-xctest` lo quita |
| Docker no arranca | Suele ser disco lleno |

```sh
LOG_LEVEL=debug swift run Run serve    # cada petición y cada SQL
swift package clean && swift build     # cuando el build se comporta raro
```
