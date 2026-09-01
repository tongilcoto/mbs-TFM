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
| **F2** ✅ | Puerto `FederationClient` + adaptador **RFFM** del calendario, contra *fixtures*. **Sin persistir nada** (detalle en §4.3) | unit puro | §5.6, Anexo RFFM |
| **F3** ✅ | **Política de *upsert***: descriptivo / volátil / propiedad / emparejamiento (detalle en §4.5) | **unit puro, cero I/O** | §3.7, [D-56] |
| **F4** ✅ | **Cadena de emparejamiento**: 3 pasos para equipos y clubes, 2 para partidos (detalle en §4.6) | **unit puro, cero I/O** | §3.7, [D-31] |
| **F5** ✅ | Ingesta del calendario **end-to-end** → `Round`, `OpponentClub`, `Team`, `Match`. Y el **transporte HTTP real** con su ***canario*** (detalle en §4.7) | integración, Postgres real | §3.7, §4.4 |
| **F6** ✅ | El `AsyncCommand`, el recorrido por tenant y la cadencia semanal — **y los dos primeros endpoints desde F0** (detalle en §4.8) | integración + E2E de contrato | §2.3-b, §4.7, §5.6 |
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


### 4.3 F2 · El puerto de federación y el calendario de la RFFM — **entregada**

La primera rebanada que habla con el mundo exterior, y la primera **sin base de datos**: 11 ficheros de
código y **36 tests**, todos de nivel 1, con la batería completa en **102**. Corre en 70 ms y **sin Docker**.

**Qué contestó.**

| Pregunta que estaba abierta | Respuesta |
|---|---|
| ¿Cómo encaja la coordenada de la FCF en las dos columnas? (cuestión abierta nº 1) | **No encaja: ya no hace falta.** La FCF rehízo su web y su coordenada es ahora la de Madrid → [D-74] |
| ¿Describe bien el anexo el calendario de la RFFM? | **No del todo.** `jornada` es un rótulo y no un número; existe `(HB)`; el *host* del escudo lo publica la fuente → [Anexo RFFM §F.15] |
| ¿Basta el *fixture* para probar el adaptador entero? | **A medias.** Ver *"lo que no demuestra"*, abajo |
| ¿Dónde vive el reformateo de la etiqueta de temporada? | En el adaptador, **delegando** en `SeasonLabel` en vez de componer la cadena — que es lo que cierra [D-71] por los dos lados |

**Lo que trae, y por qué está partido así.** Tres piezas, no una, siguiendo §7.3 de este plan:

| Pieza | Responsabilidad | Se prueba… |
|---|---|---|
| `FederationTransport` | traer bytes | **no se prueba**: no hay implementación real hasta F5 |
| `RFFMCalendarParser` (+ `RFFMValue`, `NextDataExtractor`) | interpretar el texto | contra el volcado real, sin red |
| `RFFMFederationClient` | qué se pide y en qué orden | con un transporte espía |

Esa separación es lo que hace que **toda F2 sea nivel 1**. Si el parser viviera dentro del cliente HTTP —como
en la app heredada— probar el mapeo de un campo exigiría levantar un servidor.

**Lo que no trae, y es deliberado.**

- **El transporte HTTP de verdad.** Llega en **F5**, que es donde hay integración que lo ejercite. Escribirlo
  ahora sería código sin un test que lo toque, y además tendría que resolver cosas que F2 no sabe: validar el
  `2xx` explícitamente ([Anexo RFFM §F.7]), concurrencia y *backoff*.
- **El cableado en la raíz de composición.** `App` no conoce a `Federation` todavía porque **no hay llamante**:
  el job es F6 y el `/preview` es F10. Hoy lo consume el *target* de tests, que es lo que lo mantiene en el
  grafo de *build*.
- **Clasificación, goleadores y acta** (F7, F8, [D-57]): el puerto tiene **una** operación. Una firma inventada
  hoy se escribiría contra un anexo en vez de contra un volcado.
- **Nada de emparejar ni de escribir.** El adaptador devuelve lo que la fuente dijo, con sus huecos intactos —
  que es la materia prima sobre la que F3 y F4 deciden.

**Lo que el *fixture* NO demuestra, y hay que decirlo.** El volcado es de una temporada **sin arrancar**: los
306 partidos llegan sin marcador y sin hora, y las 34 fechas son el sábado por defecto. Es [Anexo RFFM §F.5]
al pie de la letra, pero **la rama de "partido jugado" no la ejercita ningún dato real de calendario** — las
únicas muestras con marcador son las 3 y 4 de §F.2, que están en el anexo y no en un volcado completo. La
consecuencia práctica: **F5 necesita un volcado de temporada en curso** para que la ingesta de resultados no
se estrene en producción.

**F2 sí se escribió en TDD**, al contrario que F1: los cuatro *suites* se escribieron antes que su
implementación y los cuatro se vieron fallar. Pero **fue test-first, no el bucle de §5 entero**, y conviene
decir en qué se quedó corto, que son tres cosas y ninguna es la misma:

1. **El rojo fue de compilación, no de aserción.** `cannot find 'RFFMValue' in scope`, cuatro veces. Eso compra
   la presión de diseño entera y **nada** de la garantía de que la aserción cace el fallo que dice cazar. Lo
   que faltó —un minuto de trabajo— es el **esqueleto**: la implementación falsa que compila y devuelve mal, de
   modo que el rojo traiga el valor delante. Está explicado en §5.1, que nació de aquí.
2. **La granularidad fue de *suite*, no de regla.** §5 pide *"una regla: rojo → verde → refactor"* y aquí
   fueron cuatro ciclos de suite entero → unidad entera. Es independiente de lo anterior, y además es lo que
   habría hecho útil el esqueleto: fingiendo doce respuestas a la vez, un esqueleto no dice nada.
3. **Las aserciones del parser salen de haber leído el volcado**, así que son *tests de caracterización*: fijan
   lo que la fuente hace hoy, no lo que debería hacer. Esto **no** es un desvío del método —es lo correcto
   contra un sistema de terceros, donde la alternativa sería inventarse la forma del JSON— y es justo por eso
   que el anexo fechado y la marca `[C]` son parte del método y no decoración.

