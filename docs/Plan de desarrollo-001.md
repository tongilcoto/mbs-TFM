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
| **F6-bis** ✅ | Dos mitades, las dos *"antes de que F7 y F8 lo copien"*: **el sobre del puerto de federación** —y con él la guarda de temporada ([D-91])— y **la resiliencia del recorrido** (`4d66aa0`). Detalle abajo | unit puro · niveles 1, 2 y 3 | `A-1` · H-08, H-09, H-10 · `A-3` · H-23, H-24, H-26 · [D-91] |
| **F6-ter** ✅ | **El segundo freno de [D-86] bajo el arnés**: extraer *"¿este resultado detiene el recorrido?"* de `IngestCommand` como regla pura y probarla. Una función, su test y nada más — está aquí porque cambia una API pública y la regla 2 del plan de auditoría no admite excepciones por tamaño. Detalle abajo | unit puro | `A-7` · H-45, H-48 · [D-86] |
| **F7** ✅ | `StandingRow` (RFFM histórica) + ***fallback* calculado** desde `Match` — **y su migración se añade con [D-90] delante** (ver abajo). Detalle abajo | unit + integración | [D-15], [D-55], [D-92], `A-5` · H-31 |
| **F8** ✅ | `LeagueScorer` — con la clave de *upsert* que §3.5 no tenía ([D-93]), la **única retirada de filas** de la salida de la ingesta ([D-94]) y el `CHECK` de un enumerado que **no se mantenía solo**. Detalle abajo | integración | [D-09], [D-48], [D-93], [D-94], [D-90] |
| **F9** | Adaptador **FCF** — **API JSON, no raspado**: el calendario entero en **una** petición ([D-74], [Anexo FCF §C.10.4]), más las capacidades del catálogo | unit + integración | [D-17], [D-55], [D-74], Anexo FCF §C.10 |
| **F10** | `POST /teams/{id}/federation-link` **+ `/preview`**, y con ellos el alta en cascada de `Season` y `Competition`. **Y la pasada aceptada tiene que dejar fila** (ver abajo). Su migración de `TeamRegistration` lleva además **los dos índices compuestos de `Match`** que §4.6 manda y no existen (`A-5` · H-36). **Y es la fase que hace cruzar la frontera HTTP a los errores de la ingesta** — tres deberes de A-6 y A-7, abajo | E2E de contrato | [D-67], §2.3-c, `A-4` · H-27, `A-5` · H-36, `A-6` · H-15, H-40, H-42, `A-7` · H-46 |

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

**Y F10 llega con un deber heredado de la auditoría** (`A-4`, H-27), que conviene tener delante **antes** de
escribir el `202` de [D-67] y no después: **una pasada aceptada no deja hoy ninguna huella hasta que termina.**
`IngestionOutcome` solo tiene `succeeded` y `failed`, así que entre el `202` y el final del trabajo **no existe
fila ninguna** — y si el trabajo muere ahí en medio, no queda un hueco: queda el estado anterior, intacto y con
cara de sano. Medido en A-4: el cliente recibe su `202` con dos competiciones, se pierden las dos, y
`GET /v1/ingestion-runs` sigue devolviendo una pasada `succeeded` **anterior a la propia petición**, con lo que
`ingestionHealth` ([D-89]) evalúa **`ok`**.

El arreglo de A-4 tapó la ceguera del **operador** —el fallo se registra en el log, `77b2056`— pero **no la del
backoffice**, y no puede: no hay *push*, así que la pantalla solo sabe lo que pueda **leer**. Las dos salidas,
a decidir en F10 con [D-67] delante:

- **Escribir la fila al aceptar**, con un desenlace nuevo (`running`/`accepted`) que la pasada cierra. Es lo que
  hace que el backoffice se entere leyendo lo que ya lee, y lo que convierte *"lleva veinte minutos en curso"*
  en una frase que la pantalla puede decir. Toca **Dominio, migración y contrato**, y obliga a **enmendar
  [D-88]**, que hoy dice *"el `POST` no crea la fila"* — la enmienda es de alcance, no de dirección: seguiría
  sin llevar ni un dato de la pasada.
- **Que el cliente compare marcas de tiempo** —*"¿ha aparecido una pasada más nueva que mi petición?"*—, que no
  toca nada del backend y es el N+1 por recarga que [D-89] descartó **a propósito**.

**Y F10 hereda tres deberes más, los tres de la frontera de error** (`A-6` y `A-7`), que van juntos porque
son el mismo sitio: hasta F10 la ingesta **no pasa por HTTP** (§2.3-b), y el `/preview` la ejecuta **en línea
y dentro de la respuesta**.

- **Los cuatro casos de `FederationError` acaban hoy en el mismo 500** (`A-6`, H-15). El fichero justifica su
  taxonomía —*"un caso de uso tiene que poder distinguir «la fuente no contesta» de «la fuente contesta algo
  que no entiendo»"*— y en producción **no los distingue nadie**: se lanzan en `Federation/` y se discriminan
  solo en `Tests/`. `ProblemMiddleware`, cuyo `switch` sobre `DomainError` es exhaustivo **a propósito**, no
  contempla `FederationError`. Hoy no se nota porque el `202` responde antes de llamar a la federación
  ([D-88]); el `/preview` llama **dentro** de la petición, y ahí *"la RFFM está caída"* y *"la RFFM cambió de
  formato"* merecen respuestas distintas.
- **La guarda de tenant de §6.1 está donde no puede dispararse** (`A-6`, H-42). `tenantMismatch` existe,
  funciona y está mapeada a **403**, pero en el camino HTTP el actor **se deriva del propio ambiente**, así que
  la comparación es una tautología; A-6 la dejó como **puerta y cinturón**, con el cinturón abrochado en
  Persistencia y la puerta pendiente del *claim*. F10 escribe endpoints de escritura con *"rol elevado"* en el
  *spec*: es cuando la puerta hace falta.
