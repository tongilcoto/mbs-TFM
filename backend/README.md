# Backend · Manual de uso

> Cómo levantar esto, hablar con ello a mano y ver lo que pasa por dentro.
> El **diseño** está en [`docs/`](../docs/); esto es el **manual de a bordo**.
>
> Convención: **`§x` remite siempre al [LLD-001](../docs/API_y_BBDD%20LLD-001.md)** y `D-nn` a la
> [bitácora de decisiones](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md). Las remisiones a **este
> fichero** van como enlace, porque los números chocan: §5.2 es *«DTOs»* en el LLD y
> [otra cosa](#52-si-postgres-no-está-levantado) aquí.

---

## Índice

| | |
|---|---|
| [0 · Qué hay montado](#0-qué-hay-montado) | qué responde hoy y qué no |
| [1 · Arranque en 60 segundos](#1-arranque-en-60-segundos) | de cero a `curl` |
| [2 · Los dos modos de ejecución](#2-los-dos-modos-de-ejecución) | nativo o todo en Docker, y la configuración |
| [3 · Mirar la base de datos](#3-mirar-la-base-de-datos) | TablePlus y `psql` |
| [4 · Hablar con la API a mano](#4-hablar-con-la-api-a-mano) | leer, escribir, los errores, la ingesta |
| [5 · Los tests](#5-los-tests) | filtros, tus datos, el canario |
| [6 · Los comandos](#6-los-comandos) | provisión, siembra e ingesta |
| [7 · El *spec* y el código generado](#7-el-spec-y-el-código-generado) | cómo se añade un endpoint |
| [8 · Arquitectura, en una pantalla](#8-arquitectura-en-una-pantalla) | el grafo de capas |
| [9 · Cuando algo falla](#9-cuando-algo-falla) | los tropiezos conocidos |

---

## 0. Qué hay montado

Del [Plan de desarrollo](../docs/Plan%20de%20desarrollo-001.md) están entregadas **F0 a F6**. **266 tests.**
Qué trajo cada fase y qué preguntas contestó está en **Plan §3 y §4.2–§4.8**; aquí solo lo que se puede
**tocar**.

| Operación HTTP | |
|---|---|
| `GET /v1/club` · `PATCH /v1/club` | F0 |
| `GET /v1/ingestion-runs` · `POST /v1/ingestion-runs` | F6 |
| Todo lo demás del *spec* (79 de sus 83 operaciones) | ⛔ no generado — §7 |

**Esa lista no dice lo que hay montado, solo lo que se toca con `curl`.** De F1 a F5 no se añadió un endpoint
y era el plan: el adaptador primario de la ingesta es un `AsyncCommand`, no un Controller (§2.3-b). Lo que
hay debajo se mira por **la base de datos** (§3), por **los comandos** (§6) o por **los tests** (§5) — que es
lo que el plan pide: *"los tests son la especificación revisable, no el código"* (Plan §9).

```sh
swift run Run --help              # todos los comandos
swift test                        # 266 tests, ~5 s con Docker levantado
```

**La BD vive siempre en Docker.** Lo que cambia entre los dos modos de §2 es dónde corre **la API**.

---

## 1. Arranque en 60 segundos

```sh
cd backend
docker compose up -d db            # Postgres 16 en localhost:5434

swift run Run migrate --yes        # crea public.tenants (plano de control)

# Alta del club: schema + registro + migraciones + la fila del club (§6.3).
# `--federation` es obligatoria: determina a qué API se sincroniza el tenant
# entero (§3.6) y no hay valor por defecto que no sea inventárselo.
swift run Run provision-tenant atleti \
  --federation rffm --name "Club Atlético de Ejemplo" --short-name "CD Atleti"

swift run Run serve                # la API en :8080
```

En otra terminal:

```sh
curl -s http://atleti.localhost:8080/v1/club | jq
```

> **`atleti.localhost` funciona sin configurar nada**: `*.localhost` resuelve a 127.0.0.1 en macOS y en
> los navegadores. Por eso desarrollo usa **la misma vía que producción** —el club en el subdominio (§6.1)—
> y no hace falta ninguna cabecera especial.

Para parar: `Ctrl-C` la API, y `docker compose down` (conserva los datos) o `down -v` (los borra).

---

## 2. Los dos modos de ejecución

### 2.1 API nativa + BD en Docker ← **el modo normal**

```sh
docker compose up -d db
swift run Run serve
```

Recompila en segundos, funcionan los *breakpoints* de Xcode y los `print`. **Es donde vas a vivir.**

### 2.2 Todo en Docker

```sh
docker compose --profile full up --build
```

Levanta la API dentro de un contenedor Linux, compilada en **release** con el `Dockerfile` real. Tarda
~3 minutos porque compila de cero. No sirve para desarrollar; sirve para responder *"¿esto seguiría
funcionando desplegado?"* — que es una pregunta distinta y que conviene hacerse de vez en cuando.

Una diferencia que confunde la primera vez: dentro de la red de compose, la API usa `DB_HOST=db` y el
puerto **interno** `5432`. Desde el Mac es `localhost:5434`. Es la misma base de datos.

### 2.3 Configuración por entorno

Todo por variables, para que CI apunte a lo suyo sin tocar código:

| Variable                              | Por defecto | Para qué                                                                               |
| ------------------------------------- | ----------- | -------------------------------------------------------------------------------------- |
| `DB_HOST`                             | `localhost` | `db` dentro de compose                                                                 |
| `DB_PORT`                             | `5434`      | `5432` dentro de compose                                                               |
| `DB_USER` / `DB_PASSWORD` / `DB_NAME` | `tfm`       |                                                                                        |
| `DOMAIN_SUFFIX`                       | `localhost` | El sufijo que se recorta del `Host` (§6.1)                                             |
| `LOG_LEVEL`                           | `info`      | `debug` para ver cada petición y cada SQL. Vale también en `swift test`                |
| `HTTP_TRACE`                          | apagado     | `1` vuelca los cuerpos HTTP ([§2.4](#24-ver-lo-que-cruza-la-frontera)). Solo en `.development`/`.testing`                  |
| `REQUIRE_DB`                          | apagado     | `1` hace que los tests de BD **fallen** en vez de omitirse ([§5.2](#52-si-postgres-no-está-levantado)). `CI` la activa sola |
| `KEEP_TEST_DATA` | apagado | `1` conserva los *schemas* de test para inspeccionarlos ([§5.1](#51-tus-datos-no-se-tocan)). **Solo la mira `swift test`**: en un `swift run Run …` no hace nada |

```sh
LOG_LEVEL=debug swift run Run serve      # verás el SQL que emite Fluent
HTTP_TRACE=1  swift run Run serve        # verás los cuerpos que entran y salen
LOG_LEVEL=debug HTTP_TRACE=1 swift run Run serve  # verás ambas cosas
```

### 2.4 Ver lo que cruza la frontera

**`--log debug` no enseña los cuerpos, y ninguna combinación de niveles lo hará**: Vapor registra la línea de
petición, las cabeceras y el SQL de Fluent, pero nunca el cuerpo — ni el que entra ni el que sale. Hace falta
**`HTTP_TRACE=1`**, que es una variable aparte y **no** un nivel de log:

```sh
swift run Run serve --log debug                 # SQL sí, cuerpos no
HTTP_TRACE=1 swift run Run serve --log debug    # las dos cosas
```

```
┌─ → PATCH /v1/club
│  Host: atleti.localhost:8080
│  Content-Type: application/json
│
│  {
│    "name" : "   "
│  }
├─ ← 422 Unprocessable Entity
│  Content-Type: application/problem+json; charset=utf-8
│
│  {
│    "code" : "INVALID_VALUE",
│    "detail" : "name: no puede estar vacío",
│    "status" : 422,
│    "title" : "Valor no válido",
│    "type" : "https://api.example.com/problems/invalid-value"
│  }
└─
```

Los parámetros de consulta salen aparte, uno por línea (`?page=2`), que es donde se ve qué recibió de verdad
el *handler* — importante porque sus valores por defecto los aplica él a mano, ya que el generador ignora
`default` (`D-65`).

> **Solo funciona en `.development` y `.testing`**, y el candado no es celo: los cuerpos de esta API llevan
> nombres, fechas y fotos **de menores** (§3.2). Un volcado completo en un log de producción es una fuga de
> datos personales, no un log verboso. Misma lista **blanca** que `X-Club`: un entorno nuevo nace con la
> traza apagada.

El equivalente en los tests es `HTTP_TRACE=1 swift test` ([§5.3](#53-ver-los-cuerpos-que-cruzan-la-frontera)).

---

## 3. Mirar la base de datos

### 3.1 TablePlus

| Campo | Valor |
|---|---|
| Host | `127.0.0.1` |
| Port | **5434** |
| User / Password | `tfm` / `tfm` |
| Database | **`tfm`** ← tu trabajo manual |
| SSL | desactivado |

**Hay una segunda base, `tfm_test`**, con las mismas credenciales y el mismo puerto: solo cambia el nombre.
Ahí es donde corren los tests ([§5.1](#51-tus-datos-no-se-tocan)), y por eso `swift test` no puede tocar nada de `tfm`. Merece su propia
conexión en TablePlus si quieres ver qué dejan los tests — pero **no hace falta para trabajar**: se crea sola
y se puede borrar entera sin consecuencias.

| | `tfm` | `tfm_test` |
|---|---|---|
| Quién escribe | tú, a mano, y `swift run Run …` | `swift test` |
| *Schemas* de club | `club_<slug>` | `test_<slug>` y `e2e_<slug>` |
| Si la borras | pierdes tu trabajo | nada: se recrea en la siguiente pasada |

**Lo que verás, y es el diseño entero en una captura** (§6.2):

```
tfm
├── public          ← plano de control: tenants  (+ su propia _fluent_migrations)
├── club_atleti     ← un club: clubs  (+ su propia _fluent_migrations)
└── club_celtic     ← otro club: las mismas tablas, datos distintos
```

Cada uno de los tres tiene **su propia `_fluent_migrations`**, y eso no es ruido: el plano de control se
migra con `migrate` y cada club con `migrate-tenants`, por separado (§4.7). Revertir un club no toca a los
demás.

Cada club tiene **su propio juego de tablas** en su propio *schema*. La API no filtra por `club_id`: fija
`search_path` al *schema* del club y el mismo SQL —byte a byte— lee de uno o de otro. Por eso ninguna
tabla tiene columna de club y ninguna ruta lleva `clubId`.

Fíjate también en que **`_fluent_migrations` está en cada *schema***: el progreso de migración se rastrea
**por club** (§4.7).

### 3.2 psql, si prefieres terminal

```sh
docker compose exec db psql -U tfm -d tfm

\dn                        -- lista los schemas: ahí están los clubes
\dt club_atleti.*          -- tablas de un club
SELECT * FROM public.tenants;
SELECT * FROM club_atleti.clubs;
```

---

## 4. Hablar con la API a mano

### 4.1 Leer

```sh
curl -s http://atleti.localhost:8080/v1/club | jq
```

```json
{
  "id": "83f43370-bf17-4916-b8ae-97b13da59a69",
  "name": "Club Atlético de Ejemplo",
  "shortName": "CD Atleti",
  "slug": "atleti",
  "federation": "rffm",
  "federationProvidesRoundStandings": true,
  "federationProvidesScorers": true,
  "settings": {},
  "createdAt": "2026-08-25T22:12:08Z",
  "updatedAt": "2026-08-25T22:12:08Z"
}
```

**El experimento que más enseña:** provisiona un segundo club con otra federación y pide **la misma URL**.

```sh
swift run Run provision-tenant celtic -f fcf --name "Celtic de Ejemplo" --short-name Celtic

curl -s http://celtic.localhost:8080/v1/club | jq '{slug, federation, federationProvidesRoundStandings}'
```

```json
{ "slug": "celtic", "federation": "fcf", "federationProvidesRoundStandings": false }
```

> **Ojo con el ejemplo que había aquí antes**, que usaba `federationProvidesScorers` y decía `false`. Es
> falso desde el 2026-08-28: la FCF **sí** publica goleadores en su web nueva (`D-74`, Anexo FCF §C.10.7), y
> el catálogo se corrigió entonces. La bandera que sigue distinguiendo a las dos federaciones es la de la
> **clasificación por jornada** (`D-55`). Corregido en F6 al releer este manual.

La bandera cambió **sin que nadie la escribiera en la base de datos**: se derivan del catálogo de
federaciones, que es **código y no tabla** (§3.6, `D-17`). Mira `Sources/Domain/FederationCode.swift` — es
el único sitio del proyecto donde aparecen las cadenas `"rffm"` y `"fcf"`.

### 4.2 Escribir

```sh
curl -s -X PATCH http://atleti.localhost:8080/v1/club \
  -H 'Content-Type: application/json' \
  -d '{"name":"Club Deportivo Renombrado"}' | jq
```

`PATCH` es **parcial**: el campo que no mandas no se toca (§5.5). Comprueba que `shortName` sigue igual.

### 4.3 Los errores, que es donde está el diseño

Prueba estos tres seguidos y compara. **La diferencia entre ellos es el reparto de responsabilidades de
§5.5**, no un detalle de códigos:

```sh
# 1) Cuerpo sin ningún campo → 400. Lo rechaza el ADAPTADOR.
curl -s -i -X PATCH http://atleti.localhost:8080/v1/club \
  -H 'Content-Type: application/json' -d '{}' | head -1

# 2) Campo presente pero vacío → 422. Lo rechaza el DOMINIO.
curl -s -X PATCH http://atleti.localhost:8080/v1/club \
  -H 'Content-Type: application/json' -d '{"name":"   "}' | jq

# 3) Club que no existe → 404. Lo rechaza el MIDDLEWARE de tenancy, antes de tocar ningún schema.
curl -s http://noexiste.localhost:8080/v1/club | jq
```

| Caso | Código | Quién lo decide | Por qué |
|---|---|---|---|
| `{}` | **400** | Adaptador primario | `minProperties: 1` del *spec*, que **el generador ignora** (`D-65`) |
| `{"name":"   "}` | **422** | *Value Object* del Dominio | El JSON es válido y el tipo correcto; falla el **valor**. Y la regla vive en el Dominio para que la ingesta —que no pasa por HTTP— quede sujeta a ella |
| club inexistente | **404** | `TenantResolutionMiddleware` | Literal: no existe. No es el 404 defensivo que `D-64` descarta |

Todos devuelven `Content-Type: application/problem+json` (RFC 7807, §5.4):

```json
{
  "type": "https://api.example.com/problems/invalid-value",
  "title": "Valor no válido",
  "status": 422,
  "detail": "name: no puede estar vacío",
  "code": "INVALID_VALUE"
}
```

El `code` es lo que el cliente debe usar para ramificar; el `title` es para leerlo.

### 4.4 La cabecera `X-Club`, y por qué casi nunca la necesitas

Existe como atajo cuando no quieres usar subdominios:

```sh
curl -s -H 'X-Club: atleti' http://localhost:8080/v1/club | jq
```

**Solo funciona en `.development` y `.testing`.** En producción está apagada por lista blanca: es un dato
que controla el cliente entero, así que aceptarla allí sería dejar abierto un conmutador de tenant (§6.1).

---

### 4.5 La ingesta, desde `curl`

Los dos endpoints que trae F6 (`D-88`). Necesitas una `Season` y una `Competition` dadas de alta — hoy se
siembran por repositorio o por *script*, porque su `POST` no está generado todavía (§7).

```sh
# Lanzar la pasada de UNA competición: síncrona, 200, con el resultado dentro
curl -s -X POST http://atleti.localhost:8080/v1/ingestion-runs \
  -H 'Content-Type: application/json' \
  -d '{"competitionId":"<uuid>"}' | jq

# La temporada vigente entera: 202, y dice qué ha aceptado
curl -s -i -X POST http://atleti.localhost:8080/v1/ingestion-runs \
  -H 'Content-Type: application/json' -d '{}'

# Leer el registro
curl -s "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<uuid>&limit=5" | jq
```

**Tres cosas que se aprenden más rápido probándolas que leyéndolas:**

- **El cuerpo `{}` no es opcional.** Un `POST` sin cuerpo devuelve **400**: el servidor generado lo parsea
  igual, así que el *spec* declara `required: true` con todos los campos opcionales. Es `D-65` otra vez — lo
  que el YAML promete hay que ir a comprobarlo.
- **200 o 202 según el coste** (`D-67` un nivel más abajo): **exactamente una** competición cabe en la
  respuesta; dos o más, o una temporada, no. **Lo decide la petición, no los datos**: con `{}` sobre un club
  de una sola competición sigue siendo 202, porque una respuesta que cambia de forma según cuántos equipos
  tenga el club no se puede programar.
- **`competitionIds` es una lista porque la pantalla lo es**: equipos con una casilla al lado. Vacía →
  **400**; para la temporada entera, se omite. Lo que el backoffice llama *"un equipo"* es en realidad la
  terna *(equipo, temporada, competición)*, y el id que viaja es el de la **competición** — pero **ninguna
  lectura sirve esa terna entera** todavía: hoy costaría N+1 peticiones. Está abierto en §9.12 del LLD, y no
  bloquea este endpoint, que recibe ids en vez de descubrirlos.
- **Una pasada que falla también se lee.** Prueba con una coordenada mala: el `POST` devuelve **502** y el
  `GET` te enseña la fila con `outcome: "failed"` y su motivo. Es la razón de ser entera de `D-85` — la
  pasada que falla es la que nadie ve.
- **Y el motivo dice algo.** Si el fallo viene de Postgres, la fila lleva el `sqlState` y la restricción que
  reventó, no la descripción genérica que `PSQLError` da por defecto. Costó una sesión de pruebas manuales
  descubrir que ahí no había nada legible (`D-85`).

## 5. Los tests

```sh
swift test                                  # los cuatro niveles
swift test --filter DomainTests             # nivel 1
swift test --filter ApplicationTests        # nivel 2
swift test --filter PersistenceTests        # nivel 3 — necesita Docker
swift test --filter APITests                # nivel 4 — necesita Docker
REQUIRE_DB=1 swift test                     # falla si no hay BD, en vez de omitir
KEEP_TEST_DATA=1 swift test                 # conserva los schemas para inspeccionarlos
swift test --filter TenancyTests            # nivel rápido, aunque sea infraestructura
swift test --filter FederationTests         # nivel 1 — federación: sin red y sin Docker
FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests
                                            # EL CANARIO — fuera de la batería, con red (§5.5)
swift test --no-parallel                    # en serie, útil al depurar
swift test --disable-xctest                 # sin el ruido de XCTest (ver abajo)
```

**Para revisar una fase, sus tests** (Plan §9: *"los tests son la especificación revisable"*). Las comillas
simples **no son decorativas**: sin ellas `zsh` se come el `|` como una tubería.

| Fase | Filtro | Docker |
|---|---|---|
| F3 · política de *upsert* | `'UpsertPolicyTests\|KickoffTests\|KickoffMergeTests\|MatchResultTests'` | no |
| F4 · cadena de emparejamiento | `'MatchingChainTests\|NormalizedNameTests'` | no |
| F5 · entidades de la ingesta | `'RoundTests\|OpponentClubTests\|TeamTests\|MatchTests\|IngestionRunTests'` | no |
| F5 · la pasada, con dobles | `IngestCalendarTests` | no |
| F5 · las tablas y la pasada real | `'IngestionPersistenceTests\|CalendarIngestionEndToEndTests'` | **sí** |
| F6 · el recorrido y sus argumentos | `'IngestClubCalendars\|IngestArguments'` | no |
| F6 · el recorrido por tenant | `TenantTraversal` | **sí** |
| F6 · los dos endpoints | `IngestionEndpoint` | **sí** |

> **`--filter` es una expresión regular sobre identificadores de Swift** —el tipo de la *suite* y la función
> del `@Test`—, y de ahí salen tres sorpresas. **Arrastra tests de suites que no esperas**, así que las
> cuentas se mueven solas al añadir una fase. **`Season` coge también `SeasonLabel`**, y `Federation` a secas
> se lleva el catálogo entero. Y la que más despista: **el rótulo del `@Test` no se filtra** — `--filter
> reconoce` devuelve **0** aunque "se reconoce" esté en seis rótulos. Para buscar por rótulo, `grep` sobre
> `Tests/`. Son filtros para trabajar: **para saber si algo está roto, `swift test` a secas.**

**Para estudiar, usa `--no-parallel --disable-xctest`.**

```sh
swift test --no-parallel --disable-xctest
```

Por defecto `swift-testing` ejecuta en paralelo —también los tests **dentro** de una misma suite— y escribe
en **orden de finalización**, así que la salida sale entrelazada y cambia entre pasadas. En serie da todo lo
que hace falta para leerla:

- **Orden exacto del código fuente**, y determinista: tres pasadas, la misma salida byte a byte.
- **Agrupada por suite**, abriendo y cerrando cada una antes de la siguiente.
- **Un renglón por caso** en los tests parametrizados, con el argumento concreto
  (`→ "cd--ejemplo" to "rechaza lo que el pattern del spec no admite"`), que es lo que quieres ver cuando
  falla uno de nueve.

El paralelo no sobra —cuando se midió, los 138 tests bajaban de **3,7 s a 0,9 s**, y correrlos concurrentes **es** lo que destapó
las dos carreras de §5.1, que un orden fijo habría escondido—. Pero para leer, en serie.

> **`Test Suite 'ClubBackendPackageTests.xctest' … Executed 0 tests` no significa que haya XCTest.** No hay
> ni un `import XCTest` en el proyecto (`D-70`). Lo que pasa es que SwiftPM ejecuta **las dos** bibliotecas
> de test por defecto: la mitad de XCTest arranca, no encuentra nada y lo dice, y luego corre
> `swift-testing`. El nombre `.xctest` tampoco delata nada: es el **formato de empaquetado** de Apple, y
> todos los *targets* acaban en un único *bundle* con ese nombre usen el framework que usen.
> `--disable-xctest` lo quita.

### 5.1 Tus datos no se tocan

**Los tests corren contra otra base, `tfm_test`**, que crean solos la primera vez. Tu trabajo manual vive en
`tfm` y `swift test` **no la abre siquiera** — comprobado creando un `e2e_trampa` dentro de `tfm`: sigue ahí
después de correr los tests.

> No siempre fue así, y el fallo merece recordarse porque no avisaba: compartían base, y `public.tenants` es
> **una sola tabla**. Un test con el *slug* `madrid` borraba al terminar el registro del `madrid` que
> tuvieras dado de alta — los datos seguían en su *schema*, pero **el club dejaba de ser alcanzable**. Un 404
> sobre datos que están ahí.

**Y la dejan limpia.** Cada test borra su *schema*, y `swift test` **barre al arrancar** lo que dejara una
pasada anterior que no acabó bien — al entrar y no en un `defer`, para que la corrección no dependa del
camino de error:

| Cómo terminó la pasada | Qué queda |
|---|---|
| Todo verde, o un `#expect` que falla | Limpio (`#expect` **no lanza**: la limpieza final se ejecuta) |
| Algo **lanza** | Su *schema*, hasta el siguiente `swift test` |

```sh
docker compose exec db psql -U tfm -d tfm_test -c '\dn'   # lo que dejan los tests

KEEP_TEST_DATA=1 swift test --filter ClubUpdateTests      # conservarlos para mirarlos
```

Luego los abres en TablePlus sobre **`tfm_test`**:

```sql
SELECT name, short_name, updated_at FROM e2e_patch1.clubs;
```

Es la alternativa barata al *breakpoint*, y a menudo mejor: parar el depurador dentro de un test de
integración te deja mirando **una transacción que aún no ha confirmado**. El barrido de arranque sigue
corriendo con la bandera puesta, a propósito: cada pasada te deja **su** estado, no la acumulación.

**Los niveles 1 y 2 corren sin Docker**, y es el dividendo de separar el Dominio de Fluent (`D-01`): son los
que ejecutas cien veces al día.

### 5.2 Si Postgres no está levantado

**Los tests que necesitan base de datos se omiten**, y te dicen el comando que falta:

```
➜ Suite "Tenancy · §6.2 · el search_path aísla de verdad" skipped: "Postgres no responde en
  localhost:5434 … Levántalo con `docker compose up -d db` desde `backend/`. Para que fallen
  en vez de omitirse —lo que hace CI— define REQUIRE_DB=1."
```

Así el bucle rápido no se te bloquea por tener Docker parado. Pero omitir tiene un riesgo evidente
—**verde no puede significar "no probado"**— y por eso hay guarda:

| Situación | Resultado |
|---|---|
| BD arriba | Todo corre |
| BD abajo, en local | Los tests de BD **se omiten**, `exit 0` |
| BD abajo, con `CI` o `REQUIRE_DB` | **Falla**, `exit 1`, diciendo por qué en una línea |

`CI` la exportan GitHub Actions, GitLab y la mayoría por defecto, así que en integración continua la guarda
se activa sola. En local decides tú, viendo el motivo.

**Lo que deliberadamente NO hace es arrancar Docker por su cuenta.** Una batería que levanta contenedores
muta tu máquina, se acopla a que Docker esté instalado y no tiene respuesta buena a *"¿y quién lo para?"* —
te tumbaría el contenedor que estabas usando, o te lo dejaría vivo. En CI además sobra, porque allí la BD la
da el *runner* como servicio.

`TenancyTests` lleva asterisco porque es el único que rompe la correspondencia nivel↔capa de §8.1:
`HostSlugExtractor` vive en infraestructura pero **no hace I/O**, así que se prueba en el nivel barato. La
regla que se deriva, y que aplica a lo que venga: **si un componente no hace I/O, se prueba sin él, esté en
la capa que esté.** Mandarlo a integración por estar "fuera" solo lo haría más lento sin probar nada más.

| Nivel | *Target*           | Qué prueba                                   | I/O           |
| ----- | ------------------ | -------------------------------------------- | ------------- |
| 1     | `DomainTests`      | Invariantes y *Value Objects*                | **cero**      |
| 2     | `ApplicationTests` | Casos de uso con puertos **falseados**       | **cero**      |
| 1\*    | `TenancyTests`     | Slug del `Host` — **pura, pero en infraestructura** | **cero**      |
| 3     | `PersistenceTests` | Mapeo, migraciones, `search_path`            | Postgres real |
| 4     | `APITests`         | Rutas, DTOs, códigos de error                | Postgres real |

### 5.3 Ver los cuerpos que cruzan la frontera

```sh
HTTP_TRACE=1 swift test --filter APITests --no-parallel     # los cuerpos HTTP
LOG_LEVEL=debug swift test --filter PersistenceTests        # el SQL que emite Fluent
LOG_LEVEL=debug HTTP_TRACE=1 swift test --no-parallel       # las dos cosas
```

Es **el mismo middleware** que usa el servidor, así que la salida es la de §2.4 —no la repito— y lo que ves
en un test es exactamente lo que verías en `swift run Run serve`. Apagado por defecto para no ensuciar CI, y
`--no-parallel` porque si no las trazas se entrelazan.

`LOG_LEVEL` enseña el SQL, que en los niveles 3 y 4 es justo lo que quieres ver:

```
debug codes.vapor.application: sql=SET LOCAL search_path TO "test_scope-a"
debug codes.vapor.application: sql=UPDATE "clubs" SET "name" = $1, …
```

### 5.4 Cómo leer un test

Cada `@Test` cita en su nombre la sección del LLD o la decisión que lo exige, y eso es deliberado: **revisar
una fase es leer sus tests y comprobar que dicen lo que el diseño dice**, sin leer el código (Plan §9).

```sh
swift test --filter 'UpsertPolicyTests|KickoffTests|KickoffMergeTests|MatchResultTests' \
           --no-parallel --disable-xctest
```

Trece renglones, en orden de fichero, cada uno con su `§x` o su `D-nn`. Eso **es** la revisión de F3.

**La destreza que hay que traer: hay parejas que solo significan algo leídas juntas.**

```swift
@Test("sin marcador, la hora que desaparece devuelve el horario a provisional (D-30)")
@Test("con marcador, la hora que desaparece se ignora: es pérdida de dato (D-56)")
```

Es `D-56` hecha código — **el mismo campo vacío significa dos cosas** según el partido se haya jugado o no.
Leído solo uno, la regla parece incoherente. F4 tiene otra pareja igual (`D-78`), y la comentan Plan §4.5 y
§4.6.

**Y algún test no puede fallar, a propósito.** Los que sostiene **un tipo** y no una guarda —`TeamOwnership`
no lleva nombre de club, `MatchCandidate` no tiene fecha— parecen tautologías y son lo contrario: fijan la
decisión de modelado que hace que la regla **no se pueda desobedecer**. Es lo que hay que leer antes de
añadirle un campo "para desempatar" a un candidato.

> Que un test llegue en verde sin haber estado en rojo es **deuda declarada** (Plan §5.1). Lo que compra la
> garantía en su lugar es la **comprobación de mutación**, fase por fase en Plan §4.5–§4.8.

---

### 5.5 El canario, que **no** corre con `swift test`

```sh
FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests
```

Es la única prueba del repositorio que **habla con internet**, y vive fuera de la batería a propósito. Las dos
contestan preguntas distintas:

| | Responde a | Determinista | Cuándo corre |
|---|---|---|---|
| Los volcados de `Tests/FederationTests/Fixtures/` | *¿he roto yo el parser?* | sí | **siempre**, sin red |
| **El canario** | *¿han cambiado ellos?* | **no, por naturaleza** | a demanda |

Fusionarlas las estropea las dos: con una petición de red dentro de `swift test`, un rojo puede significar que
la federación está caída — y entonces el verde deja de significar *"mi cambio está bien"*.

**No compara bytes.** El calendario cambia todas las semanas por diseño: los horarios se fijan el domingo y
los marcadores entran el fin de semana. Un `diff` daría alarma **cada lunes**, y una bandera que grita siempre
es peor que ninguna. Lo que hace es pasar **nuestro parser** por encima de la respuesta viva y exigir que no
falle, más unos invariantes baratos (que haya jornadas, que los `codacta` sigan siendo únicos).

**Sabe decir cuatro cosas distintas, y solo una es un hallazgo:**

| Lo que sale | Qué significa | ¿Hay que hacer algo? |
|---|---|---|
| *"No se pudo hablar con la RFFM"* | no hay red, o su servidor está caído | no |
| *"La coordenada ha caducado"* | `competicion`/`grupo` reciben un bloque nuevo cada temporada | pasarle otra por variable de entorno |
| *"Respondió 500"* | fallo suyo | no, salvo que se repita días |
| **⚠️ *"El parser ya no traga"*** | **han cambiado la forma de la respuesta** | **sí: recapturar volcado, revalidar el anexo, y solo entonces tocar el parser** |

Y una quinta que no es del parser: si la respuesta llega, parsea bien y **es de otra competición**. La RFFM
**no reutiliza los códigos entre temporadas** —cada una recibe un bloque nuevo— y además **ignora el
parámetro `temporada`** (`D-84` enmendada), así que una coordenada caducada **no da 404**: devuelve el
calendario del año pasado, para siempre y sin error. El canario compara también el nombre.

**Solo `FEDERATION_LIVE=1` es obligatoria.** La coordenada por defecto caduca —`competicion` y `grupo`
cambian cada temporada—, así que las otras cuatro son configurables sin tocar código:

| Variable | Por defecto |
|---|---|
| `FEDERATION_LIVE_SEASON` | `21` |
| `FEDERATION_LIVE_COMPETITION` | `24037548` |
| `FEDERATION_LIVE_GROUP` | `24037549` |
| `FEDERATION_LIVE_MODALITY` | `futbol_11` — es el `tipojuego` de la URL |
| `FEDERATION_LIVE_NAME` | `PRIMERA DIVISION AUTONOMICA CADETE` |

Son las del volcado de temporada jugada, a propósito: así el canario y el *fixture* hablan de lo mismo.

```sh
FEDERATION_LIVE=1 \
  FEDERATION_LIVE_SEASON=22 \
  FEDERATION_LIVE_COMPETITION=26737701 \
  FEDERATION_LIVE_GROUP=26737702 \
  FEDERATION_LIVE_MODALITY=futbol_7 \
  FEDERATION_LIVE_NAME="PREFERENTE AFICIONADO" \
  swift test --filter RFFMCanaryTests
```

Una modalidad fuera del catálogo **falla diciendo cuáles hay**, en vez de caer a `futbol_11`: elegir por
quien llama es lo que haría que el canario mirase otra modalidad y lo llamase verde.

> **El filtro es `RFFMCanaryTests`, el nombre del tipo.** `--filter FederationCanary` —el rótulo del *suite*—
> no casa con nada y se queda en `Test run with 0 tests … passed`, que **se lee como verde**. Es la misma
> trampa de §5.1 con otra cara: `--filter` es una expresión regular sobre identificadores de Swift.


## 6. Los comandos

```sh
swift run Run --help
swift run Run migrate --yes                 # plano de control (public.tenants)
swift run Run migrate-tenants               # migraciones nuevas a TODOS los clubes
swift run Run migrate-tenants -t atleti     # solo a uno
swift run Run migrate-tenants --revert      # revierte

# Alta de club: los cuatro pasos de §6.3, idempotente
swift run Run provision-tenant atleti -f rffm
swift run Run provision-tenant atleti -f rffm --name "Nombre Largo" --short-name "Corto"
swift run Run provision-tenant atleti -f rffm -s mi_schema
```

> ⚠️ **`migrate-tenants` va siempre por conexión directa, nunca por un *pooler*** (§6.4). Se apoya en un
> `SET` de sesión, que detrás de un *pooler* en modo transacción deja de significar lo que parece. El precio
> de equivocarse no es leer mal: es **crear la tabla en el *schema* de otro club**, y eso no se deshace
> reintentando.

**Cuatro cosas que ahorran un rato:**

- **`swift run Run …` trabaja siempre sobre `tfm`**, tu base manual. `tfm_test` no existe para estos
  comandos: los tenants de los tests los crean y borran ellos (§5.1). Así que `1 tenant(s) procesados` es la
  respuesta correcta si solo diste de alta `atleti`.
- **Cuando una fase añade tablas, vuelve a pasar `migrate-tenants`.** Fluent aplica solo las que faltan y no
  hay que reaprovisionar nada.
- **`--name` no tiene forma corta**: `-n` lo reserva ConsoleKit y, si se declara, sale en el `--help` pero el
  valor acaba en `.unknownInput`. `-f` y `-s` sí funcionan.
- **El alta de un club es un comando, no un endpoint** (`D-23`), y por eso hace **cuatro** cosas: crea el
  *schema*, registra el club en `public.tenants`, pasa el juego **completo** de migraciones y **siembra la
  fila de `clubs`**. El cuarto es el que se olvida, y su síntoma es un `500 TENANT_NOT_PROVISIONED` en la
  primera lectura: el *schema* existe, las tablas existen, y el club no está dado de alta.

### 6.1 `seed-competition` — dar de alta lo que la ingesta necesita

La ingesta necesita una `Season` y una `Competition` **antes** de poder pasar (`D-16`: son su *entrada*).
El camino de verdad es pegar la URL en la ficha del equipo (`D-67`), y eso es **F10**; hasta entonces, esto:

```sh
swift run Run seed-competition -t atleti \
  -u "https://www.rffm.es/competicion/calendario?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549" \
  -c cadete -g masculino
```

```
→ consultando la federación…
  temporada:   2025/26  (temporada=21)
  competición: PRIMERA DIVISION AUTONOMICA CADETE
  grupo:       Grupo 1
  jornadas:    30
Competición lista: db679b16-f61d-42ec-b83f-3455fd67ccc6
```

Y te imprime el `ingest` y el `curl` listos para pegar.

**Es una herramienta, no contrato.** `POST /v1/competitions` existe en el *spec* y no es esto — aquél es el
camino del administrador, con su `preview` (`D-22`). Esto vive donde `provision-tenant`.

**Cuatro cosas que hace y un `INSERT` a mano no:**

- **Se pega la URL entera** (`D-22`), que es la mitigación contra el dígito mal tecleado. Un dígito cambiado
  **no da error**: sincroniza otro calendario (`D-84`).
- **Los rótulos los dice la federación** —etiqueta de temporada, nombre de la competición, grupo—, así que no
  te los inventas tú.
- **Pasa por el Dominio**, de modo que las fechas de la temporada se derivan de su etiqueta (§3.2) y las
  invariantes se comprueban.
- **Valida antes de escribir.** Coordenada inexistente o URL incompleta → falla **sin dejar fila**:

```
Error: FederationError.coordinateNotFound(detail: "la respuesta llegó sin calendario: competicion/grupo no existen")
Error: A la URL le falta el parámetro 'grupo': …
```

`--category` y `--gender` son obligatorios y no tienen valor por defecto: el género entra en la clave única de
cada equipo que la ingesta cree (`D-58`), así que equivocarlo no da un rótulo feo — da un 409 tres días
después. La federación no lo publica por competición, va dentro del nombre, y **inferirlo es el `/preview` de
F10**, no una herramienta.

Repetirlo es idempotente: si la competición ya existe, la reutiliza y te devuelve su id.

---

### 6.2 `ingest` — la pasada de la federación

El adaptador primario del módulo de ingesta (§2.3-b). **No es un endpoint** porque un job de sistema no tiene
usuario ni JWT que validar; el botón del backoffice existe además, y llama al mismo caso de uso (§4.5).

```sh
swift run Run ingest                        # todos los clubes, temporada vigente
swift run Run ingest -t atleti              # solo un club (o varios: -t "atleti,otro")
swift run Run ingest -c <uuid>              # solo una competición
swift run Run ingest -c "<uuid>,<uuid>"     # varias, en el orden pedido
swift run Run ingest --season <uuid>        # una temporada concreta, aunque no sea la vigente
swift run Run ingest --force                # ignora el antirrebote de 6 h
swift run Run ingest --min-interval-hours 24
```

**Sale con código distinto de cero si algo falló**, y esa es la única señal que ve un cron (`D-86`). Un fallo
**no detiene el recorrido**: la unidad de aislamiento es la competición, porque la pasada ya es atómica
(`D-83`) y ya deja constancia de su fallo (`D-85`). Para leerla:

```sh
curl "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<uuid>" | jq
```

**Lo que este comando no trae es la cadencia** (`D-87`). No hay temporizador dentro del proceso: quien lo
llama es un cron o una *scheduled machine*, y §5.6 pide **lunes** (horarios confirmados + resultado de la
jornada) más **sábado y domingo** (marcadores). De martes a viernes no hay nada nuevo que traer. Lo que el
comando sí trae es el **antirrebote**: una competición sincronizada con éxito hace menos de 6 h no se vuelve
a pedir, para que un disparo de más no repita trabajo. **No confundirlo con el tope semanal**, que es un
máximo y lo hace cumplir el calendario de disparos, no el código.

**Una competición que nunca se sincronizó entra siempre**, tenga el antirrebote el valor que tenga — si no,
la recién dada de alta esperaría para siempre.

> **Hoy no hay cron.** Mientras no exista, la ingesta corre a mano o por el `POST` del backoffice, y el tope
> semanal de §5.6 **no lo garantiza nada**. Está apuntado en el Plan §9 como deber del desarrollador.

---

## 7. El *spec* y el código generado

El contrato está en `Sources/APIContract/openapi.yaml` — **6.565 líneas, 83 operaciones en 45 rutas y las
21 entidades completas**
(F6 añadió la 21ª, `IngestionRun`, con su recurso). Es la
**fuente de verdad** (`D-25`): de él se generan los tipos y el `APIProtocol` que el servidor conforma
(`D-65`).

```sh
npx @redocly/cli lint Sources/APIContract/openapi.yaml    # validar
```

### 7.1 Añadir un endpoint

`APIProtocol` obliga a implementar **todas** las operaciones generadas, así que se genera **solo lo
implementado** (`D-69`). La lista está en `openapi-generator-config.yaml` y **es, literalmente, el alcance
entregado**:

```yaml
filter:
  operations:
    - getClub             # F0
    - updateClub          # F0
    - listIngestionRuns   # F6
    - triggerIngestion    # F6
```

Añades ahí la operación → compilas → **no compila**, porque falta su método → la implementas. Ese "no
compila" es la garantía entera de *design-first*.

> **Esa lista estuvo congelada en dos entradas de F0 a F5, y era información, no abandono.** F1 a F5
> entregaron dominio, persistencia, dos reglas puras y la pasada entera, y **nada de eso pasa por HTTP**: el
> adaptador primario de la ingesta es un `AsyncCommand` (§2.3-b). **F6 es la primera que la mueve**, con las
> dos operaciones que el módulo de ingesta sí necesita asomar (`D-88`). Las siguientes llegan en **F10**
> (`D-67`).
>
> **Comprobado al añadirlas**: poner las dos en el `filter` y compilar da
> `type 'APIHandler' does not conform to protocol 'APIProtocol'`, exactamente como promete `D-69`.

### 7.2 Dos cosas que sorprenden

**El generador emite tipos, no validación** (`D-65`). Ignora `pattern`, `minLength`, `readOnly`,
`minProperties`, `default`, `tags` y `security`. Esas reglas las hace cumplir el **Dominio** o el *handler*,
según la tabla de §5.5. Que algo esté declarado en el YAML **no** significa que se compruebe.

**Los errores se devuelven, no se lanzan.** El transporte generado atrapa lo que lance un *handler* y lo
convierte en **500** antes de que ningún middleware de Vapor lo vea. Así que dentro de un *handler* se
devuelve el caso del `Output` que toque. La consecuencia es buena aunque cueste descubrirla: **un código de
error que el *spec* no declara no se puede devolver**, porque no existe como caso del enum.

`ProblemMiddleware` sigue haciendo falta, pero para lo de **fuera** del transporte: resolución de tenant,
404 de ruta — y, desde F6, **lo que el transporte rechaza antes de llegar al *handler***. Ése es el tercer
caso y hay que conocerlo: un **parámetro obligatorio que falta** ni siquiera llega a tu código, así que
`GET /ingestion-runs` sin `competitionId` daba **500** aunque el *spec* declare 400. El middleware traduce
ahora el `ServerError` del runtime reutilizando su propia tabla de códigos. Lo que **no** se usa es el
`ErrorHandlingMiddleware` que trae `swift-openapi-runtime`: devuelve el código **sin cuerpo**, y §5.4 exige
`application/problem+json` en *todo* error del contrato.

### 7.3 El código generado, para curiosear

```sh
ls .build/plugins/outputs/backend/APIContract/destination/OpenAPIGenerator/GeneratedSources/
```

`Types.swift` (DTOs y `APIProtocol`) y `Server.swift` (registro de rutas). **No se editan**: se regeneran en
cada compilación.

---

## 8. Arquitectura, en una pantalla

```
Run ─► App ─┬─► HTTPAdapter ─┬─► APIContract   (generado del spec)
            │                └─► Application
            ├─► Persistence ────► Application
            ├─► Federation ─────► Application   (adaptadores RFFM / FCF)
            ├─► Tenancy
            └─► Application ────► Domain        (Domain no depende de NADA)
```

**`Federation` cuelga de `App` desde F6.** De F2 a F5 no colgaba, y no era un olvido: no tenía llamante, así
que lo mantenía en el grafo de *build* su *target* de tests. El llamante es
[el job de ingesta](#62-ingest-la-pasada-de-la-federación), y el `/preview` de F10 será el segundo.

**El grafo de `Package.swift` *es* la Regla de dependencia** (§2.2), no una convención de carpetas.
Compruébalo tú mismo:

```sh
swift package clean
echo "import Vapor" > Sources/Domain/Prueba.swift
swift build --target Domain      # error: no such module 'Vapor'
rm Sources/Domain/Prueba.swift
```

Ese error es el diseño defendiéndose solo.

> El `swift package clean` no sobra. Con `.build` caliente el compilador **también falla** —la regla se
> sostiene igual— pero con un mensaje distinto y desconcertante (`missing required module '_NumericsShims'`),
> porque se le filtran rutas de búsqueda de los *targets* hermanos ya compilados. El fallo es real en los dos
> casos; el mensaje limpio solo sale del build limpio.

### 8.1 Seguir una petición por las capas

`GET /v1/club`, de fuera adentro:

| # | Fichero | Qué hace |
|---|---|---|
| 1 | `Tenancy/TenantResolutionMiddleware.swift` | Saca el slug del `Host`, lo resuelve contra `public.tenants` y lo deja en un `@TaskLocal` |
| 2 | `HTTPAdapter/ClubHandler.swift` | Conforma el `APIProtocol` generado; monta el `ActorContext` |
| 3 | `Persistence/FluentTenantUnitOfWork.swift` | Abre la transacción y hace `SET LOCAL search_path` |
| 4 | `Application/GetClub.swift` | El caso de uso: depende del **puerto**, no de Fluent |
| 5 | `Persistence/FluentClubRepository.swift` | Implementa el puerto; mapea `Record` → Entidad |
| 6 | `HTTPAdapter/ClubHandler.swift` | Mapea Entidad → DTO generado |

Tres traducciones por entidad —dominio, persistencia, DTO— y ninguna se salta (`D-01`). Parece mucho para
leer un club; deja de parecerlo cuando la misma entidad la escriben el BFF **y** la ingesta con reglas
distintas (§2.1).

---

## 9. Cuando algo falla

| Síntoma | Causa casi segura |
|---|---|
| `Cannot find type 'Components' in scope` en Xcode | Los tipos del contrato no existen hasta que corre el plugin. Acepta el aviso de confianza y ⌘B. **La CLI es la fuente de verdad**, no el índice |
| `connection refused` al 5434 | `docker compose up -d db`. Los tests ya lo detectan y se omiten con ese aviso ([§5.2](#52-si-postgres-no-está-levantado)) |
| `400` con `TENANT_NOT_RESOLVED` | Llamaste a `localhost:8080` sin subdominio ni `X-Club` |
| `404` con `UNKNOWN_TENANT` | Falta `swift run Run provision-tenant <slug>` |
| `500` con `TENANT_NOT_PROVISIONED` | El *schema* existe pero `clubs` está vacío. Vuelve a lanzar `provision-tenant <slug> -f <federación>`: es idempotente y siembra la fila |
| Los tests petan con **señal 5** | Una `Application` destruida sin esperar a su cierre. Usa `TestEnvironment.withApp` |
| Los tests fallan **la primera vez** y pasan a la segunda | Algo de arranque compartido en carrera entre suites paralelas. Va en `TestEnvironment.bootstrap()`, que se ejecuta una sola vez por proceso |
| `PSQLError – Generic description…` | PostgresNIO esconde el detalle para no filtrarlo en logs. Se reexpone con `String(reflecting:)` — lo hacen `TestEnvironment` y, desde F6, el registro de pasadas (`D-85`), que si no guardaba una fila que no decía nada |
| `Address already in use` (errno 48) al hacer `serve` | Ya hay un `Run serve` vivo: `lsof -nP -iTCP:8080 -sTCP:LISTEN`, y `kill <PID>` |
| Docker no arranca | Suele ser disco lleno. Mira el log de `~/Library/Containers/com.docker.docker/Data/log/host/` |

```sh
LOG_LEVEL=debug swift run Run serve    # cada petición y cada SQL de Fluent
swift package clean && swift build     # cuando el build se comporta raro
```