Lo que tapó el hueco del punto 1 fue la comprobación de mutación, conseguida al final en vez de por el camino.
Funcionó; pero es la red, no el procedimiento.

**La comprobación de mutación encontró algo que los tests verdes no podían.** Once mutaciones, **once
detectadas** —y con especificidad: cambiar `codjornada` por `jornada` tumba el test de la numeración y ningún
otro—. Pero la interesante fue la **duodécima, que no se detectó**: romper el descarte del `?nova=1` de la
ruta del escudo no tumbó nada. No era un hueco de test: era **código defensivo que no defendía nada** —la
consulta va detrás de la extensión y nunca toca al segmento del id—. Se borró la línea.

> **Ése es un uso de la técnica que F1 no había visto.** Una mutación no detectada tiene **dos** lecturas, y
> conviene mirarlas en este orden: falta un test, **o sobra el código**. Asumir la primera es como se acaba
> escribiendo un test para justificar una línea inútil.

**Dos hallazgos de montaje**, los dos ya anunciados en `AGENTS.md` y los dos volvieron a morder:
`MemberImportVisibility` cazó un `import Foundation` que llegaba de gratis, y SwiftPM **descartó en silencio**
el *target* nuevo hasta que tuvo su primer `.swift` — el primer rojo de la fase fue un `no such module`.

**Lo que se llevó por delante sin planearlo:** dos tests de F0 (`GetClubTests`, `ClubEndpointTests`) afirmaban
que la FCF no publica goleadores. Era cierto cuando se escribieron; el saneamiento previo a esta fase lo
corrigió en el catálogo y estos dos se quedaron atrás hasta que la batería completa los cazó.


### 4.4 Lo que F5 tiene que traer además de la ingesta: el *canario*

*Anotado tras F2, a propuesta del desarrollador, para que no se pierda.*

`D-74` dejó escrita una lección — **revalidar el anexo de una federación antes de escribir su adaptador**— y
la dejó dependiendo de que alguien se acuerde. No basta: la FCF rehízo su web entera y estuvimos meses con un
anexo que describía un sitio inexistente, hasta que se descubrió **por casualidad**. F5 es la fase que puede
automatizar ese aviso, porque es donde nace el **transporte HTTP real** — hoy `FederationTransport` es un
protocolo sin implementación, así que antes de F5 no hay con qué hacer la petición.

**El canario no sustituye al volcado guardado: son dos preguntas distintas.**

| | Responde a | Determinista | Cuándo corre |
|---|---|---|---|
| **Volcado guardado** (F2) | *¿he roto yo el parser?* | sí | **siempre**, sin red, nivel 1 |
| **Canario** (F5) | *¿han cambiado ellos?* | **no, por naturaleza** | a demanda |

Fusionarlos las estropea las dos. El valor de la batería en verde es que un rojo significa *"mi cambio está
mal"*; con una petición de red dentro, un rojo puede significar que la federación está caída o que no hay
conexión. Y §4.1 fija que F2 es *unit puro*: el canario **vive fuera de la suite normal**, tras un
interruptor —`FEDERATION_LIVE=1`— y no entra en el camino de `swift test`.

#### La regla que decide si esto sirve de algo: **no es un `diff` de bytes**

**El calendario cambia todas las semanas, y por diseño.** Los horarios se fijan el domingo al cierre y los
marcadores entran el fin de semana ([Anexo RFFM §F.5]). Un canario que compare el fichero guardado contra una
captura nueva daría alarma **cada lunes** — y una bandera que grita siempre es peor que ninguna, porque a las
tres semanas nadie la mira.

Lo que se afirma es **estructural**, y la herramienta ya existe: **pasar nuestro parser por encima de la
respuesta viva y exigir que no falle.** Si el `__NEXT_DATA__` desaparece, si `codjornada` deja de ser un
número, si cambian los nombres de las 15 claves del partido o se va `calendar.host`, el parser revienta — y
ése **es** el aviso. Encima, unos pocos invariantes baratos: que haya jornadas, que los `codacta` sigan siendo
únicos, que la etiqueta de temporada siga teniendo la forma `AAAA-BBBB`.

En una frase: **el canario no comprueba que el fichero siga igual, sino que el parser siga tragando.**

#### Y tiene que distinguir "cambió la fuente" de "caducó la coordenada"

`temporada=22` cambia cada año, y `competicion`/`grupo` con ella ([Anexo RFFM §F.1]). Un canario cableado a
una coordenada concreta empieza a dar falsos positivos en cuanto pase la temporada. **Un 404 tiene que decir
una cosa y un parseo fallido otra**, o vuelve a ser la bandera que grita sin motivo.

#### Y a largo plazo la bandera de verdad es otra

El **job de ingesta de F6**, con su pasada semanal, detecta el cambio aunque nadie mire — y encima sobre las
coordenadas reales de los clubes, que no caducan porque las mantiene el administrador. El canario de F5 es la
versión **preventiva** de eso: lo que se ejecuta a mano **antes de abrir una fase de federación**, cuando
todavía no hay job ni tenants.


### 4.5 F3 · La política de *upsert* — **entregada**

La fase más pequeña en código y la más cara de equivocar: **3 ficheros** en el Dominio y **13 tests**, todos
de nivel 1, con la batería completa en **115**. Corre en **11 ms**, sin red y sin Docker.

| Fichero | Qué contiene |
|---|---|
| `Domain/UpsertPolicy.swift` | Las **cuatro clases de campo** de §3.7, una función pura cada una |
| `Domain/Kickoff.swift` | El VO de [D-30] y **la regla de [D-56]**: el único sitio de la fase donde escribir `nil` es lo correcto |
| `Domain/MatchResult.swift` | El VO que contesta *«¿se ha jugado?»*, del que cuelga esa desambiguación |

**Qué contestó.**