- **De los 14 códigos `Problem` que el middleware puede emitir, 3 los afirma un test** (`A-7`, H-46). La ronda
  de A-7 fijó **por caso** los cinco casos de `ApplicationError` que la ingesta levanta —404 contra 500 contra
  503 no son intercambiables y hasta entonces lo eran sin que la batería lo notase—, pero eso es el nivel 2.
  **La superficie HTTP sigue sin afirmarse**, y es F10 quien la estrena.

**Y F7 llega con otro deber heredado, éste de una línea** (`A-5`, H-31 → [D-90]): **no se edita una
migración ya aplicada.** F7, F8 y F10 añaden tres tablas a un esquema que ya tiene clubes con historia, y
`_fluent_migrations` guarda el **nombre** de cada migración, no su contenido — así que un `CHECK` corregido
*a posteriori* sobre un `prepare` viejo llega a la base del desarrollador (que la recrea) y **no** a la de un
club (que no). Ya ocurrió una vez, con `CreateClub`. Lo que se corrige va en una migración nueva, al final de
la lista **que le toque por FK**. La buena noticia del bloque es la otra mitad, y está medida: **el esquema de
un club no depende de cuándo se dio de alta** —cuatro caminos distintos, un solo `md5`—, y desde `A-5` eso lo
guarda un test (H-38) en vez de depender de que alguien lo repita a mano.

**Y el deber de operación que trae A-7, que es el más barato de todos y el que más tiempo lleva pendiente:
montar el *workflow* de integración continua** (H-07, H-49). No hay CI de ningún tipo en el repositorio, y el
código **sí está preparado**: la guarda de `DatabaseAvailability` —los tests de BD se omiten en local pero
**fallan** con `CI` o `REQUIRE_DB` definidas— se escribió *para* un CI que no existe. La consecuencia, medida
en A-7: con Postgres parado, `swift test` sale **0** y sus seis renglones de resumen son **idénticos en texto
y en recuento** a los de una pasada de verdad —el total sale de la lista, no de lo ejecutado—, así que **lo
único que distingue *"probado"* de *"no probado"* es la duración**: 5,70 s contra 0,002 s. A-7 deja la
propuesta entera con sus cuatro pasos medidos y la señal que hay que leer, que **no es texto**:
`swift test --xunit-output` emite el recuento por *target* y el motivo de cada omitido. **Va con el cron**
([D-87], §9), porque es la misma decisión de despliegue y porque el canario necesita exactamente lo mismo: un
disparo programado y separado de la batería.

**Los dos deberes de A-5 que no son de fase sino de operación**, apuntados aquí para que no se pierdan y
decididos en §9.3 del LLD: **cerrar el *pool* de cada club** al terminar con él —hoy se registra uno por
tenant y no se suelta: 25 clubes, 25 conexiones **directas** simultáneas, medido— y **poder preguntar en qué
versión quedó cada club** tras un fallo, que hoy exige abrir `_fluent_migrations` *schema* a *schema*. El
recorrido ya se para y ya dice de quién fue el fallo (H-33); lo que falta es la constancia durable. Ninguno
de los dos bloquea a F7: los dos empiezan a doler con el número de clubes, que es exactamente cuándo hay que
tenerlos hechos.

**Y una fase que no estaba prevista y la trajo la auditoría: F6-bis.** El bloque `A-1` del
[plan de auditoría](../backend/Plan%20de%20auditor%C3%ADa-001.md) hizo el ensayo en seco del adaptador de la
FCF contra los DTOs del puerto y encontró que **`FederationMatch` y `FederationTeamRef` aguantan campo a
campo, y el *sobre* de `FederationCalendar` no**: de sus cinco campos, el calendario de la FCF publica **uno**,
y los dos obligatorios —`seasonLabel` y `FederationRound.label`— son justo los dos que esa fuente no tiene
(H-08). De ahí sale una consecuencia funcional, H-09: la guarda de [D-84] compara `competitionName`, y como
la FCF no publica nombre de competición en su calendario, **para un tenant catalán la guarda no se dispararía
nunca**.

**Va antes de F7 y no dentro de F9, y la razón es el coste de copiarla.** F7 y F8 no estrenan puerto: le
añaden `fetchStandings` y `fetchScorers`, con sus DTOs. Y la asimetría se repite ahí — `/api/standings` y
`/api/scorers` de la RFFM devuelven `competicion` y `grupo` ([Anexo RFFM §F.8], §F.13) y sus equivalentes de
la FCF no ([Anexo FCF §C.10.6], §C.10.7)—, así que un sobre nuevo modelado por analogía con el de F2
reproduce H-08 y H-09 **dos veces más** antes de que nadie escriba el adaptador catalán. Es el error de la
abstracción validada contra un solo caso, y aquí está localizado con nombre y línea.

**Qué entrega, y las dos mitades están ya decididas** (2026-09-13):

1. **La forma del sobre.** `FederationRound.label` **se elimina** —no lo lee nadie: su única aparición en
   todo el backend es `self.label = label`— y `seasonLabel` pasa a **opcional**, que es lo que el puerto
   promete de sí mismo (*"un `nil` significa «la fuente no lo dijo»"*) y lo que cierra H-10 de paso: un
   rótulo raro deja el campo vacío en vez de tumbar un `fetchCalendar` con sus 30 jornadas ya parseadas. Su
   único lector es `seed-competition`, que es herramienta y no contrato. **Coste medido: 6 ficheros** —el
   parser y cinco de test— y dos `init` públicos.
