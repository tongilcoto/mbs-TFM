# Plan de desarrollo R2 · Alta de equipo

> Rebanada 2 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Como la
> [rebanada 1](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md), toca la web y el servidor, y lo que se haga
> en el servidor se apunta **solo aquí**, también la mini-fase.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md); y la rebanada 1, cerrada el
> 2026-10-20 con 682 tests en el backend y, en la web, 80 pruebas de piezas y 35 escenarios. Antes de esta
> rebanada se revisó la tabla de equipos (`D-104`, el rival es de una temporada; `D-105`, la jornada de descanso):
> 682 → **697 tests** en el backend. Y se decidió cómo nace una temporada sin código de la federación (`D-106`).
>
> **Convención de remisiones**, la misma de la rebanada 1: `LLD-B §x` y `DW-nn` son el LLD de la web y su anexo;
> `LLD §x` y `D-nn`, el LLD del backend y su bitácora.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: borrador, 2026-10-23.** El flujo (§1 y §3) está colocado con el desarrollador, y la
> decisión 1 es `D-106`, ya grabada. **Las decisiones 2 a 6 son propuestas** y se revisan una a una antes de
> construir; las secciones 2, 3, 5 y 7 se corrigen con lo que se acuerde.

---

## 1. Objetivo

**El club puede dar de alta un equipo desde la web**, inscrito en una temporada que ya existe o en una que crea
en ese momento. Es lo que hace el club en julio, cuando forma los equipos de la temporada siguiente y la
federación todavía no ha publicado nada.

El alta tiene **dos pasos**, y esta rebanada hace el primero:

1. **El formulario** da de alta el equipo en una temporada. Sin ningún dato de la federación (`D-66`).
2. **El enganche**: cuando hay calendario, una acción sobre el equipo pide la dirección del calendario de la
   federación. Es la rebanada 3.

**Por qué ahora** (plan del backoffice, §4): es la primera escritura de la web, y sin ella un club nuevo no
puede empezar: la portada vacía dice «Todavía no hay ninguna temporada» y no ofrece salida
([Plan R1, decisión 6](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md)).

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **En la portada, el botón «Dar de alta un equipo»**, junto al selector de temporada, y también en los dos mensajes de la portada vacía | Ficha, §3.1 · decisión 6 |
| **El formulario de alta** (`/equipos/nuevo`): categoría, letra, género, modalidad y temporada, con la comprobación de todos los campos a la vez antes de enviar | Ficha, §3.2 · LLD-B §5 · decisiones 2 y 3 |
| **«Crear nueva temporada»**, desde el selector del formulario: el mismo camino para la primera temporada del club y para las siguientes | Ficha, §3.3 · `D-106` · decisión 4 |
| **La vuelta a la portada** en la temporada del equipo creado, con el aviso «Guardado» | Ficha, §3.4 · decisión 5 |
| **Los mensajes de los errores nuevos**, y el aviso de «cambios sin guardar» al salir del formulario | LLD-B §4.3, §5.5 · decisión 6 |
| En el servidor, **la temporada sin código** (`D-106`) y **dos operaciones nuevas**: `createSeason` y `createTeam`. Con ellas, el servidor sirve **11 de las 85** | §5 |

**Lo que no trae** (llega después): el enganche desde la web (rebanada 3); corregir o borrar un equipo
(rebanada 13); y la gestión de temporadas: corregir, archivar o borrar una creada por error (rebanada 11).

---

## 3. La ficha de las pantallas

### 3.1 La portada, con el botón

- **«Dar de alta un equipo»**, con texto y no solo un «+», junto al selector de temporada (LLD-B §10.1: lo que
  hace un botón se lee). Lleva a `/equipos/nuevo`.
- **En la portada vacía** (Plan R1, decisión 6) el mismo botón, debajo del mensaje:

| Caso | Mensaje | Debajo |
|---|---|---|
| El club no tiene ninguna temporada | «Todavía no hay ninguna temporada.» | «Para empezar, da de alta el primer equipo. La temporada se crea desde el mismo formulario.» y el botón |
| La temporada elegida no tiene equipos | «No hay equipos en la temporada 2025/26.» | El botón |

