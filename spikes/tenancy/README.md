# Spike · Multi-tenancy por *schema* (LLD §4.7, §6)

**Spike desechable.** No es el esqueleto del backend: aquí no hay capas (§2.2), ni dominio, ni
mapeo Dominio↔Persistencia. Es el mínimo código capaz de **confirmar o desmentir** tres
suposiciones que el LLD-001 da por buenas sin haberlas ejecutado nunca contra un Postgres real.

Su producto no son los tests en verde: son las **conclusiones de abajo** y los cambios de
redacción que implican en el LLD. Una vez incorporadas, este directorio puede borrarse.

---

## Veredicto

| # | Hipótesis del LLD | Veredicto |
|---|---|---|
| **H1** | §4.7 — Un `AsyncCommand` propio puede recorrer `public.tenants` y aplicar el juego completo de migraciones a cada *schema*, con progreso rastreado **por club**. | **Confirmada** |
| **H2** | §6.2 — Enrutar por `search_path` aísla de verdad a los clubes, también con peticiones concurrentes sobre el mismo *pool*. | **Confirmada** |
| **H3** | §6.4 — El *pooling* obliga a **resetear** el `search_path` al devolver la conexión. | **Confirmada como riesgo, pero la mitigación del LLD es la equivocada.** Ver H3 abajo: `SET LOCAL` en transacción hace innecesario el código de reseteo. |
| **H4** | Recomendación, punto 3 — Con un *pooler* en **modo transacción** delante, la estrategia A aguanta y la B no. Era **inferencia, no medición**. | **Confirmada, y peor de lo que se suponía.** Ver H4: la B no solo pierde el `search_path`, sino que hace que el **plano de control escriba DDL dentro del schema de un club**. |

18 tests, 0 fallos, contra Postgres 16 real (§8.1: la integración no se prueba contra SQLite):
11 contra Postgres directo y **7 contra PgBouncer en modo transacción**.

---

## Cómo correrlo

```bash
docker compose up -d          # Postgres efímero en :5433 + PgBouncer en :6432
swift test                    # los 18 tests + las líneas "· EVIDENCIA ·"
docker compose down -v        # -v borra el volumen: la BD es desechable a propósito
```

`PoolerTests` se **salta solo** si PgBouncer no responde, así que `swift test` sigue
funcionando con solo `docker compose up -d db`. Es una omisión silenciosa a propósito: las
conclusiones de H1–H3 no dependen del pooler.

Los comandos de tenancy, contra el mismo Postgres:

```bash
swift run Run provision-tenant atleti           # crea schema + registro + migra
swift run Run migrate-tenants                   # recorre todos los clubes
swift run Run migrate-tenants -t atleti         # solo uno
swift run Run migrate-tenants --revert
swift run Run serve
curl -H 'X-Club: atleti' localhost:8080/seasons
curl -H 'X-Club: atleti' localhost:8080/debug/search-path   # sonda
```

