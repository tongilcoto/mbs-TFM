# Plan de desarrollo-001 · Cómo se construye este proyecto

- **Estado:** Vigente — gobierna el orden y el método de construcción del backend
- **Fecha:** 2026-08-24
- **Decisores:** desarrollador único (+ Claude Code)
- **Relacionado:** [HLD-001](./Project%20HLD-001.md) · [ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md) · [LLD-001](./API_y_BBDD%20LLD-001.md)

> **Alcance.** Este documento no dice *qué* se construye —eso es el LLD— sino **en qué orden y con qué
> método**. Es normativo para el ritmo de trabajo: qué se hace antes, qué nivel de test cubre cada cosa y
> cuándo se considera terminada una unidad de trabajo.
>
> **Dónde va cada cosa (D-26) sigue aplicando.** Si al ejecutar este plan se descarta una opción de diseño,
> la razón va al [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) como `D-nn`, no aquí. Este documento se limita al
> método.

---

## 1. Los dos bucles

El desarrollo se organiza en dos bucles anidados:

| Bucle | Unidad | Qué cierra el ciclo |
|-------|--------|---------------------|
| **Exterior · alcance** | una **fase**: una *rebanada vertical* — un caso de uso completo, de la invariante de dominio al dato en Postgres | comportamiento demostrable **y** documentación al día |
| **Interior · TDD** | una regla | rojo → verde → refactor |

El bucle exterior no cierra con el test en verde. Cierra cuando `AGENTS.md`, las cifras de §8.2 del LLD y —si
nació una decisión— la bitácora quedan al día. En un proyecto documentado antes que codificado, ese es el paso
que no se salta.

---

## 2. El bucle exterior: la regla

Hay **dos** ejes de avance, y confundirlos es lo que hace que la pregunta "¿horizontal o vertical?" no tenga
respuesta:

| | Eje de **alcance** | Eje de **profundidad** |
|---|---|---|
| Qué recorre | las 20 entidades de §3.2, los 3 módulos de §2.1 | Dominio → Aplicación → Adaptadores → Infraestructura |
| Avanzar en horizontal sería | muchas entidades, poca profundidad | una capa entera antes de empezar la siguiente |

**Avanzar horizontalmente en profundidad —todos los `struct` de dominio, luego todos los repositorios, luego
todos los *controllers*— queda descartado.** No por purismo: porque se llegaría a 20 entidades de dominio
escritas **sin haber ejecutado nunca** el plugin de generación contra este *spec* de 6.167 líneas, ni el
`search_path` contra un `Record` con FKs. §9.1 del LLD deja abierto *dónde vive físicamente el spec* y [D-65]
pide **remedir el build** con el plugin dentro: son preguntas que solo contesta el código, y no conviene
contestarlas con veinte entidades encima.

> **La regla, en una frase: horizontal solo cuando el compilador lo exija. Todo lo demás, vertical.**

**Cuidado con la palabra "fase".** Las unidades de trabajo se numeran `F0…F10` porque son **secuenciales**,
no porque sean etapas de una cascada. Una fase clásica de proyecto (*análisis → diseño → implementación →
pruebas*) es precisamente el corte **horizontal** que este apartado descarta. Aquí cada fase es una
**rebanada vertical**: atraviesa las cuatro capas y termina en algo que funciona.

Lo que el compilador exige es que los *targets* por capa existan antes de la primera fase — la Regla de
dependencia la impone él (§2.2), y no puede imponerla sobre carpetas que aún no hay. Eso es **andamiaje**, se
hace una vez, y es **F0**.

---

## 3. F0 · El esqueleto que camina — **entregada**

Lo más fino que atraviesa **todo** el stack: **`GET /v1/club`**. Recurso *singleton*, sin paginación, sin
ámbito, DTO mínimo — y `ClubRecord` es la migración nº 1 del orden de §4.6 de todas formas.

**Qué demuestra** (que es el motivo entero de que exista):