### 3.2 El formulario de alta (`/equipos/nuevo`)

**Qué pide al servidor al abrir**: `listSeasons`, para el selector. Nada más: categoría, género y modalidad son
listas cerradas del catálogo, y la web ya las tiene (`schema.d.ts`).

**Los campos**, cada uno con la pieza que le corresponde (LLD-B §5.2) y con asterisco si es obligatorio:

| Campo | Pieza | Obligatorio | De dónde sale |
|---|---|---|---|
| **Categoría** | Selector, de menor a mayor edad | Sí | `TeamCategory` |
| **Letra** | Texto corto, con la ayuda «Si el club tiene varios equipos de la misma categoría: A, B…» | No | — |
| **Género** | Selector | Sí | `Gender` |
| **Modalidad** | Selector | Sí | `Modality` |
| **Temporada** | Selector, de la más reciente a la más antigua, y al final «Crear nueva temporada…» (§3.3) | Sí | `listSeasons` |

- **Qué temporada viene elegida** (decisión 5): la que enseñaba la portada al pulsar el botón. Si el club no
  tiene ninguna, el selector está vacío y solo ofrece «Crear nueva temporada…».
- **Al pulsar *Guardar***: la web comprueba todos los campos contra `CreateTeamRequest` y marca **todos** los que
  fallan a la vez (LLD-B §5.1). Si todo está bien, envía `createTeam`, y mientras tanto el botón se bloquea
  (LLD-B §3.3).
- **Si el servidor rechaza**: el error junto a su campo si es de un campo, y si no, en un aviso arriba del
  formulario, sin borrar lo escrito (LLD-B §4.3). Los mensajes, en la decisión 6.
- **Salir con cambios sin guardar** pregunta antes (LLD-B §5.5). Es el primer formulario de la web, así que el
  aviso se estrena aquí.
- **«Cancelar»** vuelve a la portada, en la temporada de la que se vino.

**Los cuatro estados** (LLD-B §3.1):

| Estado | Cómo se ve |
|---|---|
| **Cargando** | «Cargando temporadas…» en el sitio del selector; el resto del formulario ya se puede rellenar |
| **Error** | El mensaje del código en el sitio del selector, con *Reintentar* si el fallo puede ser pasajero (LLD-B §4.4) |
| **Vacío** | El club sin temporadas: el selector solo ofrece «Crear nueva temporada…» |
| **Con datos** | El formulario entero |

### 3.3 «Crear nueva temporada» (decisión 4)

- **Se abre un diálogo** encima del formulario, con un solo campo: **Temporada**, con la ayuda «Por ejemplo,
  2026/27».
- **Al pulsar *Crear***: la web comprueba el formato con el `pattern` del catálogo (decisión 2) y envía
  `createSeason` solo con la etiqueta, sin código de la federación (`D-106`).
- **Si va bien**, el diálogo se cierra, la temporada nueva entra en el selector y queda elegida. El formulario
  del equipo **no se ha enviado todavía**: lo que el usuario había rellenado sigue ahí.
- **Si falla**, el error se enseña dentro del diálogo: junto al campo si es de la etiqueta, y si no, arriba.
- **«Cancelar»** cierra el diálogo sin crear nada, y el selector vuelve a la temporada que tenía.

### 3.4 Al guardar bien

- Sale el aviso breve **«Guardado»** (LLD-B §5.4).
- La web vuelve a la portada **en la temporada en la que se ha inscrito el equipo** (`/?temporada=2026-27`), no
  en la de la que se vino (decisión 5). El equipo sale en la tabla con «Sin competición» y el texto «Se engancha
  con la federación desde la ficha del equipo», como cualquier equipo de junio (Plan R1, §3.2).

---

## 4. Decisiones antes de construir

### Decisión 1 · La temporada sin código de la federación (`D-106`)

**Decidido y grabado** (`a9eea44`, 2026-10-23). En resumen:

- `seasons.federation_season_id` pasa a admitir vacío, y el código sigue sin poder repetirse.
- `createSeason` se programa en esta rebanada, y recibe la etiqueta y, si la hay, el código.
- El enganche y su `/preview` buscan la temporada **primero por el código y después por la etiqueta**; si la
  encuentran sin código, el enganche se lo pone.