Coordenadas de la BD por entorno (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`),
para que CI pueda apuntar a su propio servicio sin tocar código. Las del pooler, aparte
(`POOLER_HOST`, `POOLER_PORT`), porque `PoolerTests` necesita **las dos a la vez**: el pooler es
el sistema bajo prueba y la conexión directa es el observador fuera de banda.

---

## H1 · Migraciones por tenant (§4.7) — **confirmada**

El `migrate` de serie de Fluent migra **una** base/*schema*. `MigrateTenantsCommand` hace lo que
§4.7 describe: lee `public.tenants` y, por cada club, construye un `Migrator` sobre el
`DatabaseID` de ese tenant y ejecuta el juego completo.

De las dos vías que §4.7 dejaba abiertas — *"abre conexión con `SET search_path` **o** registra
dinámicamente un `DatabaseID` por tenant, según lo que permita la API de configuración de Fluent"* —
**funciona la segunda**, y conviene fijarla en el LLD: `Databases.use` está protegido por lock y los
drivers se crean bajo demanda, así que **registrar pools en caliente es seguro**. Con
`SQLPostgresConfiguration.searchPath` el driver emite el `SET search_path` **al abrir cada
conexión**, de modo que el DDL sin cualificar (`CREATE TABLE "seasons"`) aterriza en el *schema*
del club — y con él la propia `_fluent_migrations`.

Lo verificado:

- `seasons` y `_fluent_migrations` existen **en cada *schema*** y **ninguna en `public`**.
- El progreso es **por club**: revertir `club_a` deja intacto a `club_b`.
- Un club nuevo recibe el **juego completo**, no solo la última pendiente.

Detalle de implementación que el LLD no menciona y debería: la diferencia de `space` entre los dos
tipos de tabla es lo que hace que todo esto encaje.

- `TenantRecord` (plano de control) lleva `static let space: String? = "public"` → Fluent emite
  `"public"."tenants"`, **cualificada**, así que la resolución de tenant **no depende del
  `search_path`**. Es lo que se quiere de una tabla de infraestructura.
- `SeasonRecord` (dominio) **no** lleva `space` → se emite `"seasons"` a secas y la resuelve el
  `search_path` de la conexión. Ése es el mecanismo bajo prueba.

## H2 · Aislamiento por `search_path` (§6.2) — **confirmada**

Las dos estrategias aíslan. La prueba no es que cada club vea sus filas, sino que **las dos
unicidades de §3.5 (`label`, `federation_season_id`) son por *schema***: el club B puede crear
`2024/25` con `federation_season_id = 21` cuando el club A ya tiene esa misma fila. Si el
aislamiento no existiera, el `POST` devolvería 409.

Y aguanta la concurrencia: **40 peticiones simultáneas** alternando club A y club B contra el
mismo *pool* compartido, ninguna cruzó filas. El `search_path` no se comporta como estado
compartido entre tareas.

También comprobado el riesgo fino: una **misma conexión física** (`pg_backend_pid()` idéntico)
sirviendo a dos clubes con el **mismo SQL** no cruza filas. Si hubiera caché de plan o de sentencia
preparada atada al OID de la tabla, el segundo cliente habría visto las filas del primero.

```
· EVIDENCIA · misma conexión (pid 7506) → club_a ["2023/24", "2024/25"], club_b ["2024/25"]
```

La resolución (§6.1) cierra por arriba: club desconocido → **404**, petición sin club → **400**.
En ninguno de los dos casos se llega a tocar un *schema*.

## H3 · *Pooling* (§6.4) — **el riesgo es real; la mitigación del LLD, no**

Hoy §6.2 dice: *"`SET search_path` al *schema* del club; **reseteo** al devolver la conexión al
*pool*"*. El spike ejecuta esa frase al pie de la letra, sin el reseteo, en un **control negativo**
(`naiveSetSearchPath`), y **la fuga aparece**:

```
· EVIDENCIA · A′ · search_path tras devolver la conexión (pid 7495): club_a
```

La conexión vuelve al *pool* contaminada con el *schema* del club anterior. El reseteo, por tanto,
**no es una precaución opcional**: sin él hay fuga entre tenants, y el LLD hace bien en pedirlo.

Pero hay una forma mejor que acordarse de resetear. `SET LOCAL search_path` **dentro de una
transacción** lo deshace Postgres solo al cerrarla:

```
· EVIDENCIA · A · search_path tras devolver la conexión (pid 7484): "$user", public
```

Misma conexión física, ningún código de reseteo, ninguna fuga. **La corrección no depende de que
alguien se acuerde de limpiar en el camino de error**, que es exactamente el tipo de invariante que
no debe confiarse a la disciplina del programador.

> El control negativo se queda **en la batería a propósito**: si algún día pasa a fallar, será
> porque el driver empezó a limpiar las conexiones, y entonces habrá que revisar esta conclusión.

## H4 · *Pooler* en modo transacción (§6.4) — **confirmada, y el fallo es peor de lo previsto**

Esta era la verificación pendiente. El README anterior decía, y con razón, que el punto 3 de
la recomendación —*"la A es compatible con pooling en modo transacción, la B no"*— era
**inferencia**: el spike hablaba con Postgres directo. Ahora hay un **PgBouncer 1.25.2 en modo
transacción** en el `docker-compose.yml` y `PoolerTests` corre **el mismo código** contra él.

Dos ajustes del pooler merecen explicación, porque sin ellos la medición no diría nada:

- **`default_pool_size = 1`.** Obliga a que todos los clientes multiplexen sobre **una**
  conexión de servidor. Con el default (20) la fuga aparecería o no según a qué conexión
  cayera cada petición, y un test de aislamiento probabilístico no vale para nada.
- **`server_reset_query_always = 0`** — que es el **default de PgBouncer**, no un ajuste
  nuestro. Significa que `DISCARD ALL` **solo** se ejecuta en `pool_mode = session`. En modo
  transacción PgBouncer **no limpia** la conexión entre clientes, y ése default es la causa
  última de todo lo que sigue.

Se descartó de camino una hipótesis alternativa: que PgBouncer rastreara `search_path` por
cliente y lo reinyectara (lo hace con `client_encoding`, `datestyle`, `timezone`,
`standard_conforming_strings` e `IntervalStyle`). **No lo hace.** `track_extra_parameters` solo
admite parámetros que PostgreSQL reporta al cliente, y Postgres 16 no reporta `search_path`.
Comprobado con dos sesiones `psql` intercaladas sobre la misma conexión de servidor:

```
sesion1 tras su SET   : pid=1203 sp=d_a
sesion2 (otra conn)   : pid=1203 sp=d_b
sesion1 DESPUES de s2 : pid=1203 sp=d_b     ← la sesión 1 perdió su search_path
```

### A · `SET LOCAL` en transacción — **aguanta**

La transacción es justamente la unidad que el pooler **no** parte: mientras está abierta, la
conexión de servidor queda fijada a ese cliente. Tres medidas:

```
· EVIDENCIA · A · vía pooler → club_a ["2023/24", "2024/25"], club_b ["2024/25"]
· EVIDENCIA · A · 40 peticiones concurrentes vía pooler (default_pool_size=1): sin cruces
· EVIDENCIA · A · search_path de la conexión de servidor tras la petición: "$user", public
```

Las 40 concurrentes son el caso que importa: **una** conexión de servidor para todas, y ni un
cruce. Y no deja rastro — Postgres revierte el `SET LOCAL` en el `COMMIT`, antes de que
PgBouncer devuelva la conexión a su pool.

### B · pool dedicado por tenant — **cruza datos entre clubes**

El `SET search_path` de la estrategia B es de **sesión**, y el driver lo emite **una sola vez,
al abrir la conexión** (`PostgresConnectionSource`; verificado en el log de Postgres: cinco
consultas seguidas sobre el mismo pool producen **un** `SET`). Detrás de un pooler en modo
transacción esa "sesión" es una ficción.

Tres consultas en fila, sin concurrencia y sin carreras:

```
· EVIDENCIA · B · vía pooler → A ["2023/24", "2024/25"] · B ["2019/20"] · A otra vez ["2019/20"]
```

La tercera línea es el fallo: **el club A leyendo las filas del club B**. Pasa porque en el
paso 3 la conexión de cliente de A ya estaba abierta, así que el driver no reemite su `SET`, y
la conexión de servidor lleva puesto el `search_path` que dejó B en el paso 2.

Y contamina hacia fuera:

```
· EVIDENCIA · B · search_path de la conexión de servidor tras la petición: pooler_club_a
```

### El que de verdad cierra la discusión

Leer mal las filas de otro club es grave pero se deshace. Esto no:

```
· EVIDENCIA · B · DDL del plano de control sin cualificar → en pooler_club_a: true · en public: false
```

El **plano de control** no fija ningún `search_path` —no tiene por qué: `public.tenants` va
cualificada—, así que hereda el que dejó el último club. Y `_fluent_migrations` es una tabla
**sin `space`**, igual que las de dominio: su DDL va sin cualificar. Resultado: una migración
del plano de control **crea su tabla dentro del schema de un club**. Un `CREATE TABLE` a
destiempo no se arregla reintentando.

El corolario operativo es que **`migrate-tenants` tampoco puede ir por el pooler**, por el mismo
motivo. En Supabase eso no es un problema: publica el puerto directo además del pooler, y las
migraciones deben apuntar al directo. `PoolerTests` no provoca ese fallo —hacerlo determinista
exigiría orquestar una carrera de DDL, y un DDL a destiempo deja la BD sucia—, comprueba el
mecanismo del que dependería:

```
· EVIDENCIA · B · migrador vía pooler: al abrir pooler_club_a → tras usarla otro cliente public
```

### Un hallazgo lateral que cambia el argumento

Sin fijar el *event loop*, `app.db(id)` reparte entre ellos y **cada uno abre su propia conexión
con su propio `SET`**. Al escribir estos tests eso hizo que la primera versión pareciera correcta:
la estrategia B "funcionaba" porque cada consulta caía en un event loop que acababa de reabrir.
Es decir: **el fallo de B no es reproducible**, depende de en qué event loop caiga la petición y
de si esa conexión se acaba de abrir. Un fallo de aislamiento intermitente es peor que uno
constante, y es una razón más para no querer la B — independiente de todas las anteriores.

Por eso `PoolerTests` fija el event loop, igual que ya hacía `TenancyTests` con
`pinnedDatabase()` y por la misma razón.

> Nota de metodología: el primer intento de estos tests falló acusando a `SET LOCAL` de una
> contaminación que en realidad había dejado un test **anterior** de la estrategia B. PgBouncer
> mantiene viva su conexión de servidor entre tests (`server_lifetime` es una hora). Está
> resuelto con un `SET search_path TO DEFAULT` en el `setUp`, y se cuenta aquí porque es el
> mismo fenómeno que la suite estudia, aplicado a la suite.

---

## Recomendación

**Estrategia A — `SET LOCAL search_path` dentro de transacción — como camino por defecto del tier
gestionado.** Razones, por orden:

1. **No hay nada que resetear**, luego no hay reseteo que olvidar (H3).
2. **Un solo *pool***, dimensionable, independiente del número de clubes. La estrategia B mantiene
   un *pool* por tenant: con 50 clubes son 50 *pools* de conexiones vivas contra el mismo Postgres,
   y el límite de conexiones de Supabase es un recurso escaso y compartido.
3. **Compatible con *pooling* en modo transacción** (PgBouncer/Supavisor), que es como Supabase
   sirve las conexiones de aplicación. Un `SET` de sesión, como el que hace la estrategia B al
   abrir conexión, **no** sobrevive a ese modo — la conexión de servidor que atiende la siguiente
   transacción puede ser otra. `SET LOCAL` sí, porque su ámbito *es* la transacción.
   **Medido** contra PgBouncer 1.25.2 en modo transacción (H4): la A aísla incluso con 40
   peticiones concurrentes sobre **una** conexión de servidor; la B cruza filas entre clubes en
   tres consultas seguidas. Este punto era el único que quedaba sin verificar y ya no lo está.
4. El coste es que **todo acceso de tenant queda dentro de una transacción**. Para escrituras ya lo
   estaría; para lecturas es una transacción de solo lectura, barata, y a cambio da consistencia de
   instantánea dentro de la petición.

**Estrategia B — *pool* dedicado por tenant — se queda para las migraciones**, que es donde encaja
bien: `migrate-tenants` es un proceso administrativo, de corta vida, un club cada vez, y necesita
que el DDL sin cualificar aterrice en el *schema* correcto desde el nacimiento de la conexión.

**Con una condición que H4 convierte en obligatoria: las migraciones van por la conexión
directa, nunca por el pooler.** Supabase publica los dos puertos; el de las migraciones es el
directo. Por el pooler, el `SET` de sesión en el que se apoya la B deja de valer y el DDL puede
aterrizar en el schema equivocado — un fallo que no se deshace reintentando.

Nótese que ambas se ejercitan hoy: `TenantPools` está registrado siempre, porque el migrador de
`setUp` lo usa. Por eso la línea `pools de tenant registrados: 2` aparece **también** bajo la
estrategia A — lo que distingue a B es que **las peticiones** pasen por esos *pools*.

El punto único por el que pasa todo acceso a datos de tenant es `Request.withTenantDB`. El resto del
código no sabe qué estrategia hay debajo, y eso es lo que hace que esta decisión sea reversible.

---

## Consecuencias para el LLD

1. **§6.2 — reescribir la mitigación.** Donde dice *"`SET search_path` …; reseteo al devolver la
   conexión al *pool*"*, decir: **`SET LOCAL search_path` dentro de la transacción de la petición**,
   que Postgres revierte al cerrarla y no requiere reseteo explícito. Añadir el control negativo
   como justificación.
2. **§4.7 — fijar la vía.** Sustituir el *"o registra dinámicamente un `DatabaseID` por tenant,
   según lo que permita la API de configuración de Fluent"* por la afirmación en firme: el registro
   dinámico funciona, es seguro en caliente, y es el mecanismo elegido **para las migraciones**.
   Mencionar `SQLPostgresConfiguration.searchPath` y el contraste de `space` entre `public.tenants`
   y las tablas de dominio.
3. **§6.4 — deja de ser un enunciado y pasa a tener contenido**, con las dos estrategias, sus costes
   de conexiones y la restricción del *pooling* en modo transacción, ya **medida** (H4). Añadir
   dos afirmaciones en firme: (a) el acceso de tenant va por el *pooler* con `SET LOCAL` en
   transacción; (b) **las migraciones van por la conexión directa**, porque el `SET` de sesión
   del que dependen no sobrevive al modo transacción y el precio de que falle es DDL en el
   schema equivocado.
4. **§9.3 (cuestión abierta) — se estrecha, no se cierra.** La idempotencia por club está resuelta
   (`_fluent_migrations` por *schema*, migrador completo en altas). Sigue abierto el fallo a mitad
   de recorrido y el paralelismo entre clubes.
5. **§3.5 — queda comprobado** que las unicidades por tenant se satisfacen con índices normales por
   *schema*: no hace falta nada especial.

---

## Lo que el spike **no** prueba

Enumerado para que nadie cite estas conclusiones más allá de su alcance:

- **Supavisor en concreto.** H4 se midió contra **PgBouncer 1.25.2**. Supavisor es otra
  implementación (Elixir), no un *fork*, y el resultado depende de detalles de comportamiento
  —qué parámetros de sesión rastrea, si limpia la conexión entre clientes— que no tienen por qué
  coincidir. La conclusión *"usa `SET LOCAL` en transacción"* es la conservadora y vale para los
  dos; la que **no** se puede extrapolar es la contraria, así que nadie debería leer H4 como
  permiso para usar la estrategia B detrás de Supavisor sin volver a medir.
- **Pooling en modo *session* o *statement*.** Solo se probó `transaction`, que es el modo en
  que Supabase sirve las conexiones de aplicación.
- **RLS (§7.4)** como capa extra. Aquí el aislamiento es solo por `search_path`.
- **Auth real (§7.1/§7.2)**: el club se resuelve por cabecera `X-Club` o subdominio, no por *claim*
  `club_id` de un JWT validado contra Supabase.
- **Escala**: 2–3 clubes y una entidad. Ni 50 clubes, ni las 15 migraciones en orden de dependencia
  de FK, ni el coste de N *pools*.
- **Tier dedicado (§6.3)**: un proyecto Supabase por club no necesita nada de esto y no se ha
  tocado.
- **Fallo a mitad del recorrido** de `migrate-tenants` (§9.3).
- **Las capas del §2.2**: no hay Dominio, ni Puertos, ni mapeo. El `SeasonDTO` va directo al
  `SeasonRecord`.

---

## Medidas

| Medida | Valor |
|---|---|
| Imagen final (multi-stage, `ubuntu:jammy` + binario estático) | **434 MB** |
| Suite completa contra Postgres real | 18 tests, 2,7 s (11 directos + 7 vía pooler) |
| RAM de compilación de Swift en el *builder* | **sin medir** — pendiente |

La RAM de compilación estaba entre lo que el `Dockerfile` se proponía medir (el ADR la da por
neutralizada y nadie la había comprobado). Requiere un `docker build --no-cache` observando
`docker stats`; no se llegó a hacer.

---

## Entorno de la ejecución

- Swift 6.3.2 (arm64, macOS) · modo de lenguaje v5
- Vapor 4.122.0 · Fluent 4.13.0 / FluentKit 1.57.0 · fluent-postgres-driver 2.12.0 · postgres-nio 1.33.1
- PostgreSQL 16.14 (`postgres:16-alpine`, contenedor efímero en `:5433`)
- PgBouncer 1.25.2 (`edoburu/pgbouncer`, `pool_mode = transaction`, `default_pool_size = 1`, en `:6432`)
- Docker 29.7.2

> Los tests de fuga fijan la base de datos a **un** *event loop*; con
> `maxConnectionsPerEventLoop: 1` (el valor por defecto del driver) eso significa **una** conexión
> física. Es la única forma de que `pg_backend_pid()` antes y después coincida y de que la prueba
> diga algo. Si esa suposición del driver cambia, los tests lo dicen: comparan el pid y fallan.