- Los *targets* SwiftPM por capa compilan, y violar la Regla de dependencia **falla al compilar**.
- El plugin de `swift-openapi-generator` digiere este *spec* y emite el `APIProtocol` → cierra §9.1.
- El `SET LOCAL search_path` del [spike](../spikes/tenancy/README.md) vive dentro de un repositorio de
  verdad (§6.2), no de un *closure* de prueba.
- `migrate-tenants` corre con un `Record` con FKs, no con la entidad suelta del spike.
- **Nueva medida de RAM y tiempo de *build* con el plugin dentro** → actualiza §8.2 del LLD, que hoy declara
  1,54 GiB y ~175 s como **suelo** de un spike sin generador.

**Qué trae aunque todavía no sirva de nada.** El **contexto de actor atravesando la frontera de los casos de
uso**. §7.4 lo pide con todas las letras: *"añadir después un parámetro a todas las firmas es el refactor caro
que esta decisión existe para evitar"*. En F0 solo llevará el club dentro. Da igual: la firma nace con él.

**Qué NO trae.** Ninguna regla de negocio, y ningún JWT: el tenant se resuelve por cabecera, como el spike.
Provisional y declarado como tal — §7.7 ya avisa de que **nada de §7 se ha ejecutado**.

### 3.1 Qué contestó

| Pregunta que estaba abierta | Respuesta |
|---|---|
| ¿Digiere el plugin este *spec* de 6.167 líneas? | **Sí.** Y §9.1 queda cerrada: el fichero vive en `backend/Sources/APIContract/` |
| ¿Impone el compilador la Regla de dependencia? | **Sí.** `import Vapor` desde `Domain` o `Application` → *no such module* |
| ¿Cuánto sube el *build* con el plugin dentro? | Pico `anon` **1,54 → 1,76 GiB** (+14 %), compilación ~175 → 185 s. Sigue por debajo del suelo de 2–4 GB del ADR |
| ¿Aguanta el `search_path` con un `Record` de verdad? | **Sí.** `clubs` y `_fluent_migrations` en cada *schema* de club; `tenants` solo en `public` |

**Y trajo dos decisiones que el plan no anticipaba**, las dos por la misma causa —que `APIProtocol` obliga a
implementar *todas* las operaciones generadas—: **[D-69]** (el *spec* se genera **filtrado**, y esa lista es
el alcance entregado) y, de paso, **[D-70]** (`swift-testing` en lugar de XCTest, que §8.1 daba por sentado).

### 3.2 Lo que se le añadió después, y por qué

F0 se cerró con `GET /v1/club`. Se le sumaron luego tres cosas, **a petición de aprender a operar el sistema
a mano**, y las tres resultaron ser deuda de F0 más que alcance nuevo:

| Añadido | Por qué no era opcional |
|---|---|
| `PATCH /v1/club` | F0 no tenía **ningún** camino de escritura, así que la plantilla que F1–F10 iban a copiar no existía ni estaba probada |
| `ProblemMiddleware` (RFC 7807) | §5.4 exige `application/problem+json` en **todo** error del contrato. Se servía el formato propio de Vapor, que un cliente generado del *spec* no sabe leer |
| `HTTP_TRACE=1` en los tests | Sin ver los cuerpos que cruzan la frontera no se puede revisar un adaptador primario leyendo tests, que es lo que §9 exige del desarrollador |

Y de implementar la escritura salió un **hueco del contrato**: `updateClub` declaraba 400/401/403 pero no
**422**, pese a que `UpdateClubRequest.name` lleva `minLength: 1`. Corregido en el *spec* — el detalle, en
[D-65].

**Tres hallazgos de montaje** que costaron tiempo y conviene no volver a descubrir: SwiftPM **descarta en
silencio** un *target* sin ningún `.swift` (los YAML son recursos), **omite del grafo de *build*** un *target*
que nadie consume, y `registerHandlers` monta **una sola instancia** del *handler* para todo el transporte —
así que el tenant no puede viajar en su `init` y va por `@TaskLocal`, con el middleware el **último** de la
cadena.

---

## 4. Por dónde se sigue: la ingesta

Terminada F0, el bloque de trabajo es el **módulo de ingesta** (§2.1, módulo 2). Tres razones, en este
orden:

1. **Es donde vive el riesgo técnico.** Dos proveedores no intercambiables, uno de ellos *scraping*, y una
   política de escritura ([D-56]) donde equivocarse **destruye datos que no vuelven**.
2. **Es la fuente de casi todo.** `Round`, `Match`, `OpponentClub`, `Team` rival, `StandingRow` y
   `LeagueScorer` salen de ahí, y el dominio manual (`Goal`, `Card`, `Appearance`) **cuelga de `Match`**. Sin
   ingesta no hay de qué colgarlo.
3. **Su adaptador primario es un `AsyncCommand`, no un Controller** (§2.3-b). Ejercita dominio, aplicación,
   persistencia y tenancy **sin HTTP, sin auth y sin JWT** — permite aplazar §7 honestamente, porque la
   ingesta es un actor de sistema.

**Lo que queda fuera de este bloque, y por qué.** El **acta** del partido. §5.6 y [D-57] dejan sin observar los
códigos de `tipo_gol` y `codigo_tipo_amonestacion`, y de ellos depende si el desglose de `Goal` y el tipo de
`Card` llegan del acta o siguen siendo entrada manual. Calendario, resultados, clasificación y goleadores no
dependen de eso.

### 4.1 Las fases

| # | Fase | Nivel de test dominante | Referencias |
|---|----------|-------------------------|-------------|
| **F0** ✅ | **El esqueleto que camina** (§3) — andamiaje, sin regla de negocio | *build* + integración | §2.2, §9.1, [D-65] |
| **F1** ✅ | `Season` + `Competition` — dominio y persistencia (detalle abajo). **Sin HTTP**: en los tests se siembran por repositorio | dominio + integración | §3.2, §4.6 |
| **F2** | Puerto `FederationClient` + adaptador **RFFM** del calendario, contra *fixtures*. **Sin persistir nada** | unit puro | §5.6, Anexo RFFM |
| **F3** | **Política de *upsert***: descriptivo / volátil / propiedad / emparejamiento | **unit puro, cero I/O** | §3.7, [D-56] |
| **F4** | **Cadena de emparejamiento**: 3 pasos para equipos y clubes, 2 para partidos | unit puro | §3.7, [D-31] |
| **F5** | Ingesta del calendario **end-to-end** → `Round`, `OpponentClub`, `Team`, `Match` | integración, Postgres real | §3.7, §4.4 |
| **F6** | El `AsyncCommand`, el recorrido por tenant y la cadencia semanal | integración | §2.3-b, §4.7, §5.6 |
| **F7** | `StandingRow` (RFFM histórica) + ***fallback* calculado** desde `Match` | unit + integración | [D-15], [D-55] |
| **F8** | `LeagueScorer` | integración | [D-09] |
| **F9** | Adaptador **FCF** (*scraping*, ~34 peticiones, capacidades del catálogo) | unit + integración | [D-17], [D-55], Anexo FCF |
| **F10** | `POST /teams/{id}/federation-link` **+ `/preview`**, y con ellos el alta en cascada de `Season` y `Competition` | E2E de contrato | [D-67], §2.3-c |

**F0 es la única horizontal, y no entrega funcionalidad**: está en la tabla para que la secuencia se lea
de un tirón, no porque sea una fase como las demás. Es la excepción de §2 — el andamiaje que el
compilador exige antes de la primera *rebanada vertical* de verdad.

**Dos observaciones sobre el orden de F1–F10, que no son casuales:**

- **F3 y F4 son las dos reglas más delicadas del diseño y se testean con cero infraestructura.** Ese es el
  dividendo de [D-01]: separar el Dominio de Fluent es lo que permite que la política de *upsert* se pruebe en
  milisegundos y sin contenedor.
- **F10 va al final aunque sea por donde entra el usuario.** Es el único punto que necesita el
  `FederationClient` ya construido y probado, porque `/preview` lo llama **en línea y dentro de la respuesta**
  (§2.3-c). Construirlo antes obligaría a falsearlo dos veces.

### 4.2 F1 · `Season` y `Competition` — **entregada**