- Si la temporada de esa etiqueta ya tiene **otro** código: **409 `SEASON_ALREADY_LINKED`**.
- La etiqueta de la federación la traduce **su conector**, nunca el catálogo. La guarda de fechas de `D-91` sigue
  siendo la red.

Lo que eso pide al servidor está en la §5. El texto entero, en [D-106](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md).

### Decisión 2 · Las reglas del formulario salen del catálogo; el servidor tiene la última palabra

**Propuesta.** Lo que dice el LLD-B §5.1 y `DW-07`, sin cambios: Ajv comprueba lo rellenado contra la descripción
del catálogo (`CreateTeamRequest` y `CreateSeasonRequest`), y la web escribe a mano solo el texto de cada tipo de
regla, en una tabla de unas seis entradas.

- **La etiqueta de la temporada** se comprueba con el `pattern` del catálogo (`^\d{4}/\d{2}$`), que es la misma
  regla con la que el servidor la rechaza en su puerta. El mensaje de un `pattern` es «El formato no es válido»,
  y la ayuda del campo pone el ejemplo.
- **Que el segundo año sea el siguiente** («2026/28» no vale) solo lo sabe el servidor, en el Dominio: llega como
  `INVALID_VALUE` con `label: …` en el `detail`, y la web lo enseña junto al campo (LLD-B §4.5 *a*).
- **Que ya exista** un equipo igual o una temporada con esa etiqueta, también solo el servidor (decisión 6).

### Decisión 3 · Cómo llega el catálogo a la web

**Lo que falta por decidir.** `DW-07` dice que Ajv lee el catálogo, pero no **cómo llega** a la web: la web no
puede leer `openapi.yaml` del disco del servidor al abrirse.

**Propuesta.** Igual que las descripciones de los datos: **se saca del catálogo al preparar la web**, no al
abrirla. `npm run gen:api`, que ya genera `schema.d.ts`, genera también un `src/api/schemas.json` con los
esquemas de `components/schemas`, y sin guardarlo en git, como `schema.d.ts`. Ajv lo lee de ahí. Así el catálogo
sigue siendo la única fuente, y la web nunca valida contra uno distinto del de los tipos con los que compiló.

**Se entra con una dependencia nueva**: Ajv (y su complemento de formatos, para `format: uuid`). Va en el commit
de su paso, y en el README de la web.

### Decisión 4 · «Crear nueva temporada» es un diálogo que guarda por su cuenta

**Propuesta.** El diálogo de la §3.3 **crea la temporada al pulsar *Crear***, antes de guardar el equipo. Dos
peticiones, cada una con su botón y sus errores.

| Opción | Qué pasa si algo falla | Veredicto |
|---|---|---|
| **(a) Diálogo que crea la temporada al momento** | Cada error sale en su sitio: el de la etiqueta en el diálogo, el del equipo en el formulario | **Propuesta** |
| (b) Un campo de texto en el mismo formulario, y al guardar se envían las dos | Si la temporada se crea y el equipo falla (por ejemplo, porque ya existe), queda una temporada creada y un formulario con error, y el usuario no sabe si tiene que volver a crearla | Descartada |

**Lo que se asume a cambio**: si el usuario crea la temporada y luego cancela el alta, la temporada se queda. Es
lo que `D-106` ya acepta («una temporada creada por error se queda»), y saldrá en el selector de la portada sin
equipos, con su mensaje.

### Decisión 5 · Qué temporada viene elegida, y a cuál se vuelve

**Propuesta.**

- **Al abrir el formulario**, el selector viene con la temporada que enseñaba la portada. Se le pasa **sin
  ponerla en la dirección**: `/equipos/nuevo` es siempre el mismo camino, y recargarlo deja el selector en la
  temporada en curso, o en la más reciente si no hay ninguna en curso (la regla de la portada, Plan R1,
  decisión 5).
- **Al guardar**, la vuelta es a la temporada **del equipo creado**, que puede no ser la de partida: es la que
  el usuario acaba de elegir, y donde quiere ver el equipo nuevo.
- **Al cancelar**, a la de partida.

### Decisión 6 · Los errores nuevos, y qué dice la web en cada uno