2. **Dónde vive la evidencia de la coordenada: en las fechas, no en el nombre** ([D-91]). Aquí la respuesta
   cambió al ir a medirla, y es lo más valioso de esta mitad: las tres opciones que H-09 traía evaluadas
   giraban alrededor **del nombre**, y el nombre **es idéntico entre temporadas** ([Anexo RFFM §F.17]:
   `PRIMERA CADETE` / `Grupo 4` en 25-26 y en 26-27). O sea que ninguna cubría el error que ocurre cada
   verano —copiar los códigos del año pasado—, tampoco en Madrid. La guarda que sí lo cubre compara **la
   mediana de las fechas del calendario** contra la ventana de la `Season`: sin columna nueva, sin llamada
   extra, y **funciona igual en la FCF**, que no publica nombre pero sí fecha.

**No implementa nada de la FCF**: eso sigue siendo F9, y allí queda solo la mitad *"otra competición"* de
H-09.

**Entregada el 2026-09-13.** Lo que quedó escrito, en orden de valor:

- **La guarda de [D-91]**, en el Dominio (`Season.requireOwnsCalendar(matchDates:)`) y llamada por la pasada
  justo detrás de la de [D-84]. **Siete tests de nivel 1 y uno de nivel 2, con 7 mutaciones cazadas** — y
  tres de esas mutaciones son exactamente las tres alternativas que la decisión descartó (*"todas dentro"*,
  *"que solapen"*, bordes exclusivos), así que los tests no solo protegen la regla: **documentan por qué es
  ésa**.
- **El sobre**: `FederationRound.label` fuera y `seasonLabel` opcional, con el parser degradando a `nil`
  en vez de tumbar 34 jornadas ya parseadas (H-10, con su test y su mutación).
- **Y lo primero que cazó la guarda nueva fue el arnés**: el *fixture* de nivel 3 sembraba `2025/26` para
  **los dos** volcados, y el de *"temporada sin jugar"* es de **26-27**. Llevaba así desde F5 —una
  competición apuntando a un calendario de otro año— y **nada lo decía**. Es el mejor argumento a favor de la
  decisión: el error que `D-91` describe no es hipotético, estaba dentro de la propia batería.

**293 tests** (284 → 293).

#### F6-bis, segunda mitad · la resiliencia del recorrido — **entregada** (`4d66aa0`, 2026-09-12)

**Esta mitad se ejecutó dentro de la ronda de arreglos del bloque `A-3`, y se registra aquí a posteriori**
porque por la regla 2 de §3 del plan de auditoría era una mini-fase y le tocaba estar en esta tabla: toca tres
*targets* —`Application`, `App` y `HTTPAdapter`— y añade dos casos a una enumeración pública. Se hizo dentro de
la ronda porque la decisión de diseño que esa válvula existe para forzar **ya estaba tomada por el
desarrollador**, con las tres salidas de H-23 y sus costes delante. El apunte va aquí para que el registro de
fases diga lo que de verdad pasó; la lectura de método está en §7 del plan de auditoría.

**Por qué es hermana de la otra mitad y no una fase aparte.** Las dos son *"arréglalo antes de que F7 y F8 lo
copien"*. La primera lo dice de la **forma del puerto**; ésta, de la **forma del recorrido**: `StandingRow` y
`LeagueScorer` se sincronizan por el mismo `IngestClubCalendars` y con un `execute` de la misma forma que
`IngestCalendar`, así que una garantía rota ahí se hereda tres veces en vez de una.

**Qué entregó:**

- **El recorrido se detiene cuando el que falla es la base** (H-23). [D-86] continúa ante un fallo *de datos*
  porque [D-85] deja constancia; con la base caída no la dejaba —el tercer ámbito de [D-83] usa el mismo
  recurso que acaba de fallar—, así que continuaba haciendo justo lo que [D-86] declara inseguro. Y la
  distinción **no se hace clasificando el error**: se le **pregunta a la base si sigue ahí** después de cada
  fallo. Una lista de códigos de `PSQLError`, *pool* y *pooler* sería una premisa sobre un sistema ajeno, que
  es lo que [D-84] enseñó a no heredar. Se detiene también el recorrido de los clubes que faltan: el *pool* y
  el Postgres son **uno solo** (§6.4).
- **Una pasada escrita ya no se registra como fallida** (H-24): si lo único que falla es el apunte, se lanza
  `runNotRecorded` y **no se escribe fila**, en vez de dejar tres testigos contradiciéndose.
- **El test de nivel 3 con un fallo real de Postgres** (H-26), que hasta entonces no existía: los dos que
  guardaban [D-83] y [D-85] usaban un `DomainError`, que salta antes de emitir la sentencia.

Enmendadas [D-85] y [D-86] en la bitácora, las dos porque prometían más de lo que cumplían. Cinco mutaciones,
cinco cazadas. **272 → 276 tests.**

**Lo que esta mitad dejó fuera a propósito**, para que no parezca hecho: el **código de salida numérico
distinto** para *"falló la infraestructura"*, que va con la decisión de **montar el cron** — el deber de
despliegue que sigue pendiente desde F6 (§9). **Lo que sí cambió después, y deja el terreno preparado**
(`A-5`/H-39, `3fed005`): el punto de entrada ya no propaga el error sino que hace **`exit(1)`**, porque un
`throw` en el nivel superior de un ejecutable es un `fatalError` y salía **133** —indistinguible de un
*crash*—. Así que el sitio donde vivirá ese `exit(n)` ya existe y ya es el dueño de la cuenta: **el comando
decide si falló lanzando; `Run/main.swift` decide cómo se cuenta.** Lo que falta es solo **qué número** para
cada clase de fallo, y eso lo pide el cron, no el código.

#### F6-ter · el segundo freno de [D-86] bajo el arnés — **entregada** (2026-09-14)

