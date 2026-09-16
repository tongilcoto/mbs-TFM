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

Entregadas **F0 a F8**, más F6-bis y F6-ter. **446 tests.** Qué trajo cada una:
[Plan §4](../docs/Plan%20de%20desarrollo-001.md).

| Operación HTTP | |
|---|---|
| `GET /v1/club` · `PATCH /v1/club` | F0 |
| `GET /v1/ingestion-runs` · `POST /v1/ingestion-runs` | F6 |
| Las otras 79 del *spec* | ⛔ no generadas — [§7](#7-el-spec) |

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

swift run Run serve                # la API en :8080
```

```sh
curl -s http://atleti.localhost:8080/v1/club | jq     # en otra terminal
```

- **`--federation` es obligatoria**: fija a qué API se sincroniza el tenant entero y no hay defecto que no sea
  inventárselo (§3.6).
- **`*.localhost` resuelve a 127.0.0.1 sin configurar nada**, así que desarrollo usa la misma vía que
  producción: el club en el subdominio (§6.1). No hace falta ninguna cabecera.
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
├── club_atleti     ← un club: sus DIEZ tablas    (+ su _fluent_migrations)
└── club_celtic     ← otro club: las mismas tablas, datos distintos
```

Las diez de hoy, en el orden de FK con que se crean — **no son las 21 entidades de §3.2**, solo las que las
fases entregadas han necesitado:

```
clubs · seasons · opponent_clubs · teams · competitions · rounds · matches
      · standing_rows · league_scorers · ingestion_runs
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

```sh
curl -s http://atleti.localhost:8080/v1/club | jq

curl -s -X PATCH http://atleti.localhost:8080/v1/club \
  -H 'Content-Type: application/json' -d '{"name":"Renombrado"}' | jq
```

`PATCH` es **parcial**: lo que no mandas no se toca (§5.5).

**Las banderas de federación del `GET` no están en la base**: se derivan del catálogo en código (`D-17`), y
`Sources/Domain/FederationCode.swift` es el único sitio del proyecto donde aparecen `"rffm"` y `"fcf"`. Da de
alta un club con `-f fcf` y pide la misma URL para verlo.

**Los tres errores que conviene probar seguidos**, porque la diferencia entre ellos es el reparto de §5.5:

```sh
curl -s -i -X PATCH …  -d '{}'               | head -1   # 400
curl -s    -X PATCH …  -d '{"name":"   "}'   | jq        # 422
curl -s http://noexiste.localhost:8080/v1/club | jq      # 404
```

| Caso | Código | Quién lo decide |
|---|---|---|
| `{}` | **400** | el adaptador — `minProperties` del *spec*, que el generador ignora (`D-65`) |
| `{"name":"   "}` | **422** | el *Value Object* del Dominio: el JSON es válido, falla el **valor** |
| club inexistente | **404** | `TenantResolutionMiddleware`, antes de tocar ningún *schema* |

Todos devuelven `application/problem+json` (§5.4). **El `code` es para ramificar; el `title`, para leerlo.**

```sh
curl -s -H 'X-Club: atleti' http://localhost:8080/v1/club | jq   # atajo sin subdominio
```

`X-Club` **solo funciona en `.development`/`.testing`**: es un dato que controla el cliente entero, así que
aceptarla en producción sería dejar abierto un conmutador de tenant (§6.1).

### 4.1 La ingesta

```sh
# UNA competición: síncrona, 200, con el resultado dentro
curl -s -X POST http://atleti.localhost:8080/v1/ingestion-runs \
  -H 'Content-Type: application/json' -d '{"competitionId":"<uuid>"}' | jq

# La temporada vigente entera: 202, y dice qué ha aceptado
curl -s -i -X POST http://atleti.localhost:8080/v1/ingestion-runs \
  -H 'Content-Type: application/json' -d '{}'

curl -s "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<uuid>&limit=5" | jq
```

- **El cuerpo `{}` no es opcional**: un `POST` sin cuerpo da **400**, porque el servidor generado lo parsea
  igual (`D-65`).
- **200 con exactamente una competición, 202 con dos o más o con la temporada.** Lo decide **la petición, no
  los datos**: con `{}` sigue siendo 202 aunque el club tenga una sola competición (`D-88`).
- **`competitionIds` vacía es 400**, no *"todas"*. Para la temporada entera, se omite.
- **Una pasada fallida también se lee**: el `POST` da **502** y el `GET` enseña la fila con su `outcome` y su
  motivo — con el `sqlState` y la restricción si el fallo vino de Postgres (`D-85`).

---

## 5. Los tests

```sh
REQUIRE_DB=1 swift test                 # 446 tests, ~17 s — LA FORMA BUENA
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
> sale de la lista, no de lo ejecutado. Lo único que cambia es la duración: **17 s contra 0,002 s**. Omitir
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

**No compara bytes** (el calendario cambia cada semana por diseño): pasa nuestro parser por encima de la
respuesta viva y exige que no falle. **Sabe decir cuatro cosas y solo una es un hallazgo:**

| Lo que sale | ¿Hay que hacer algo? |
|---|---|
| *"No se pudo hablar con la RFFM"* · *"Respondió 500"* | no |
| *"La coordenada no designa nada"* | pasarle otra por variable |
| **⚠️ *"El parser ya no traga"*** | **sí**: recapturar volcado, revalidar el anexo, y solo entonces tocar el parser |

**Solo `FEDERATION_LIVE=1` es obligatoria**; la coordenada por defecto **envejece** —seguirá sirviendo su
temporada para siempre—, así que las otras cinco se configuran. Son las del volcado de temporada jugada, para
que el canario y el *fixture* hablen de lo mismo:

| Variable | Por defecto |
|---|---|
| `FEDERATION_LIVE_SEASON` | `21` |
| `FEDERATION_LIVE_COMPETITION` | `24037548` |
| `FEDERATION_LIVE_GROUP` | `24037549` |
| `FEDERATION_LIVE_MODALITY` | `futbol_11` — es el `tipojuego` de la URL |
| `FEDERATION_LIVE_NAME` | `PRIMERA DIVISION AUTONOMICA CADETE` |

Una modalidad fuera del catálogo **falla diciendo cuáles hay**, en vez de caer a `futbol_11`: elegir por quien
llama es lo que haría que el canario mirase otra modalidad y lo llamase verde.

> **El filtro es `RFFMCanaryTests`, el nombre del tipo.** `--filter FederationCanary` —el rótulo del *suite*—
> no casa con nada y da `0 tests … passed`, que **se lee como verde**.

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
pegar la URL en la ficha del equipo (`D-67`), y eso es **F10**; hasta entonces, esto:

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

### 6.2 `ingest` — la pasada de la federación

```sh
swift run Run ingest                        # todos los clubes, temporada vigente
swift run Run ingest -t atleti              # un club (o varios: -t "atleti,otro")
swift run Run ingest -c "<uuid>,<uuid>"     # competiciones concretas, en el orden pedido
swift run Run ingest --season <uuid>        # una temporada aunque no sea la vigente
swift run Run ingest --force                # ignora el antirrebote de 6 h
swift run Run ingest --min-interval-hours 24   # o cámbialo en vez de ignorarlo
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
- **Hoy no hay cron**, así que el tope semanal de §5.6 no lo garantiza nada. Apuntado en Plan §9.

---

## 7. El *spec*

`Sources/APIContract/openapi.yaml` — **6.644 líneas, 83 operaciones en 45 rutas y las 21 entidades de §3.2**.
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