**Lo que falta.** La lista cerrada de códigos (`ProblemCode`, 32) **no tiene ninguno para «ya existe»**: hasta
ahora el servidor no daba de alta nada que el usuario escribiera. Sin código propio, un duplicado volvería como
el `23505` de Postgres dentro de un 500, como pasó con `FEDERATION_TEAM_ID_TAKEN` en F10.

**Propuesta: tres códigos nuevos**, 32 → **35**:

| Código | Operación | Cuándo | Qué dice la web | Dónde |
|---|---|---|---|---|
| `TEAM_ALREADY_EXISTS` (409) | `createTeam` | Ya hay un equipo del club con esa categoría, letra, género y modalidad | «Ya existe un equipo con esa categoría, letra, género y modalidad.» | Aviso arriba del formulario |
| `SEASON_ALREADY_EXISTS` (409) | `createSeason` | Ya hay una temporada con esa etiqueta, o con ese código | «Ya existe la temporada 2026/27. Elígela en el selector.» | Dentro del diálogo, junto al campo |
| `SEASON_ALREADY_LINKED` (409) | enganche y `/preview` | `D-106`, punto 4 | Su mensaje se escribe ya, porque `errors.ts` exige uno para cada código; se enseña en la rebanada 3 | — |

Y los que ya existen y estas pantallas pueden recibir: `SEASON_NOT_FOUND` (404: la temporada elegida se ha
borrado entre que se abrió el formulario y se guardó), `INVALID_VALUE` (422, junto a su campo) y los de conexión,
con *Reintentar* (LLD-B §4.4).

**Una temporada sin equipos que ya existe**, que es el caso más probable de `SEASON_ALREADY_EXISTS` desde la web
(se creó, se canceló el alta, y se intenta crear otra vez), no puede pasar desde el diálogo si el selector está
al día: la temporada ya sale en él. Puede pasar si otra persona la creó a la vez (LLD-B §5.6).

---

## 5. Lo que le falta al servidor

Todo con el método del backend: prueba → esqueleto que devuelve mal a propósito → rojo de aserción →
implementación → mutación con `Tools/Mutate`. Y `REQUIRE_DB=1 swift test`, nunca `swift test` a secas. Las
migraciones, siempre nuevas, nunca editando una que ya existe (`D-90`).

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **El catálogo**: `CreateSeasonRequest.federationSeasonId` opcional; `SeasonResponse.federationSeasonId` puede ser `null`; las descripciones de `createSeason`, de su 409 y de `PreviewSeason.exists` (que también vale `true` cuando la temporada se encuentra por etiqueta); el 409 del enganche y de su `/preview`; y los tres códigos nuevos | `openapi.yaml` | **Sí**: cambia el catálogo | 1, 6 |
| **La temporada sin código**: una migración nueva que quita el «obligatorio» de `federation_season_id` (el `UNIQUE` se queda); `Season.federationSeasonID` pasa a opcional en el Dominio; y la ingesta, si encuentra una competición cuya temporada no tiene código, falla esa pasada con un error claro en vez de llamar a la federación sin él (`D-106`, punto 7) | Dominio, Persistencia, Aplicación | Va con el catálogo: la respuesta cambia de forma | 1 |
| **`createSeason`**: etiqueta y, si la hay, código; fechas derivadas de la etiqueta; 409 `SEASON_ALREADY_EXISTS` si la etiqueta o el código ya existen, **comprobado antes de escribir**, no esperando al `23505` | Las cuatro | No, con el catálogo ya cambiado | 1, 6 |
| **El enganche y su `/preview` buscan la temporada en dos pasos**: por código y, si no, por etiqueta. El repositorio de temporadas gana la lectura por etiqueta. El enganche pone el código a la temporada que no lo tiene; el `/preview` no escribe. 409 `SEASON_ALREADY_LINKED` si la de esa etiqueta tiene otro | Aplicación, Persistencia, HTTP | No | 1 |
| **`createTeam`**: el equipo propio, sin código, inscrito en la temporada que se indica (`D-68`); 404 si la temporada no existe; 409 `TEAM_ALREADY_EXISTS` si ya hay uno igual, comprobado antes de escribir | Las cuatro | No | 6 |