**La fase más pequeña de todo el plan, y está aquí por la misma razón por la que F6-bis está: la regla 2 del
plan de auditoría no admite excepciones por tamaño.** Un arreglo que cambia una API pública deja de ser una
corrección de auditoría, y esto la cambia: hay que poder llamar a la regla desde un test.

**Qué encontró A-7** (H-45). [D-86] enmendada tiene **dos** frenos, y hasta A-7 solo uno estaba probado:

| Freno | Dónde | Estado |
|---|---|---|
| Entre **competiciones** de un club | `IngestClubCalendars` pone `report.abortedByInfrastructure` | ✅ probado desde F6-bis, y A-3 lo mutó |
| Entre **clubes** del recorrido | `IngestCommand` empareja `if case ApplicationError.databaseUnavailable` | ⚠️ **el lado que lanza ya tiene test** (ronda de A-7); **el que empareja, no** |

El lado que lanza lo cerró la ronda de A-7 con un test de nivel 2 y aserción **sobre el caso** — mata las dos
mutaciones que sobrevivían: cambiar el caso, y borrar la sonda entera. Lo que queda es el `if case`, y **no se
puede probar hoy**: la unidad de trabajo se construye *dentro* de `ingest` desde `app.db(.control)` y no es
inyectable, y provocar el fallo de verdad exige parar Postgres a mitad de un test, que `A-3` ya descartó.

**Qué entrega.** Extraer la pregunta *"¿este resultado detiene el recorrido?"* como regla pura y llamarla
desde el bucle. **El criterio no hay que inventarlo: el fichero ya tiene el hermano** —`incomplete(outcomes)`
se separó de `run` *"porque es la regla —no el `print`— y probarla no puede exigir montar una consola"*—, así
que esto es la misma decisión aplicada catorce líneas más arriba. Con eso, las dos mitades del freno quedan
bajo el arnés y `D-86` deja de depender de que dos *targets* estén de acuerdo sin que nada lo compruebe.

**Por qué antes de F7 y no después.** Porque F7 y F8 **no estrenan recorrido: le cuelgan trabajo**.
`StandingRow` y `LeagueScorer` se sincronizan por el mismo `IngestClubCalendars`, así que el recorrido de
clubes se recorre tres veces más antes de que nadie vuelva a mirarlo. Es el mismo argumento con el que F6-bis
se adelantó a F7, y la única razón por la que esto no entró en ella es que A-3 no llegó a esta sonda.

**Y una lección de A-7 que conviene tener delante al escribirla** (H-48): *antes de aceptar que algo no se
puede probar, buscar si el proyecto ya resolvió el caso hermano*. A-6 lo aprendió con el log —declarado
*"fuera del arnés"* cuando `CapturingLogHandler` ya existía— y aquí vuelve a pasar con el mismo desenlace.

**Qué entregó, y es exactamente lo que la fila prometía: una función, su test y nada más.**

- **`IngestCommand.stopsTraversal(_:)`**, que recibe un `Result<ClubIngestionReport, any Error>` —el desenlace
  de **un club**— y contesta sí o no. Los dos frenos entran por la misma puerta porque **son la misma razón
  contada desde dos sitios**: el club que se recorrió y se paró solo (`abortedByInfrastructure`) y el que ni
  empezó porque el ámbito 1 se encontró la base caída (`databaseUnavailable`). En los dos falta el sitio donde
  se apuntan los fallos, y el *pool*, la conexión y el Postgres son uno solo (§6.4).
- **El bucle pasa de dos `if` a uno**, y de dos `break` a uno. El desenlace se guarda **entero** —antes el
  `catch` lo convertía en texto en el acto— porque quien decide si el recorrido sigue necesita **el caso** del
  error, y `diagnosticText` lo pierde. Se apunta siempre, y solo después se pregunta si se sigue.
- **Cuatro tests de nivel 1** (`IngestTraversalStopTests`), en dos pares. Los pares no son simetría decorativa:
  [D-86] es una decisión con **dos mitades inseparables** —*"se continúa y se apunta"* y *"se para cuando no se
  puede apuntar"*—, así que probar solo que se para dejaría pasar un freno que frena siempre, que es volver a
  antes de [D-86].

**El ciclo de §5.1, entero y con el esqueleto.** El esqueleto fue `return false` —*"nunca se para"*, que es
literalmente la implementación ingenua que la enmienda de [D-86] existe para prohibir—, y contra él los dos
tests de *"sí para"* fallaron **por su aserción**, con la expectativa delante. Los otros dos pasaron desde el
esqueleto, y eso también es información: son la mitad que ya estaba bien y que había que no romper.

**Cinco mutaciones, cuatro cazadas — y la quinta es el borde de la fase, no un descuido.**

| Se rompe | Resultado | Quién la caza |
|---|---|---|
| **M1** · la rama de éxito devuelve `false` | **cazada** | `un club que abortó por infraestructura para el recorrido` |
| **M2** · `databaseUnavailable` → `federationAdapterMissing` | **cazada** | `databaseUnavailable para el recorrido` **y** `cualquier otro fallo no para el recorrido` — el par entero, que es para lo que existe |
| **M3** · la rama de fallo desaparece entera | **cazada** | `databaseUnavailable para el recorrido` — es la M1c de `A-7` un piso más arriba, y allí también la cazó el test del extremo que lanza |
| **M4** · `stopsTraversal` devuelve `true` siempre | **cazada, con seis testigos** | los dos de *"no para"* de nivel 1 **y cuatro de nivel 3** —`un club sin adaptador no detiene el recorrido de los demás` entre ellos—. Es la M1b de `A-7`, que ya se cazaba; ahora además se caza sin Docker |
| **M5** · el bucle deja de llamar a la regla | **sobrevive** | nadie |

