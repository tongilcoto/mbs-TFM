# Multi-tenancy por schema: `search_path`, `SET LOCAL` y pooling

> Explicación de apoyo al spike `spikes/tenancy`. Repaso de cuatro afirmaciones sobre el spike
> (dos correctas, dos a corregir) más las dos dudas abiertas: RLS y Supavisor/PgBouncer.

Leído el README y el código del spike. Vas bien en dos de los cuatro puntos; dos hay que corregirlos. Te los repaso uno a uno.

## 1. Qué es el spike — ✅ casi

Es correcto, pero afínalo: no es "entender relaciones técnicas" en abstracto, es **falsar tres hipótesis concretas** que el LLD-001 daba por buenas sin haberlas ejecutado nunca (H1 migraciones por tenant, H2 aislamiento, H3 pooling). El producto no es el código: son las conclusiones y los cambios de redacción del LLD. Por eso el directorio es desechable.

## 2. `search_path` — ❌ esto está mal

`search_path` **no es** el nombre del club en el endpoint. Son dos cosas distintas que el spike encadena:

- **`search_path` es una variable de sesión de Postgres.** Es una lista ordenada de schemas. Cuando escribes SQL con el nombre de tabla *sin cualificar* (`SELECT * FROM seasons`), Postgres recorre esa lista para decidir a qué tabla física se refiere. Si `search_path = club_a`, `seasons` resuelve a `club_a.seasons`. Si vale `club_b`, la misma sentencia SQL, byte a byte, lee otra tabla. Ése es todo el mecanismo de aislamiento.
- **El nombre del club sí sale de la petición**, pero no de la ruta. En el spike sale de la cabecera `X-Club` o del **subdominio** (`atleti.api.myapp.com`) — mira `TenantResolutionMiddleware.slug(from:)` en `spikes/tenancy/Sources/App/TenantResolutionMiddleware.swift:26`. No de un segmento de path tipo `/club/seasons`.

La cadena completa es:

```
slug (X-Club / subdominio)
  → busca en public.tenants  ← tabla CUALIFICADA, no depende del search_path
  → obtiene schemaName
  → ese valor va al search_path de la conexión
  → SELECT ... FROM seasons  ← sin cualificar, lo resuelve el search_path
```

El detalle fino que hace que esto no se muerda la cola: `TenantRecord` lleva `space = "public"` (Fluent emite `"public"."tenants"`), así que **resolver el tenant nunca depende del `search_path`**. `SeasonRecord` no lleva `space`, y por eso sí depende. Está en el README, sección H1.

## 3. `SET LOCAL` — ✅ correcto, pero te falta el porqué

Sí: es SQL que el código Swift emite sobre la conexión (`TenantRouting.withSearchPath`, `TenantRouting.swift:47`). Lo importante no es que se ejecute desde Swift, sino el **`LOCAL`**:

- `SET search_path TO club_a` → persiste en la conexión. Cuando la conexión vuelve al pool, sigue contaminada. Ésa es la estrategia A′, el **control negativo** del spike, y la fuga se reproduce: `· EVIDENCIA · A′ · search_path tras devolver la conexión (pid 7495): club_a`.
- `SET LOCAL search_path TO club_a` **dentro de una transacción** → Postgres lo revierte solo al hacer COMMIT/ROLLBACK. La conexión vuelve limpia sin una sola línea de código de reseteo, y tampoco por el camino de error.

Ésa es la conclusión que cambia el LLD: §6.2 pedía "reseteo al devolver la conexión al pool", y el spike dice que la mitigación correcta es no tener nada que resetear.

## 4. Pool dedicado por tenant — ❌ no es eso

No es "cómo se inicializa la conexión a Supabase". Es la **estrategia B**, la alternativa a la A:

En Vapor registras bases de datos con un `DatabaseID`. La estrategia B registra **un `DatabaseID` distinto por club**, cada uno configurado con `SQLPostgresConfiguration(searchPath: [schema])` — ver `TenantPools` en `TenantRouting.swift:76`. Con eso, el driver emite el `SET search_path` **al abrir cada conexión**, y esa conexión ya nunca sirve a otro club. No hace falta transacción ni reseteo.

El coste es el que la descarta como camino por defecto: **un pool por club**. 50 clubes = 50 juegos de conexiones vivas contra el mismo Postgres, y las conexiones de Supabase son un recurso escaso. Por eso la recomendación es A para las peticiones, y B se queda **solo para las migraciones** (`migrate-tenants`): proceso administrativo, corto, un club cada vez, y necesita que el DDL sin cualificar aterrice en el schema correcto desde el nacimiento de la conexión.

Detalle que confunde al leer los logs: `TenantPools` está registrado siempre (el migrador de `setUp` lo usa), así que `pools de tenant registrados: 2` aparece también corriendo la estrategia A. Lo que distingue a B es que **las peticiones** pasen por esos pools.

---

## Tus dos dudas

### RLS (Row Level Security)