| Pregunta que estaba abierta | Respuesta |
|---|---|
| ¿Sigue en pie [D-56] sin su ejemplo estrella? | **Sí, y con mejor argumento.** No es que la fuente borre: es que **los dos errores no cuestan lo mismo** → [D-75] |
| ¿Basta *"solo al insertar"* para las claves de emparejamiento? | **No.** Condena a no recuperarse a la fila que nació sin clave. No sobrescribe, pero **rellena el hueco** → [D-76] |
| ¿Hacen falta banderas nuevas —`..._overridden_at`, un `jsonb` de *overrides*—? | **No.** [D-18] se sostiene: cuatro clases de campo, cuatro funciones, cero columnas |
| ¿Qué marcador desambigua el horario vacío? | **El fusionado, no el de la pasada.** Y la firma lo impone: `merging` recibe los dos y fusiona dentro |
| ¿Sigue siendo un **requisito** el tope semanal de §5.6? | **Sí, pero por [D-55]**, no por la fecha: lo irrecuperable es la clasificación de la FCF, no el horario |

**Lo que no trae, y es deliberado.** **Ninguna entidad de ingesta.** `Match`, `Round`, `OpponentClub` y
`Team` son de **F5**, y la cadena de emparejamiento es **F4**: lo que aquí se entrega son las cuatro reglas
que las dos van a usar, sin llamante todavía. Escribir hoy el *merge* de `Match` obligaría a inventar la
entidad **y** la cadena para poder probarlo, que es exactamente lo que §4.1 separó en tres fases.

**Lo que se llevó por delante sin planearlo:** `WallClockTime` se muda de `Application` a `Domain`. Nació con
el puerto de F2, que fue quien primero necesitó nombrar una hora suelta, pero es un VO con invariante y §4.1
los pone en el Dominio — lo forzó `Kickoff`, que lo lleva dentro. Un segundo tipo idéntico en la otra capa
era la alternativa, y es peor.

**Esta vez sí se hizo el bucle entero de §5.1**, que es lo que F2 se dejó por el camino: **doce ciclos**, uno
por regla, cada uno con su esqueleto y su **rojo de aserción**. Tres cosas que solo se ven haciéndolo así:

1. **La triangulación del campo volátil funcionó como está descrita.** El esqueleto de `volatile` fue
   `incoming` —pisar siempre, la implementación que [D-56] existe para prohibir—, y el primer test *(«la
   fuente gana cuando dice algo»)* lo dio por bueno. Lo tumbó el segundo, con el borrado a la vista:
   `Expectation failed: (merged → nil) == 3`. **Ese rojo es toda la fase en una línea.**
2. **El rojo cazó un error del propio test.** La constante del *fixture* se llamaba `sabado` y era un
   **viernes**: se vio porque el fallo imprime las dos fechas. Un test escrito después de la implementación
   habría pasado en verde con el nombre mintiendo.
3. **`MemberImportVisibility` volvió a morder** al mudar `WallClockTime`: el *target* de tests de federación
   lo usaba de gratis y dejó de compilar hasta declarar su `import Domain`. Es la tercera fase seguida en que
   esa bandera se gana el sitio.

**Comprobación de mutación: 11 mutaciones, 11 detectadas**, y con especificidad — romper *solo* el relleno
del hueco tumba *solo* el test de [D-76], y romper la desambiguación por marcador tumba *solo* el de
[D-56]. Las dos que más importan, porque son las dos líneas casi idénticas de las que avisaba §5.1:

| Se rompe | Lo caza |
|---|---|
| `volatile` → `incoming` (pisar siempre) | `lo que la fuente no dice no borra lo que hay` ([D-56]) |
| la hora se pisa **siempre** | `con marcador, la hora que desaparece se ignora` ([D-56]) |
| la hora **no se vacía nunca** | `sin marcador, la hora que desaparece devuelve el horario a provisional` ([D-30]) |
| `matching` → `incoming ?? existing` | `un codacta distinto no reescribe el que ya emparejaba` ([D-31]) |
| `matching` → `existing` (sin relleno) | `una fila que nació sin clave la recibe cuando la fuente la publica` ([D-76]) |
| `owned` → `incoming ?? existing` | `la ingesta no reasigna el club de un equipo` ([D-18]) |

**Y una deuda que esta fase salda, además de la suya.** [D-74] dejó apuntado que el `202` de [D-67] se
justificaba con las *"~34 peticiones"* de la FCF, que hoy es **1**. Revisado: el `202` **se mantiene**, con
dos argumentos nuevos —lo caro es lo que viene detrás del calendario (~240 partidos y **un escudo por club**
que descargar y subir a Storage, [D-19]), y encolar es lo que permite reintentar sin romper el enganche—.
Queda anotado dentro de [D-67], y con lo que F10 tiene que medir para cerrarlo del todo.


### 4.6 F4 · La cadena de emparejamiento — **entregada**

La otra mitad de §3.7, y la segunda fase seguida sin infraestructura: **4 ficheros** en el Dominio y **23
tests**, todos de nivel 1, con la batería completa en **138**. Corre en milisegundos, sin red y sin Docker.

| Fichero | Qué contiene |
|---|---|
| `Domain/MatchingChain.swift` | Las **tres cadenas** de §3.7 —club, equipo, partido—, sus tipos de candidato y los dos escalones compartidos |
| `Domain/MatchOutcome.swift` | El desenlace (`matched` / `ambiguous` / `unmatched`) y **por qué escalón se supo** |
| `Domain/NormalizedName.swift` | El VO del paso 2, con el sesgo de [D-80] |
| `Domain/Identifiers.swift` | `OpponentClubID`, `TeamID`, `RoundID`, `MatchID` |

**Qué contestó.**

| Pregunta que estaba abierta | Respuesta |
|---|---|
| ¿Basta *"nombre normalizado más categoría"* para emparejar un equipo? | **No.** Fusiona el "Infantil A" y el "Infantil B" del mismo club. El paso 2 compara la **clave única entera** → [D-77] |
| El *"si no"* que encadena los pasos, ¿es *"si no viene el dato"*? | **No, y con la otra lectura [D-76] no ocurre jamás**: es *"si el escalón anterior no resolvió"* → [D-78] |
| ¿Y si el paso inexacto encuentra dos? | Ni se elige ni se crea: **se reporta**. Y la *"marca para revisión"* de §3.7 **no es una columna** → [D-79] |
| ¿Dónde vive la cadena? | En el **Dominio**, con `UpsertPolicy`. El comentario de `FederationClient` que la situaba en Aplicación queda corregido |
| ¿Hace falta una guarda para que la ingesta no enganche un equipo propio? | **No: hace falta un tipo.** `TeamOwnership` es un `enum` y el caso `.own` no lleva nombre de club, así que el paso 2 no puede alcanzarlo ([D-66], [D-67], [D-76]) |