La primera rebanada vertical de verdad, y la primera que **no toca HTTP**: dominio, puertos y persistencia.
Entrega **16 ficheros nuevos** y **35 tests** (22 de dominio, 13 de integración), con la batería completa en
**66**.

**Qué contestó.**

| Pregunta que estaba abierta | Respuesta |
|---|---|
| ¿Basta el `pattern` del *spec* para `SeasonLabel`? | **No.** No relaciona los dos años, y la ruta de ingesta no pasa por el contrato → [D-71] |
| ¿Qué era el `name` de `Competition` en §3.2? | Un resto: no existe en el *spec* ni en los anexos. Pasa a `federation_name`, **procedencia y no rótulo** → [D-72] |
| ¿`CASCADE` o `RESTRICT` bajo `Season`? | **`CASCADE`**, que es como §5.4 ejecuta la purga; el 409 del borrado normal queda en el caso de uso → [D-73] |
| ¿Aguanta el `search_path` con FKs entre dos tablas de dominio? | **Sí**, y la cascada también: las dos viven dentro del *schema* del club |

**Lo que no trae, y es deliberado.** **Ningún caso de uso** — el nivel 2 de la pirámide queda vacío en esta
fase, tal como anticipa la tabla de §4.1. F1 no tiene llamante: el alta por HTTP es F10, y escribir
`CreateSeason` ahora sería adivinar su forma. Tampoco **`delete` en los puertos**: con la FK en `CASCADE`
([D-73]), el borrado y su guarda de 409 **nacen juntos** o no nacen.

**Tres hallazgos de montaje**, los tres sobre la misma frontera y ninguno anticipado:

1. **El ámbito de tenant *es* una transacción, y eso se nota al escribir tests.** Lo que se escribe dentro de
   un `withRepositories` **no lo ve otra conexión** hasta que cierra, así que un `SELECT` en crudo para
   comprobar una columna no encuentra nada. El andamiaje (`TenantFixture`) obliga ahora a declarar dónde
   empieza y acaba cada ámbito, que es lo que hace que un test se parezca a una petición.
2. **Una violación de restricción aborta la transacción entera** (`sqlState 25P02`). Encadenar dos intentos
   que deben fallar dentro del mismo ámbito hace que el segundo pase **por el motivo equivocado** —"current
   transaction is aborted"— en vez de por su `UNIQUE`. Cada intento va en su propio ámbito.
3. **El `switch` exhaustivo sobre `DomainError` cobró su primera pieza.** Al añadir el caso de la guarda de
   [D-22], el compilador paró el *build* en `ProblemMiddleware` exigiendo su traducción a RFC 7807 — que
   además **no** es 422 sino **409**: el valor es válido, lo que no lo es es el momento.

**F1 se escribió *code-first*, no en TDD, y hay que decirlo.** El orden real fue implementación →
`swift build` → tests, en dominio y en persistencia. §5 pide lo contrario, y lo que ese desvío cuesta no es
ortodoxia: **un test que nunca ha estado en rojo es un test sin probar**. Escrito después, un test se redacta
contra la implementación que tiene delante, así que hereda sus errores en vez de cazarlos — y donde más
duele es justo en la pieza que sostiene [D-71], que existe para demostrar que el *Value Object* atrapa lo que
el `pattern` deja pasar.

**Lo que se hizo para recuperar la garantía perdida: comprobación de mutación.** Se rompió a propósito una
línea de implementación por regla y se exigió que cayeran los tests que dicen cubrirla. **Doce mutaciones,
doce detectadas**, y con especificidad —quitar solo la guarda de `gender` tumba el test de [D-58] y **no** el
de las coordenadas—:

| Se rompe | Lo caza |
|---|---|
| la coherencia de años de `SeasonLabel` | `rechaza lo que el pattern deja pasar` ([D-71]) |
| UTC → `Europe/Madrid` en las fechas derivadas | 4 tests, unidad e integración |
| la guarda de sincronización, invertida | los 3 de [D-22]/[D-58] |
| solo la guarda de `gender` | **solo** el de [D-58] |
| `CASCADE` → `NO ACTION` en la FK | `borrar la temporada se lleva sus competiciones` ([D-73]) |
| el `UNIQUE`, el `CHECK` de enumerado, el *scope* de archivadas | uno cada uno |

