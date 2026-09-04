# Plan de auditoría-001 · El backend antes de F7

> Abierto el **2026-09-03**, con **F0–F6 entregadas** y **266 tests en verde**.
>
> Convención, la misma del resto del proyecto: **`§x` remite al [LLD-001](../docs/API_y_BBDD%20LLD-001.md)**,
> `D-nn` a la [bitácora de decisiones](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md), y `Plan §x`
> al [Plan de desarrollo-001](../docs/Plan%20de%20desarrollo-001.md). Las remisiones a **este** fichero van
> como `A-n` (bloque) o `H-nn` (hallazgo).
>
> **Este fichero es plan y libro a la vez**: los bloques de §5 se ejecutan de uno en uno y cada uno escribe
> su resultado en §6, aunque el resultado sea *"nada"*. Un bloque sin renglón en §6 **no está hecho**.

---

## 0. Qué es esto, y sobre todo qué no

**No es una caza de bugs.** La premisa de partida es que el código funciona: 266 tests pasan, los cuatro
niveles de §8.1 están poblados, y las dos reglas delicadas del diseño —la política de *upsert* (F3) y la
cadena de emparejamiento (F4)— llegaron con comprobación de mutación de 11/11 y 16/16. Un *bug* en este
estado es barato: se arregla donde está y no arrastra nada.

Lo que se audita es otra cosa: **las decisiones que ya están tomadas y sobre las que F7–F10 se van a
apoyar**. Un *bug* cuesta una sesión; una costura mal puesta cuesta rehacer lo que se construyó encima. De
ahí el criterio que ordena todo este plan, y el único que decide qué va antes:

> **Coste de descubrirlo tarde**, no gravedad, no tamaño, no en qué capa vive.

El momento es el que es porque quedan cuatro fases y **dos de ellas amplían cosas que ya existen** en vez de
añadir cosas nuevas: F7 y F8 le **añaden métodos al puerto de federación** que F2 diseñó, y F10 escribe **los
primeros endpoints** desde F0 sobre la costura de actor que F0 dejó a medias. Ahí es donde un error de base se
copia en vez de descubrirse.

**El tamaño de lo que se audita**, para calibrar el esfuerzo: ~8.760 líneas en `Sources/` (de las que 428 son
`TestSupport`) y ~7.620 en `Tests/`. Nueve *targets*, nueve migraciones, cuatro operaciones HTTP generadas de
las ~100 del *spec*.

---

## 1. La premisa está escrita para poder ser falsa

El plan supone que los problemas existentes **no son grandes** y que el código está bien *"al 80%"*. Eso es
una hipótesis, no un dato, y los dos primeros bloques la miden. La regla:

> Si **A-0** y **A-1** juntos producen **más de dos hallazgos S1**, este documento deja de ser una auditoría y
> se convierte en una **fase de reparación previa a F7**, con su entrada en el Plan de desarrollo. No se sigue
> auditando encima de un cimiento que ya se sabe torcido.

Es la lección de `D-84` aplicada al propio proyecto: *una premisa no se hereda, se mide* — y la premisa
*"esto está bien"* es una premisa como cualquier otra.

---

## 2. Cómo se mide un hallazgo

La severidad **no** es susto ni tamaño: es **qué cuesta arreglarlo si se arregla después**.

| | Severidad | Qué significa | Cuándo se arregla |
|---|---|---|---|
| **S1** | **Cimiento** | Arreglarlo después obliga a **rehacer código ya entregado** | **Antes de seguir con F7** |
| **S2** | **Coste creciente** | Cuesta en proporción a lo que se haya construido encima | En la fase que lo toque, y se apunta cuál |
| **S3** | **Local** | Se arregla donde está, sin arrastrar nada | Cuando se pase por ahí |
| **S4** | **Nota** | Cierto, comprobado, y no hay que hacer nada hoy | Nunca; queda escrito para que no se vuelva a descubrir |

Un hallazgo **S4 no es un hallazgo fallido**. La mitad del valor de este ejercicio es convertir *"creo que
esto está bien"* en *"esto está comprobado y aquí está cómo"*, que es exactamente lo que `D-84` demostró que
faltaba cuando una premisa de F2 sobrevivió tres fases siendo falsa.

---

## 3. Las reglas del juego

Cinco, y las cinco salen de métodos que este proyecto ya usa:

1. **Un hallazgo sin reproducción no es un hallazgo.** Va con el comando, el `curl`, el test o la consulta
   que lo enseña. Si no se puede reproducir, se escribe como *sospecha* y se dice que lo es. (`D-84`: una
   premisa sobre un sistema ajeno **se mide**; una sobre el propio código, también.)
2. **El arreglo no va en la misma sesión que el hallazgo**, salvo que sea S3 trivial. Auditar y reparar a la
   vez es cómo una auditoría se convierte en un refactor sin control.
3. **Todo arreglo entra por el bucle de Plan §5.1**: el test primero, con esqueleto, y el rojo tiene que ser
   **de aserción y no de compilación**. Un arreglo de auditoría sin test es un hallazgo que volverá.