**La decisión de diseño que más rinde, y se puede copiar.** Los candidatos son tipos propios y no las
entidades de F5, con **solo las claves de emparejamiento** dentro. Eso convierte tres reglas de §3.7 de
disciplina en estructura: `MatchCandidate` no tiene fecha, así que *"ni la fecha ni la hora entran nunca en la
cadena"* **no se puede desobedecer**; `TeamOwnership.own` no tiene nombre de club, así que el enganche por la
puerta de atrás de [D-76] **no se puede escribir**. El precio es un mapeo trivial en F5.

**Tres cosas que solo se ven haciendo el bucle de §5.1:**

1. **El rojo cazó un fixture equivocado, otra vez, y el hallazgo era de otro fichero.** El test de ambigüedad
   se escribió con `"C.D. Fútbol Tres Cantos"` y `"CD Futbol Tres Cantos"` dando por hecho que colisionaban.
   No colisionaban: la normalización trataba la puntuación como **separador**, así que `"C.D."` daba `"c d"` y
   `"CD"` daba `"cd"`. Es decir, **el administrador escribiendo las siglas sin puntos rompía el
   emparejamiento** — justo lo que ese VO existe para impedir. Salió al preparar un test de la cadena, no del
   VO → [D-80].
2. **Dos tests llegaron en verde y no se disimuló.** Los de la frontera de [D-66]/[D-67] pasan sin haber
   estado rojos, porque los sostiene un `enum` y no una línea. Se verificaron con una **mutación de
   modelado** —abrir el paso 2 a los equipos propios— en vez de fingir un ciclo.
3. **La comprobación de mutación encontró dos huecos de cobertura antes de correr.** Al listar qué línea
   rompería cada test se vio que **nada** distinguía dos partidos que solo difieren en la jornada
   (eliminatoria a doble vuelta, [D-12]) ni el local del visitante. Los dos ciclos que faltaban se hicieron
   con rojo real, rompiendo la implementación a propósito para escribirlos.

**Comprobación de mutación: 16 mutaciones, 16 detectadas**, y con especificidad — quitar *solo* la letra del
paso 2 tumba *solo* el test de [D-77], y lo mismo el género, la modalidad y la categoría por separado:

| Se rompe | Lo caza |
|---|---|
| el paso 1 compara los dos opcionales (`nil` casa con `nil`) | `no tener clave no es tener la misma clave` (y 12 más) |
| el paso 2 no descarta la clave que contradice | `una clave distinta descarta al candidato aunque el nombre case` ([D-78]) |
| el *"si no"* leído como *"si no viene la clave"* | `la clave que no encuentra a nadie cae al paso 2` ([D-78]) |
| la ambigüedad se resuelve con el primero | `dos candidatos por nombre no se resuelven: se reportan` ([D-79]) |
| el paso 2 sin la letra / el género / la modalidad / la categoría | **un test cada uno**, y solo ése |
| el paso 2 alcanza a los equipos propios sin enganchar | `un equipo propio sin enganchar no lo engancha la ingesta` ([D-76]) |
| emparejar solo por coordenadas (la alternativa que [D-31] descartó) | `el partido reubicado en otra jornada no se duplica` |
| las coordenadas sin la jornada | `los dos partidos de una eliminatoria no son el mismo` ([D-12]) |
| local y visitante cruzados | 5 tests, incluido `el local y el visitante no son intercambiables` |
| la normalización no pliega acentos / caja, o la puntuación separa | 2, 6 y 2 tests respectivamente |

**Y una lección de arnés que hay que apuntar junto a la de F1.** El *script* de mutación decide por el
**código de salida**, no raspando nombres —eso ya lo enseñó F1—, pero esta vez falló por otro sitio: una
mutación **no llegó a aplicarse** porque su patrón de texto no casaba, y el resultado se leyó como
*"sobrevive"* cuando en realidad era *"no se probó"*. Un arnés de mutación tiene que distinguir esos dos
casos explícitamente, o miente en la dirección tranquilizadora.

**Lo que no trae, y es deliberado.** **Ningún llamante**, igual que F3: la cadena se prueba con listas de
candidatos pasadas por argumento, y quien las cargue del repositorio será F5. Escribir hoy esa consulta
obligaría a inventar las entidades **y** los repositorios de `Team`, `OpponentClub` y `Match`, que es lo que
§4.1 separó en dos fases.


### 4.7 F5 · La ingesta del calendario de punta a punta — **entregada**

La fase que **junta** lo que F3 y F4 entregaron sueltos —la cadena decide qué fila es, `UpsertPolicy` decide
qué se le escribe— y la primera que toca las cuatro capas a la vez: **23 ficheros de código** y **79 tests**,
con la batería completa en **217**. Corre en 4 s con Postgres; los de dominio y aplicación, en 30 ms sin él.

| Bloque | Qué entrega |
|---|---|
| Dominio | `Round`, `OpponentClub`, `Team`, `Match`, `MatchStatus`, `IngestionRun` — cada entidad con su `merging` campo a campo por las cuatro clases de §3.7 |
| Aplicación | `IngestCalendar` + `CalendarPass`, los puertos `Clock` y `UUIDProvider`, y cinco repositorios nuevos |
| Persistencia | Cinco tablas con sus migraciones en el orden de FK de §4.6, y la clave de `Team` con `NULLS NOT DISTINCT` |
| Federación | El **transporte HTTP real** y el ***canario*** |

**Qué contestó.**