El arnés dio **un verde falso** en la primera pasada, y conviene que quede escrito porque volverá a morder:
en tests **parametrizados** `swift-testing` escribe `✘ Test "…" with 4 test cases failed`, así que buscar
`" failed"` pegado al nombre se come precisamente los casos con argumentos. La regla, para cualquier script
que lea esa salida: **fiarse del código de salida, no de raspar el nombre**.

**Para F2 se vuelve al bucle de §5**, y ahí el orden importa más que aquí: el adaptador RFFM es *nuestro*
código contra *sus* datos, y el reformateo de `"2025-2026"` a `"2025/26"` es exactamente el sitio donde un
test escrito después se limitaría a bendecir el error.

**Lo que se llevó por delante de F0**, sin planearlo: el `sqlValueList` de `FederationCode` se generalizó a
`CaseIterable where RawValue == String`, así que los tres enumerados nuevos de §3.3 derivan sus `CHECK` sin
copiar nada.


---

## 5. El bucle interior · TDD sobre esta arquitectura

Por fase, en este orden:

1. **Rojo en Dominio** — la invariante o el *Value Object*. Milisegundos, sin I/O (§8.1, nivel 1).
2. **Rojo en caso de uso** — orquestación con los puertos falseados: `FederationClient` en memoria, `Clock` y
   `UUIDProvider` fijos (§4.3). Sin I/O (nivel 2).
3. Solo cuando eso está verde: **integración** — Postgres 16 real en contenedor efímero (nivel 3).
4. **E2E de contrato** solo en fases con superficie HTTP, y pocas (nivel 4).

> **La disciplina que sostiene la pirámide de §8.1: cada regla se testea una sola vez, en el nivel más barato
> donde vive.** Si el `pattern` de `SeasonLabel` está en un *Value Object*, no se re-testea por HTTP.

**Un test de integración por adaptador, no por regla.** Lo que la integración prueba es el **mapeo** y la
**consulta** (`Record` ↔ Entidad, `search_path`, migraciones), no la lógica que ya cubrió el nivel 1.

**Los tests citan el diseño.** Cada test lleva en su nombre la referencia `§x` o `D-nn` que lo exige, de modo
que se pueda trazar del test a la línea del LLD que lo justifica. Es lo que permite revisar una fase
leyendo los tests en vez del código.

---

## 6. Decisiones técnicas de arranque

| Decisión | Elección | Nota |
|---|---|---|
| Toolchain | **Swift 6.3**, SwiftPM, un *target* por capa | lo que ya exige §2.2 |
| Framework de test | **`swift-testing` + `VaporTesting`** | **desvía de §8.1**, que dice XCTest/XCTVapor. Requiere `D-nn` y actualizar §8.1 |
| Modo de lenguaje | **Swift 6 en todos los *targets***, sin excepción | sin válvula de escape a `.v5`. Si Fluent pelea con la concurrencia estricta, se resuelve con aislamiento correcto (actores, `sending`), **no bajando el modo** |
| Concurrencia | *upcoming features* modernas activadas en todos los *targets* | **con una salvedad de servidor**: `defaultIsolation: MainActor` es recomendación **de apps**, no de un backend concurrente — no se adopta. La lista exacta se fija al montar F0 |
| Dónde vive el *spec* | **se mueve** a `Sources/…/openapi.yaml`, junto a `openapi-generator-config.yaml` | SwiftPM no referencia bien ficheros fuera del *target*, y los enlaces simbólicos son frágiles. **Cierra §9.1** y obliga a actualizar la ruta canónica en `AGENTS.md`, el LLD y el ADR |
| Base de datos de test | Postgres 16 efímero en Docker, reutilizando el `docker-compose.yml` del spike | §8.1: la integración no se prueba contra SQLite |

---

## 7. El puerto de federación: qué se hereda del código iOS y qué no

