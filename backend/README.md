# Backend · Manual de uso

> Cómo levantar esto, hablar con ello a mano y ver lo que pasa por dentro.
> El **diseño** está en [`docs/`](../docs/); esto es el **manual de a bordo**.
>
> Convención: `§x` remite al [LLD-001](../docs/API_y_BBDD%20LLD-001.md) y `D-nn` a la
> [bitácora de decisiones](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md).

---

## 0. Qué hay montado ahora mismo

Fase **F0** del [Plan de desarrollo](../docs/Plan%20de%20desarrollo-001.md): el esqueleto que camina.

| Operación | Estado |
|---|---|
| `GET /v1/club` | ✅ |
| `PATCH /v1/club` | ✅ |
| Todo lo demás del *spec* (~98 operaciones) | ⛔ No generado — ver §7 |

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

| Variable | Por defecto | Para qué |
|---|---|---|
| `DB_HOST` | `localhost` | `db` dentro de compose |
| `DB_PORT` | `5434` | `5432` dentro de compose |
| `DB_USER` / `DB_PASSWORD` / `DB_NAME` | `tfm` | |
| `DOMAIN_SUFFIX` | `localhost` | El sufijo que se recorta del `Host` (§6.1) |
| `LOG_LEVEL` | `info` | `debug` para ver cada petición y cada SQL |

```sh
LOG_LEVEL=debug swift run Run serve      # verás el SQL que emite Fluent
```

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
Ahí es donde corren los tests (§5.0), y por eso `swift test` no puede tocar nada de `tfm`. Merece su propia
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
swift test --no-parallel                    # en serie, útil al depurar
```

### 5.0 Tus datos no se tocan

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

**Los niveles 1 y 2 corren sin Docker**, y eso no es casualidad: es el dividendo de separar el Dominio de
Fluent (`D-01`). Son los que vas a ejecutar cien veces al día.

| Nivel | *Target* | Qué prueba | I/O |
|---|---|---|---|
| 1 | `DomainTests` | Invariantes y *Value Objects* | **cero** |
| 2 | `ApplicationTests` | Casos de uso con puertos **falseados** | **cero** |
| — | `TenancyTests` | Extracción del slug del `Host` (lógica pura) | **cero** |
| 3 | `PersistenceTests` | Mapeo, migraciones, `search_path` | Postgres real |
| 4 | `APITests` | Rutas, DTOs, códigos de error | Postgres real |

### 5.1 Ver los cuerpos que cruzan la frontera

```sh
HTTP_TRACE=1 swift test --filter APITests --no-parallel
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

### 5.2 Cómo leer un test

Cada `@Test` cita en su nombre la sección del LLD o la decisión que lo exige. Es deliberado: **revisar una
fase es leer sus tests y comprobar que dicen lo que el diseño dice**, sin necesidad de leer el código.

```swift
@Test("un cuerpo vacío es 400: el spec lo declara pero no lo hace cumplir (D-65)")
```

Ese nombre afirma tres cosas comprobables contra la documentación: que la regla existe en el *spec*, que el
generador **no** la aplica, y que por tanto alguien tiene que aplicarla a mano.

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

El contrato está en `Sources/APIContract/openapi.yaml` — **6.100 líneas y las 20 entidades completas**. Es la
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
```

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
| `connection refused` al 5434 | `docker compose up -d db` |
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