| Pregunta que estaba abierta | Respuesta |
|---|---|
| ¿De dónde salen `Round.start_date` y `end_date`, que la fuente no publica? | Del **mínimo y el máximo de las fechas de sus partidos**. Medido: en la temporada jugada da sábado→domingo en 26 de 30 jornadas → [D-81] |
| ¿Cómo se genera el `slug` de `OpponentClub`? | **Mecánicamente**, sin lista de formas jurídicas. Y el desempate de colisiones vive en el caso de uso, no en el VO → [D-82] |
| ¿Dónde están las fronteras transaccionales de una pasada? | **Tres ámbitos, y la red fuera de los tres.** La decisión vive en el caso de uso, no en el adaptador → [D-83] |
| ¿Una coordenada caducada falla? | **No.** Devuelve `200` y el calendario de **otra competición** → [D-84] |
| ¿Dónde queda constancia de una pasada? | En una **tabla**, y escrita **fuera** de la transacción de la pasada → [D-85] |
| ¿Sirve el volcado que había para la rama de "partido jugado"? | No, y ya no hace falta: el volcado de temporada jugada cierra el deber de §4.3 |

**El hallazgo de la fase, y no se buscaba.** El volcado de temporada jugada se capturó con **la misma
coordenada** que el anterior cambiando solo `temporada`, y devolvió **otra competición**: PREFERENTE
AFICIONADO con `temporada=22`, PRIMERA DIVISION AUTONOMICA CADETE con `temporada=21`. **La RFFM reutiliza los
códigos de competición y grupo entre temporadas.**

Eso confirmó con dato real una regla que solo estaba razonada (§3.5: `Competition` se identifica por
`season_id` + `federation_group_id`) y **rompió una premisa de §4.4 de este plan**. Al medirlo entero, la RFFM
**no da 404 nunca** en la ruta del calendario: dice que no de tres maneras y las tres son `200`. Sin guarda, la
pasada habría escrito un calendario cadete dentro de una competición senior, con los equipos heredando de ella
la categoría equivocada ([D-07]) y sin `PATCH` con el que arreglarlo después. La evidencia para detectarlo ya
existía —`federation_name`, [D-72]— y **ésta es la primera vez que se cobra**.

> **La lección es la de [D-74] otra vez, y conviene contarla como se dio: no se descubrió revisando el anexo,
> sino capturando un volcado que se pedía para otra cosa.** Una premisa sobre un sistema de terceros no se
> hereda: se mide, y se mide cuando se va a usar.

**Lo que el nivel 3 cazó y el nivel 2 no podía.** Tres veces, y las tres por lo mismo: **los dobles no tienen
restricciones**.

1. §3.5 declara `OpponentClub(name)` **único**, y la cadena sí produce el intento de crear un segundo club con
   el mismo nombre —descarta al candidato cuya clave contradice y cae al paso 3—. Sin guarda, una coincidencia
   de nombre reventaría el `UNIQUE` y con él **la pasada de toda la competición**.
2. PostgresKit mapea un array de Swift a un **array de Postgres**, así que `[IngestionSkip]` se enlazaba como
   `jsonb[]` contra una columna `jsonb`.
3. La clave única de `Team`: con un `UNIQUE` normal entraron **dos "Cadete A" propios idénticos**, que es
   literalmente la trampa de la que §3.5 avisa. Ése sí se escribió como ciclo con esqueleto, y el rojo salió
   contra Postgres.

**Lo que no trae, y es deliberado.**

- **Ningún endpoint.** La superficie HTTP sigue siendo la de F0: el `filter` del generador no cambia. El
  adaptador primario de la ingesta es el `AsyncCommand` de **F6**, y el `GET` del registro de pasadas va con
  él —hoy la única forma de generar una fila es un test—.
- **El escudo** (`crest_key`, [D-19]): exige un adaptador de Supabase Storage que §4.1 no pone en esta fase.
  La columna existe y su regla de *upsert* está decidida; el valor se queda nulo.
- **El cableado de `Federation` en `App`**: sigue sin llamante hasta F6.

**El bucle de §5.1, entero: 35 ciclos**, cada uno con su esqueleto y su rojo de aserción. Cuatro cosas que
solo se ven haciéndolo así:

1. **El rojo cazó un error del test, por tercera fase seguida.** La aserción de la ambigüedad daba por hecho
   que no se crearía ningún club, olvidando que el equipo **local** sí se resuelve. Escrito después, habría
   pasado en verde diciendo algo falso.
2. **Un esqueleto no se pudo escribir, y eso también es información.** `Round.merging` con "pisar siempre"
   exigiría inventarse una fecha centinela, porque las dos columnas son `NOT NULL`: el fallo **no es
   representable**. Es el mismo argumento estructural de `TeamOwnership.own` en F4, y se dijo en el test en vez
   de fingir un ciclo.
3. **Dos tests llegaron en verde y se dejaron escritos**: la idempotencia de la segunda pasada y el equipo
   propio ya enganchado. Los sostiene la **composición** —la cadena más la política— y el **orden**, no una
   línea; se verificaron con mutación en vez de con un rojo fingido.
4. **El orden equipo→club es una regla que ningún tipo protege.** Resolver el club primero crearía un
   `OpponentClub` con el nombre de nuestro propio club en cuanto la pasada se cruce con nuestro equipo — que es
   lo que hace en todas las jornadas. Tiene test propio por eso.

**Comprobación de mutación: 35 mutaciones, 34 cazadas y 1 equivalente**, con especificidad — romper *solo* la
letra del slug tumba *solo* los tres de [D-82], y romper la guarda de la competición tumba *solo* los dos de
[D-84].

| Se rompe | Lo caza |
|---|---|
| el rango de la jornada es el primero, no mín/máx | `el rango de la jornada es el mínimo y el máximo` ([D-81]) |
| el nombre del club es volátil y no descriptivo | `la corrección del nombre sobrevive a la pasada siguiente` |
| la ingesta reasigna `opponent_club_id` | los 2 de [D-20] |
| el estado sale del marcador **de la pasada** | `el estado sale del marcador fusionado` ([D-57]) |
| el club se resuelve **también** para el equipo propio | `el equipo propio ya enganchado no vuelve a rival ni crea club` |
| la guarda de [D-84] se quita | `una coordenada que apunta a otra competición para la pasada` |
| el slug no se desempata | `dos clubes distintos con el mismo nombre no colisionan de slug` ([D-82]) |
| la pasada fallida no se registra | los 2 de [D-85], uno de ellos contra Postgres |
| la clave de `Team` pierde `NULLS NOT DISTINCT` | 6 tests de nivel 3 |
| el transporte no valida el `2xx` | `un 500 no llega al parser` ([Anexo RFFM §F.7]) |