**M5 es el residuo declarado, y conviene que esté escrito para que nadie lo confunda con cobertura.** Lo que
esta fase pone bajo el arnés es **la regla**; lo que queda fuera es **el cable** —la línea
`if Self.stopsTraversal(result) { break }`—, y queda fuera por lo mismo que lo estaba todo antes: la unidad de
trabajo se construye dentro de `ingest` desde `app.db(.control)` y no es inyectable, así que ningún test puede
hacer que un club devuelva `databaseUnavailable` de verdad. La diferencia con el punto de partida no es
pequeña: antes el freno **era** el cable —dos `if` dentro del bucle, sin regla que nombrar y sin un solo test
que los alcanzara—, y `D-86` dependía de que dos *targets* estuvieran de acuerdo sin testigo; ahora el acuerdo
está afirmado por su nombre y lo único no observado es una línea de cableado con un solo camino. Cerrar M5 exige **la otra salida que `A-7` ya había identificado y descartado
para esta fase** —una unidad de trabajo inyectable en `ingest`, más mover `SwitchableUnitOfWork` de
`Tests/ApplicationTests/IngestionFakes.swift` a `TestSupport`—, que es otra API pública y, por la regla 2, otra
mini-fase. **No se hace aquí**: la fila de esta decía *"una función, su test y nada más"*.

**304 tests** (300 → 304), 0 fallos, 1 omitido —el canario, que está fuera de la batería por diseño—, medidos
con `REQUIRE_DB=1 swift test --xunit-output`: **7+64+51+105+53+24**, y los dos *targets* de BD en **6,46 s** y
**3,46 s**, que es el testigo de H-07 de que corrieron.

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
| ¿Una coordenada equivocada falla? | **No.** Devuelve `200` y el calendario de **otra competición**. Y los códigos **no** caducan: cambian cada temporada y los viejos siguen sirviendo lo suyo → [D-84] |
| ¿Dónde queda constancia de una pasada? | En una **tabla**, y escrita **fuera** de la transacción de la pasada → [D-85] |
| ¿Sirve el volcado que había para la rama de "partido jugado"? | No, y ya no hace falta: el volcado de temporada jugada cierra el deber de §4.3 |

**El hallazgo de la fase, y no se buscaba.** Capturando los volcados se vio que **una coordenada equivocada
no falla**: devuelve `200` y un calendario perfectamente parseable **de otra competición**.

> ⚠️ **La causa que se escribió aquí era falsa, y se corrigió el 2026-09-02** —la enmienda vive en [D-84] y la
> evidencia en [Anexo RFFM §F.16]—. Se dijo que *"la RFFM reutiliza los códigos de competición y grupo entre
> temporadas"*. **No los reutiliza**: cada temporada recibe un bloque nuevo. Lo que pasa es que **ignora el
> parámetro `temporada`**, y que **lo devuelve como si fuera un dato** en `calendar.temporada`. Quien capturó
> los volcados vio a la respuesta decir *"2026-2027"* y concluyó, razonablemente, que era otra temporada.
>
> **Y esa es la lección que esta fase no podía dejar, porque no la sabía**: *"una premisa sobre un sistema de
> terceros se mide"* es necesario y **no suficiente**. Se midió, y salió mal — porque la fuente **devuelve tu
> propio parámetro** como si fuera suyo. Contra eso solo protege desconfiar de todo campo que se parezca a lo
> que enviaste, y buscar una señal que no pueda ser eco: aquí, **las fechas de los partidos**.