**Lo que ya está y se reutiliza**: el repositorio de temporadas (`SeasonRepository`), que ya guarda; el de
equipos y el de inscripciones, que ya guardan desde el enganche; y la regla de la etiqueta (`SeasonLabel`, con
las fechas del 1 de julio al 30 de junio). **`createTeam` y `createSeason` están en el catálogo y sin
programar**: se activan añadiéndolos al filtro de `openapi-generator-config.yaml`.

**Los permisos**: el catálogo dice que `createTeam` requiere rol elevado (§7.3). Como el resto de operaciones
hasta la rebanada 16, no se comprueba todavía: no hay inicio de sesión.

**Al pasar el censo** con las dos operaciones activadas, los campos y los códigos nuevos sin nombrar en ningún
test se escriben o se apuntan en `known-gaps.json` con su motivo.

**Al terminar**, el servidor sirve **11 de las 85** operaciones.

---

## 6. Los escenarios

**Lista provisional.** Los `.feature` se escriben al final (R2.15), con la *skill* de escenarios del
desarrollador, y **los que valen son ellos**. Al final de cada escenario, axe en los dos modos.

**El botón** (§3.1)

- La portada con equipos tiene el botón, y lleva al formulario.
- El club sin temporadas: el mensaje, su explicación y el botón.
- La temporada sin equipos: el mensaje y el botón.

**El alta** (§3.2, §3.4)

- Dar de alta un equipo en una temporada que ya existe: vuelve a la portada en esa temporada, con «Guardado»,
  y el equipo sale con «Sin competición».
- El formulario abre con la temporada que enseñaba la portada.
- Dar de alta un equipo en una temporada que no es la de partida: la portada vuelve en la del equipo.
- Enviar sin categoría ni temporada: los dos campos marcados a la vez, y el foco en la lista de errores (LLD-B
  §10.7).
- Un equipo que ya existe: el aviso arriba del formulario, y lo escrito sigue ahí.
- Dar de alta un equipo solo con el teclado (LLD-B §10.7).
- Salir con cambios sin guardar pregunta antes; «Cancelar» sin cambios vuelve sin preguntar.

**La temporada nueva** (§3.3)

- Club vacío: crear la primera temporada desde el diálogo, dar de alta el equipo, y la portada ya tiene selector.
- Club con temporadas: crear la siguiente, que queda elegida en el selector.
- Etiqueta con mal formato («2026-27»): el error del catálogo junto al campo, sin llegar al servidor.
- Etiqueta con años que no siguen («2026/28»): el error del servidor junto al campo.
- Una etiqueta que ya existe: su mensaje en el diálogo.
- Cancelar el diálogo deja el selector como estaba.

**El enganche de una temporada sin código** (decisión 1). En la rebanada 3 tendrá su pantalla; aquí se prueba en
el servidor, con los tests de la §5. Los escenarios de la web llegan con la pantalla del enganche.

---

## 7. Los pasos

Cada paso dice qué se hace, cómo se comprueba y qué se graba. **Al acabar cada uno se para** y se espera el visto
bueno del desarrollador antes del siguiente, y su renglón va en la §8. Cada paso deja el árbol en verde por sí
solo, y lo que no venga en el plan va en su propio commit.

### A · Los documentos de las decisiones

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.1** | `D-106` en la bitácora, con sus notas «Enmendado por» en `D-67` y `D-68` | El desarrollador lo revisa | Un commit |
| **R2.2** | Este plan, y las decisiones 2 a 6 revisadas una a una | El desarrollador lo revisa | Un commit, y otro por cada corrección |
| **R2.3** | El LLD del backend (§3.2, §3.5 y §3.7: el código de la temporada puede faltar; §5.1: `createSeason` y la búsqueda por etiqueta del enganche). El LLD-B: §6.1 con `/equipos/nuevo` confirmado, y `DW-07` con la decisión 3. Y el plan del backoffice: `createSeason` se adelanta de la rebanada 11 a la 2, con lo «pendiente de confirmar» resuelto | El desarrollador lo revisa | Un commit para el backend y otro para la web (LLD-B §E.1) |