**Y tres supervivientes, con tres lecturas distintas** — que es la primera vez que se dan las tres en la misma
fase:

1. **Falta un test** (`Round.merging`): el caso probado movía el **final** de la jornada y dejaba el inicio
   quieto, así que romper `startDate` no tumbaba nada. Corregido: ahora las dos fechas se mueven.
2. **Falta un test** (`IngestionRun`): las tres guardas del `init` no las ejercitaba nadie. Se escribieron sus
   cuatro tests, y las cinco mutaciones correspondientes caen cada una por su lado.
3. **Mutante equivalente**, y es el interesante: cruzar los dos marcadores que `Match` le pasa a
   `Kickoff.merging` **no cambia nada**. `Kickoff` solo pregunta *"¿hay marcador?"*, y `incoming ?? existing`
   es simétrico respecto a esa pregunta. La regla que [D-56] protege —que se fusione **antes** de decidir— sí
   está cubierta, por otras dos mutaciones; lo que no es observable es el **orden de los dos argumentos**.

> **Ésa es una tercera lectura que F2 no había visto.** Una mutación superviviente son *"falta un test"* o
> *"sobra el código"* — y a veces **ninguna de las dos**: el programa mutado es el mismo programa. Un arnés que
> no admita esa salida empuja a escribir un test que no puede fallar.

**Y una nota de arnés que se suma a las de F1 y F4**: el *script* imprimía el progreso por `stdout` y la
invocación lo pasaba por `tail`, así que **el resumen final se perdió** y hubo que reconstruirlo comparando la
lista de detectadas con la de definidas. El veredicto por código de salida siguió siendo correcto; lo que
falló fue poder leerlo.

### 4.8 F6 · El job, el recorrido por tenant y la cadencia — **entregada**

La fase que **le pone llamante** a todo lo que F5 dejó suelto —hasta hoy la única forma de generar una pasada
era un test— y la primera desde F0 que abre superficie HTTP: **9 ficheros de código** y **42 tests**, con la
batería completa en **259**.

| Bloque | Qué entrega |
|---|---|
| Aplicación | `IngestClubCalendars` —el recorrido de un club—, `IngestionScope`, `ClubIngestionReport` y el puerto `FederationClientProvider` |
| App | `IngestCommand` (`swift run Run ingest`), `CatalogFederationClientProvider`, y **`Federation` colgando por fin del grafo** |
| HTTPAdapter | `GET /v1/ingestion-runs` y `POST /v1/ingestion-runs`, más `BackgroundWork` y la traducción del `ServerError` del transporte |
| Contrato | Dos operaciones y seis esquemas nuevos en el *spec*; el `filter` de [D-69] deja de ser el de F0 |

**Qué contestó.**

| Pregunta que estaba abierta | Respuesta |
|---|---|
| ¿Qué pasa si una competición falla en mitad del recorrido? (§9.3 repetida) | **Se continúa.** La unidad de aislamiento es la competición, porque [D-83] la hace atómica y [D-85] deja escrito el fallo → [D-86] |
| ¿Cuál es el intervalo exacto de §5.6? | **No vive en el código.** Lunes + fin de semana, puestos por el disparador; el código trae un **antirrebote**, que no es el tope semanal → [D-87] |
| ¿Cómo se lee el registro de pasadas, y cómo se relanza una? | Un recurso, dos operaciones, y **200 o 202 según el coste** → [D-88] |
| ¿Y si el administrador quiere relanzar **varias** a la vez? | El cuerpo lleva **lista**, no un id: la pantalla son equipos con una casilla, y marcar tres es **una** acción → [D-88] |
| ¿De dónde saca el backoffice la terna *(equipo, temporada, competición)*? | **De ninguna lectura entera**: hoy son N+1 peticiones. No es fallo del modelo —la participación se deriva por diseño ([D-27], [D-28])— sino una **vista derivada que falta**. Abierta en §9.12 |
| ¿Puede el `202` prometer lo que no ha comprobado? | **No.** Planifica antes de responder, así una `seasonId` inexistente da 404 y no un 202 con un fallo invisible detrás |
| ¿Basta la temporada vigente como alcance del recorrido? | **Como valor por defecto, sí**; como prohibición, no. `seasonId` y `competitionId` son las dos filas de la coordenada de la federación (§3.5) |

**Lo que no trae, y es deliberado.** **Ninguna cola de reintentos.** Una competición que falla se vuelve a
intentar en la pasada siguiente y no antes; construirla ahora sería adivinar un problema que el registro de
[D-85] todavía no ha demostrado que exista. Y el `POST` **no crea filas**: pide que el job pase.

**Cuatro cosas que solo se ven haciendo el bucle de §5.1, y una de ellas es un error mío:**

1. **El rojo cazó un fallo que yo acababa de escribir**, y de la familia peor. Al implementar el filtro por
   temporada salió un `scope.seasonID.flatMap { … } ?? seasons.current(…)`: una `seasonId` desconocida **caía
   a la temporada vigente** y sincronizaba otra cosa **con cara de éxito**. Es [D-84] dentro de nuestro propio
   código. El ciclo siguiente lo tumbó con el dato delante — `["21"]` en vez de `["20"]`.
2. **La triangulación del antirrebote funcionó como en F3.** El esqueleto fue *"salta lo que ya se sincronizó
   alguna vez"*, que pasa el primer test tan tranquilo; lo tumbaron los dos siguientes, y por lados distintos.
3. **El rojo cazó un error del test, por cuarta fase seguida**: el recorrido va **ordenado por slug**, así que
   en `["jobuno", "jobdos"]` el sano es el segundo. La aserción decía lo contrario.
4. **Dos tests llegaron en verde y no se disimuló** (el adaptador que sale de `Club.federation`, y el club sin
   adaptador que no deja pasadas fallidas). Los sostiene la estructura, no una línea; se verificaron con
   mutación.