Existe una implementación previa de la ingesta, en Swift, en la app iOS
`rffm-agenda-ios` (fuera de este repositorio). **Tiene ya un `protocol FederationService` con las dos
federaciones detrás**, así que es material de partida real: de ahí salen los *hosts*, las rutas y los
parámetros verificados. Pero es una app de consulta con caché local, no un backend multi-tenant, y **cuatro
cosas no se portan tal cual.**

### 7.1 Lo que se hereda

- **La forma del puerto.** Un `protocol` con las dos implementaciones detrás y una **factoría por federación**
  es exactamente el catálogo en código de [D-17]. La estructura es correcta.
- **La bandera de capacidad `supportsRoundStandings`.** Es literalmente [D-55] y [D-29]
  (`ClubResponse.federationProvidesRoundStandings`), ya validada en producción por la app.
- **Las coordenadas verificadas** de los dos proveedores: rutas, parámetros y el hecho de que la FCF exige
  `User-Agent` de navegador y `X-Requested-With` en sus *endpoints* AJAX.
- **La lógica de cálculo de clasificación** (`StandingsComputer`), que es el *fallback* de [D-15].

### 7.2 Lo que NO se porta, y es donde está el trabajo de diseño

1. **La coordenada no es homogénea entre proveedores, y el puerto de la app lo esconde.** En su
   `CalendarParams`, `grupo` es un **código** en la RFFM (`grupo=…`) y una **URL completa** en la FCF
   (`…/resultats/2526/futbol-11/tercera-catalana/grup-8`). Nuestro modelo tiene dos columnas tipadas
   —`federation_competition_id` y `federation_group_id` (§3.7)— y hay que decidir cómo encaja la FCF en ellas.
   **Es una cuestión de diseño abierta y merece su `D-nn`**; se resuelve en F2, antes de escribir el segundo
   adaptador.
2. **El adaptador de la FCF guarda estado mutable entre llamadas.** Su `FCFContext` es una clase
   `@unchecked Sendable` que recuerda la temporada y la categoría de `fetchCompetitions` para usarlas en
   `fetchGroups`. En un backend concurrente y multi-tenant eso es una fuga entre peticiones esperando a
   ocurrir. **El puerto debe ser sin estado**: lo que la segunda llamada necesita, se le pasa.
3. **Su `Match` es un modelo de pantalla, no de ingesta.** Fecha y hora son `String`, y **no lleva ningún
   identificador de federación** — ni `codacta`, ni `codigo_equipo`. Le falta justo lo que sostiene la cadena
   de emparejamiento de §3.7 y el `federation_match_id` de [D-31]. El DTO de ingesta **se rediseña**, no se
   copia.
4. **Su `fetchStandings` de la FCF hace caché, cómputo y E/S de disco dentro del adaptador.** En esta
   arquitectura el *fallback* calculado ([D-15]) es un **servicio de dominio**: si vive en el adaptador, cada
   federación nueva lo reimplementa. La lógica se reutiliza; su ubicación, no.

### 7.3 Una corrección al resumen del LLD

El resumen de `AGENTS.md` y §5.6 dicen que *"la RFFM es JSON y la FCF es scraping de HTML"*. **El código
verificado matiza eso**, y el Anexo RFFM ya lo recoge bien (§F.7, §F.10): en la RFFM, `/api/standings`,
`/api/competitions` y `/api/groups` son **JSON puro**, pero el **calendario** es
`GET /competicion/calendario` → **HTML** del que hay que extraer el bloque
`<script id="__NEXT_DATA__" type="application/json">`.

O sea: **los dos adaptadores parsean HTML.** Lo que cambia es la *forma* —JSON embebido frente a recorrido del
DOM—, no la naturaleza. Conviene tenerlo presente al diseñar el puerto: la frontera "cliente HTTP" y la
frontera "parser" son **dos** responsabilidades en ambos proveedores, no una en uno y dos en el otro.

### 7.4 Lo que queda fuera del modelo

La app trae datos de **campo de juego** (dirección, localidad, GPS, código de campo) que §3.2 **no modela**:
`Match.venue` es un `String?` y nada más. No se incorpora ahora; queda anotado por si algún día la app móvil
de este proyecto quiere el mapa.

---

## 8. Ritmo de entrega y git