### B · El catálogo (la mini-fase)

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.4** | `openapi.yaml`: lo de la primera fila de la §5. Y en el mismo paso, los tres mensajes nuevos de `errors.ts`, porque sin ellos la web no compila | `npx @redocly/cli lint`, `swift build`, `REQUIRE_DB=1 swift test` sin cambios en el recuento, los tipos de la web regenerados y `npm run build` en verde. El censo, con los tres códigos que todavía nadie emite | Un commit |

### C · El servidor

Con el método del backend (§5).

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.5** | **La temporada sin código**: la migración, el Dominio, la Persistencia, la respuesta de `listSeasons` con `null`, y el error claro de la ingesta | Tests de los niveles que toque, el test de migraciones con la nueva, mutación con su catálogo; y la migración pasada a la base de trabajo **por el desarrollador** | Un commit |
| **R2.6** | `createSeason` | Tests, mutación y `curl` contra la base de trabajo, con un servidor aparte en el 8799 | Un commit |
| **R2.7** | **El enganche busca la temporada por etiqueta**, en el enganche y en su `/preview`, con `SEASON_ALREADY_LINKED` | Tests de los dos caminos y de los tres casos (por código, por etiqueta sin código, por etiqueta con otro código), mutación; y un enganche de verdad contra la RFFM sobre una temporada creada con `curl` | Un commit |
| **R2.8** | `createTeam` | Tests, mutación y `curl` | Un commit |
| **R2.9** | Cierre del servidor: el recuento leído del XML, el censo con las dos operaciones, los catálogos de mutación de la rebanada pasados otra vez sobre el código final, y el README del backend | `REQUIRE_DB=1 swift test --xunit-output`, el censo con salida `0` | Un commit |

### D · La web

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.10** | **Las reglas del catálogo en la web**: `gen:api` saca los esquemas (decisión 3), Ajv los lee, y la tabla de mensajes por tipo de regla. Y la lectura del `detail` con formato `<campo>: <motivo>` (LLD-B §4.5 *a*) | Vitest: cada tipo de regla con su mensaje, `CreateTeamRequest` vacío nombra sus campos obligatorios, y un `detail` sin formato va al aviso de arriba | Un commit |
| **R2.11** | **El formulario** (`/equipos/nuevo`): los campos, el selector de temporada, sus cuatro estados, los errores en su sitio y el aviso de cambios sin guardar | Vitest, y la web abierta contra el servidor del desarrollador | Un commit |
| **R2.12** | **«Crear nueva temporada»**: el diálogo, su comprobación, sus errores y la temporada nueva elegida en el selector | Vitest, y la web abierta | Un commit |
| **R2.13** | **La portada**: el botón, el botón en los dos vacíos, y la vuelta a la temporada del equipo creado con «Guardado» | Vitest, y la web abierta con el club del desarrollador | Un commit |

### E · Los escenarios y el cierre

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.14** | Los datos de los escenarios: el club vacío y el club con temporadas, por la aplicación (LLD-B §11.3) | Un escenario que los use | Un commit |
| **R2.15** | Los `.feature` de la §6, con la *skill* de escenarios del desarrollador | `npm run e2e` en verde, con axe en los dos modos; y la revisión a mano del LLD-B §10.7 *b* | Un commit |
| **R2.16** | Cierre: los cinco pasos de `AGENTS.md` («Al cerrar una fase»), el README de la web y lo aprendido | Las cifras buscadas por su número viejo en todo el árbol | Un commit |

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| **R2.1** | ✅ 2026-10-23 (`a9eea44`) | `D-106` en la bitácora, con su fila en el índice, su enlace y las notas «Enmendado por [D-106]» en el paso 1 de la cascada de `D-67` y en la consecuencia 2 de `D-68`. Revisado por el desarrollador |
| **R2.2** | | |
| **R2.3** | | |
| **R2.4** | | |
| **R2.5** | | |
| **R2.6** | | |
| **R2.7** | | |
| **R2.8** | | |
| **R2.9** | | |
| **R2.10** | | |
| **R2.11** | | |
| **R2.12** | | |
| **R2.13** | | |
| **R2.14** | | |
| **R2.15** | | |
| **R2.16** | | |

## 9. Lo aprendido

Se escribe al cerrar la rebanada (R2.16).