**El hallazgo de arnés, y es nuevo: un test de nivel 3 puede romper los de otras suites.** El primer test del
recorrido enumeraba **todos** los tenants de `public.tenants` — y las suites corren en paralelo, así que se
puso a ingerir los clubes de las otras y a escribirles filas en sus *schemas*. Salió a la luz porque el
recorrido devolvió `["e2e-sinjugar", "jobcat", "jobmad", "match-rt", "season-arch"]`. **La lección: probar una
regla global con efectos globales, en una batería paralela, no es un test — es una carrera.** Se separó en dos:
la regla *"sin filtro son todos"* se afirma sobre una consulta **sin efectos**, y el recorrido de verdad se
lanza sobre una lista explícita de clubes.

**Y dos hallazgos del contrato, los dos por lo mismo — que el *spec* declara y el generador no obedece**
([D-65], tercera fase que lo cobra):

1. El `requestBody` se declaró `required: false` prometiendo que el cuerpo se podía **omitir**. Es falso: el
   servidor generado lo parsea igual y un `POST` sin nada da 400. **Se corrigió el contrato, no la realidad.**
2. Un parámetro obligatorio que **falta** lo rechaza el código generado antes de llegar al *handler*, así que
   `GET /ingestion-runs` sin `competitionId` daba **500** aunque el *spec* declare 400. Lo traduce ahora
   `ProblemMiddleware`, reutilizando la tabla que el propio runtime ya tiene — y **no** su
   `ErrorHandlingMiddleware`, que devuelve el código **sin cuerpo** y §5.4 exige `application/problem+json` en
   todo error del contrato.

**Y una sesión de pruebas manuales que encontró dos defectos que la batería no podía ver** —contra la base de
trabajo, con la RFFM de verdad y 240 partidos reales entrando—. Los dos en `IngestionRun`, y los dos por el
mismo motivo de método: **los niveles 2 y 3 corren con un reloj fijo y con dobles sin restricciones**.

1. **El motivo de una pasada fallida era ilegible.** Un `UNIQUE` reventando deja un `PSQLError`, que esconde
   su descripción tras *"Generic description to prevent accidental leakage of sensitive data"*. La fila que
   existe para contestar *"¿por qué falta este partido?"* no contestaba nada. Con `String(reflecting:)` deja
   `sqlState: 23505 · Key (federation_match_id)=(5374968) already exists`.
2. **La pasada con éxito no medía su duración.** El informe se construye al empezar, así que
   `started_at == finished_at`; la fallida sí se medía, y esa **asimetría era el síntoma**. Ninguna invariante
   lo delataba, porque `finishedAt >= startedAt` se cumple trivialmente.

Se cubren con dos dobles nuevos —`TickingClock` y un error opaco al estilo de `PSQLError`— y **32 mutaciones,
32 cazadas** en total. La lección se apunta junto a las de arnés de F1, F4 y F5: **un reloj fijo y unos dobles
sin restricciones son exactamente las dos cosas que hacen barata la batería, y exactamente las dos que ocultan
esta clase de fallo.** Ejecutar el sistema y mirar la tabla no es opcional.

> **De propina, `D-84` quedó reverificado en vivo el 2026-08-31**, y por accidente: al sembrar una segunda
> competición con `temporada=22` la RFFM devolvió el calendario de 2025/26 — **ignoró el parámetro**, que es
> su tercer modo de fallo. El sistema se negó a escribir un calendario cadete en una competición senior: la
> guarda no podía disparar (primera sincronización, sin `federation_name` con qué comparar), lo paró el
> `UNIQUE`, `D-85` dejó la fila y `D-86` siguió con lo demás. **La defensa en profundidad funcionó, y el
> escalón que la salvó no fue el que se diseñó para eso.**

**Comprobación de mutación: 30 mutaciones, 30 cazadas**, con especificidad — romper *solo* la guarda de la
temporada desconocida tumba *solo* el test de [D-84], y romper *solo* el 502 tumba *solo* el de la pasada
fallida. **Cinco sobrevivieron a la primera pasada, y las cinco eran «falta un test»** — ninguna era código
que sobrara, y una de ellas era seria:

| Se rompe | Lo caza |
|---|---|
| la vigente deja de elegirse | `solo se recorre la temporada vigente` (§3.2) |
| una `seasonId` desconocida cae a la vigente | `no cae a la vigente: falla` ([D-84]) |
| el antirrebote se aplica sin pedirlo / no deja pasar nunca | un test cada uno (§5.6) |
| **la competición nunca sincronizada no entra** | *(faltaba)* `entra aunque haya intervalo mínimo` |
| **el antirrebote no alcanza a la competición pedida por id** | *(faltaba)* `alcanza también a la pedida por id` |
| un fallo detiene el recorrido / se continúa sin apuntarlo | los 3 de [D-86] |
| el adaptador no sale del club · la FCF usa el de Madrid | los 2 de [D-17] |
| el recorrido se queda en el primer club | `los dos clubes se sincronizan en la misma pasada` |
| **el código de salida no ve los fallos** | *(faltaba)* `un club con una competición fallida no cuenta como éxito` |
| **el rango del `limit` no se comprueba** | *(faltaba)* `un limit fuera de rango es 400` |
| el ámbito del `GET` no se comprueba | `una competición de otro club no existe: 404` |
| el 502 pasa a 404 · el 202 no planifica antes | los 2 de [D-88] |
| el `ServerError` del transporte vuelve a ser 500 | `sin competitionId el registro no se sirve: 400` |
| solo se recorre la primera de la lista · el orden se pierde | los 2 de la lista de [D-88] |
| un id desconocido de la lista se ignora | `si una no existe, no se sincroniza ninguna` |
| dos competiciones responden 200 · la lista vacía es "todas" | los 2 del nivel 4 |
| **`-c` deja de partir la coma** · **el trim se cae** | *(faltaban)* los 8 de `IngestArgumentsTests` |

**Y una superviviente más, encontrada al añadir la lista de [D-88]: el parseo de argumentos no lo miraba
nadie.** Romper `--competition` para que solo cogiera el primer valor **no tumbaba ningún test** — los del
recorrido reciben el `IngestionScope` ya construido, así que entre la cadena que teclea el operador y el
ámbito no había ningún test. Se cerró como se cerró la del código de salida: **extrayendo la traducción a una
función pura** (`IngestCommand.scope(season:competition:minIntervalHours:force:)`) y probándola sin Docker.
Ahí viven además las dos precedencias que el `--help` no puede explicar: `--force` gana sobre
`--min-interval-hours`, y una lista vacía es como no pasar ninguna.