4. **Si el código y el diseño discrepan, el hallazgo dice cuál de los dos está mal.** No siempre es el
   código: `D-84` y `D-74` son dos casos en que el documento era el equivocado. Y si el que cambia es el
   documento, va a la bitácora como entrada `D-nn` nueva o enmienda, según la tabla de *"dónde va cada cosa"*
   de `AGENTS.md`.
5. **La auditoría no amplía el alcance.** No añade endpoints, ni entidades, ni entra en el `filter` de
   `openapi-generator-config.yaml` (`D-69`). Lo que descubra que falta, lo apunta para su fase.

---

## 4. El orden, y por qué es ése

| Bloque | La pregunta que contesta | Bloquea a | Coste |
|---|---|---|---|
| **A-0** | ¿Los documentos que voy a usar de vara de medir dicen la verdad? | *(a todo)* | ½ sesión |
| **A-1** | ¿El puerto de federación abstrae **una federación** o abstrae **la RFFM**? | **F7, F8, F9** | 1 sesión |
| **A-2** | La regla que destruye datos, ¿es la que corre de verdad contra Postgres? | **F7** | 1 sesión |
| **A-3** | La atomicidad y la constancia del fallo, ¿aguantan un fallo que no sea el que se probó? | F7 | 1 sesión |
| **A-4** | La ruta de producción del `202`, ¿la ejercita algo? | **F10** | ½ sesión |
| **A-5** | ¿`--revert` deshace de verdad, y dos tenants migrados por caminos distintos quedan iguales? | **F7, F8, F10** | 1 sesión |
| **A-6** | Las costuras de §7, ¿están puestas, para no rehacer los *handlers*? | **F10** | 1 sesión |
| **A-7** | Hoy, ¿qué significa "verde"? | *(a todo)* | ½ sesión |

**Seis sesiones y media**, de una en una y en cualquier hueco: ningún bloque necesita a otro terminado, salvo
que **A-0 va primero**.

**Por qué A-1 va antes que todo lo demás sustantivo.** F7 y F8 no estrenan puerto: **le añaden un método al
que ya existe** (`fetchStandings`, `fetchScorers`). Si la forma de `FederationClient` lleva incrustado un
supuesto de la RFFM, ese supuesto **no se descubre en F9** —donde llega la segunda implementación— sino que
se habrá copiado ya dos veces más, con sus dobles y sus tests. Es el error clásico de la abstracción validada
contra un solo caso, y este proyecto tiene el aviso escrito en su propia bitácora: `D-74`, la premisa sobre la
FCF que resultó falsa después de tres fases.

**Por qué A-0 va antes de A-1.** Porque Plan §9 dice que *"los tests son la especificación revisable"* y el
LLD es contra lo que se revisan. Auditar contra un documento a la deriva es medir con una vara torcida — y ya
hay prueba de que la deriva existe: ver **H-01**.

---

## 4-bis. Cómo se arranca una sesión de auditoría

**Un bloque, una sesión, y el contexto se tira al terminar.** Por eso cada bloque de §5 es autocontenido: su
pregunta, sus ficheros, su criterio y su renglón en §6. Lo que la sesión deja escrito es el hallazgo; lo que
leyó para encontrarlo, no hace falta conservarlo.

**El coste de una sesión nueva no es el bloque: es ponerse al día.** `AGENTS.md` son 409 líneas, el
`README.md` 899 y el LLD 2.790. Una sesión que los lea todos llega al bloque con el contexto medio gastado y
sin haber mirado una línea de código. De ahí que cada bloque de §5 lleve su **«Leer antes»**: lo mínimo, con
la sección concreta, **y nada más**. Lo que no esté en esa lista se lee **solo si el bloque lo pide** — y si
hace falta y no estaba, se añade a la lista al cerrar el bloque, que es información para el siguiente.

### La base común, igual para todos los bloques

| Qué | Por qué |
|---|---|
| **Este fichero, §0 a §4 y §6** | El encuadre, la escala de severidad, las reglas del juego y lo ya encontrado |
| `AGENTS.md`, solo la sección **«El backend: cómo está montado y cómo se trabaja»** | El grafo de capas, la tabla de *targets* y los comandos. Es el mapa; el resto de `AGENTS.md` es historia de las fases |

Eso es ~150 líneas. Lo demás lo pone el «Leer antes» del bloque.

### La plantilla del prompt de entrada

```
Ejecuta el bloque A-n del plan de auditoría en `backend/Plan de auditoría-001.md`.

Lee primero la base común de §4-bis y el «Leer antes» de tu bloque. No leas el
resto del LLD ni del README salvo que el bloque lo pida.

Tres límites:
  1. Audita SOLO tu bloque. Si tropiezas con algo de otro, lo apuntas en §6 con
     el bloque al que pertenece y sigues con el tuyo.
  2. NO arregles nada. Ni el hallazgo ni lo que veas de camino. (Regla 2 de §3.)
  3. Todo hallazgo va con su reproducción; sin ella se escribe como *sospecha* y
     se dice que lo es. (Regla 1 de §3.)

Al terminar: añade tus hallazgos a §6 con su severidad de §2 —aunque no encuentres
nada, que también se escribe— y pon tu bloque al día en §7.
```

### Dos cosas que la troceabilidad no arregla