Es un **eje distinto**, no una pieza que falte de éste. RLS son políticas de Postgres a nivel de *fila*: activas `ROW LEVEL SECURITY` sobre una tabla y defines una política del tipo "solo ves las filas donde `club_id = current_setting('app.club')`". Es la alternativa clásica al schema-por-tenant: **una** tabla compartida con una columna discriminadora, en vez de N schemas.

Aquí el aislamiento es **solo** por `search_path`. RLS entraría como segunda capa (cinturón y tirantes): si un bug hace que el `search_path` apunte al schema equivocado, RLS todavía te para. Dos matices para cuando lo evalúes:

- Con schema-per-tenant y la API conectando con un rol privilegiado, RLS aporta poco: el rol de la API normalmente hace `BYPASSRLS` o es el owner.
- RLS pesa de verdad cuando el **cliente** habla directo con PostgREST (`/rest/v1` de Supabase) usando el JWT del usuario, sin pasar por tu API. Ahí es la única defensa que hay. Depende de si vuestra arquitectura permite ese camino o todo pasa por la API en Swift.

### Supavisor / PgBouncer

Corrección: **no son servicios alternativos a "la API de Postgres"**. Son *poolers* de conexiones — proxies que hablan el mismo protocolo de cable de Postgres. Desde el código Swift no cambia nada: apuntas `DB_HOST`/`DB_PORT` al pooler en lugar de a Postgres directo y el driver ni se entera. Existen porque Postgres tolera mal miles de conexiones y Supabase las raciona.

(Aparte, y esto sí que puede ser lo que mezclabas: en Supabase conviven **dos** vías de acceso. La conexión Postgres directa por protocolo de cable — la que usan Vapor/Fluent/postgres-nio y el spike — y **PostgREST**, la REST API autogenerada en `/rest/v1` que usa el cliente `supabase-swift`. Son cosas distintas; el spike va por la primera.)

Lo que sí importa del pooler, y es **la verificación pendiente más importante** del spike, es el **modo transacción**. En ese modo el pooler te asigna una conexión de servidor distinta para cada transacción. Consecuencia:

- Un `SET` de sesión — estrategia B, y también A′ — **no sobrevive**: la siguiente transacción puede caer en otra conexión física que no tiene ese `search_path`.
- `SET LOCAL` **sí** sobrevive, porque su ámbito *es* la transacción, que no se parte.

O sea: el punto 3 de la recomendación (A es compatible con pooling en modo transacción, B no) es **inferencia, no medición**. El spike corrió contra un Postgres directo, sin pooler delante. Está declarado como tal en "Lo que el spike no prueba", y hay que verificarlo antes de cerrar §6.4 del LLD.

---

Si quieres, el siguiente paso natural es meter un PgBouncer en modo transacción en el `docker-compose.yml` y volver a correr la misma batería: debería confirmar A y hacer caer B. Dime y lo montamos.

---

## Addendum · lo que salió al medirlo (21/08/2026)

Lo de arriba se queda tal cual se escribió. Esto es lo que pasó al montar PgBouncer de verdad
en el spike, porque cambia un matiz de la última sección.

**La inferencia era correcta, pero por poco.** Se comprobó primero si PgBouncer rastrea
`search_path` por cliente y lo reinyecta al enlazar (lo hace con `client_encoding`, `datestyle`,
`timezone`, `standard_conforming_strings` e `IntervalStyle`). **No lo hace**: `track_extra_parameters`
solo admite parámetros que PostgreSQL reporta al cliente, y Postgres 16 no reporta `search_path`.
Si lo hiciera, la estrategia B habría "funcionado" detrás del pooler y la conclusión habría sido
otra.

**El fallo de la estrategia B es peor de lo que decía el texto.** No es solo que un club lea las
filas de otro —que también, y en tres consultas seguidas, sin concurrencia—. Es que el **plano de
control**, que nunca fija `search_path` porque no lo necesita, hereda el que dejó el último club;
y como `_fluent_migrations` es una tabla **sin `space`**, su DDL va sin cualificar. Medido: una
migración del plano de control **crea su tabla dentro del schema de un club**. Leer mal se
reintenta; un `CREATE TABLE` en el sitio equivocado, no.

**Corolario operativo nuevo:** las migraciones (`migrate-tenants`) van por la **conexión directa**,
nunca por el pooler. Supabase publica los dos puertos precisamente por esto.

**Y un hallazgo lateral que importa para razonar sobre el riesgo:** sin fijar el *event loop*,
`app.db(id)` reparte entre ellos y cada uno abre su propia conexión con su propio `SET`. La
primera versión de los tests dio verde por eso y pareció desmentir la hipótesis. O sea que el
fallo de aislamiento de la estrategia B **no es reproducible**: depende de en qué event loop caiga
la petición. Un fallo intermitente es peor que uno constante.

**Límite que se mantiene:** todo esto se midió contra **PgBouncer 1.25.2**. Supavisor es otra
implementación (Elixir), no un fork. La conclusión conservadora —usar `SET LOCAL` en transacción—
vale para ambos; la contraria no se puede extrapolar.

Detalle completo en `spikes/tenancy/README.md`, sección **H4**.
