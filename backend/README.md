# Backend · Manual de uso

> Cómo levantar esto, hablar con ello a mano y ver lo que pasa por dentro.
> El **diseño** está en [`docs/`](../docs/); esto es el **manual de a bordo**.
>
> Convención: `§x` remite al [LLD-001](../docs/API_y_BBDD%20LLD-001.md) y `D-nn` a la
> [bitácora de decisiones](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md).

---

## 0. Qué hay montado ahora mismo

Del [Plan de desarrollo](../docs/Plan%20de%20desarrollo-001.md) están entregadas **F0**, **F1**, **F2** y
**F3**. **115 tests.**

| Operación HTTP | Estado |
|---|---|
| `GET /v1/club` | ✅ |
| `PATCH /v1/club` | ✅ |
| Todo lo demás del *spec* (~98 operaciones) | ⛔ No generado — ver §7 |

**Esa tabla no ha cambiado desde F0, y es lo esperado, no un descuido.** Ni F1, ni F2, ni F3 tienen superficie HTTP,
así que **la lista de operaciones no sirve para saber qué hay montado** — solo para saber qué se puede tocar
con `curl`. Lo que hay:

| Fase   | Qué añadió                                                                                                               | Cómo se **prueba**                                                                                                                     | Cómo se **mira**                                                          |
| ------ | ------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **F0** | El esqueleto que camina: las capas, el *spec* generado, la tenancy y las dos operaciones de arriba                       | `swift test --filter 'Club\|Tenancy\|Tenant'` → **29 tests** · necesita Docker                                                         | `curl` (§4)                                                               |
| **F1** | `Season` y `Competition` — dominio, puertos, tablas y migraciones. **Sin HTTP**: se siembran por repositorio             | `swift test --filter 'Season\|Competition'` → **41 tests** · necesita Docker                                                           | TablePlus sobre `tfm_test`, tras `KEEP_TEST_DATA=1 swift test` (§3, §5.2) |
| **F2** | El puerto `FederationClient` y el adaptador **RFFM del calendario**, contra volcados reales                              | `swift test --filter FederationTests` → **36 tests** · **sin Docker y sin red**                                                        | los volcados de `Tests/FederationTests/Fixtures/` y sus tests (§5.4)      |
| **F3** | La **política de *upsert*** (§3.7): `UpsertPolicy`, `Kickoff` y `MatchResult`. Funciones puras, **sin llamante todavía** | `swift test --filter 'UpsertPolicyTests\|KickoffTests\|KickoffMergeTests\|MatchResultTests'` → **13 tests** · **sin Docker y sin red** | sus tests, y solo sus tests (§5.4)                                        |

> **Las cifras son reales: cada filtro se ha ejecutado.** Y las comillas simples **no son decorativas** — sin
> ellas, `zsh` se come el `|` como una tubería.
>
> `--filter` es una **expresión regular sobre el nombre del test**, no un nombre de *target*, y eso tiene dos
> consecuencias que sorprenden. Una: arrastra tests sueltos de *suites* que no esperabas —el filtro de F0 se
> lleva un par de `SeasonPersistenceTests` porque llevan la palabra "tenant" en el nombre—. Y otra: hay que
> escribir **las dos** raíces, `Tenancy` y `Tenant`, porque son *suites* distintas; con solo una se pierden
> tests. Por lo mismo, `Season` coge también `SeasonLabel`, y `Federation` a secas se llevaría de propina el
> catálogo de federaciones, que vive en `DomainTests` (40 en vez de 36).
>
> **El filtro de F3 va por nombre de *suite* justo por eso**, y conviene saber qué pasa si se acorta: el
> `'Upsert|Kickoff|MatchResult'` que pide el cuerpo devuelve **16 en vez de 13**, porque `--filter` mira
> también el nombre de la **función** de Swift, no solo el rótulo del `@Test`. Se lleva dos del parser de F2
> (sus funciones se llaman `kickoff…`) y —lo importante— **uno de Postgres**: `save da de alta y luego
> actualiza la misma fila`, que por dentro se llama *upsert* y **necesita Docker**. Con el filtro de la
> tabla, F3 corre sin contenedor.
>
> **Son filtros para trabajar, no una partición del proyecto.** Para saber si algo está roto, `swift test` a
> secas.