- **El orden importa en dos sitios, no en los ocho.** **A-0 va primero**: si los documentos han derivado, los
  demás bloques miden con la vara torcida. Y **A-1 antes que A-2**: si A-1 cambia la forma del puerto, A-2
  audita un cableado que va a moverse. Los otros cinco son intercambiables.
- **Dos bloques en paralelo chocan en el libro de hallazgos**, porque los dos escriben en §6 y §7 de este
  fichero. En serie no hay problema. Si alguna vez se paralelizan, que cada sesión escriba en un
  `Hallazgos-A-n.md` aparte y se consoliden a mano.

---

## 5. Los bloques

Cada uno lleva **la pregunta**, **dónde mirar**, **cómo se decide** (para que el hallazgo no sea cuestión de
gusto), **qué sale** y su **«Leer antes»** — la lectura mínima de §4-bis, además de la base común.

---

### A-0 · La vara de medir · ½ sesión

> **Leer antes:** nada más que la base común. **Este bloque no lee documentos: los indexa.** Todo sale de
> `grep` sobre `docs/`, `Sources/` y `Tests/`; leer el LLD entero aquí sería justamente el error.
> Si quieres una página de contexto, **Plan §9** —*"los tests son la especificación revisable"*—, que es la
> razón de que este bloque exista.

**Pregunta.** ¿Los documentos contra los que se audita dicen lo que el código hace?

**Dónde mirar.** Mecánico, y casi todo con `grep`:

- Cada `D-nn` citado en `Sources/` y `Tests/` **existe** en la bitácora. Cada `§x` existe en el LLD.
- Al revés: cada `D-nn` que la bitácora marque como *implementada* tiene código o test que la cite.
- Las afirmaciones **verificables** de `AGENTS.md` y `backend/README.md`, una por una. Tres para empezar,
  porque las tres se pueden comprobar en un comando: *"266 tests"*, *"~96 operaciones no generadas"*, y
  *"`FederationCode.swift` es el único sitio del proyecto donde aparecen las cadenas `"rffm"` y `"fcf"`"*.
- Los cuatro rótulos de fase (*"entregada"*) contra lo que hay en `Sources/`.

**Cómo se decide.** Una cita rota o una cifra desfasada es **S3**. Una afirmación que dice **lo contrario** de
lo que el código hace es **S2**, porque el que la lea actuará en consecuencia — y en este proyecto el que la
lee es el mecanismo de control.

**Qué sale.** La lista de correcciones documentales, y la respuesta a si la deriva es puntual o sistemática.
Si es sistemática, sale también una propuesta de comprobación automatizable (que sería trabajo para A-7).

> **Este bloque ya empezó, y por eso está aquí.** Ver **H-01**: el mismo buscar-y-reemplazar mal aplicado
> había dejado cinco sitios tocados, y uno de ellos afirmaba justo lo contrario de lo medido. Se arregló el
> 2026-09-03.

---

### A-1 · El puerto de federación contra su segunda implementación · 1 sesión · **bloquea F7, F8, F9**

> **Leer antes:**
> **Anexo FCF §C.10 entero** (§C.10.1 a §C.10.8) — es el material del ensayo en seco, y §C.1–§C.9 están
> **obsoletas**: no leerlas. Dos subsecciones son la sustancia del bloque: **§C.10.3** (*`disciplinaId` no es
> la modalidad: lleva el género dentro*) y **§C.10.5** (*dos trampas nuevas, y una al revés que en Madrid*).
> · **Anexo RFFM §F.3, §F.4 y §F.15** — el código de equipo, el club deducido del escudo y el volcado real.
> · **LLD §5.6** (integración con la federación) y **§3.7** (fuentes y *provenance*).
> · **`D-17`, `D-55`, `D-71`, `D-74`** de la bitácora.
> No hace falta nada de migraciones, tenancy, HTTP ni auth.

**Pregunta.** ¿`FederationClient` abstrae *una federación*, o abstrae *la RFFM* con otro nombre?

**Dónde mirar.** `Sources/Application/FederationClient.swift` (236 líneas: el puerto y sus cuatro DTOs),
`Sources/Application/FederationError.swift`, y `Sources/Federation/` entero (812 líneas) para ver **qué hace
el adaptador y qué le deja al puerto**.

**El método: un ensayo en seco del adaptador de la FCF.** No escribirlo —eso es F9— sino recorrer el
[Anexo FCF §C.10](../docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md) **campo a campo** contra los
DTOs del puerto y anotar tres cosas: campos de la FCF que **no tienen sitio**, opcionalidades que para la FCF
están **al revés**, y supuestos de la RFFM **incrustados** en un tipo que se llama genérico. Con el anexo
delante, no de memoria (`D-74`).

**Cuatro sospechas concretas para empezar** — son puntos de partida, no conclusiones:

| # | Sospecha | Por qué importa |
|---|---|---|
| 1 | `FederationTeamRef.federationClubID` es opcional *porque la RFFM lo deduce del nombre del fichero del escudo* ([Anexo RFFM §F.4]). La FCF lo publica **como campo propio** (`D-74`) | El puerto codifica **cómo lo obtiene una fuente**, no **qué es el dato**. Si la degradación se documenta en el puerto y no en el adaptador, el llamante degrada para las dos |
| 2 | `FederationTeamRef.letter` — la letra *"que iba embebida en el nombre"*. ¿Quién la extrae, el adaptador o el Dominio? | Si la extracción vive fuera del adaptador, F9 hereda la gramática de nombres de la RFFM. Y la letra entra en la clave única de `Team` (`D-77`), así que no es cosmético |
| 3 | `FederationError.malformedResponse(field:)` documenta `field` como *coordenada dentro del cuerpo* (`"calendar.rounds[3].codjornada"`) | Tiene sentido para JSON. Los §C.1–§C.9 del anexo FCF están obsoletos **pero describen raspado**, y `D-74` es reciente: si la FCF vuelve a HTML, ¿qué se pone en `field`? |
| 4 | `FederationCoordinate` tiene exactamente tres códigos **+** `modality`, con `modality` justificada como *"contrapartida del `tipojuego` de la RFFM"* | `D-74` dice que las dos federaciones usan tres códigos. Falta comprobar que la FCF **no** necesita un cuarto eje, y que `SeasonLabel` reformateada por el adaptador (`D-71`) le sirve igual |

**Cómo se decide.** Un cambio en la forma del puerto hoy cuesta **un adaptador y sus dobles**. El mismo
cambio después de F8 cuesta **tres métodos, dos adaptadores y los dobles de tres suites**. Así que el listón
es bajo a propósito: **cualquier campo del puerto que solo se explique nombrando a la RFFM es S1 o S2**, y se
decide cuál según si F7/F8 lo tocan.

**Qué sale.** La **forma definitiva del puerto antes de que F7 y F8 le añadan dos métodos**. Y, si hay que
cambiarlo, la lista de qué se mueve al adaptador — que es donde `D-71` ya puso el reformateo de la etiqueta de
temporada, así que hay precedente y criterio.

---

### A-2 · La regla que destruye datos, de punta a punta · 1 sesión · **bloquea F7**

> **Leer antes:**
> **LLD §3.7** (la política de *upsert* y la cadena, las dos mitades) · **`D-56`, `D-75`, `D-30`, `D-31`** —
> `D-75` es la que dice qué se pierde y por qué los dos errores no cuestan lo mismo · **Plan §4.5 y §4.7**
> (qué entregó F3 y qué F5, con sus mutaciones) · del **README, §5.4 y la tabla de filtros de §5** — de ahí
> salen los comandos que ejecutan justo estos tests.
> **Y el aviso de §6.2 del LLD sobre el ámbito transaccional**, que es el que decide cómo se escribe la
> lectura de comprobación. No hace falta nada de federación, HTTP ni auth.

**Pregunta.** La política de *upsert* que los tests de nivel 1 demuestran, ¿es la que corre contra Postgres?

**Por qué este bloque existe teniendo 11/11 y 16/16 de mutación.** Porque la comprobación de mutación de F3 y
F4 se hizo **sobre las reglas puras**, y demuestra que la regla es correcta y que sus tests la cazan. Lo que
no puede demostrar es que **esté bien cableada**: una regla impecable llamada en el sitio equivocado, o cuyo
resultado se pisa al traducir a SQL, pasa las dos comprobaciones. Y `D-75` dice qué se pierde si eso ocurre:
*"escribir un silencio pierde el dato, y `Match` no tiene `PATCH`"*.

**Dónde mirar.** `Sources/Domain/UpsertPolicy.swift`, `Kickoff.swift`, `MatchResult.swift` (las reglas) contra
`Sources/Application/CalendarPass.swift` (**425 líneas, el fichero más grande del proyecto**) y
`Sources/Persistence/FluentIngestionRepositories.swift` (338).

**El método: cobertura diferencial.** Para cada rama probada en nivel 1, localizar su llamante y preguntar si
**algún test de nivel 3 o 4 la alcanza**. Lo que se busca son ramas demostradas en unit y **inalcanzables o
sorteadas** en el camino real.

**La sospecha principal, y es concreta.** `D-56` dice *"ausente o vacío nunca sobrescribe"*. En nivel 1 eso es
una función pura y es fácil de probar. **En SQL depende de cómo el repositorio construya el `UPDATE`**: un
modelo de Fluent con un campo `Optional` puesto a `nil` escribe `NULL` en la columna, **no se la salta**. La
pregunta exacta:

> ¿Existe un test de nivel 3 que haga **dos** pasadas —la segunda con el campo vacío— y **lea la columna
> después** para comprobar que el valor de la primera sigue ahí?

Si existe, esto es **S4** y queda cerrado con su nombre apuntado. Si no existe, es **S1**: es el único fallo
de todo el sistema que **pierde datos que no vuelven**, y hay que escribir el test antes de F7 — porque F7
trae `StandingRow`, que se escribe con la misma política.

**Cómo se decide.** Mirando la columna en la base, no el valor devuelto. Y con el aviso de §6.2 en la cabeza:
dentro de un `withRepositories` un `SELECT` de otra conexión no ve nada, así que la lectura de comprobación va
en su propio ámbito.