- **Se trabaja en rama**, nunca directamente sobre `main`.
- ***Commits* pequeños y por fase**, para que los diffs se puedan leer sin saber Swift.
- **El `push` es libre; el `merge` no.** Cuando una rama esté lista para integrarse, el trabajo se detiene y
  se avisa al desarrollador. La integración a `main` es siempre decisión humana.

---

## 9. Qué exige este plan del desarrollador

El desarrollador no conoce Swift ni Vapor, y las decisiones de esas dos tecnologías quedan delegadas. La
consecuencia práctica:

> **Los tests son la especificación revisable, no el código.**

Revisar una fase es leer sus tests y comprobar que dicen lo que el LLD dice. Por eso §5 exige que cada test
cite su `§x` o su `D-nn`: sin esa trazabilidad, la revisión no es posible y el control se pierde.

Lo que sí hace falta del desarrollador, y no puede delegarse:

- **Coordenadas reales de la RFFM** para F5 en adelante — una URL de calendario de la web de la federación,
  del tipo que el administrador pegaría en `/federation-link`. Hasta F4 bastan los *fixtures* de
  `docs/Federation APIs examples/`.
- Las **muestras de acta** que [D-57] necesita, si algún día se quiere el desglose de `Goal` automático.

---

## 10. Cuestiones abiertas de este plan

1. ~~**La representación de la coordenada de la FCF**~~ (§7.2, punto 1). **RESUELTA en F2 — por
   desaparición**, [D-74]. Al buscar una URL actual con la que fijarla se descubrió que **la FCF ha rehecho
   su web y ahora tiene API JSON**, con una coordenada de tres códigos numéricos que encaja uno a uno en las
   columnas del modelo. No hay nada que decidir ni que cambiar. La reobservación está en el
   [Anexo FCF §C.10](./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md); **§C.1–§C.9 de ese anexo quedan
   obsoletas**.

   > **Y deja dos deberes para F3, que es la fase siguiente.** [D-56] y §5.6 del LLD apoyan la regla de
   > escritura y la cadencia semanal en que *"la FCF borra la fecha y la hora al jugarse el partido"*; una
   > temporada entera ya jugada las conserva en **240 de 240**. [D-67] justifica su `202` con las *"~34
   > peticiones"* de la FCF, que ahora es **1**. Las dos decisiones pueden seguir siendo correctas por otros
   > motivos — pero **hay que rehacerles la justificación al implementarlas**, no darlas por buenas.
2. ~~La lista exacta de *upcoming features* de concurrencia.~~ **Resuelta en F0**: `ExistentialAny`,
   `MemberImportVisibility`, `InferIsolatedConformances` y `NonisolatedNonsendingByDefault`, en modo de
   lenguaje `.v6` y en **todos** los *targets*. **Fluent no peleó**: no hizo falta bajar el modo en ninguno,
   así que la válvula de escape que §6 descartaba tampoco se ha echado en falta. `MemberImportVisibility` se
   ganó el sitio de inmediato — cazó tres *imports* transitivos implícitos que habrían compilado en silencio.
3. **Cuánto vale la evidencia de `federation_name`.** [D-72] guarda el nombre literal de la competición para
   cerrar el `[I]` de [Anexo RFFM §F.14] —que la inferencia de género descansaba sobre **una** muestra—.
   **Parcialmente resuelta en F2**: el volcado de las 30 competiciones de una temporada dice que el marcador
   `FEMENINO` **no siempre va al final** (2 de 6) y que **no hay truncado** en ese endpoint, y aporta una
   segunda señal de contraste (`nombre_grupo_categoria`). La inferencia acierta más de lo que se temía; la
   columna sigue sin llenarse **hasta F10**, que es cuando la pregunta de fondo —cuánto vale como evidencia
   forense— tendrá datos de verdad.
4. **Orden de ataque tras la ingesta.** Este plan cubre hasta F10. Lo siguiente —dominio manual, roles, auth
   real— se planifica cuando la ingesta esté entregada, no antes.

[D-22]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-65]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-69]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-71]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-72]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-73]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-74]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-56]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-67]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