La conclusión, en cambio, se mantiene entera: confirmó con dato real una regla que solo estaba razonada (§3.5: `Competition` se identifica por
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

> **Y aun así el paralelismo no sobra, que es la otra mitad y está medida**: con `--no-parallel` los 138 tests
> de entonces tardaban **3,7 s**; en paralelo, **0,9 s**. Correrlos concurrentes es además **lo que destapó
> esta carrera** — un orden fijo la habría escondido hasta que apareciera en CI o en la máquina de otro. Así
> que la batería corre en paralelo y **para leerla** se usa `--no-parallel --disable-xctest`, que además da
> orden de fichero determinista y un renglón por caso parametrizado.

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

### 4.9 F7 · La clasificación, ingerida y calculada — **entregada** (2026-09-16)

**La entidad 22 del modelo, y la primera fase con dos fuentes para la misma fila.** [D-15] dice que
`StandingRow` es **agnóstica a la fuente** —vale igual ingerida que calculada— y F7 es donde esa frase se
convierte en un `switch` de dos ramas que acaban en el mismo `save`.

**Qué entrega, de abajo arriba:**

| Capa | Qué |
|---|---|
| Dominio | `StandingRow`, `StandingTable` (el *fallback* de [D-15]) y la columna PREV de [D-33] |
| `Application` | `StandingsSyncPlan` —qué jornadas y de dónde— y `IngestStandings`, la pasada |
| `Federation` | `fetchStandings(_:round:)`, su DTO y `RFFMStandingsParser` contra el volcado real |
| `Persistence` | `standing_rows` y **tres columnas más** en `ingestion_runs` |

#### Las cuatro decisiones que costaron discusión, y las cuatro las corrigió el desarrollador

**1. La fila guarda lo estructural y NO la aritmética.** Posición ≥ 1 y contadores ≥ 0, sí; `points == 3·G+E`
y `played == G+E+P`, **no**. El *spec* ya se había comprometido en `points` y la RFFM publica
`puntos_sancion`: la tabla oficial de un grupo sancionado **no cumple** la identidad. Una invariante de más
convierte *"la federación hace cuentas que no controlamos"* en una excepción que tira la clasificación entera
de la jornada. Hay un test por cada sitio donde esa decisión se puede romper —la entidad y el esquema— y una
**mutación inversa** que caza el intento de añadirla.

**2. El orden del *fallback* es [D-92], y su cuarto criterio no es deportivo.** Puntos, diferencia, goles a
favor… y el `id` del equipo, para que el orden sea **total**. Lo destapó una mutación: la primera versión
ordenaba el `Dictionary` de acumuladores, cuyo recorrido depende del proceso, así que el mismo programa con
los mismos datos podía dar dos tablas distintas en cuanto dos equipos empataran a todo — y sobre esa tabla se
calcula PREV. **Ningún rojo lo habría encontrado.**

**3. La unidad de una pasada de clasificación es la jornada, no la competición.** Lo decide el endpoint: el
calendario devuelve la competición entera en **una** petición, y `/api/standings?round=N` sirve **una**
jornada. De ahí que un alta en la jornada 10 deje **diez** filas en `ingestion_runs`, cada una con su
desenlace — y de ahí que se viera que a esa tabla **le faltaba `round_id` desde el principio**. No es un
campo nuevo: es un agujero que no se notaba mientras la única pasada posible era agnóstica de jornada.

**4. El emparejamiento va solo por identificador de federación.** De los tres pasos de la cadena de §3.7 aquí
solo cabe el primero: los otros dos comparan la clave única entera —nombre, categoría, letra, género,
modalidad ([D-77])— y una fila de clasificación no trae tres de esas cinco. Y hay una razón mejor que la
imposibilidad: **la clasificación no crea equipos** ([D-66]), así que una fila que no case no es un equipo
nuevo sino uno que el calendario aún no ha visto. Degradar a nombre ataría un *snapshot* al equipo
equivocado, y un *snapshot* no lo corrige nadie. Se descarta con `unknownStandingTeam` y la pasada siguiente
lo resuelve sola.

#### Lo que la medición cambió, que es el argumento de [D-92]

El volcado de clasificación se capturó **del mismo grupo** que el del calendario, y eso permitió comparar la
tabla calculada desde los 240 partidos contra la que publica la federación:

| | Filas que cuadran | Orden |
|---|---|---|
| Jornada 29 | **16/16** | **idéntico** |
| Jornada 30 | 14/16 | **un intercambio, puestos 12 y 13** |

El intercambio es un empate a 29 puntos con idéntico 7-8-15 donde la federación pone arriba al de **peor**
diferencia de goles, porque entre ellos ganó él. Es el **enfrentamiento directo**, que [D-55] deja fuera del
cálculo — y que hasta ahora era una salvedad escrita y ahora tiene número. **Y no es "el *fallback* está
roto"**: en la jornada 29 había otro empate a puntos que la diferencia de goles resolvió igual que el
oficial. Dos empates, uno acertado y uno no.

La comparación está **afirmada contra Postgres** en `StandingIngestionEndToEndTests`, no en una hoja aparte:
el calendario crea los 16 equipos, la clasificación casa con ellos **por id y con cero descartes**, y la
jornada 29 calculada se compara campo a campo con el volcado oficial.

#### La comprobación de mutación, y lo que enseñó del instrumento

**57 mutaciones, 57 cazadas.** Cinco sobrevivieron a la primera pasada: **una era un defecto real** —el
`Dictionary` de arriba— y cuatro eran *"falta un test"*, entre ellas dos que importan:

- **la PREV de un refresco sale del *snapshot* guardado**, que es el caso semanal —el 99% de las pasadas— y
  sin él la pantalla perdería las flechas justo en la jornada que la gente mira;
- **la pasada no medía su duración**, y con un reloj fijo un cronómetro roto pasa el test. Es exactamente el
  defecto que F6 solo encontró ejecutando el sistema contra la base de verdad, y `TickingClock` existe desde
  entonces — pero había que acordarse de usarlo.

**Y una lección nueva, que es de método y no de código: el instrumento de medir falló tres veces antes que lo
medido.** Un `$0` sin escapar en el reemplazo de `perl` hizo que una mutación no compilara y el detector lo
leyó como *"sobrevive"*; el detector comprobaba `error:` **antes** que `✘`, y como un fallo de Postgres trae
esa palabra dentro, leyó dos mutaciones **cazadas** como fallos de compilación; y un patrón que no casaba
producía un *"sobrevive"* sin haber mutado nada. Las tres dan **el mismo tipo de error que H-07**: confundir
*"no se ejecutó"* con un resultado. El guion comprueba ahora las tres cosas —que el fichero cambió, que
compila, y el `✘` antes que el `error:`—, y la regla que queda escrita es:

> **Una mutación que no compila, o que no llegó a aplicarse, no es una mutación que sobrevive.** Antes de
> creerse un *"sobrevive"*, comprobar que hubo mutación y que el programa mutado se ejecutó.

#### Los dos deberes heredados, hechos

- **[D-90] delante** (`A-5`/H-31): F7 añade **tres** migraciones y **no edita ni una línea** de las ocho que
  ya existían. Y la lección cayó dentro de la propia fase: `AddStandingsToIngestionRun` ya estaba aplicada
  contra la base de trabajo cuando se vio que faltaba `round_id`, así que `round_id` fue a una **cuarta**
  migración en vez de a la anterior. Se comprobó en `_fluent_migrations` antes de decidirlo, no de memoria.
- **El volcado antes que la firma**: el DTO del puerto se escribió **después** de capturar
  `/api/standings`, y lo medido cambió dos decisiones —qué evidencia lleva el sobre y cómo se detecta una
  coordenada que no designa nada ([Anexo RFFM §F.18])—. Es la regla de [D-74] aplicada dentro de la misma
  federación.

**394 tests** (304 → 394): 7 + 76 + 62 + 142 + 75 + 24, 0 fallos y 1 omitido —el canario—, con los dos
*targets* de BD en **6,24 s** y **2,99 s**, que es el testigo de H-07 de que corrieron.

#### Lo que F7 deja apuntado y no resuelve

**`ingestionHealth` y `lastIngestionAt` ([D-89]) se derivan de *"la última pasada de esta competición"*, y
ahora hay once por disparo.** Con dos clases de pasada, *"la última"* deja de ser una sola cosa: una
clasificación que va bien podría tapar un calendario que falla. Es una regla de **lectura** y hay que
decidirla —probablemente *"`failing` si falla cualquiera de las dos"*—; no bloquea nada hasta que el
backoffice lea esos campos de verdad.

Y la enmienda de [D-92] sigue anotada y sin aplicar: el desempate por enfrentamiento directo es **una
recursión sobre `StandingTable.upTo`**, no una regla nueva, pero sería su propia mini-fase y habría que
hacerlo **entero** —la mini-liga de N equipos, no solo el caso de dos—.

---

### 4.10 F8 · Los goleadores, y el `CHECK` que se creía vivo — **entregada** (2026-09-16)

**La entidad 23 del modelo, y la fase que cierra la salida de la ingesta.** Con `LeagueScorer` escrita, las
seis entidades que la ingesta produce tienen su tabla, su puerto y su pasada.

**Qué entrega, de abajo arriba:**

| Capa | Qué |
|---|---|
| Dominio | `LeagueScorer` y el caso `scorers` de `IngestionKind` |
| `Application` | `fetchScorers` en el puerto, sus DTOs, `LeagueScorerRepository` —el primero con `retire`— e `IngestScorers` |
| `Federation` | `RFFMScorersParser` contra **dos volcados reales nuevos** |
| `Persistence` | `league_scorers`, tres contadores más en `ingestion_runs` y **un `CHECK` rehecho** |

#### Lo que la medición cambió, que otra vez fue lo primero que se hizo

La regla de [D-74] —**el volcado antes que la firma**— se aplicó por tercera vez, y por tercera vez cobró.
`/api/scorers` **no se comporta como su vecina**:

| | `/api/standings` | `/api/scorers` |
|---|---|---|
| Parámetros | `idGroup` + `round` | `idGroup` **e** `idCompetition`, **los dos obligatorios** |
| Coordenada mala | `200` + `null` | `200` + `null` — **y también si falta uno de los dos** |
| Evidencia del sobre | `codigo_competicion`, que **no puede ser eco** | solo el **nombre**: ese código se envía |
| ¿Puede servir otra competición? | **sí** ([D-84]) | **no**: el par se valida |

Es la **única ruta medida de la RFFM donde [D-84] no ocurre**. El riesgo no desaparece —copiar *los dos*
códigos del año pasado da un par perfectamente válido— pero se estrecha; y como la respuesta **no trae ni una
fecha**, la guarda de temporada de [D-91] **no se puede aplicar aquí**: la sigue haciendo el calendario.

Y el volcado nuevo se capturó **del mismo grupo** que los de F5 y F7, lo que permitió comprobar una afirmación
que [Anexo RFFM §F.13] solo podía deducir entre grupos distintos: el `codigo_equipo` del ranking **casa 16/16**
con el del calendario. **Eso no cambia [D-09], cambia su argumento** — unir `LeagueScorer` con `Team` *se
podría*; no se hace porque no se quiere. Quien reabra la decisión tiene que discutir eso y no la imposibilidad.

De regalo, sin salir a la red: el `total` de la FCF **no es el total de goles, son partidos jugados** (0/50
filas cuadran con `goles + penalti`). Un campo que se llama como la pregunta que te haces no es la respuesta.

#### Las dos decisiones que la fase tuvo que tomar

**1. `LeagueScorer` no tenía clave ([D-93]).** Era la **única** entidad de la salida de la ingesta sin
unicidad declarada en §3.5, y mientras el ranking no se ingería no se notaba. La alternativa aparente
—`(competición, nombre, equipo)`— **la desmiente el propio *spec***, que dice en la descripción del `id` que
*"`fullName` no es identificador: dos jugadores pueden llamarse igual"*. Se añade `federation_player_id`, que
**las dos federaciones publican** y que está medido: **426/426** filas únicas y no vacías. Es [D-06] aplicado
a la séptima entidad, y **no viaja en el DTO**, igual que `synced_at`.

**2. Es la única salida de la ingesta que borra ([D-94]).** [D-75] dice que lo que la fuente deja de publicar
no se destruye, y por eso ningún otro repositorio tiene `delete`. La condición que autoriza la excepción es
*"la tabla es **estado vigente** y no histórico"*, y en toda la salida solo la cumple ésta: una fila de
clasificación es la foto de una jornada que ya pasó y sigue siendo verdad; un goleador que el proveedor dejó
de publicar es una fila **indistinguible de las buenas** dentro de una tabla que afirma ser la de hoy.

> **Al añadir la entidad 24: si tiene jornada, es histórico y no se borra.**

#### El hallazgo que nadie buscaba: **derivado no significa vivo**

[D-02] dice que el `CHECK` de un enumerado **se deriva y no se teclea**, y `sqlValueList` lo cumple. De ahí
F7 concluyó —y lo dejó escrito en `AddStandingsToIngestionRun`— que *"el caso que F8 añada lo hereda sin tocar
SQL"*. **Es falso**, y se midió antes de escribir una línea:

```
club_atleti | chk_ingestion_runs_kind
            | CHECK (kind = ANY (ARRAY['calendar'::text, 'standings'::text]))
```

La derivación ocurre **una sola vez**, cuando la migración corre; lo que queda en el *schema* es el texto de
aquel día. Es **[D-90] un piso más abajo**: `_fluent_migrations` guarda el nombre y no el contenido, así que
el caso nuevo no llega jamás a un *schema* que ya existe. Sin arreglarlo, el fallo tendría la peor forma
posible — **un alta limpia acepta la pasada y un club vivo la rechaza**, con un `23514` que nadie relaciona
con un `enum` de Swift, y solo al ejecutar. Exactamente la divergencia entre caminos que `A-5`/H-38 mide que
no debe existir.

Se arregla con una migración nueva que **rehace** la constraint (`replaceCheckConstraint`), verificada contra
la base de trabajo. Y queda escrito en tres sitios —el enumerado, la migración y el README— porque la
tentación de creer que se mantiene solo es exactamente la que produjo el defecto.

#### La comprobación de mutación, y lo que enseñó del método

**46 mutaciones, 46 cazadas.** Ocho sobrevivieron a la primera pasada, y **ninguna era "sobra el código"**:

- **Dos eran huecos de regla en el nivel 2**, y las dos importan: *"la clave del *upsert* es el nombre"* —que
  significa que una **errata corregida por la federación** duplica al goleador— y *"`createdAt` se pisa en cada
  pasada"*, que vacía de significado un campo que el *spec* publica.
- **Cuatro apuntaban todas al mismo sitio, y ése es el hallazgo de método: F8 se había saltado su suite de
  nivel 3.** El `UNIQUE` de [D-93] y las dos mitades del `WHERE` de la retirada **solo existen en el esquema**,
  y el doble en memoria hace *upsert* por `id`, así que con él la clave de negocio sencillamente no existe.
  Quitar el índice de la migración no rompía **ni un test**. La mutación no encontró un defecto: **encontró un
  agujero en la pirámide** — F7 tiene `StandingPersistenceTests` y F8 no tenía su equivalente.

> **La lectura que se añade a las de F2, F5 y F7:** cuando **varias** mutaciones supervivientes caen en la
> misma capa, no son N tests que faltan — es **un nivel de la pirámide que falta**. Conviene mirar el patrón
> antes de escribir el primer test.

Y el guion de mutación llevaba desde el principio los **tres frenos** que F7 tuvo que aprender a base de leer
mal el instrumento: comprobar que el fichero **cambió**, que **compila**, y mirar el `✘` **antes** que el
`error:`. Esta vez ninguna lectura fue falsa.

#### Una regla que un test corrigió, y no al revés

`retire` era `syncedBefore:` con un `<`, que se lee igual de bien y **es frágil**: hace depender la regla de
la resolución del reloj. Dos pasadas en el mismo instante —un reintento rápido— no retirarían nada. Lo destapó
el test de la retirada, que con `TickingClock` compartía instante entre las dos pasadas. Pasa a ser
**`keepingMark:`** —*"lo que esta pasada no ha tocado"*—, que es exacto. **Y el test también estaba mal**: la
cadencia real de §5.6 es semanal, no simultánea, así que la segunda pasada corre con el reloj de la semana
siguiente. Se arreglaron los dos.

#### Lo ejecutado contra la base de trabajo, que es lo que la batería no ve

La lección de F6 —*"al añadir algo a `IngestionRun`, ejecutarlo y mirar la tabla"*— aplicada:

| Competición | Creados | Retirados | Duración |
|---|---|---|---|
| PRIMERA INFANTIL | 208 | 0 | **1,241 s** |
| PRIMERA DIVISION AUTONOMICA CADETE | 218 | 0 | **1,534 s** |

Segunda pasada: **0 creados, 218 actualizados, 218 filas** — el *upsert* contra el `UNIQUE` de verdad. Y con
una fila rancia sembrada a mano: **218 actualizados, 1 retirado**, y las 208 de la otra competición intactas.
La duración **se mide y no sale cero**: el defecto de F6 no ha vuelto.

**446 tests** (394 → 446): 7 + 90 + 79 + 152 + 94 + 24, 0 fallos y 1 omitido —el canario—, con los dos
*targets* de BD en **6,76 s** y **3,98 s**, que es el testigo de H-07 de que corrieron.

#### Lo que F8 deja apuntado y no resuelve

- **`ingestionHealth` ([D-89]) tiene ahora tres clases de pasada que reconciliar**, no dos. F7 ya lo dejó
  anotado; con `scorers` la regla de lectura *"la última pasada de esta competición"* es aún menos una sola
  cosa. Sigue sin bloquear nada hasta que el backoffice lea esos campos.
- **`GET /v1/league-scorers` sigue sin implementarse**, y es deliberado: F8 es la ingesta, como F7. El
  `filter` del generador no se toca.
- **Tres cosas de `/api/scorers` sin observar** ([Anexo RFFM §F.19]): qué devuelve un grupo sin goles todavía
  —si fuera `null`, sería indistinguible de una coordenada mala—, dos jugadores homónimos en el mismo equipo
  (0 en 426 filas, así que [D-93] está argumentada pero no exhibida), y si la lista tiene tope, que en la FCF
  huele a *top-50*.

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
- **Montar el *workflow* de integración continua** (`A-7`, H-07 y H-49), y **va con el punto de arriba**: son
  la misma decisión de despliegue y el canario necesita lo mismo que el cron, un disparo programado y fuera de
  la batería (§5.5 del README). Hoy **no hay CI**, y el mecanismo que debía impedir un verde falso está
  escrito y desconectado: la guarda de `DatabaseAvailability` falla con `CI` o `REQUIRE_DB` definidas, y nadie
  las define. Mientras no exista, **lo único que separa *"probado"* de *"no probado"* es la disciplina de
  correr `REQUIRE_DB=1 swift test` y mirar el reloj** — porque el texto de la salida es idéntico en los dos
  casos, medido. La propuesta está entera en §7 del plan de auditoría, con sus cuatro pasos comprobados; lo
  que falta es decidir cuándo.
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
[D-90]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[Anexo RFFM §F.16]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.17]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[D-91]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