> **Y de escribir ese test salió una trampa de aserción que conviene conocer.** `#expect(scope.minInterval ==
> 6 * 3600)` **falla**, e imprime `21600.0 == 21600` — los dos valores iguales. Un literal entero contra un
> `TimeInterval?` no compara lo que parece; hay que escribir `Double(6 * 3600)`. Es el caso peor de la familia
> de §5.1: no un rojo que no demuestra nada, sino una **aserción que no puede pasar** — y su gemela con `!=`
> sería una que no puede fallar.

> **La superviviente que más enseña es la tercera.** *"La competición que nunca se sincronizó no entra"* pasaba
> todos los tests, y significa que **una competición recién dada de alta —el enganche de [D-67], que es F10—
> se quedaría esperando para siempre**: nunca se sincronizó, así que nunca sería "vieja", así que el cron
> nunca la tocaría. Ningún rojo la habría encontrado, porque ningún test tenía motivo para existir hasta que
> la mutación preguntó.

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

### 5.1 Qué compra cada rojo, y por qué hay que escribir el esqueleto

*Añadido tras F2, que se escribió test-first y aun así se dejó la mitad del ciclo por el camino.*

Escribir el test antes produce **dos** cosas, y **no se compran a la vez**:

| Producto | Qué lo compra |
|---|---|
| **Presión de diseño** — la interfaz queda decidida antes que la implementación | escribir el test primero. **Da igual la forma del rojo** |
| **Aserción verificada** — *esta comprobación caza este fallo* | que el test **se ejecute** y falle **por su aserción** |

La primera es real y se cobra sola. En F2 se ve en decisiones que se tomaron **en el fichero de test** y que
la implementación después obedeció: que `RFFMValue.score` devuelva `Int?` y no un centinela —que es la
frontera de [D-56] expresada en una firma—, que `kickoff` reciba un `String?` porque la muestra 2 de
[Anexo RFFM §F.2] no trae el campo, o que `federationClubID` **no lance** mientras sus vecinas sí, que es la
regla de degradación de §3.7 hecha tipo.

**La segunda no la compra un rojo de compilación.** Y en Swift, con un tipo que todavía no existe, el rojo por
defecto es ése: `cannot find 'X' in scope`. Demuestra que el código no estaba; **no** demuestra que la
aserción sirva, porque nunca llegó a ejecutarse. Un `#expect` mal escrito da exactamente el mismo rojo que uno
bien escrito.

> **El esqueleto es lo que convierte un rojo en el otro, y cuesta un minuto.**
>
> **Esqueleto** aquí **no** es la lista de tests —cuidado con la palabra, que en §3 significa otra cosa— ni un
> diseño previo. Es la **implementación falsa**: el tipo y la función existen, con su nombre y su firma
> definitivos, compilan, y devuelven a propósito **la respuesta equivocada**. Entonces el rojo es
> `Expectation failed: 3 == 0`, con el valor delante.
>
> **Que devuelva un valor válido pero mal, nunca `fatalError()`:** eso *trapea* y mata el proceso, así que no
> da una aserción fallida sino una caída que se lleva por delante el resto de la ejecución.

**Y el esqueleto solo se paga si la granularidad es de una regla.** Son dos cosas independientes, y en F2
faltaron las dos en distinto grado: se escribieron *suites* enteros contra unidades enteras, en vez de una
regla → su test → su esqueleto → verde. Con un *suite* entero, el esqueleto tendría que fingir doce respuestas
a la vez y deja de decir nada.

Así que el bucle interior, completo:

```
una regla → su test → su esqueleto (rojo de aserción) → implementación (verde) → refactor
```

**Dónde se paga más caro saltárselo: F3.** Es la política de *upsert* de [D-56], donde equivocarse **destruye
datos que no vuelven**, y sus aserciones son sutiles —*"vacío no sobrescribe"* y *"vacío sobrescribe"* son dos
líneas casi idénticas—. El esqueleto se escribe solo: si la función es `merge(existing:incoming:)`, el
esqueleto es **devolver `incoming`**, que es exactamente la implementación ingenua que la decisión existe para
prohibir. Contra ese esqueleto, cada test de la fase falla por su aserción y con el dato a la vista.

**Lo que esto no sustituye.** La comprobación de mutación (§4.2) compra la misma garantía **a posteriori**, y
sigue haciendo falta: en F2 encontró algo que ningún rojo de aserción habría encontrado — código defensivo que
no defendía nada (§4.3). El esqueleto la adelanta y la reparte por el camino; no la reemplaza.

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

- **Poner en marcha el disparador de la cadencia** (`D-87`): F6 entrega el comando, pero **quién lo llama los
  lunes y los fines de semana es una decisión de despliegue**, no de código. Hasta que exista ese cron, la
  ingesta solo corre a mano o por el `POST` del backoffice — y el tope semanal de §5.6 no está garantizado
  por nada.
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

   > **Dejó dos deberes para F3, y F3 los ha hecho** (§4.5). [D-56] se mantiene con el argumento cambiado
   > —el coste de los dos errores no es simétrico, [D-75]— y el `202` de [D-67] también, por el volumen de
   > escritura y los escudos en vez de por el número de peticiones. De paso, el tope semanal de §5.6 conserva
   > su rango de **requisito** pero apoyado en [D-55] (la clasificación de la FCF no se puede pedir hacia
   > atrás), no en la fecha. **Ninguna de las dos reglas cambió; las dos cambiaron de razón**, que era
   > exactamente lo que había que averiguar.
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
[D-75]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-76]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-77]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-78]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-79]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-80]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-18]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-19]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-30]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-31]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-55]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-09]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-15]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-17]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-29]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-57]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-58]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-70]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[Anexo RFFM §F.1]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.2]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.5]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.7]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.14]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.15]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[D-12]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-66]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-86]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-87]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-88]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md