**Tres de las cuatro fases no se prueban con `curl`, y no hay endpoint que tocar.** Es deliberado: el plan
construye la ingesta antes que su superficie de alta, que es **F10**. Para F1 lo que se mira es la **base de
datos**; para F2 y F3, los **tests** — que es lo que el plan pide expresamente (§9: *"los tests son la
especificación revisable, no el código"*).

> **Ni F2 ni F3 dejan rastro en la base de datos, y no es un fallo.** F2 es *"contra fixtures, **sin
> persistir nada**"* y F3 es *"unit puro, **cero I/O**"*: cuatro funciones y dos *Value Objects* que ni
> siquiera saben que existe Postgres. Si buscas sus efectos en TablePlus no vas a encontrar ninguno.
>
> **Y F3 todavía no tiene llamante**, que es lo que más despista al mirarlo: la ingesta que usará estas
> reglas —el *merge* de cada entidad— es **F5**, y la cadena que decide *qué fila* se fusiona con qué es
> **F4**. Hoy lo que las mantiene en el grafo de *build* son sus tests, igual que le pasa a `Federation`.

**La BD vive siempre en Docker.** Lo que cambia entre los dos modos de abajo es dónde corre **la API**.

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
| `HTTP_TRACE`                          | apagado     | `1` vuelca los cuerpos HTTP (§2.4). Solo en `.development`/`.testing`                  |
| `REQUIRE_DB`                          | apagado     | `1` hace que los tests de BD **fallen** en vez de omitirse (§5.2). `CI` la activa sola |
| `KEEP_TEST_DATA` | apagado | `1` conserva los *schemas* de test para inspeccionarlos (§5.2). **Solo la mira `swift test`**: en un `swift run Run …` no hace nada |

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

El equivalente en los tests es `HTTP_TRACE=1 swift test` (§5.3).

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
Ahí es donde corren los tests (§5.1), y por eso `swift test` no puede tocar nada de `tfm`. Merece su propia
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

curl -s http://celtic.localhost:8080/v1/club | jq '{slug, federation, federationProvidesScorers}'
```

```json
{ "slug": "celtic", "federation": "fcf", "federationProvidesScorers": false }
```

Las dos banderas cambiaron **sin que nadie las escribiera en la base de datos**: se derivan del catálogo de
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
swift test --filter 'UpsertPolicyTests|KickoffTests|KickoffMergeTests|MatchResultTests'
                                            # nivel 1 — F3: la política de upsert (§0)
swift test --no-parallel                    # en serie, útil al depurar
swift test --disable-xctest                 # sin el ruido de XCTest (ver abajo)
```

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

El paralelo no sobra —los 115 tests bajan de **2,8 s a 0,9 s**, y correrlos concurrentes **es** lo que destapó
las dos carreras de §5.1, que un orden fijo habría escondido—. Pero para leer, en serie.

> **`Test Suite 'ClubBackendPackageTests.xctest' … Executed 0 tests` no significa que haya XCTest.** No hay
> ni un `import XCTest` en el proyecto (`D-70`). Lo que pasa es que SwiftPM ejecuta **las dos** bibliotecas
> de test por defecto: la mitad de XCTest arranca, no encuentra nada y lo dice, y luego corre
> `swift-testing`. El nombre `.xctest` tampoco delata nada: es el **formato de empaquetado** de Apple, y
> todos los *targets* acaban en un único *bundle* con ese nombre usen el framework que usen.
> `--disable-xctest` lo quita.

### 5.1 Tus datos no se tocan

**Los tests corren contra una base distinta, `tfm_test`.** La crean solos la primera vez; no hay que hacer
nada. Tu trabajo manual vive en `tfm` y `swift test` no lo mira siquiera.

No siempre fue así, y el fallo merece contarse porque es del tipo que no avisa. Compartían base, y el plano
de control (`public.tenants`) es **una sola tabla para todas**. Un test que use el *slug* `madrid`
—perfectamente plausible como club real— borraba al terminar el registro del `madrid` que tuvieras dado de
alta: los datos seguían en su *schema*, intactos, pero **el club dejaba de ser alcanzable**, porque la fila
que lo enruta ya no estaba. Un `404` sobre datos que están ahí.

Aislar por prefijo de *slug* habría hecho la colisión improbable en vez de imposible, y una colisión
improbable que corrompe datos es **peor** que una frecuente: aparece el día menos oportuno y nadie la
relaciona con haber corrido los tests.

```sh
docker compose exec db psql -U tfm -d tfm_test -c '\dn'   # lo que dejan los tests
```

**Y la dejan limpia.** Cada test borra su *schema* al terminar, y `swift test` **barre al arrancar** lo que
hubiera quedado de una pasada anterior que no acabase bien:

| Cómo terminó la pasada | Qué queda |
|---|---|
| Todo verde | Limpio |
| Un `#expect` falla | Limpio — `#expect` **no lanza**, así que la limpieza final se ejecuta igual |
| Algo **lanza** | Queda su *schema*… hasta el siguiente `swift test`, que lo barre |

**Y si quieres inspeccionar lo que dejó un test que falla**, `KEEP_TEST_DATA=1` conserva los *schemas*:

```sh
KEEP_TEST_DATA=1 swift test --filter ClubUpdateTests
```

```
⚠︎ KEEP_TEST_DATA=1 · los schemas de test NO se borrarán al terminar.
  Míralos en la base `tfm_test`; la siguiente pasada los barre.
```

Luego los abres en TablePlus (base **`tfm_test`**) y consultas el estado exacto en que quedó la fila:

```sql
SELECT name, short_name, updated_at FROM e2e_patch1.clubs;
```

Es la alternativa barata al *breakpoint*, y muchas veces mejor: parar el depurador dentro de un test de
integración te deja mirando una transacción **que aún no ha confirmado**, así que lo que ves en la BD no es
lo que verá el siguiente paso.

**El barrido de arranque sigue corriendo con la bandera puesta**, a propósito: cada pasada te deja **su**
estado, no la acumulación de todas. Comprobado con dos pasadas seguidas — la segunda barre la primera.

El barrido va al arrancar y no en un `defer` por test, por el mismo motivo que el `SET LOCAL` de §6.2: **la
corrección no debe depender del camino de error** ni de que cada test nuevo se acuerde. Y garantiza algo más
fuerte que limpiar al salir — pizarra limpia **al entrar**.

Solo toca `tfm_test`, y no por el prefijo del *schema* sino porque **no abre `tfm` siquiera**. Comprobado
creando un `e2e_trampa` dentro de `tfm`: sigue ahí después de correr los tests.

**Los niveles 1 y 2 corren sin Docker**, y eso no es casualidad: es el dividendo de separar el Dominio de
Fluent (`D-01`). Son los que vas a ejecutar cien veces al día.

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
HTTP_TRACE=1  swift test --filter APITests --no-parallel   # los cuerpos HTTP
LOG_LEVEL=debug swift test --filter PersistenceTests       # el SQL que emite Fluent
```

```
┌─ → PATCH /v1/club
│  X-Club: patch2
│  content-type: application/json; charset=utf-8
│
│  {
│  }
├─ ← 400 Bad Request
│  Content-Type: application/problem+json; charset=utf-8
│
│  {
│    "code" : "EMPTY_PATCH",
│    "detail" : "minProperties: 1",
│    "status" : 400,
│    "title" : "El cuerpo debe traer al menos un campo",
│    "type" : "https://api.example.com/problems/empty-patch"
│  }
└─
```

Apagado por defecto, para no ensuciar CI. `--no-parallel` porque si no las trazas se entrelazan.

Es **el mismo middleware** que usa el servidor (§2.4), no un trazador aparte: lo que ves en un test es
exactamente lo que verías en `swift run Run serve`.

**`LOG_LEVEL` también funciona en los tests**, y enseña el SQL que emite Fluent — que en los niveles 3 y 4 es
justo lo que quieres ver:

```
debug codes.vapor.application: sql=SET LOCAL search_path TO "test_scope-a"
debug codes.vapor.application: sql=UPDATE "clubs" SET "name" = $1, …
```

Las dos se combinan: `LOG_LEVEL=debug HTTP_TRACE=1 swift test --no-parallel` da el cuerpo HTTP **y** las
consultas que provoca.

### 5.4 Cómo leer un test

Cada `@Test` cita en su nombre la sección del LLD o la decisión que lo exige. Es deliberado: **revisar una
fase es leer sus tests y comprobar que dicen lo que el diseño dice**, sin necesidad de leer el código.

```swift
@Test("un cuerpo vacío es 400: el spec lo declara pero no lo hace cumplir (D-65)")
```

Ese nombre afirma tres cosas comprobables contra la documentación: que la regla existe en el *spec*, que el
generador **no** la aplica, y que por tanto alguien tiene que aplicarla a mano.

**Dónde esto se vuelve imprescindible: F3.** Su política de *upsert* no tiene endpoint ni fila que mirar, así
que **los tests son literalmente el entregable**. Y hay dos que se leen de dos en dos, porque dicen lo
contrario con las mismas palabras:

```swift
@Test("sin marcador, la hora que desaparece devuelve el horario a provisional (D-30)")
@Test("con marcador, la hora que desaparece se ignora: es pérdida de dato (D-56)")
```

Es la tabla de `D-56` hecha código: **el mismo campo vacío significa dos cosas** según el partido se haya
jugado o no. Si al revisar solo se lee uno de los dos, la regla parece incoherente; leídos juntos, es lo que
impide que una sincronización borre la hora a la que se jugó un partido.

```sh
swift test --filter 'UpsertPolicyTests|KickoffTests|KickoffMergeTests|MatchResultTests' \
           --no-parallel --disable-xctest
```

Trece renglones, en orden de fichero, y cada uno con su `§x` o su `D-nn`. Eso **es** la revisión de la fase.

---

## 6. Los comandos administrativos

```sh
swift run Run migrate --yes                 # plano de control (public.tenants)

# Alta de club. Los cuatro pasos de §6.3, y es idempotente: repetirla no duplica.
swift run Run provision-tenant atleti -f rffm
swift run Run provision-tenant atleti -f rffm --name "Nombre Largo" --short-name "Corto"
swift run Run provision-tenant atleti -f rffm -s mi_schema     # schema propio
```

> `--name` **no tiene forma corta**: `-n` lo reserva ConsoleKit y, si se declara, aparece en el `--help`
> pero el valor acaba en `.unknownInput`. `-f` y `-s` sí funcionan.

```sh
swift run Run migrate-tenants               # aplica migraciones nuevas a TODOS los clubes
swift run Run migrate-tenants -t atleti     # solo a uno
swift run Run migrate-tenants --revert      # revierte
swift run Run --help
```

> **«TODOS los clubes» son los de `tfm`, y `tfm_test` no existe para estos comandos.** Es la confusión
> natural y conviene atajarla: `swift run Run …` trabaja **siempre** sobre tu base manual (§3.1), así que
> `migrate-tenants` recorre lo que haya en `tfm.public.tenants` — si solo diste de alta `atleti`, la
> respuesta correcta es `1 tenant(s) procesados`, y no falta ninguno.
>
> Los tenants de los tests viven en **otra base**, `tfm_test`, los crean los propios tests —**uno por test**,
> con el *slug* diciendo qué prueban: `season-uq-label`, `comp-cascade`, `scope-a`— y los borran al terminar.
> Ni `migrate-tenants` los ve, ni `KEEP_TEST_DATA=1` cambia nada al ejecutarlo, porque **esa variable solo la
> lee `swift test`**. Para verlos: `KEEP_TEST_DATA=1 swift test`, y luego TablePlus sobre `tfm_test`.

**El alta de un club es un comando, no un endpoint** (`D-23`, §6.3). Por eso `/club` no tiene `POST` ni
`DELETE`. Y por eso el comando hace **cuatro** cosas, no tres:

1. crea el *schema*,
2. registra el club en `public.tenants`,
3. le pasa el juego **completo** de migraciones,
4. **siembra la fila de `clubs`**, que es la raíz del tenant (§4.2).

El cuarto es el que se olvida, y su síntoma es un `500 TENANT_NOT_PROVISIONED` en la primera lectura: el
*schema* existe, las tablas existen, pero el club no está dado de alta. Si el alta de un club **es**
provisión, la provisión tiene que dejarlo dado de alta.

La URL del club se le entrega al firmar el contrato (§9.10).

> ⚠️ **`migrate-tenants` va siempre por conexión directa, nunca por un *pooler*** (§6.4). Se apoya en un
> `SET` de sesión, que detrás de un *pooler* en modo transacción deja de significar lo que parece. El precio
> de equivocarse no es leer mal: es **crear la tabla en el *schema* de otro club**, y eso no se deshace
> reintentando.

---

## 7. El *spec* y el código generado

El contrato está en `Sources/APIContract/openapi.yaml` — **6.184 líneas y las 20 entidades completas**. Es la
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
    - getClub
    - updateClub
```

Añades ahí la operación → compilas → **no compila**, porque falta su método → la implementas. Ese "no
compila" es la garantía entera de *design-first*.

> **Que esa lista siga teniendo dos entradas después de tres fases es información, no abandono.** F1 y F2
> entregaron dominio, persistencia y un adaptador de federación, y ninguna de las tres cosas pasa por HTTP.
> La primera operación nueva la traerá **F10** (`D-67`).

### 7.2 Dos cosas que sorprenden

**El generador emite tipos, no validación** (`D-65`). Ignora `pattern`, `minLength`, `readOnly`,
`minProperties`, `default`, `tags` y `security`. Esas reglas las hace cumplir el **Dominio** o el *handler*,
según la tabla de §5.5. Que algo esté declarado en el YAML **no** significa que se compruebe.

**Los errores se devuelven, no se lanzan.** El transporte generado atrapa lo que lance un *handler* y lo
convierte en **500** antes de que ningún middleware de Vapor lo vea. Así que dentro de un *handler* se
devuelve el caso del `Output` que toque. La consecuencia es buena aunque cueste descubrirla: **un código de
error que el *spec* no declara no se puede devolver**, porque no existe como caso del enum.

`ProblemMiddleware` sigue haciendo falta, pero para lo de **fuera** del transporte: resolución de tenant,
404 de ruta.

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
            ├─► Tenancy
            └─► Application ────► Domain        (Domain no depende de NADA)

            Federation ────────► Application    (adaptadores RFFM / FCF)
```

`Federation` **todavía no cuelga de `App`**: su primer llamante es el job de ingesta (F6) y el `/preview`
(F10). Hoy lo mantiene en el grafo de *build* su *target* de tests.

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
| `connection refused` al 5434 | `docker compose up -d db`. Los tests ya lo detectan y se omiten con ese aviso (§5.2) |
| `400` con `TENANT_NOT_RESOLVED` | Llamaste a `localhost:8080` sin subdominio ni `X-Club` |
| `404` con `UNKNOWN_TENANT` | Falta `swift run Run provision-tenant <slug>` |
| `500` con `TENANT_NOT_PROVISIONED` | El *schema* existe pero `clubs` está vacío. Vuelve a lanzar `provision-tenant <slug> -f <federación>`: es idempotente y siembra la fila |
| Los tests petan con **señal 5** | Una `Application` destruida sin esperar a su cierre. Usa `TestEnvironment.withApp` |
| Los tests fallan **la primera vez** y pasan a la segunda | Algo de arranque compartido en carrera entre suites paralelas. Va en `TestEnvironment.bootstrap()`, que se ejecuta una sola vez por proceso |
| `PSQLError – Generic description…` en un test | Es a propósito, para no filtrar datos en producción. `TestEnvironment` lo reexpone con `String(reflecting:)` |
| Docker no arranca | Suele ser disco lleno. Mira el log de `~/Library/Containers/com.docker.docker/Data/log/host/` |

```sh
LOG_LEVEL=debug swift run Run serve    # cada petición y cada SQL de Fluent
swift package clean && swift build     # cuando el build se comporta raro
```