**Qué sale.** El mapa rama-a-test de las tres reglas, y los tests que falten. Cada uno con su mutación, que es
la vara que este proyecto ya usa.

---

### A-3 · Lo que sobrevive a un fallo · 1 sesión

> **Leer antes:**
> **`D-83`, `D-85` y `D-86`** — las tres son este bloque, y `D-86` trae el criterio (*"se continúa y se
> apunta"*) · **LLD §6.2** (el ámbito de tenant **es** una transacción) y **§6.4** (*pooling*) · del
> **README, §5.1** —el aviso de que una violación de restricción aborta la transacción entera y hace que el
> segundo intento falle por el motivo equivocado— y **la fila de `PSQLError` de §9**.
> No hace falta nada de federación ni de auth.

**Pregunta.** `D-83` (la pasada es atómica) y `D-85` (deja constancia) están probadas para el fallo que se
probó. ¿Aguantan los otros?

**Dónde mirar.** `Sources/Application/IngestCalendar.swift` —tres ámbitos de tenant distintos, en las líneas
**95**, **104** y **124**—, `IngestClubCalendars.swift:99`, y `Sources/Persistence/FluentTenantUnitOfWork.swift`.

**Lo que `D-83` ya deja cerrado, para no auditarlo dos veces.** La decisión de los **tres ámbitos** está
tomada y razonada —leer la coordenada · escribir · registrar la pasada—, con la red **fuera de los tres** y el
argumento del *pool* agotado escrito. Y el comportamiento del `rollback` no es deducción: *"comprobado contra
Postgres real"*. Eso corresponde a `IngestCalendar.swift`, líneas **104**, **124** y **95**.

**Lo que `D-83` y `D-85` no establecen, que es este bloque.** Las dos hablan de **dónde** están las fronteras
y de qué hace un `rollback`. Ninguna dice qué pasa cuando el fallo **no** es el que se probó:

| # | Pregunta | Por qué no es teórica |
|---|---|---|
| 1 | ¿Se ejecuta el **tercer** ámbito —el de registrar— cuando el **segundo** —el de escribir— abortó con `25P02`? | El README ya advierte que una violación de restricción **aborta la transacción entera** y que eso hace que un segundo intento *"pase por el motivo equivocado"* |
| 2 | ¿De qué conexión sale ese tercer ámbito? Si el *pool* le devuelve la de la transacción abortada, la fila de `D-85` no se escribe — y `D-85` es exactamente *"la pasada que nadie ve"* | Es el fallo que se traga a sí mismo: falla, y falla el registro de que falló. `D-83` dice que el tercer ámbito está fuera del segundo *a propósito*, pero no que se haya medido con el segundo abortado |
| 3 | ¿Hay test de nivel 3 que provoque un fallo **real** —una violación de restricción, no un doble que lanza— y **luego lea la fila**? | Los niveles 2 y 3 corren *"con dobles sin restricciones"*, y el README dice que es justo lo que ocultó los dos defectos que F6 encontró a mano |
| 4 | `D-86` dice que el recorrido continúa. ¿Continúa también si el fallo es de **conexión o de *pool***, y no de una coordenada caducada? | La unidad de aislamiento es la competición. Un fallo de infraestructura no está aislado por competición |

**Cómo se decide.** Provocando los fallos, no razonando sobre ellos: una restricción violada de verdad, y el
contenedor de Postgres parado a mitad de recorrido. Los dos defectos que F6 destapó salieron **ejecutando el
sistema contra la base de trabajo**, y ese precedente es el que fija el método aquí.

**Qué sale.** Los tests adversariales que falten, y —si la pregunta 2 sale mal— un arreglo S1, porque tira por
tierra la razón de ser de `D-85`.

---

### A-4 · El `202`, el TaskLocal y el trabajo que sobrevive a la respuesta · ½ sesión · **bloquea F10**

> **Leer antes:**
> **`D-88`** (los dos endpoints, y por qué el `202` planifica antes de responder), **`D-87`** (la cadencia
> vive fuera del proceso) y **`D-67`** (el `202` de F10, que hereda lo que se decida aquí) · **LLD §6.1**
> (resolución del tenant y el `@TaskLocal`) y **§2.3-c** · del **README, §4.5** — los dos endpoints desde
> `curl`, con las tres cosas *"que se aprenden más rápido probándolas"*.
> Es el bloque más corto: **son 41 líneas de `BackgroundWork.swift` y tres preguntas.**

**Pregunta.** La ruta que corre en producción cuando el `POST` devuelve `202`, ¿la ejercita algo?

**Dónde mirar.** `Sources/HTTPAdapter/BackgroundWork.swift` (41 líneas, y las 41 razonadas),
`IngestionHandler.swift`, y `Sources/Tenancy/TenantContext.swift`.

**Lo que ya está bien pensado, para no auditarlo dos veces.** `DetachedBackgroundWork` usa `Task { }` y **no**
`Task.detached`, deliberadamente y con el porqué escrito: `detached` no hereda los `@TaskLocal` y perdería el
tenant que fijó el middleware. Eso está resuelto.

**Lo que la auditoría sí pregunta.** Los tests usan `InlineBackgroundWork`, que ejecuta **antes** de que la
respuesta salga. Es una decisión buena —el comentario explica que la alternativa es un test intermitente—,
pero tiene una consecuencia que conviene tener escrita: **la ruta que corre en producción no la ejercita
ningún test**, y las dos difieren justo en lo que puede fallar.

| # | Pregunta | Riesgo |
|---|---|---|
| 1 | Cuando el trabajo corre **después** de la respuesta, ¿sigue vivo el *pool* del tenant y se puede abrir un ámbito nuevo? | En línea nunca se comprueba: la respuesta aún no ha salido |
| 2 | ¿Qué pasa con un `SIGTERM` a mitad? Fly.io despliega así | El comentario dice *"si el proceso muere no hay reintento, y no hace falta"* porque la pasada es atómica. Puede que la respuesta sea **"sí, y basta"** — pero entonces es **S4 comprobada**, no una suposición |
| 3 | El `202` *"planifica antes de responder"* (`D-88`) para que una `seasonId` inexistente dé 404. ¿Dónde acaba la planificación y empieza la ejecución? | Es la frontera exacta que F10 va a heredar |

**Cómo se decide.** Con `LOG_TRACE`/`LOG_LEVEL=debug` y el servidor de verdad: `curl` con `{}`, respuesta
inmediata, y mirar en la base si la fila de `IngestionRun` aparece después. Si aparece, la ruta de producción
funciona y queda **probada a mano y escrita**.

**Qué sale.** La respuesta escrita a las tres, y —si hace falta— la forma de un test que cubra la ruta de
producción sin arbitrar una carrera. **F10 devuelve `202` en `/federation-link` (`D-67`)**: lo que se decida
aquí, lo hereda.

---

### A-5 · Las migraciones, antes de que el esquema doble · 1 sesión · **bloquea F7, F8, F10**

> **Leer antes:**
> **LLD §4.6** (migraciones), **§4.7** (aplicación por tenant), **§6.4** (el *pooler*, y por qué aquí no) y
> **§9.3** —la cuestión abierta que este bloque tiene que cerrar o dejar apuntada— · **`D-02`** (el `CHECK`
> se deriva, nunca se teclea), **`D-23`** (el alta es comando, no endpoint) y **`D-86`** (de donde se toma
> prestado el criterio) · del **README, §3.1** (la foto de los *schemas*) y **§6** (los comandos, con el
> aviso del *pooler*).
> **Y §3.5 del LLD** para las convenciones de restricciones —`NULLS NOT DISTINCT`, FKs compuestas—, que es
> contra lo que se comprueban. No hace falta nada de federación.

**Pregunta.** ¿`--revert` deshace de verdad, y dos tenants migrados por **caminos distintos** quedan iguales?

**El momento.** Hoy hay **nueve migraciones**: ocho por tenant (`CreateClub`, `CreateSeason`,
`CreateCompetition`, `CreateRound`, `CreateOpponentClub`, `CreateTeam`, `CreateMatch`, `CreateIngestionRun`)
y `CreateTenants` en el plano de control. F7 y F8 añaden `StandingRow` y `LeagueScorer`; F10, `TeamRegistration`
con su `UNIQUE` de tres columnas y su FK compuesta. El esquema va a crecer un 40% en tres fases.

**Dónde mirar.** Los `AsyncMigration` de `Sources/Persistence/` y `Sources/Tenancy/TenantRecord.swift`,
`Sources/Persistence/SQLHelpers.swift` (donde vive `sqlValueList`) y `Sources/App/TenantMigrations.swift`.

**Qué comprobar.**

- **Reversibilidad, una por una.** Que el `revert` de cada migración deshaga lo que su `prepare` hizo,
  incluidos los tipos, los `CHECK` y los índices — no solo la tabla.
- **Que ningún `CHECK` de enumerado esté teclado a mano** (§4.6, `D-02`): tienen que salir todos de
  `sqlValueList`, que es genérico sobre `CaseIterable`. Un `CHECK` teclado es una lista que no se enterará del
  próximo caso del enumerado.
- **La divergencia, que es el hallazgo que este bloque busca.** `provision-tenant` pasa el juego **completo**
  de migraciones a un *schema* nuevo; `migrate-tenants` aplica **solo las que faltan** a uno viejo. Los dos
  caminos deberían dar el mismo esquema. Compararlos de verdad:

  ```sh
  swift run Run provision-tenant nuevo -f rffm      # camino A: juego completo
  # (camino B: un tenant provisionado antes de F5 y migrado incrementalmente)
  docker compose exec db pg_dump -U tfm -d tfm --schema-only -n club_nuevo
  docker compose exec db pg_dump -U tfm -d tfm --schema-only -n club_atleti
  ```

  Un `diff` con algo más que el nombre del *schema* es **S1**: significa que el esquema de un club depende de
  cuándo se dio de alta.
- **§9.3, que sigue abierta y ahora tiene precedente.** Un fallo a mitad del recorrido de `migrate-tenants`
  deja *schemas* a distinta versión **y nada que lo diga**. `D-86` ya fijó el criterio para la pregunta
  hermana: *"continuar solo es seguro cuando el fallo deja constancia y no deja estado a medias"*. Aquí no hay
  constancia. Decidir **ahora**, con nueve migraciones y dos clubes, si hace falta que el comando informe de
  la versión por tenant — porque a 50 clubes deja de ser estético, y el LLD ya lo dice.

**Cómo se decide.** Con `pg_dump --schema-only` y `diff`, no leyendo las migraciones. Y con la advertencia de
§6.4 respetada: **conexión directa, nunca *pooler***.

**Qué sale.** La lista de migraciones que no revierten bien, la respuesta a la divergencia, y una decisión
escrita sobre §9.3 — aunque la decisión sea *"se acepta el riesgo y así queda apuntado"*.

---

### A-6 · Las costuras de §7, para no rehacer los *handlers* · 1 sesión · **bloquea F10**

> **Leer antes:**
> **LLD §7 entero** — son ~120 líneas y es diseño puro, así que se lee rápido; dentro, lo que decide el
> bloque es **§7.4** (dónde vive la decisión: en el caso de uso), **§7.5** (403, no 404) y **§7.7** (lo que
> no está comprobado, que es *todo*) · **§6.1** (la jerarquía *claim* sobre subdominio, y la deuda de F0) y
> **§9.10** (el *slug* contractual, y por qué no hay superficie que enumere tenants) · **`D-64`** (el 404
> defensivo que se descarta) · del **README, §4.3** (los tres errores y quién decide cada uno) y **§4.4**.
> **No se lee nada de Supabase ni de JWKS**: este bloque no implementa auth, mide costuras.

**Pregunta.** La autenticación está aplazada a propósito y este bloque **no la reabre**. Lo que pregunta es si
las **costuras** están puestas donde §7 las va a necesitar, o si cada endpoint que se escriba antes habrá que
revisitarlo.

**Por qué es el bloque que más se parece al miedo del §0.** §7.7 dice que **nada de §7 se ha ejecutado**, y
F0 dejó declarada su deuda: el tenant se resuelve por `Host` y no por *claim* firmado, cuando §6.1 exige que
el *claim* sea autoritativo y que **una discrepancia se rechace**. F10 escribe endpoints. Si la costura no
está, F10 los escribe dos veces.

**Qué comprobar.**

| # | Costura | Cómo se comprueba |
|---|---|---|
| 1 | **Todos** los casos de uso reciben `ActorContext`, no solo los que hoy lo usan | `grep` de las firmas en `Sources/Application/`. `AGENTS.md` lo declara requisito: *"un caso de uso nuevo lo recibe desde el principio"* |
| 2 | Hay **un solo sitio** donde se decide el tenant | Que ningún *handler* ni repositorio lea el `Host` ni el `@TaskLocal` por su cuenta. Si el arreglo de la deuda de F0 toca más de un fichero, ya es S2 |
| 3 | La comprobación de ámbito **tiene dónde caer** | `UpdateClub.swift:21` tiene el `TODO(§7)` puesto en el sitio correcto. ¿Lo tienen los demás casos de uso de escritura, o solo ése? |
| 4 | **403, no 404** (§7.5) es representable hoy | `ProblemMiddleware` (235 líneas) hace un `switch` **exhaustivo** sobre `DomainError` a propósito, para que un error nuevo no compile hasta que alguien decida su HTTP. ¿Encaja ahí un error de autorización, o hay que tocar la forma? |
| 5 | El **403 vs 404** no filtra existencia de tenants | §9.10 cerró que no hay descubridor de tenants; conviene que los códigos de error no lo reintroduzcan |

**Cómo se decide.** El listón: **¿cuántos ficheros toca poner §7 en marcha?** Si la respuesta es *"el
middleware y los casos de uso, cada uno una línea"*, las costuras están y esto es **S4**. Si es *"además, cada
*handler*"*, es **S1** y se arregla antes de F10 — no implementando auth, sino poniendo la costura.

**Qué sale.** El inventario de costuras, y la respuesta a esa pregunta en número de ficheros.

---

### A-7 · El arnés: hoy, ¿qué significa "verde"? · ½ sesión

> **Leer antes:**
> Del **README, §5 entero** — es el manual de los tests y la mitad del bloque está ahí: la guarda de **§5.2**
> (`REQUIRE_DB`/`CI`), el canario de **§5.5** y cómo se lee un test en **§5.4**, incluidos **los testigos de
> tipo deliberados**, que no son hallazgos · **LLD §8.1** (la pirámide y la correspondencia nivel↔capa) ·
> **Plan §5.1** (qué compra cada rojo) y **§9** (los deberes del desarrollador, donde ya está apuntado el
> cron) · **`D-70`** (swift-testing, no XCTest) y **`D-87`** (la cadencia vive fuera del proceso — el mismo
> argumento vale para el canario).

**Pregunta.** ¿Quién ejecuta los 266 tests, y qué pasa si alguien rompe algo?

**El hallazgo de partida, ya comprobado.** **No hay CI**: `.github/workflows` no existe. Y eso tiene una
consecuencia precisa, porque el código **sí** está preparado para tenerlo: la guarda de §5.2 —los tests de BD
se omiten en local pero **fallan** si está definida la variable `CI` o `REQUIRE_DB`— se escribió *para* un CI
que no existe. Así que hoy **el único que impide un "verde" que en realidad es "no probado" es la disciplina
del desarrollador**, y el mecanismo que debía impedirlo está escrito y desconectado. Es **S2**: no rompe nada
hoy, y su coste crece con cada fase.

**Qué proponer** (decisión del desarrollador, no de la auditoría):

- Un *workflow* con **Postgres como servicio** y `REQUIRE_DB=1`, que corra los cuatro niveles.
- `npx @redocly/cli lint Sources/APIContract/openapi.yaml`, que hoy se ejecuta a mano.
- `swift build`, para que un *spec* que rompa el generador filtrado (`D-69`) no pase en silencio.
- **El canario, aparte y con su propio disparo.** No puede ir en el CI de cada *push*: habla con internet, y
  §5.5 del README explica que mezclarlo estropea las dos señales. Necesita un disparo **programado**, que es
  el mismo deber pendiente que el cron de la ingesta (`D-87`, Plan §9) — **y conviene resolver los dos
  juntos**, porque son la misma decisión de despliegue.

**Y la otra mitad: la calidad de los tests.** Si los tests son la especificación revisable (Plan §9), están
sujetos a auditoría como el código. Tres cosas que buscar:

1. **Tests que no puedan fallar** — más allá de los testigos de tipo **deliberados** que el README §5.4
   documenta y defiende (`TeamOwnership` sin nombre de club, `MatchCandidate` sin fecha). Los deliberados no
   son hallazgos; los accidentales sí.
2. **Aserciones sobre el doble en vez de sobre el efecto**: comprobar que se llamó al falso no es comprobar
   que se escribió la fila.
3. **Caminos de error sin test**, sobre todo los de `FederationError` y `ApplicationError`.

**Qué sale.** El *workflow* propuesto (sin montarlo: eso es una decisión de despliegue), y la lista de tests
flojos si los hay.

---

## 6. Libro de hallazgos

Numeración `H-nn`, correlativa y sin reutilizar. **Se escribe aquí incluso cuando el bloque no encuentra
nada** — un bloque cerrado en blanco es información, y es la mitad del valor de §2.

| # | Bloque | Severidad | Hallazgo | Reproducción | Estado |
|---|---|---|---|---|---|
| **H-01** | A-0 | **S2** | Un buscar-y-reemplazar mal aplicado al enmendar `D-84` dejó **cinco** sitios tocados: tres en `README.md` (una frase que se contradecía a sí misma, más dos que atribuían la caducidad de la coordenada a `temporada`, que es justo el parámetro que la RFFM ignora) y dos en `RFFMCanaryTests.swift` (una frase sin verbo, y el mensaje de `coordinateNotFound` anunciando un **404** que `FederationError` documenta que **nunca ocurre**) | `git show` del 2026-09-03; el mensaje del canario contra `FederationError.swift:26-31` | **Arreglado** el 2026-09-03. `swift build --build-tests` y `FederationTests` (48) en verde |

---

## 7. Estado

| Bloque | Estado | Sesión | Hallazgos |
|---|---|---|---|
| **A-0** · La vara de medir | ◐ empezado (H-01) | 2026-09-03 | H-01 |
| **A-1** · El puerto de federación | ○ pendiente | — | — |
| **A-2** · La regla que destruye datos | ○ pendiente | — | — |
| **A-3** · Lo que sobrevive a un fallo | ○ pendiente | — | — |
| **A-4** · El `202` y el TaskLocal | ○ pendiente | — | — |
| **A-5** · Las migraciones | ○ pendiente | — | — |
| **A-6** · Las costuras de §7 | ○ pendiente | — | — |
| **A-7** · El arnés | ○ pendiente | — | — |

---

## 8. Lo que esta auditoría deja fuera, y por qué

Para que nadie la cite más allá de su alcance — igual que hacen §6.5 y §7.7 del LLD:

| Fuera de alcance | Por qué |
|---|---|
| **Rendimiento y escala** (§6.5) | Está medido a dos o tres clubes y declarado como no comprobado. Auditar rendimiento sin carga real es inventarse un número |
| **Forma del *tier* dedicado** (§9.2) | Es una decisión de diseño **aplazada a propósito**, no un defecto. Un aplazamiento consciente no es un hallazgo |
| **Política de retención RGPD** (§9.4) | Igual: el *mecanismo* existe (`D-24`), falta la política, y es una decisión de negocio |
| **Implementar §7** (auth) | Fuera. A-6 audita **las costuras**, no la ausencia |
| **La forma del *spec*** más allá de lo generado | El *spec* está completo y validado con `redocly`. Auditar 100 operaciones de las que 4 tienen código sería auditar un documento, y eso es revisión de diseño |
| **Los adaptadores de la FCF** | No existen todavía: es F9. A-1 audita **el puerto**, que sí existe |

Y una que no es "fuera de alcance" sino **explícitamente no negociable**: la auditoría **no cambia el
alcance entregado**. Lo que descubra que falta se apunta con su fase; el `filter` de
`openapi-generator-config.yaml` sigue siendo `D-69` y sigue siendo la verdad sobre lo que hay montado.

[Anexo RFFM §F.4]: ../docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
