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
las **83** del *spec* (medidas en A-0, H-03).

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
| **S3** | **Local** | Se arregla donde está, sin arrastrar nada | Al cerrar el bloque. **Si es documental, en el acto** — ver abajo |
| **S4** | **Nota** | Cierto, comprobado, y no hay que hacer nada hoy | Nunca; queda escrito para que no se vuelva a descubrir |

Un hallazgo **S4 no es un hallazgo fallido**. La mitad del valor de este ejercicio es convertir *"creo que
esto está bien"* en *"esto está comprobado y aquí está cómo"*, que es exactamente lo que `D-84` demostró que
faltaba cuando una premisa de F2 sobrevivió tres fases siendo falsa.

**Y una excepción que la primera pasada de A-0 obligó a escribir: el S3 *documental* se arregla en el acto.**
Para código, *"se arregla cuando se pase por ahí"* funciona: alguien pasa. Por una cifra desfasada del README
**no pasa nadie nunca** — que es precisamente cómo H-03 y H-04 llegaron a estar desfasadas. Anotar una cita
roída o un número viejo cuesta más que corregirlo, así que no se anota para después: se corrige y se anota
como corregido.

---

## 3. Las reglas del juego

Seis, y las seis salen de métodos que este proyecto ya usa — la 4ª la añadió el cierre de A-0:

1. **Un hallazgo sin reproducción no es un hallazgo.** Va con el comando, el `curl`, el test o la consulta
   que lo enseña. Si no se puede reproducir, se escribe como *sospecha* y se dice que lo es. (`D-84`: una
   premisa sobre un sistema ajeno **se mide**; una sobre el propio código, también.)
2. **Se audita un bloque, se cierra, y *entonces* se arregla.** El ciclo es
   **auditar A-n → corregir sus hallazgos → auditar A-n+1**, no auditar y reparar entrelazados dentro de la
   misma sesión, que es cómo una auditoría se convierte en un refactor sin control. Reparar **entre** bloques
   además favorece al siguiente: si A-1 cambia la forma del puerto, A-2 audita el cableado definitivo y no
   uno que está a punto de moverse. Con tres condiciones:
   - **Auditoría y arreglo van en commits separados.** Mezclados se pierde el diff de *"qué encontró"* frente
     a *"qué cambié"*, y con él la posibilidad de revisar cualquiera de los dos.
   - **Un arreglo que crece deja de ser un arreglo.** Si toca más de un *target*, cambia una API pública o
     mueve los dobles de varias *suites*, **no** es una corrección de auditoría: es una mini-fase y va al
     Plan de desarrollo con su nombre. Sin esta válvula, la auditoría se convierte en reescritura sin que
     nadie lo haya decidido.
   - **El libro de hallazgos es el traspaso.** Cada bloque corre en sesión nueva, así que la de A-3 no sabrá
     lo que A-1 arregló salvo que esté en §6 con su `sha`. Por eso §6 va en la base común de §4-bis.
3. **Todo arreglo entra por el bucle de Plan §5.1**: el test primero, con esqueleto, y el rojo tiene que ser
   **de aserción y no de compilación**. Un arreglo de auditoría sin test es un hallazgo que volverá.
4. **Una ronda de arreglos se cierra corriendo la batería, y se corre con `REQUIRE_DB=1`.**

   ```sh
   REQUIRE_DB=1 swift test          # y no `swift test` a secas
   ```

   **La bandera no es celo, y esto se aprendió fallando:** con Postgres parado, `swift test` **omite** los
   niveles 3 y 4 (§5.2 del README) y su renglón final dice
   `✔ Test run with 266 tests in 40 suites passed` — **exactamente el mismo texto** que cuando sí corren.
   El recuento tampoco delata nada, porque el total sale de la lista y no de lo ejecutado. **Lo único que
   cambia es la duración**: 0,1 s omitiendo contra 4,6 s de verdad. Un verde de 0,1 s significa *"no se probó
   nada que toque la base"*. Con `REQUIRE_DB=1`, en cambio, falla y dice por qué.
   Ver **H-07**, que es este mismo tropiezo anotado para A-7.
5. **Si el código y el diseño discrepan, el hallazgo dice cuál de los dos está mal.** No siempre es el
   código: `D-84` y `D-74` son dos casos en que el documento era el equivocado. Y si el que cambia es el
   documento, va a la bitácora como entrada `D-nn` nueva o enmienda, según la tabla de *"dónde va cada cosa"*
   de `AGENTS.md`.
6. **La auditoría no amplía el alcance.** No añade endpoints, ni entidades, ni entra en el `filter` de
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
  porque las tres se pueden comprobar en un comando: *"266 tests"*, *"las operaciones no generadas"*, y
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
> · **Añadido al cerrar el bloque:** el **volcado** `docs/Federation APIs examples/FCF-partidos-temporada-jugada.txt`.
> El ensayo en seco no se puede hacer con el anexo solo — el juego **completo** de claves del objeto de
> partido está en el volcado y de contarlas sale H-08.
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
> · **Añadido el 2026-09-12, al llegar el deber que A-3 le deja** (§7, cierre de A-3): **`D-86` enmendada** y
> los hallazgos **H-23** y **H-24** de §6 — y con ellos lo que `4d66aa0` dejó **nuevo en el camino que corre
> detrás del `202`**: los dos casos de `ApplicationError` (`databaseUnavailable`, `runNotRecorded`), la sonda
> de `IngestClubCalendars.swift` y los `case` que `ProblemMiddleware` les puso. **La ruta del `202` cambió de
> comportamiento el mismo día en que este bloque pasó a ser el siguiente**, así que la pregunta 4 se audita
> contra el código de hoy y no contra el que F6 entregó.
> · **Y lo que hay que tener montado antes de sentarse, que el bloque daba por hecho:** el `202` **solo sale
> con `seasonId`** en el cuerpo —con `competitionIds` la respuesta es `200` (`IngestionHandler.swift:92-98`)—,
> así que hace falta un tenant provisionado **con una temporada y al menos una competición sembrada**:
> `docker compose up -d` · `migrate --yes` · `provision-tenant` · `migrate-tenants` · `seed-competition`. Ese
> último **habla con la RFFM** (`SeedCompetitionCommand.swift:87-88`), o sea **red y una URL de calendario
> viva**. Es medio bloque de montaje dentro de un bloque de media sesión: tenerlo antes, no al llegar.
> Es el bloque más corto: **son 41 líneas de `BackgroundWork.swift` y cuatro preguntas.**

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
| 4 | **Heredada de A-3.** Cuando la base se cae **detrás** de un `202`, ¿se entera alguien? El recorrido ahora **se para** y lanza `ApplicationError.databaseUnavailable` (H-23, `D-86` enmendada) — dentro del trabajo de fondo, donde **no hay respuesta que devolver** porque el `202` ya salió, **no hay fila en `ingestion_runs`** porque es justo lo que no se puede escribir, y el código de salida distinto de cero es del **comando**, no del servidor | Las otras tres preguntas son del camino bueno; ésta es la única del camino de fallo. Y `GET /v1/ingestion-runs` —la forma que `D-88` prevé para enterarse— es precisamente la que se queda sin dato. Anotado aquí, y no solo en §7, porque **§7 no está en la base común de §4-bis**: la sesión que ejecute el bloque no lo leería |

**Cómo se decide.** Con `LOG_TRACE`/`LOG_LEVEL=debug` y el servidor de verdad: `curl` con `{}`, respuesta
inmediata, y mirar en la base si la fila de `IngestionRun` aparece después. Si aparece, la ruta de producción
funciona y queda **probada a mano y escrita**. Para la **4**, el mismo experimento con la base parada entre el
`202` y el trabajo —`docker compose stop db`—, que es como A-3 midió H-23; y mirando **las dos** salidas que
quedan vivas: lo que el logger saca a `stderr` y lo que `GET /v1/ingestion-runs` contesta después.

**Qué sale.** La respuesta escrita a las cuatro, y —si hace falta— la forma de un test que cubra la ruta de
producción sin arbitrar una carrera. De la 4 sale además **qué señal le queda al que disparó el `202`**, que
hoy no es ninguna de las del job. **F10 devuelve `202` en `/federation-link` (`D-67`)**: lo que se decida
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
| **H-02** | A-0 | **S3** | **`D-78` no lo cita ningún test**, y sí está probada: `MatchingChainTests.swift:107-119` explica su argumento entero en prosa —*"el «si no» es «si el paso anterior no resolvió»"*— pero el rótulo del `@Test` cita `D-76`, la decisión vecina. Quien audite `D-78` por el método que `AGENTS.md` prescribe —`grep` de la cita— concluye **"regla sin test"**, y es falso. Es la segunda instancia de la clase de H-01: la regla sobrevive, su rastro no | `grep -r "D-78" backend/` → 0 aciertos en `Tests/`. Contrastar con `MatchingChainTests.swift:107-119` | **Arreglado** (`31699a0`) |
| **H-03** | A-0 | **S3** | **La cifra de operaciones del *spec* está desfasada en tres sitios, y uno es este mismo plan.** El *spec* tiene **83** operaciones, no ~96 ni ~100: `README.md:40` dice *"~96 operaciones"* no generadas (son **79**); `openapi-generator-config.yaml:17-18` dice *"~100 operaciones"* y *"99 stubs"* (son **83** y **79**); y `Plan de auditoría-001.md:191` repite el ~96 | Dos vías independientes: `grep -c "operationId:"` → **83**, y `grep -cE "^    (get\|post\|put\|patch\|delete):"` → **83**, en **45** rutas | **Arreglado** (`31699a0`) |
| **H-04** | A-0 | **S3** | `README.md:764` afirma que el *spec* tiene **6.477 líneas**; tiene **6.565** | `wc -l < Sources/APIContract/openapi.yaml` | **Arreglado** (`31699a0`) |
| **H-05** | A-0 | **S4** | **La integridad de las citas es completa, y queda medido.** Las **87** referencias `D-nn` de `Sources/` y `Tests/` resuelven **todas** contra las 89 decisiones de la bitácora. Los `§x` también, **incluidos los `§9.n`** (§9.1, §9.5, §9.7, §9.8, §9.9), que **no son encabezados sino puntos de la lista numerada de *Cuestiones abiertas*** — se anota porque una comprobación automática ingenua los marcaría como roídos, y no lo están. De las 5 decisiones sin citar (`D-08`, `D-26`, `D-69`, `D-70`, `D-78`), cuatro no son citables desde el código —son decisiones de método o de modelo— y la quinta es H-02 | `comm` de las dos listas; ver el detalle en la nota de cierre de abajo | **Cerrado** |
| **H-06** | A-0 | **S4** | **Las otras tres afirmaciones verificables se sostienen.** *"266 tests"*: exacto (`swift test --list-tests` → 266). *"`FederationCode.swift` es el único sitio donde aparecen `"rffm"` y `"fcf"`"*: se sostiene, un solo fichero. **Y los nueve filtros de la tabla de fases del README casan todos con algo** —ninguno cae en la trampa del `--filter` que el propio README documenta—, con el de F3 dando exactamente los *"trece renglones"* que §5.4 promete | `swift test --list-tests` y `grep -cE` de cada filtro | **Cerrado** |
| **H-07** | **A-7** | **S2** | **Un verde omitido y un verde real son indistinguibles en la línea de resumen.** Con Postgres parado, `swift test` omite los niveles 3 y 4 y remata con `✔ Test run with 266 tests in 40 suites passed` — **el mismo texto, el mismo recuento** que cuando sí corren, porque el total sale de la lista de tests y no de lo ejecutado. La única señal es **la duración**: 0,10 s omitiendo contra 4,57 s de verdad. Los avisos de omisión existen y son buenos (§5.2 del README), pero quedan sepultados y el renglón que uno mira es el último. **Lo encontró tropezando: al cerrar A-0 se dio por verde una pasada de 0,1 s.** Anotado a A-7 porque su remedio vive ahí —CI con `REQUIRE_DB=1`— y porque refuerza su S2: la guarda está escrita y desconectada | `swift test` con `docker compose stop db` (0,10 s, «passed») frente a `REQUIRE_DB=1 swift test` en las mismas condiciones (falla y dice por qué) | **Abierto** — es de A-7 |
| **H-08** | A-1 | **S2** · **F9**, y condiciona F7/F8 | **El sobre de `FederationCalendar` está cortado a la medida de la RFFM, y los dos campos obligatorios son justo los dos que la FCF no publica.** El calendario de la FCF —`/api/competition/partidos?grupId=…`, la **única** llamada de su ingesta ([Anexo FCF §C.10.4])— trae **21 claves y ninguna de sobre**: ni nombre de competición, ni etiqueta de temporada, ni rótulo de jornada. De los cinco campos que el puerto pide, publica **uno**.<br><br>· `seasonLabel: SeasonLabel` — **obligatorio** · RFFM: `calendar.temporada` · FCF: **no existe**<br>· `competitionName: String?` — opcional · RFFM: `calendar.competicion` · FCF: **no existe**<br>· `groupLabel: String?` — opcional · RFFM: `calendar.grupo` · FCF: **`GRUPO: "GRUP 1"`** ✅<br>· `currentRound: Int?` — opcional · RFFM: `pageProps.currentRound` · FCF: no existe (derivable de `CERRADA`)<br>· `FederationRound.label: String` — **obligatorio** · RFFM: `"1 (13-09-2026)"` · FCF: **no existe**<br><br>**La opcionalidad está invertida respecto al valor probatorio**: obligatorio es el eco (`seasonLabel`, §F.16) y opcional el dato (`competitionName`). Y `FederationRound.label` es obligatorio, solo la RFFM lo puede llenar y **no lo lee nadie** — su única aparición fuera del `init` es `self.label = label`. El puerto declara de sí mismo que *"casi todo sea opcional — un `nil` aquí significa «la fuente no lo dijo»"* (`FederationClient.swift:82-84`); estos dos campos son la excepción y no está razonada | `grep -o '"[A-Z_0-9]*":' "docs/Federation APIs examples/FCF-partidos-temporada-jugada.txt" \| sort -u` → 21 claves, ninguna de sobre. Contra la estructura de [Anexo RFFM §F.15]. Y `grep -rn '\.label' backend/Sources backend/Tests` → ninguna lectura de `FederationRound.label` | **Abierto** — **F6-bis** (Plan §4.1) |
| **H-09** | A-1 | **S2** · **F9** — *la que más cuesta descubrir tarde* | **La guarda de `D-84` se apaga sola en la FCF, sin error y sin aviso.** `Competition.requireSameSource(as:)` compara `Competition.federationName` contra `calendar.competitionName`, y sus dos silencios **no paran nada** a propósito (`Competition.swift:265-268`): *"si la fuente no publica nombre, callar no es contradecir"*. Pero el calendario de la FCF **no publica nombre de competición nunca** (H-08), así que para un tenant de la FCF `incoming` es `nil` en **todas** las pasadas y la guarda hace `return` siempre. §5.6 la llama *"una guarda antes de escribir nada"* y `D-84` dice que la pasada *"se para sin escribir"*: en Cataluña no se pararía jamás. **Hoy no rompe nada** —`CatalogFederationClientProvider` devuelve `nil` para `.fcf`, así que no hay pasada— y por eso no es S1: rompe **el día que F9 aterrice**, escribiendo un calendario de otro grupo dentro de la competición equivocada, que es el desenlace que `Competition.swift:249-252` describe como irreversible (`Team` sin `PATCH` de categoría, `Match` sin `PATCH`).<br><br>**Y la salida no es gratis, por eso se decide y no se parchea.** `groupLabel` sí lo publican las dos, pero es campo **descriptivo y editable por el BFF** (`Competition.swift:135`), así que como evidencia vale menos que `federationName`, que es `UpsertPolicy.matching`. Las tres opciones, para F9: (a) comparar `groupLabel` y aceptar que el administrador puede desarmar la guarda editándolo; (b) columna de evidencia nueva —`federation_group_name`—, que es migración y por tanto **A-5**; (c) segunda llamada en el adaptador de la FCF (`grupos?competicioId=…`) para traer el nombre y llenar `competitionName`, que es la que **no toca el puerto ni el modelo** | Juego de claves de H-08 (no hay nombre de competición) contra `Competition.swift:266`: `guard let federationName, let incoming, …` — con `incoming == nil` el `guard` cae al `return` | **Abierto** — **F6-bis** (Plan §4.1) |
| **H-10** | A-1 | **S3** | **Un campo que solo lee una herramienta de CLI puede tirar todas las pasadas de todos los clubes.** `FederationCalendar.seasonLabel` no es `String?` como el resto del sobre: es un *Value Object* del Dominio con invariante dura, construido en `RFFMCalendarParser.swift:70` **dentro** de la expresión que devuelve el calendario. Si `calendar.temporada` llegara con dos años no consecutivos —`"2026-2028"`—, `RFFMSeasonLabel.parse` delega en `SeasonLabel`, que lanza `DomainError`, y **se cae el `fetchCalendar` entero** con sus 34 jornadas ya parseadas detrás. Su único lector en todo el backend es `SeedCompetitionCommand` (líneas 91 y 112), que es *"HERRAMIENTA, no contrato"* (`AGENTS.md`). La ingesta no lo usa: `CalendarPass` no lo menciona. El comportamiento **está probado y es deliberado** en nivel 1 (`RFFMSeasonLabelTests.swift:69`, *"rechaza años no consecutivos, delegando en la invariante del dominio"*); lo que no está escrito en ningún sitio es su consecuencia a nivel de pasada | `grep -rn 'seasonLabel' backend/Sources` → tres aciertos: el `init` del puerto, la construcción en el parser y `SeedCompetitionCommand`. Ninguno en `CalendarPass` ni en `IngestCalendar` | **Abierto** — **F6-bis** (Plan §4.1) |
| **H-11** | **A-0** | **S2** | **El buscar-y-reemplazar de H-01 tiene cuatro víctimas más, y A-0 se cerró contándolas como cinco.** Eran nueve, y **tres están en `Sources/`**: `Domain/Competition.swift:245` se contradice en una línea (*"la RFFM **no ignora** el parámetro `temporada` … **y ignora el parámetro `temporada`**"*), `Domain/Competition.swift:205-207` quedó sin sentido gramatical y falso (*"ignora el parámetro `temporada` **de competición y grupo entre temporadas**"*, donde el original decía *"reutiliza los códigos de competición y grupo"*), y `Federation/FederationTransport.swift:20` tiene una oración empalmada a mitad. La cuarta está en el LLD §3.7, línea 589, con la misma doble negación.<br><br>**Y hay un sitio que debió tocar y no tocó, que es el peor de los cinco:** `Application/CalendarPass.swift:59-60` sigue afirmando *"La RFFM reutiliza sus códigos entre temporadas"* — la premisa que [Anexo RFFM §F.16] **refuta con dato** (*"los códigos **NO** se reutilizan entre temporadas: cada una recibe un bloque nuevo"*). Es el comentario que explica por qué existe la guarda de `D-84`, encima de la línea que la llama. La conclusión sobrevive; la causa escrita es falsa. Anotado a A-0 porque **su renglón de §7 dice «cerrado» y no lo está** | `grep -rn "no ignora el parámetro" backend/Sources docs/` → `Competition.swift:245` y `LLD-001.md:589`. `grep -n "reutiliza" backend/Sources/Application/CalendarPass.swift` → línea 59, contra §F.16 | **Arreglado** (`cc288cd`) |
| **H-12** | A-1 | **S3** | **El Dominio afirma dos veces que la FCF no publica identificador de partido, citando un anexo obsoleto.** `Domain/MatchingChain.swift:158-159` dice *"`nil` en la FCF, que **no publica identificador de partido en absoluto** (`D-31`, [Anexo FCF §C.3])"* y `Domain/Match.swift:38` repite *"la FCF no publica…"*. **§C.3 describe el sitio antiguo y está marcado obsoleto**; la web nueva trae `CODACTA` en **240 de 240** partidos, no vacío y **único**, y §C.10.4 remata que *"se llama igual que en la RFFM"*. §C.10.8 ya dejó apuntado que *"el 2.º paso de la cadena existe porque la FCF no tiene id de partido → el id **existe**; la cadena sigue siendo buena red de seguridad, pero su motivo era éste"*. Es la clase exacta de `D-56`: la regla aguanta, su justificación hay que rehacerla — y `D-56` ya recibió ese trato en `D-75`, así que hay precedente y forma. `D-31` no lo ha recibido | `grep -c '"CODACTA": "[0-9][0-9]*"' "docs/Federation APIs examples/FCF-partidos-temporada-jugada.txt"` → **240**; `… \| sort -u \| wc -l` → **240** únicos, sobre 240 `CODGRUPO` | **Arreglado** (`cc288cd`) |
| **H-13** | A-1 | **S3** | **El puerto explica tres campos nombrando el mecanismo de la RFFM, y en uno la explicación es además una trampa.** `FederationTeamRef.federationClubID` (`FederationClient.swift:212-213`) justifica su opcionalidad con *"en la RFFM se infiere del nombre del fichero del escudo"*; `crestURL` (216-217) con *"compuesta con el host que publica la propia respuesta"*, que es un campo de la RFFM (`calendar.host`, §F.15) y la FCF no tiene; y `letter` (209) con *"la letra que iba embebida en el nombre"*, que es la gramática de Madrid. La **forma** de los tres es correcta —el concepto es genérico y la opcionalidad es la unión honesta de las dos fuentes—, así que esto no es cambio de puerto: es que el comentario documenta **cómo lo obtiene una fuente** en vez de **qué es el dato**, y el puerto es lo que F9 va a leer.<br><br>**La trampa, que es lo que sube esto de nota al pie a hallazgo:** el patrón `00100_<10 dígitos>_<texto>` existe en las dos federaciones (§C.10.4 lo señala como prueba de plataforma común), pero **en la FCF ese número no es el club**. `00100_0001223396_MANLLEU.png` convive con `CODCLUB_CASA: "1023"`, y divergen en los cuatro casos mirados. Quien generalice `RFFMValue.federationClubID(fromCrestPath:)` por parecido de formato escribirá en `OpponentClub.federation_club_id` un número que no es la clave de club de esa federación — y la cadena de §3.7 empareja por ella | `grep -o '"ESCUDO_CASA": "[^"]*"' … \| head -4` frente a `grep -o '"CODCLUB_CASA": "[0-9]*"' … \| head -4` sobre el volcado FCF: `0001223396`/`1023`, `0001162525`/`2899`, `0000574621`/`1033`, `0000959029`/`1049` | **Arreglado** (`cc288cd`) |
| **H-14** | A-1 | **S4** | **Las cuatro sospechas del plan, contestadas — y dos salen bien.** **Sospecha 2 (la letra): correcta.** La extrae el **adaptador**, en `RFFMValue.teamName` (`RFFMValue.swift:167-181`), y `NormalizedName.swift:26-27` lo deja escrito (*"la letra no llega aquí: quien la separa es el adaptador"*). F9 no hereda la gramática de nombres de Madrid. **Sospecha 4 (la coordenada): correcta, tres códigos bastan.** La FCF **no necesita un cuarto eje** y de hecho necesita menos: `partidos?grupId=…` toma **un solo parámetro** ([Anexo FCF §C.10.1]), así que `federationSeasonID` y `modality` le sobran. El `disciplinaId` que colapsa (modalidad, género) de §C.10.3 **no entra en la ruta de ingesta** —solo en el descubrimiento, que §5.6 declara inexistente—, así que el género que la FCF sabe con certeza no le hace falta al calendario. Queda un hueco, y es de **F10**: el `/preview` de `D-58` tendrá *"dos caminos"* (§C.10.3) y hoy ni `FederationCoordinate` ni `FederationCalendar` pueden transportar *"la fuente sabe el género"*. **Sospecha 3 (`field` como coordenada del cuerpo): sobrevive.** La FCF es JSON desde `D-74`, y `field` es `String`: si volviese a HTML cabe una coordenada de raspado. **Sospecha 1: parcialmente** → H-13.<br><br>**Y una confirmación para F7/F8: la coordenada no hay que rehacerla.** `/api/standings?idGroup=…&round=9` (§F.8) y `/api/scorers?idGroup=…&idCompetition=…` (§F.13) **no piden `temporada` ni `tipojuego`**, y sus equivalentes de la FCF piden `grupId` (+`temporada` en goleadores, §C.10.1). `FederationCoordinate` es superconjunto suficiente para los cuatro: la jornada de F7 va como **parámetro del método**, no como campo de la coordenada — meterla ahí volvería la coordenada dependiente de la operación, y la FCF la ignora por `D-55` | `grep -rn 'teamName' backend/Sources`; §C.10.1 y §C.10.3 del Anexo FCF; §F.8 y §F.13 del Anexo RFFM | **Cerrado** |
| **H-15** | **A-6** | **S2** · **F10** | **`FederationError` tiene cuatro casos con semántica cuidada y en producción no los distingue nadie.** El propio fichero justifica la taxonomía en su cabecera: *"un caso de uso tiene que poder distinguir «la fuente no contesta» de «la fuente contesta algo que no entiendo»"*, y la ingesta *"reacciona distinto a cada uno"*. No lo hace: se **lanza** solo dentro de `Sources/Federation/` y se **discrimina** solo en `Tests/`. `IngestCalendar.swift:68-81` captura `any Error` y lo aplana con `diagnosticText(for:)`, que es `String(reflecting:)`. Y `ProblemMiddleware` —el `switch` exhaustivo de `DomainError` que existe para que un error nuevo no compile hasta decidir su HTTP— **no contempla `FederationError`**. Hoy no se nota porque el `202` responde antes de llamar a la federación (`D-88`); **F10 sí llama dentro de la petición** (§2.3-c, el `/preview`), y ahí las cuatro señales acabarían en el mismo 500. Anotado a A-6, que es el bloque de las costuras | `grep -rn 'FederationError' backend/Sources backend/Tests \| grep -v '^backend/Sources/Application/FederationError.swift'` → todos los `throw` en `Sources/Federation/`, todos los `case` en `Tests/`. Ninguno en `Application/`, `HTTPAdapter/` ni `App/` | **Abierto** — es de A-6 |
| **H-16** | **A-0** | **S3** | **`Plan de desarrollo-001.md:153` sigue vendiendo F9 como *scraping*.** La fila dice *"Adaptador **FCF** (*scraping*, ~34 peticiones, capacidades del catálogo)"*, y `D-74` cerró que la FCF publica API JSON y que el calendario entero cuesta **una** petición. Es la cifra de coste de la fase que viene después de F8: quien planifique F9 con esa fila delante presupuesta un raspador con control de concurrencia y *backoff*. La misma premisa caducada asoma en `Federation/FederationTransport.swift:23`, que cita *"[Anexo FCF §C.6]"* —sección obsoleta— para *"concurrencia y backoff"* | `sed -n '153p' "docs/Plan de desarrollo-001.md"` contra `D-74` y [Anexo FCF §C.10.4] | **Arreglado** (`cc288cd`) |
| **H-17** | **A-2** | **S1** | **La política de §3.7 es la regla del UPDATE, y contra Postgres no hay ni una aserción sobre un UPDATE.** El fichero del Dominio lo dice de sí mismo —*"todas las funciones de aquí son la regla del **UPDATE**, que es donde se destruyen datos"* (`UpsertPolicy.swift:21-24`)—, y la pregunta exacta que A-2 traía escrita (*"¿existe un test de nivel 3 que haga dos pasadas, la segunda con el campo vacío, y lea la columna después?"*) tiene respuesta: **no**. No es que falte contra Postgres: **el sentido que destruye datos no lo prueba nada por encima del nivel 1**, ni con dobles.<br><br>· **Nivel 3** — la única pasada doble del proyecto es `CalendarIngestionEndToEndTests.swift:201-202`, y repite **el mismo volcado**, así que ningún campo volátil llega nunca a `nil` en la segunda. La cabecera de la otra *suite* declara la omisión a propósito: *"lo que se prueba aquí es el **mapeo** y las **restricciones**, no la política de §3.7 — ésa ya la cubrió el nivel 1 … volver a probarla contra Postgres sería pagarla dos veces"* (`IngestionPersistenceTests.swift:14-19`).<br>· **Nivel 2** — `secondPassUpdatesInsteadOfDuplicating` (`IngestCalendarTests.swift:306`) recorre el sentido bueno, `nil` → valor: primera pasada sin marcador ni hora, segunda con los dos. **El sentido malo, valor → `nil`, no lo recorre nadie.**<br>· Y el testigo mecánico: **`grep -rn "Updated" Tests/PersistenceTests Tests/APITests` da cero aciertos**. Los cuatro contadores de `IngestionRun` que cuentan filas *actualizadas* no aparecen en los niveles 3 y 4 — se comprueba lo que se **crea**, nunca lo que se **reescribe**.<br><br>**Lo que no es este hallazgo, y conviene decirlo:** no es un fallo demostrado. La lectura del cableado sale bien y queda medida en H-21 — la trampa que el plan temía (*"un `Optional` de Fluent puesto a `nil` escribe `NULL`"*) está estructuralmente fuera de alcance. Lo que falta es **la medición**, y falta justo donde `D-75` dice que el error *"pierde el dato"* y `Match` no tiene `PATCH`. **F7 trae `StandingRow`, que se escribe con esta misma política**, así que la medición se paga una vez o tres | `grep -rn "Updated" backend/Tests/PersistenceTests backend/Tests/APITests` → 0. `grep -rn "\.execute(" backend/Tests/PersistenceTests` → 7 llamadas, y las dos consecutivas (201-202) con el mismo *fixture* | **Arreglado** (`4564617`) — tres tests de nivel 3 nuevos, con su mutación (§7) |
| **H-18** | A-2 | **S3** | **La rama `date == nil` del horario es inalcanzable desde el camino real, y lo que la pasada hace en su lugar no es lo que la rama describe.** `CalendarPass.swift:115` descarta el partido **antes** de la cadena y antes de fusionar (*"`guard let date = federationMatch.date else { report.skipped.append(…); return }"*), así que `Match.merging(date:)` y `Kickoff.merging(date:)` **nunca reciben `nil` en producción**: el `Date?` de las dos firmas es opcional solo para los tests. El nivel 1 demuestra *"la fecha se mueve con la fuente, pero su silencio no la vacía"* (`UpsertPolicyTests.swift:133`) y `Kickoff.swift:61-64` lo razona como *"`volatile` de §3.7 sobre una columna `NOT NULL`"*; lo que de verdad ocurre con un partido **ya guardado** cuya fecha la fuente deja de publicar es que **se descarta entero**, y con él el marcador, la hora y el campo de esa pasada. Es el lado **recuperable** de `D-75` —la pasada siguiente lo repone— así que no destruye nada y no sube de S3. Lo que no está escrito en ningún sitio es que la rama no se ejercita nunca y que el que protege la fecha es el `guard`, no la política | `grep -n "federationMatch.date" backend/Sources/Application/CalendarPass.swift` → un solo `guard`, en 115, **antes** del `merging` de 129-132. Ninguna otra llamada a `Match.merging` en `Sources/` | **Arreglado** (`4564617`) — escrito en los dos sitios: el `guard` de `CalendarPass` y la rama de `Kickoff.merging` |
| **H-19** | A-2 | **S3** | **El test de idempotencia de nivel 3 no comprueba que la segunda pasada no escriba.** `secondPassIsIdempotentAgainstRealConstraints` (`CalendarIngestionEndToEndTests.swift:194-217`) afirma `matchesCreated == 0`, `roundsCreated == 0`, `opponentClubsCreated == 0`, `teamsCreated == 0` y `skipped.isEmpty` — **ninguno de los cuatro `…Updated`**. Su rótulo es honesto (habla de restricciones), pero el hueco importa: si cualquiera de las columnas volátiles no diese la vuelta fiel —el `date` de Postgres contra el `Date` de UTC, el `HH:mm` de texto, el `venue` vuelto a limpiar—, `merged != existing` sería cierto en las **240** filas, la pasada del lunes reescribiría el calendario entero y **el verde no se movería**. Es la aserción más barata de todo el bloque, y la única que cubre a la vez las tres coerciones y el ida-y-vuelta del mapeo | `grep -n "expect" backend/Tests/PersistenceTests/CalendarIngestionEndToEndTests.swift` líneas 204-215: cinco aserciones, ninguna sobre `…Updated` | **Arreglado** (`4564617`) — los cuatro `…Updated == 0` añadidos, y el rótulo del test dice ahora *"y no escribe"* |
| **H-20** | A-2 | **S3** | **`RFFMValue.venue` es la única coerción de campo volátil que no pasa por la función que aplica «vacío no es un valor».** `sanitised` existe exactamente para eso —*"quita espacios, espacios duros y `&nbsp;`, y devuelve `nil` si no queda nada. **Vacío no es un valor** (`D-56`): esta es la función que lo aplica"* (`RFFMValue.swift:185-197`)— y la llaman `score`, `matchDate` y `kickoff`. `venue` (111-118) no: se defiende sola con `!text.isEmpty` más el colapso de espacios, lo que cubre `""` y `"   "` (sus dos tests de nivel 1, `RFFMValueTests.swift:109-113`) y **deja fuera las dos formas de callar que §F.11 documenta**: el `&nbsp;` sin descodificar y el espacio duro `\u{00A0}`. Un `campo` que solo trajera `&nbsp;` volvería como el texto literal `"&nbsp;"`, y `venue` es **volátil** (§3.7): se escribiría encima del nombre bueno del campo de juego. **Es reachability no observada** —§F.11 documenta el `&nbsp;` dentro de campos **numéricos**, no en `campo`—, así que la explotación concreta es *sospecha*; la asimetría de la frontera no lo es, y la frontera es justo lo que `UpsertPolicy.swift:72-76` declara que vive en el adaptador | `grep -n "sanitised\|public static func" backend/Sources/Federation/RFFMValue.swift` → tres de las cuatro coerciones la llaman; `venue` es la que no. **Y medido con el rojo del arreglo**: `venue("&nbsp;") → "&nbsp;"` y `venue("\u{00A0}") → " "` — una cadena de un espacio duro, que no es vacía y por tanto se escribía | **Arreglado** (`4564617`) — `venue` empieza por `sanitised` como las otras tres, con dos tests de nivel 1: el silencio y su reverso (un espacio duro **dentro** de un nombre no lo invalida) |
| **H-21** | A-2 | **S2** · ***después de la ingesta***, en la fase que abra la **corrección de `OpponentClub`** en el BFF — y **decidido antes de abrirla**, no dentro | **Las dos mitades de §3.7 se contradicen en un punto, y ahí la pasada da de alta un club duplicado sin reportarlo.** La política clasifica `OpponentClub.name` como **descriptivo**: lo corrige el administrador y la fuente **no lo reescribe nunca** (`D-18`). La cadena empareja clubes por el **paso 2** con `NormalizedName(name)`. Y `matchingName` lo justificaba afirmando que *"`NormalizedName` existe precisamente para que esa corrección no rompa el emparejamiento"* (`OpponentClub.swift:71-79`) — **es falso**: `NormalizedName` quita acentos, puntuación y caja (`D-80`), **no palabras**. Corregir `"C.D. GALAPAGAR"` a `"Club Deportivo Galapagar"` produce otra clave y el paso 2 deja de reconocer ese club **para siempre**.<br><br>**Con el paso 1 disponible no pasa nada** —`federation_club_id` resuelve y la corrección sobrevive; tiene test nuevo—, así que el caso vivo es *club sin clave de federación* **+** *nombre corregido*, y `D-76` deja de ser cosmética: rellenar el hueco es lo que mantiene vivo el único escalón que una corrección no rompe. Sin clave, la cadena cae al **paso 3** y crea. **Y nada lo para ni lo cuenta**: el `UNIQUE(name)` de §3.5 no lo ve —son dos nombres distintos—, y el desempate de `freeSlug` **le pone `-2` y lo deja pasar**, porque no puede distinguirlo del caso legítimo que existe para servir (*"dos clubes distintos con el mismo nombre"*, `CalendarPass.swift:391-399`). **Medido: 3 filas de club donde había 2, `opponentClubsCreated: 2`, y `skipped` vacío** — el informe de la pasada la describe como un día normal. El duplicado nace **huérfano** (el equipo no se reasigna, por `owned`), lo que lo hace menos grave y más difícil de ver; el siguiente equipo nuevo de ese club sí se le engancharía, y ahí la plantilla del club queda partida en dos filas.<br><br>**Por qué S2 y no S1: hoy no hay por dónde disparar el gatillo.** El `filter` de `openapi-generator-config.yaml` son cuatro operaciones y ninguna corrige un `OpponentClub`, así que el nombre solo puede cambiarlo un `UPDATE` a mano. **Las tres salidas, para la fase que lo abra:** (a) comparar por `slug`, que es inmutable y se deriva del nombre **original** — barato y sin migración, pero `D-82` hizo el *slug* y `NormalizedName` reglas **opuestas** a propósito, así que cambia la semántica del emparejamiento; (b) una columna de nombre de emparejamiento sembrada en el `INSERT` y nunca corregida — es lo correcto y es migración, o sea **A-5**; (c) aceptarlo y **reportar** el alta como sospechosa cuando el club se crea con un *slug* desempatado, que no arregla el duplicado pero lo hace visible. Ninguna es un parche: por eso no se arregla en esta ronda (§3, regla 2) | Nivel 2, `IngestionStore` sembrado con un club de nombre corregido y `federationClubID: nil` más su equipo rival con `federationTeamID`, y un calendario que trae ese equipo sin clave de club. Salida: `clubes: 3`, `nombres: ["Club Deportivo Galapagar", "CELTIC CASTILLA C.F.", "C.D. GALAPAGAR"]`, `slugs: [… "c-d-galapagar", "c-d-galapagar-2"]`, `creados: 2`, `descartes: []`. El camino que sí aguanta quedó como test permanente: `aRenamedClubIsMatchedByItsFederationKey` | **Abierto** — documental corregido (`4564617`); la decisión, a su fase |
| **H-22** | A-2 | **S4** | **El cableado de la regla sale bien, y queda medido en tres puntos.** **(1) `merging` siempre fusiona sobre valores de la base, y en el mismo ámbito.** `IngestCalendar.swift:124-135` abre el ámbito 2, y **dentro** `CalendarPass.init` carga los cuatro candidatos (`CalendarPass.swift:47-50`) y `run` escribe. `existing` no puede ser una copia en memoria de otra transacción ni un blanco recién construido. **(2) El `UPDATE` reescribe la fila entera desde la entidad ya fusionada**, columna por columna (`FluentIngestionRepositories.swift:211-224` y sus tres hermanos): nadie construye nunca un `Record` a partir del *payload* entrante, así que la trampa que A-2 venía a buscar —*"un `Optional` de Fluent puesto a `nil` escribe `NULL` en la columna, no se la salta"*— **no tiene por dónde ocurrir**. No es que esté defendida: es que no hay ese camino. **(3) `UpsertPolicy.owned` con `incoming != nil` es inalcanzable en producción**: el único llamante pasa `nil` literal siempre (`CalendarPass.swift:265-266`), y el comentario de arriba lo dice. La protección de `D-20` la dan **las dos cosas**, y con que quede una sigue en pie.<br><br>**Y dos divergencias entidad↔columna que no son de §3.7 pero se ven desde aquí y conviene no volver a descubrir.** `merging` conserva el `updatedAt` viejo (`Match.swift:147`) y `apply()` no toca ni `created_at` ni `updated_at`: los dos son `@Timestamp` de Fluent (`MatchRecord.swift:39-40`), así que **la columna la sella el driver y el valor del Dominio se descarta al escribir**. Consecuencia: el `Clock` inyectado **no** gobierna esas dos columnas —sí `last_synced_at`, que es campo de dominio— y la entidad devuelta por un `merging` lleva un `updatedAt` caducado hasta que se relee. Ninguna de las dos cosas rompe nada hoy; las dos sorprenden si se descubren depurando | Las tres, por lectura de los ficheros y líneas citadas. La (3) además con `grep -n "owned" backend/Sources` → un llamante | **Cerrado** |
| **H-23** | **A-3** | **S2** · **F6-bis** — *el hallazgo del bloque* | **Con la base caída, `D-86` sigue continuando y `D-85` deja de apuntar — y son las dos mitades que `D-86` declara inseparables.** El criterio escrito es *"continuar solo es seguro cuando el fallo deja constancia y no deja estado a medias"*, y para el fallo de **infraestructura** —el único que **no está aislado por competición**, como el propio plan sospechaba— la primera mitad se cumple y la segunda no. Medido parando el contenedor a mitad de recorrido, con tres competiciones: **el recorrido continúa las tres** (`entradas: 3`, desenlaces `synced, failed, failed`, `hasFailures: true`), y en `ingestion_runs` queda **una sola fila**, la de la que fue bien. De las dos que fallaron **no queda constancia ninguna**, porque el ámbito 3 tampoco puede escribir contra una base que no está y `IngestCalendar.swift:86` se lo traga a propósito (`do { try await record(failed, actor: actor) } catch {}`). Es el *"fallo que se traga a sí mismo"* de la pregunta 2 del bloque, llegando por la puerta de la 4.<br><br>**Lo que sí sobrevive, y por eso no es S1:** el código de salida —`IngestCommand.swift:231` lo deriva de `hasFailures`, así que el cron ve el fallo— y el informe por consola, que lleva los tres desenlaces. Y se repone solo: las dos competiciones sin sincronizar entran en la pasada siguiente. Lo que se pierde es **el registro durable**, que es justo lo que `D-88` dice que hay que mirar porque `last_synced_at` no sirve para saber si algo va mal. **Además, el recorrido falla rápido**: tras caerse la base, la tercera competición ni llega a llamar a la federación (`llamadas: 2` para 3 competiciones), porque revienta en el ámbito 1 — así que no hay peticiones desperdiciadas contra el tercero, que era el otro riesgo imaginable.<br><br>**Por qué F6-bis y no más tarde:** F7 y F8 montan dos pasadas más —`StandingRow` y `LeagueScorer`— sobre **este mismo recorrido**, así que la garantía rota se hereda tres veces en vez de una. Tres salidas, y la elección es de diseño: (a) **distinguir el fallo de infraestructura y abortar el recorrido**, que es lo que `D-86` dice que hay que hacer cuando no hay constancia; (b) acumular las pasadas fallidas y escribirlas cuando la base vuelva, que añade estado en memoria a un job que hoy no lo tiene; (c) **aceptarlo y escribirlo** —la constancia de `D-85` vale *"salvo que la base sea el que falla"*—, que no cuesta código pero obliga a enmendar `D-85` y `D-86` | Nivel 3 con tenant real: tres competiciones en el `scope`, y un `FederationClient` que ejecuta `docker compose stop db` justo antes de devolver el calendario de la segunda. Después se revive la base y se cuentan las filas de `ingestion_runs`. Salida: `llamadas: 2`, `entradas: 3`, `desenlaces: synced, failed, failed`, `hasFailures: true`, `filas: 1` | **Arreglado** (`4d66aa0`) — salida (a): se para, y la infraestructura se detecta **preguntándole a la base**, no clasificando el error |
| **H-24** | A-3 | **S3** — y **S2 si llega a F7 sin arreglar** | **Una pasada que fue bien se registra como fallida si el que falla es el tercer ámbito, y los tres testigos se contradicen.** `IngestCalendar.execute` mete `record(run)` **dentro** del `do` (`IngestCalendar.swift:64-67`), así que un fallo al escribir el registro de una pasada **con éxito** cae en el `catch`, que construye un `IngestionRun` con `outcome: .failed` y lo escribe. El ámbito 2 ya comprometió: los datos están, `last_synced_at` está puesto. Medido con el ámbito 3 reventado y el 4 —el del `catch`— bueno, que es el caso del fallo **transitorio** (un *pool* agotado un instante, un relevo del *pooler* de §6.4): **1 partido escrito, `last_synced_at: 2026-09-21`, y la fila del registro diciendo `failed`**.<br><br>Quedan tres señales que dicen cosas distintas de la misma pasada: `last_synced_at` dice *"sincronizada con éxito"* (§3.2) y además la deja fuera del antirrebote de `D-87` seis horas; `ingestion_runs` dice `failed`, que es lo que `D-89` proyecta como `ingestionHealth`; y el recorrido la reporta como fallida, así que el job sale con código distinto de cero. **Y el motivo que se registra es el del fallo al apuntar** —una excepción de conexión— **no nada sobre la pasada**, así que quien depure mirará al sitio equivocado, que es exactamente lo que el comentario de `IngestCalendar.swift:83-85` quería evitar y aquí consigue lo contrario. Es S3 porque se arregla donde está —decidir qué hace `execute` cuando lo único que falla es apuntar— pero **F7 copia la forma de este método** para `StandingRow`, y entonces son tres | Nivel 2 sobre Postgres real: se envuelve el `TenantUnitOfWork` real en uno que cuenta ámbitos y lanza en el **3.º** (el `record` del camino de éxito), dejando bueno el 4.º (el `record` del `catch`). Salida: `partidos escritos: 1`, `last_synced_at: 2026-09-21 14:13:20 +0000`, `filas ingestion_runs: 1`, `outcome: failed` | **Arreglado** (`4d66aa0`) — el registro del camino de éxito sale del `do`; se lanza `runNotRecorded` y no se escribe fila |
| **H-25** | A-3 | **S4** | **`D-83` y `D-85` aguantan un fallo que no es el que se probó, y queda medido.** Con una violación de restricción **real** dentro del ámbito 2 —`23505` sobre `uq:matches.federation_match_id`—: el ámbito 3 **se ejecuta y escribe** (`filas: 1`, `outcome: failed`), el ámbito 2 se deshace entero (`jornadas: 0`, `partidos: 0`, `last_synced_at: nil`) y el registro guarda **el motivo verdadero**, con la clave duplicada dentro: *"duplicate key value violates unique constraint «uq:matches.federation_match_id», detail: Key (federation_match_id)=(SHARED) already exists"*. Las preguntas 1 y 2 del bloque quedan contestadas: **el *pool* no devuelve una conexión envenenada**, porque el `rollback` que emite `database.transaction` al propagarse la excepción deja la sesión limpia antes de soltarla — el `25P02` no sobrevive al cierre del ámbito.<br><br>**Y el aviso de §5.1 del README —el `25P02` que hace que el segundo intento falle por el motivo equivocado— no alcanza a la pasada, por una razón de forma:** `CalendarPass` **no tiene ni un `catch` ni un `try?`** en sus 436 líneas, así que el primer error de SQL se propaga y **no hay una segunda sentencia dentro de la transacción ya abortada**. El aviso vale para quien escriba un test con dos operaciones en el mismo ámbito —se ha cobrado tres— pero no para el camino de producción. Igual que H-22: no es que esté defendido, es que no hay ese camino | Nivel 3 con tenant real: dos competiciones en la misma temporada, una pasada buena sobre la primera con `federationMatchID: "SHARED"`, y otra sobre la segunda con la **misma** acta. Los candidatos se cargan filtrados por competición (`CalendarPass.swift:50`), así que la segunda no la ve, hace `INSERT` y choca. `grep -nE "catch\|try\?" Sources/Application/CalendarPass.swift` → dos `try?`, los dos en `freeSlug`, ninguno alrededor de una escritura | **Cerrado** |
| **H-26** | A-3 | **S3** | **Los dos tests que guardan `D-83` y `D-85` provocan el fallo con un `DomainError`, no con un fallo de la base — y es la pregunta 3 del bloque, con respuesta «no».** `aFailedPassLeavesNothingBehind` y `theRunRecordSurvivesTheRollback` usan `brokenCalendar()`, *"un equipo contra sí mismo, que la invariante de `Match` (§3.5) rechaza"*, y los dos esperan `DomainError.self`. Es un fallo **del lado de Swift**: la invariante lanza **antes** de que se emita la sentencia, así que la transacción se deshace sin que Postgres haya rechazado nunca nada y **la conexión no llega a entrar en `25P02`**. Son buenos tests y prueban lo que dicen; lo que no ejercita **ninguno** es el camino que el bloque venía a medir —el que sí existe en producción, porque las restricciones de §3.5 son siete `UNIQUE` y una FK compuesta—. H-25 lo midió a mano y salió bien, así que esto no es un fallo: es que **la garantía vuelve a depender de que alguien lo repita a mano**, que es la misma forma que H-17. El arreglo es barato: el vehículo de la reproducción de H-25 es un test más | `grep -n "expect(throws:" Tests/PersistenceTests/CalendarIngestionEndToEndTests.swift` → `DomainError.self` en los dos casos de fallo (272, 334). `grep -rn "PSQLError" Tests/` → ninguna aparición en los niveles 3 y 4 | **Arreglado** (`4d66aa0`) — test de nivel 3 con un `23505` real, y su mutación |
| **H-27** | **A-4** | **S2** · **F10** — *el hallazgo del bloque* | **Detrás del `202` no hay nadie escuchando: el informe se tira y los errores también.** `IngestionHandler.swift:167-169` es `await background.enqueue { _ = try? await useCase.execute(scope: scope, actor: actor) }`. El `try?` se traga **todo** lo que `execute` lance —incluidos los dos casos que A-3 acaba de añadir, `databaseUnavailable` (H-23) y lo que venga de `runNotRecorded` (H-24)— y el `_ =` tira el `ClubIngestionReport` **entero**, con su `hasFailures` y su `abortedByInfrastructure`, que es justo la bandera que A-3 creó para que el llamante pudiera distinguir *"falló una"* de *"el recorrido se paró"*. **En la ruta del job las dos señales existen** —`IngestCommand.swift:231` deriva el código de salida y la consola imprime los desenlaces—; en la ruta del `202` **no existe ninguna**.<br><br>**Medido, y la variante parcial es la peor.** Con la base parada **a los 5 s** de un `202` que aceptó **dos** competiciones: la primera escribe su fila (`succeeded`, 12:24:29) y la segunda **se pierde sin dejar nada**. El log del servidor, quitado el ruido del *pool*, tiene **una sola línea** y es de Vapor (`INFO POST /v1/ingestion-runs`): nuestro código no dice **nada**. Y la vía que `D-88` prevé para enterarse miente por omisión — `GET /v1/ingestion-runs?competitionId=0299af02…` devuelve como más reciente `2026-09-12T12:22:00Z succeeded`, **anterior al `202` de las 12:24**, así que `ingestionHealth` (`D-89`) evaluaría **`ok`**. Con la base parada **desde el principio** no se escribe ni una fila (8 antes, 8 después) y el único `ERROR` del log es de `AsyncKit` quejándose del *pool*, que desaparece en cuanto la base vuelve — el trabajo aceptado, no.<br><br>**Por qué S2 y no S1: no se destruye nada y se repone solo.** Las competiciones que no llegaron a correr **no han movido su `last_synced_at`**, así que entran enteras en el disparo siguiente del cron — el mismo argumento con el que A-3 aceptó parar el recorrido. Lo que se pierde es que **quien pulsó el botón no se entera jamás**, y el `202` le dio una lista de ids diciéndole que sí. **Y hay una razón de forma para no parchearlo aquí:** en `Sources/Application/` **no hay un solo `Logger`**, y en `HTTPAdapter` solo lo tienen `ProblemMiddleware` y `RequestTraceMiddleware` — los dos en el camino de la **respuesta**. Apuntar un fallo de fondo exige **un puerto nuevo** (o el `swift-metrics` que ya está en el grafo y no se usa, A-3 → A-7), que es decisión de diseño y no corrección de auditoría (§3, regla 2). **F10 es su fase porque F10 escribe el segundo `202`** (`D-67`), y con él la segunda copia de este silencio; va de la mano de **H-15**, que es el mismo problema un paso antes —los errores que no se distinguen— en el mismo camino | `curl -X POST …/v1/ingestion-runs -d '{"seasonId":"6b236687…"}'` → `202` en 0,016 s con dos ids · `sleep 5 && docker compose stop db` · a los 20 s: `filas 8→9`, y `grep -iv "query\|connection\|waitlist\|Pruning"` sobre el log deja **una** línea, la de Vapor. Variante inmediata: `filas 8→8`. Y `grep -rn "DetachedBackgroundWork" Tests/` → **0 aciertos**; la única instancia de test es `InlineBackgroundWork` (`IngestionEndpointTests.swift:75`) | **Arreglado a medias, y la mitad que falta tiene fase** (`77b2056`). Lo que se cierra: el fallo **se registra**, con dos tests, **cuatro mutaciones cazadas** y verificado en la ruta que ningún test alcanza —`DetachedBackgroundWork` contra el servidor, parando Postgres a los 5 s de un `202`—. Lo que **no** cierra, y va escrito en el código: **un log lo lee el operador, no el backoffice**; que la pantalla se entere sin *push* exige fila desde el instante en que se acepta → **F10**, con las dos salidas evaluadas en Plan §4.1 |
| **H-28** | A-4 | **S3** — y **S2 si llega a F10 sin arreglar** | **La federación sin adaptador da 501 por una ruta y un `202` mudo por la otra, y el dato para decidirlo ya estaba leído.** `plan()` devuelve `(federation, competitions)` y `plannedCompetitions` se queda solo con los ids (`IngestClubCalendars.swift:143`), así que la comprobación de `federationAdapterMissing` —que vive en `execute`, línea 57— **queda del lado de allá de la respuesta**. Con el mismo club y en el mismo instante: `competitionIds` con **uno** → **501** con su cuerpo RFC 7807 (*"No hay adaptador de ingesta para 'fcf'"*); `seasonId` → **`202` aceptando dos competiciones**, cero filas escritas y **cero menciones** de `fcf`, `adapter` o `501` en el log.<br><br>**Es el caso que `D-88` dice que el `202` existe para evitar**, con sus mismas palabras: *"planificar antes de responder es lo que hace que una `seasonId` inexistente dé 404 aquí y no un `202` seguido de un fallo que nadie ve"*. La mitad de la temporada está cubierta —medido: `seasonId` desconocida → **404**, e id desconocido dentro de una lista de dos → **404**, las dos antes de empezar—; la del adaptador no, **y es la única que se sabe con certeza un instante antes de responder**. Hoy es alcanzable: `Club.federation` es dato (`D-17`) y la FCF está en el catálogo sin adaptador hasta F9. **F10 lo hereda con creces**: `/federation-link` (`D-67`) devuelve `202` y va **precisamente sobre enganchar una federación**, así que ahí el adaptador ausente deja de ser el caso raro | `update club_atleti.clubs set federation='fcf';` y dos `curl` seguidos: `{"competitionIds":["db679b16…"]}` → **501**; `{"seasonId":"6b236687…"}` → **202** con dos ids, `filas 9→9`, `grep -ic "fcf\|adapter\|501" log` → **0**. Restaurado con `update … set federation='rffm';` | **Arreglado** (`5c045f4`) — la guarda pasa a `plannedCompetitions`, con rojo de aserción y **dos mutaciones cazadas**; verificado contra el servidor: las dos puertas dan **501** con el mismo cuerpo, y con `rffm` la temporada sigue dando **202** |
| **H-29** | A-4 | **S4** | **Las preguntas 1 y 2 salen bien, y quedan medidas.** **(1) El *pool* sobrevive a la respuesta, y no por suerte: nunca fue el de la petición.** El `unitOfWork` se construye con `app.db(.control)` en la raíz de composición (`Configure.swift:73`), que es el *pool* de la `Application` —uno solo, §6.4—, así que el trabajo de fondo abre ámbitos nuevos contra el mismo sitio que el *handler*. Medido: `202` en **0,016 s** y las dos filas aparecen entre los 3 y los 8 s siguientes, las dos `succeeded`, con peticiones **reales** a la RFFM (4,4 s y 6,1 s) y `0 created / 0 updated` —segunda pasada idempotente— sobre `psql_connection_id: 2`. El `Task { }` de `DetachedBackgroundWork` hereda además el `@TaskLocal` del tenant, y aunque no lo heredara `FluentTenantUnitOfWork.resolveTenant` tiene la vía del job (líneas 49-61): el `actor` viaja capturado en el cierre. **(2) El `SIGTERM` no deja nada a medias, que es lo que el comentario promete.** Medido: señal a los 2 s de un `202`, **proceso muerto en 0,21 s** —no espera al trabajo de fondo, y el log enseña el *pool* cerrándose con la pasada en vuelo— y **ninguna fila nueva**: la transacción abierta se deshizo con la conexión. `D-83` aguanta, así que *"si el proceso muere no hay reintento, y no hace falta"* es **cierto en su mitad de atomicidad**; su otra mitad —que nadie se entera— es H-27.<br><br>**Y una tercera cosa que salió sola y conviene tener escrita: el `202` de lista vacía.** Hoy, 2026-09-12, `POST` con `{}` devuelve `202` con `"competitionIds": []`, porque la 2025/26 acabó el 30-06 y no hay vigente (`plan()` → `guard let season else { return (federation, []) }`). Es correcto y además es **el único caso en que el `202` dice la verdad sobre que no va a pasar nada** — y la dice por la forma del DTO, porque la lista planificada viaja en la respuesta. Quien toque esa respuesta en F10, que sepa que esa lista es la única señal honesta que hoy tiene el cliente | (1) `curl -w "%{time_total}"` + conteo de `ingestion_runs` a 1/3/8/15 s · (2) `kill -TERM $(pgrep -f "Run serve")` a los 2 s y espera activa sobre `kill -0` · (3) `select start_date, end_date from club_atleti.seasons` → `2025-07-01 … 2026-06-30` contra la fecha de hoy | **Cerrado** |

### Nota de cierre de A-0 · ¿la deriva es puntual o sistemática?

**Las dos cosas, y la línea que las separa es útil.**

- **Las citas están intactas: 87 de 87.** No hay una sola referencia cruzada roída en el código, y eso con 89
  decisiones y ~16.400 líneas entre fuentes y tests. El mecanismo de control de Plan §9 funciona.
- **Las cifras derivan, y sistemáticamente.** Los tres hallazgos S3 (H-02 aparte) son **cantidades que eran
  ciertas cuando se escribieron**: operaciones del *spec*, líneas del *spec*. Nadie las volvió a contar
  porque contar no es gratis a mano — y por eso se desfasan solas con cada fase.

**Lo que se deriva para A-7**, que es donde vive el arnés: **las cifras son automatizables y la prosa no.**
Un comprobador que cuente operaciones, tests y líneas y falle si el documento dice otra cosa habría cazado
H-03 y H-04 el día que nacieron, y cuesta veinte líneas. **Pero no habría cazado H-01** —la frase que se
contradecía— **ni H-02** —la cita ausente—, que son las dos que de verdad engañan al lector. Conclusión para
A-7: automatizar el recuento, **y no pretender que eso cubra la revisión**.

**Y una advertencia de método para los bloques que vienen**, que este bloque se ha ganado en carne propia:
`grep -oE "D-[0-9]+"` produce **falsos positivos** (`LLD-001` contiene `D-001`; `U+266D-266F`, dentro de un
*fixture* HTML, produce `D-266`). Los tres "roídos" del primer barrido eran artefactos del patrón, no
hallazgos. **Verificar de dónde sale cada coincidencia antes de anotarla.**

### Nota de cierre de A-1 · ¿abstrae una federación o abstrae la RFFM?

**Abstrae bien el partido y mal el sobre, y la línea que los separa no es casual.**

- **Lo de dentro está genérico, y sobrevive al ensayo en seco entero.** `FederationMatch` y
  `FederationTeamRef` recorren campo a campo el volcado de la FCF sin un hueco: `CODACTA`→`federationMatchID`,
  `CODEQUIPO_*`→`federationTeamID`, `CODCLUB_*`→`federationClubID`, `CAMPO`/`CODIGO_CAMPO`→`venue`/`venueCode`,
  `COMIENZO1` partido en `date`+`kickoff` (`D-30`), y las **dos trampas al revés** de §C.10.5 —el `"0"` que
  significa *"sin jugar"* y el `CERRADA`/`ESTADO` que lo desambigua— caen **dentro del adaptador**, que es
  donde §C.10.5 pide que caigan: *"cada adaptador decide qué es «no hay marcador»; el puerto recibe `nil`"*.
  `MatchResult.swift:10-11` y `UpsertPolicy.swift:73-74` ya lo tienen escrito con las dos federaciones
  nombradas. **Lo único de la FCF que no tiene sitio es `LATITUD`/`LONGITUD`**, y no debe tenerlo: `Match.venue`
  es texto libre (§3.2) y el campo con entidad propia está declarado fuera de alcance en §F.5.
- **Lo de fuera está cortado a la medida de Madrid.** Los cinco campos de sobre son cinco campos del
  `__NEXT_DATA__` de la RFFM, uno por uno, y la FCF publica **uno** (H-08). No es que falte un campo: es que
  el sobre **no existe** en la otra fuente, porque en la FCF la identidad de la coordenada vive en llamadas
  distintas de la del calendario. Y de ahí sale la única consecuencia funcional del bloque, H-09.

**Por qué la deriva se concentró ahí, que es la lección transferible.** El partido se diseñó **contra dos
anexos** —`FederationClient.swift` cita §F.3, §F.4, §F.5, §F.11 y §C.10.5 en el mismo fichero— y el sobre se
diseñó **contra el volcado que había delante**, que era el de la RFFM: §F.15 es de 2026-08-28 y es literalmente
la estructura del sobre, campo por campo, en el mismo orden. **El puerto es genérico exactamente donde el
diseño tuvo dos fuentes a la vista**, y eso es `D-74` otra vez: *"con el anexo delante, no de memoria"* funciona,
y funciona **solo para la parte que se miró con los dos anexos abiertos**.

**Y la premisa de §1 aguanta: A-0 y A-1 juntos dan cero hallazgos S1.** Esto sigue siendo una auditoría y no
una fase de reparación previa. Los cinco S2 tienen fase asignada —F9 en H-08 y H-09, F10 en H-15, y H-11 es
reabrir A-0—, que es lo que §6-bis exige para que no cuenten como S1.

### Lo que A-1 entrega: la forma del puerto antes de que F7 y F8 le añadan dos métodos

Cuatro reglas, y son la respuesta a *"qué se mueve al adaptador"*:

1. **Los DTOs de F7 y F8 no copian el sobre de `FederationCalendar`.** Es la trampa que el §4 del plan temía
   —*"ese supuesto se habrá copiado ya dos veces más"*—, y aquí es concreta: `/api/standings` y `/api/scorers`
   de la RFFM **también** devuelven `competicion` y `grupo` (§F.8, §F.13) y sus equivalentes de la FCF **no**
   (§C.10.6, §C.10.7). Si `FederationStandings` nace con un `competitionName` opcional y un rótulo
   obligatorio, H-08 y H-09 se reproducen dos veces más antes de que nadie escriba el adaptador catalán.
2. **La coordenada no se toca** (H-14). Tres códigos más `modality`, y la **jornada de F7 va como parámetro
   del método** —`fetchStandings(_ coordinate:, round:)`— porque es de la operación y no de la competición, y
   porque la FCF la ignora por `D-55`: ese `round` que se manda y no se usa **es** la capacidad
   `providesRoundStandings` vista desde el puerto, y el sitio donde se decide qué hacer con él es el caso de
   uso, que ya lee el catálogo del Dominio.
3. **La identidad de la coordenada se diseña una vez, no por método.** H-09 no es *"a `FederationCalendar` le
   falta un campo"*: es que **la evidencia de que la coordenada sigue apuntando a esto** —lo que `D-84` exige
   antes de escribir— no es homogénea entre fuentes, y hoy vive escondida en un campo opcional del calendario.
   Decidirlo en F9 con las tres opciones de H-09 sobre la mesa, y decidirlo **antes** de escribir el segundo
   adaptador, no dentro.
4. **Los comentarios del puerto se reescriben en términos del dato, no del mecanismo** (H-13). Es lo más
   barato de la lista y lo que más rinde: el puerto es el fichero que F9 abrirá primero.

**Lo que este bloque necesitó y no estaba en su «Leer antes»**, para el que venga: los **volcados** de
`docs/Federation APIs examples/FCF-*.txt`. El ensayo en seco de §C.10 contra los DTOs no se puede hacer con el
anexo solo —el juego de claves completo del objeto de partido está en el volcado, no en el anexo, y H-08 sale
de contarlas—. Añadir a la lista: `FCF-partidos-temporada-jugada.txt`. **No hizo falta** nada de
`CalendarPass` más allá de comprobar qué campos consume, ni ningún test más allá de contar sitios de
construcción de los DTOs (**7 `FederationCalendar`, 4 de cada uno de los demás, en 10 ficheros**) — que es la
cifra que dice lo que cuesta hoy cambiar la forma, y por eso está aquí.

### Nota de cierre de A-2 · ¿es la que corre de verdad contra Postgres?

**Sí, y no hay nada que lo diga.** Es la respuesta menos cómoda de las dos posibles, porque no deja arreglo que
enseñar: el cableado está bien y el hallazgo es que **nadie lo había comprobado**.

- **La regla llega intacta a la base, y por una razón de forma y no de cuidado.** La política se aplica en el
  Dominio sobre valores **leídos de la base en el mismo ámbito**, y el adaptador reescribe la fila **entera**
  desde la entidad ya fusionada. Nadie construye nunca una fila a partir de lo que llega de la fuente, así que
  la trampa que este bloque venía a buscar —el `nil` que se convierte en `NULL` porque el `UPDATE` se armó con
  el *payload*— **no tiene camino** (H-22). Eso es mejor que estar defendida: no hace falta acordarse.
- **Y la comprobación de mutación de F3 no cubría esto, exactamente como §5 sospechaba.** 11/11 demuestra que
  la regla es correcta y que sus tests la cazan. Lo que este bloque añade es que **el cableado tampoco lo medía
  el nivel 2**: sus dobles tienen el sentido bueno probado y el malo no, así que romper el cableado del sentido
  destructivo **no tumbaba nada por encima del nivel 1**.

**La asimetría que lo explica, y que es la lección transferible.** Los tres tests de nivel 3 que existían
—idempotencia, *rollback*, registro— comprueban **lo que se crea** y **lo que se deshace**. Ninguno comprobaba
**lo que se conserva**, que es una propiedad negativa y no tiene contador: no aparece en el informe, no rompe
ninguna restricción y no cambia ningún recuento. Un `UPDATE` que borra un dato bueno **pasaba por verde en los
cuatro niveles** — literalmente el único fallo que ningún mecanismo del proyecto vigilaba.

> Dicho en el vocabulario de §2: los niveles 3 y 4 no tenían **ni una** aserción sobre un `…Updated`. La regla
> que el propio Dominio declara *"la del UPDATE, que es donde se destruyen datos"* estaba probada solo donde no
> hay `UPDATE`.

**Lo que se deriva para A-7**, que es el bloque de la calidad de los tests: **«no se creó nada» no es «no se
escribió nada»**, y la segunda es la que hace segura la cadencia semanal de §5.6. Los cuatro contadores de
`IngestionRun` ya existían; usarlos en las aserciones cuesta una línea por test y es lo que convierte el nivel
3 en una comprobación de la política y no solo del esquema. Va a la lista de A-7 junto a su tercer punto
—*"aserciones sobre el doble en vez de sobre el efecto"*—, del que esto es la variante de nivel 3: **aserciones
sobre lo que aparece en vez de sobre lo que sobrevive**.

**Lo que este bloque necesitó y no estaba en su «Leer antes»**, para el que venga:

- **`Sources/Application/IngestCalendar.swift`.** El plan lo manda a A-3, pero A-2 no puede contestar su propia
  pregunta sin él: que la carga de candidatos y la escritura compartan **el mismo** ámbito de tenant es la
  mitad de lo que hace que la política se aplique sobre el dato de la base y no sobre un blanco.
- **Los cuatro `…Record.swift` de `Sources/Persistence/`.** El «dónde mirar» solo lista
  `FluentIngestionRepositories.swift`, y ahí está el `apply()`; pero lo que decide el bloque —que se escriben
  **todas** las columnas y que las dos marcas de tiempo son `@Timestamp` y no dato de dominio— está en los
  modelos.
- **`Sources/Federation/RFFMValue.swift`.** `UpsertPolicy.volatile` documenta que *"la frontera se aplica en el
  adaptador"*, así que **la mitad de la regla vive en `Federation` y no en `Domain`**. Auditar §3.7 sin abrir
  ese fichero deja la regla pareciendo completa, y de mirarlo sale H-20.

**No hizo falta** nada de `MatchingChain` más allá de qué desenlace lleva a qué `merging` —la cadena es A-1 y
F4—, ni nada de *tenancy* más que el aviso de §6.2 que el propio bloque ya citaba.

### Lo que A-2 entrega: el mapa rama-a-test de las tres reglas

Las cuatro clases de campo de §3.7 contra los niveles que las prueban, **ya con la ronda de arreglos dentro**.
«Sorteada» significa que el camino real no llega a esa rama; «—» que no hay test en ese nivel y no hace falta.
Los tres nombres en **negrita** son los que no existían antes de este bloque.

| Clase (§3.7) | Rama | Nivel 1 | Nivel 2 (dobles) | Nivel 3 (Postgres) |
|---|---|---|---|---|
| **descriptivo** | la corrección del administrador sobrevive | `OpponentClubTests` ×3 | `aRenamedClubIsMatched…` | **`aSilentPassDestroysNothing`** |
| **volátil** | la fuente dice algo y gana | `UpsertPolicyTests` | `secondPassUpdates…` | `ingestsAPlayedSeason` |
| **volátil** | la fuente calla y **no borra** | `UpsertPolicyTests`, `MatchTests` ×2, `RoundTests` | — | **`aSilentPassDestroysNothing`** |
| **volátil** (`match_date`) | el silencio conserva la fecha | `UpsertPolicyTests:133` | — | **sorteada** (H-18) |
| **volátil** (`kickoff_time`) | sin marcador, vuelve a provisional | `UpsertPolicyTests`, `MatchTests` | — | **`withoutAScoreTheVanishing…`** |
| **volátil** (`kickoff_time`) | con marcador, se ignora | `UpsertPolicyTests`, `MatchTests` | — | **`aSilentPassDestroysNothing`** |
| **de propiedad** | la ingesta no reasigna el club | `UpsertPolicyTests`, `TeamTests` ×2 | `engagedOwnTeam…` | **sorteada** (H-22) |
| **de emparejamiento** | no sobrescribe la clave que hay | `UpsertPolicyTests`, `MatchTests`, `TeamTests`, `OpponentClubTests` | — | **`aSilentPassDestroysNothing`** |
| **de emparejamiento** | rellena el hueco (`D-76`) | los mismos cuatro | — | **`theMatchingHoleIsFilled…`** |
| **la composición de dos clases** | el nombre corregido y el emparejamiento por nombre | — | `aRenamedClubIsMatched…` | **abierto** (H-21) |

Y **la regla de forma que F7 hereda**, que es lo que este bloque compra para la fase siguiente: `StandingRow`
se escribe con esta misma política, así que su rebanada de nivel 3 nace con **dos pasadas y la segunda muda**,
no con una sola. El coste de escribirla así desde el principio es una función auxiliar; el de descubrirlo
después es el de H-17.

### Nota de cierre de A-3 · ¿aguantan un fallo que no sea el que se probó?

**Aguantan el fallo de datos y no aguantan el de infraestructura, y la línea que los separa es exactamente la
que `D-86` no miró.**

- **El fallo de datos sale bien, y con margen.** Una violación de restricción real hace todo lo que `D-83` y
  `D-85` prometen: la transacción se deshace entera, el registro se escribe desde su propio ámbito, y el
  motivo que guarda es el verdadero y no un `25P02` sobre otra cosa (H-25). La pregunta que más miedo daba
  —*"¿y si el *pool* le devuelve la conexión envenenada al tercer ámbito?"*— tiene respuesta y es que no puede:
  el `rollback` va antes de soltar la conexión. **Eso está bien por diseño de Fluent, no por cuidado nuestro**,
  y conviene saberlo: es una propiedad heredada, no una defensa escrita aquí.
- **El fallo de infraestructura parte `D-86` por la mitad** (H-23). Su criterio —*"se continúa **y** se
  apunta"*— se enunció mirando el fallo que estaba delante, que era el de una coordenada caducada: aislado por
  competición, con la base viva para apuntarlo. Cuando el que falla es **la base**, continuar sigue
  funcionando y apuntar deja de funcionar, y la decisión que `D-86` tomó se apoya en la mitad que desaparece.

**La asimetría que lo explica, y que es la lección transferible.** `D-83` y `D-85` están escritas contra un
fallo **dentro** del sistema —una fila que no cabe, una invariante que salta— y para ése el tercer ámbito es
una red que funciona. Pero el tercer ámbito **usa el mismo recurso que acaba de fallar**: si lo que se rompió
es la base, la red está hecha del material que se rompió. Es la forma general del *"fallo que se traga a sí
mismo"*, y se reconoce por una pregunta que sirve para cualquier registro de errores: **¿de qué está hecha la
red, y puede romperse por la misma causa que lo que vigila?**

> Dicho en el vocabulario de §2: `D-85` no garantiza *"la pasada fallida deja constancia"*. Garantiza *"la
> pasada fallida deja constancia **mientras la base responda**"*, que es una afirmación bastante más pequeña y
> que hoy no está escrita en ningún sitio.

**Y una tercera, que no estaba en las cuatro preguntas y salió tirando del hilo** (H-24): el tercer ámbito
también puede fallar cuando la pasada **fue bien**, y entonces el registro miente en la otra dirección — dice
`failed` de una pasada cuyos datos están escritos y cuyo `last_synced_at` está puesto. Las cuatro preguntas
del bloque miraban *"¿sobrevive el registro al fallo?"*; ésta es *"¿sobrevive **la verdad** al fallo del
registro?"*, y es la que deja tres testigos contradiciéndose.

**La premisa de §1 sigue en pie.** A-3 no añade ningún S1: el hallazgo grande es S2 y tiene fase.

**Lo que este bloque necesitó y no estaba en su «Leer antes»**, para el que venga:

- **`Sources/Tenancy/TenantRouting.swift`.** El «dónde mirar» lista `FluentTenantUnitOfWork`, pero ahí no está
  la transacción: está una llamada a `withSearchPath`, y es **esa** la que hace `database.transaction`. La
  pregunta 2 del bloque —de qué conexión sale el tercer ámbito— no se puede contestar sin abrir ese fichero.
- **`Sources/App/IngestCommand.swift`**, solo la línea del código de salida. Es la única señal que sobrevive a
  H-23, así que decidir la severidad sin mirarla habría dado S1 por error.
- **`CalendarPass` entera, para contar sus `catch`.** Que no tenga ninguno es la mitad de H-25, y es lo que
  desactiva el aviso de §5.1 para el camino de producción.

**No hizo falta** nada de §6.4 más allá de saber que hay **un** *pool* y no uno por tenant, ni nada del
`pooler` de Supabase: el experimento corre contra Postgres directo, que es como corre la batería.

### Lo que A-3 entrega: el mapa fallo-a-garantía

Las cuatro clases de fallo contra lo que cada una deja en pie. «—» significa que no hay test que lo recorra.

| Clase de fallo | ¿Ámbito 2 se deshace? | ¿Ámbito 3 escribe? | ¿Motivo correcto? | Test permanente |
|---|---|---|---|---|
| **Invariante del Dominio** (`DomainError`) | sí | sí | sí | `aFailedPassLeavesNothingBehind`, `theRunRecordSurvivesTheRollback` |
| **Restricción de Postgres** (`23505`) | sí (H-25) | sí (H-25) | sí (H-25) | **— (H-26)** |
| **La base caída / el *pool* agotado** | n/a | **no** (H-23) | n/a | **— (H-23)** |
| **Falla solo el ámbito 3, tras comprometer** | no (y es lo correcto) | escribe **`failed` de una pasada buena** (H-24) | **no** (H-24) | **— (H-24)** |

Y **la regla de forma que F7 hereda**: `StandingRow` y `LeagueScorer` se sincronizan por este mismo recorrido y
con un `execute` de la misma forma, así que **lo que se decida en H-23 y H-24 hay que decidirlo antes**, no
después de copiarlo dos veces. Es el mismo argumento con el que A-1 levantó F6-bis.

### Nota de cierre de A-4 · la ruta del `202`, ¿la ejercita algo?

**No la ejercita ningún test —eso ya lo sospechaba el bloque— y resulta que en producción tampoco la escucha
nadie, que es la mitad que no estaba escrita.**

- **La ruta funciona, y por una razón estructural que conviene saber** (H-29). El *pool* sobrevive a la
  respuesta porque **nunca fue el de la petición**: el `unitOfWork` se cablea con `app.db(.control)` en la raíz
  de composición. La pregunta 1 no era *"¿aguanta el *pool*?"* sino *"¿de quién es el *pool*?"*, y la respuesta
  estaba en `Configure.swift`, no en `BackgroundWork.swift`.
- **Lo que no hay es a quién contarle el resultado** (H-27). El informe se construye entero —con el
  `abortedByInfrastructure` que A-3 acaba de añadir— y se tira en el mismo renglón en que se pide.

**La asimetría que lo explica, y que es la lección transferible.** El job y el `202` son **dos adaptadores
primarios del mismo caso de uso** (`IngestClubCalendars` lo dice de sí mismo, líneas 16-20), y sus señales de
fallo se diseñaron **cada una mirando a su adaptador**: el job tiene dos —código de salida y consola— porque un
comando **termina**, y quien lo lanzó sigue ahí esperando. El `202` responde **antes** de que el trabajo
empiece, así que cuando hay noticias su adaptador **ya terminó**. Un trabajo que sobrevive a su respuesta
necesita **una salida que no sea la respuesta**, y hoy no existe ninguna: `Application/` no tiene un solo
`Logger` y `swift-metrics` está en el grafo de dependencias sin usar. **El caso de uso es el mismo; lo que no
se heredó al segundo adaptador fue la forma de enterarse.**

> Dicho en el vocabulario de §2: `D-88` no garantiza *"el `202` hace el trabajo"*. Garantiza *"el `202`
> **planifica** el trabajo"* — y eso, medido, es exactamente lo que hace y nada más.

**Y una consecuencia de método sobre lo que el bloque pedía.** *"La forma de un test que cubra la ruta de
producción sin arbitrar una carrera"* **no se puede escribir hoy**, y no por dificultad de arnés: un test
comprueba un efecto observable, y el efecto de un fallo de fondo **no es observable por ningún medio**. Con una
salida —puerto de registro, contador, lo que se decida en H-27— el test es trivial y no hay carrera que
arbitrar: un doble que recoge la señal y una aserción sobre lo que recogió. **El test que falta no es de la
ruta: es de la salida que no existe.**

### Lo que A-4 entrega: la frontera exacta que F10 hereda

Qué se comprueba **antes** de responder el `202` y qué queda del otro lado. Es la tabla que `D-67` copia.

| Comprobación | ¿Antes de responder? | Cómo se sabe |
|---|---|---|
| `seasonId` que no existe | **sí** → 404 | Medido (H-28) |
| `competitionId` que no existe, dentro de una lista | **sí** → 404, y antes de empezar ninguna | Medido (H-28) |
| Lista vacía / UUID malformado | **sí** → 400 | `IngestionHandler.swift:100-117` |
| Tenant sin club dentro del *schema* | **sí** → sale del ámbito 1 del plan | Lectura (`plan()`, línea 152) |
| **Federación en el catálogo sin adaptador** | **no** → `202` mudo, y el dato ya estaba leído | **H-28** |
| El trabajo falla por datos | no, y es por definición | **H-27** |
| La base se cae detrás del `202` | no, y no queda rastro en ningún sitio | **H-27** |

Las tres primeras filas son `D-88` cumpliéndose. Las tres últimas son lo que F10 va a heredar si nadie decide
otra cosa — y la cuarta por abajo es la que menos se justifica, porque **la información para decidirla está en
la mano una línea antes de responder**.

**La premisa de §1 sigue en pie.** A-4 no añade ningún S1: su hallazgo grande es S2 y tiene fase (F10), y el
otro es S3 con su aviso de a qué sube si llega a F10 sin arreglar.

**Lo que este bloque necesitó y no estaba en su «Leer antes»**, para el que venga:

- **`Sources/App/Configure.swift`, la línea 73.** La pregunta 1 se contesta ahí y no en `BackgroundWork.swift`:
  lo que decide si el trabajo de fondo tiene base a la que hablar es **de qué `Database` se construyó el
  `unitOfWork`**. Con `FluentTenantUnitOfWork.swift` y `TenantPools.swift` al lado, para saber que el *pool* es
  uno solo y de la `Application`.
- **`Sources/Application/IngestClubCalendars.swift` entero**, no solo el *handler*. La frontera entre planificar
  y ejecutar **no está en `HTTPAdapter`**: está en que `plannedCompetitions` tira la federación que `plan()`
  acababa de leer, y de ahí sale H-28.
- **`Sources/App/IngestCommand.swift`, la línea del código de salida.** Es el contraste que convierte H-27 en
  hallazgo en vez de en queja: las señales existen, pero solo en el otro adaptador. (A-3 ya dejó apuntado este
  mismo fichero, y por una razón parecida.)

**No hizo falta** nada de §7 ni de auth, ni el README §4.5 más allá de los comandos, ni tocar `IngestCalendar`
—los tres ámbitos son A-3 y ya están medidos—.

**Y lo que A-4 le deja a los bloques que vienen:**

- **A-6** — H-15 y H-27 son **el mismo camino en dos tramos**: aquél dice que las cuatro señales de
  `FederationError` acaban indistinguibles, éste que en la ruta del `202` ni se miran. Conviene mirarlos juntos,
  porque la respuesta de uno condiciona la del otro.
- **A-7** — la batería **no toca `DetachedBackgroundWork`** (`grep` en `Tests/` → 0), y eso no es un test flojo:
  es una clase de código que el arnés no alcanza por construcción. Va con el `swift-metrics` sin usar que A-3
  ya le dejó apuntado: son la misma pregunta —*¿qué señal tiene este sistema que no sea su respuesta?*—.

---

## 6-bis. La puerta: cuándo se puede arrancar F7

La auditoría no termina cuando los ocho bloques están cerrados: termina cuando **el libro no tiene deuda que
bloquee**. Escrito como condición comprobable y no como intención:

| Condición | Cómo se comprueba |
|---|---|
| **Cero hallazgos S1 abiertos** | Ninguna fila S1 de §6 sin `sha` en la columna «Estado» |
| **Cada S2 tiene fase asignada** | Su fila dice en qué fase se arregla — **F6-bis**, F7, F8, F9, F10 o *"después de la ingesta"* |
| **Los S3 documentales, corregidos** | Por la excepción de §2: no se aplazan |
| **La batería en verde y el recuento al día** | `swift test` y, si A-7 lo entrega, el comprobador de cifras |

Un S2 sin fase asignada **cuenta como S1**: una deuda sin fecha no es una deuda planificada, es una deuda
olvidada con buena letra.

---

## 7. Estado

| Bloque | Estado | Sesión | Hallazgos |
|---|---|---|---|
| **A-0** · La vara de medir | ● **cerrado de nuevo** — se reabrió por H-11 y H-16, hallados desde A-1, y los dos están corregidos (`cc288cd`) | 2026-09-03 / 09-04 | H-01 · H-02 · H-03 · H-04 · H-05 · H-06 · H-11 · H-16 |
| **A-1** · El puerto de federación | ● **cerrado**; documentales corregidos (`cc288cd`) y la forma del sobre elevada a **F6-bis** | 2026-09-04 | H-08 · H-09 · H-10 · H-12 · H-13 · H-14 (+ H-15, que es de A-6) |
| **A-2** · La regla que destruye datos | ● **cerrado**; el S1 era **la ausencia de la medición** y está escrita (`4564617`). H-21 elevado a su fase | 2026-09-05 · arreglos y cierre commiteados el 09-12 | H-17 · H-18 · H-19 · H-20 · H-21 · H-22 |
| **A-3** · Lo que sobrevive a un fallo | ● **cerrado**; aguantaba el fallo de datos y no el de infraestructura, y ya aguanta los dos (`4d66aa0`) | 2026-09-12 | H-23 · H-24 · H-25 · H-26 |
| **A-4** · El `202` y el TaskLocal | ● **cerrado** — la ruta de producción funciona y ahora **dice lo que le pasa** (`77b2056`, `5c045f4`). La mitad que un log no puede tapar —que el **backoffice** se entere sin *push*— va a **F10** con las dos salidas evaluadas. La pregunta 4, heredada de A-3, se bajó a §5 el mismo día porque §7 no viaja con la sesión | 2026-09-12 | H-27 · H-28 · H-29 |
| **A-5** · Las migraciones | ○ pendiente | — | — |
| **A-6** · Las costuras de §7 | ○ pendiente | — | H-15 (desde A-1) · **H-27** (desde A-4: el mismo camino, un tramo más allá) |
| **A-7** · El arnés | ○ pendiente | — | H-07 (desde A-0) · la nota de cierre de A-2 · las **tres condiciones** que le deja la ronda de A-2: `$? == 0`, `skipped == 0` y **no leer el resumen de texto**, que no existe · y de A-4: **`DetachedBackgroundWork` no lo toca ningún test**, que es código fuera del alcance del arnés por construcción |

### La ronda de arreglos de A-1, y qué enseñó del método

**Cuatro hallazgos corregidos, tres elevados a fase, y la válvula de §3 regla 2 disparó por primera vez.**

- **Corregidos** (`cc288cd`): H-11, H-12, H-13 y H-16. Los cuatro son comentarios y prosa de diseño; ninguno
  cambia comportamiento, así que **ninguno tuvo rojo previo** — la regla 3 (*"el test primero, y el rojo de
  aserción"*) no aplica a un comentario, y decirlo es más honesto que fingir un ciclo. La verificación fue
  `swift build --build-tests` y la batería.
- **Elevados a F6-bis**: H-08, H-09 y H-10. La válvula de la regla 2 —*"un arreglo que toca más de un target
  o cambia una API pública no es una corrección de auditoría: es una mini-fase y va al Plan de desarrollo con
  su nombre"*— es exactamente este caso: volver opcionales `seasonLabel` y `FederationRound.label` cambia dos
  `init` públicos y toca `Application`, `Federation`, `App` y diez ficheros de test. **Sin la válvula, esta
  ronda se habría convertido en un refactor del puerto sin que nadie lo decidiera**, que es la frase que la
  regla usa para justificarse.
- **Y lo que la válvula no cubre y hubo que resolver a mano:** una mini-fase aplazada deja el hallazgo escrito
  en un plan que F7 no tiene por qué leer. Así que el aviso va **también en el puerto**, que es el fichero que
  F7 abrirá primero. La lección, para las rondas que vengan: **un hallazgo aplazado necesita un ancla en el
  código que la fase siguiente va a tocar**, no solo una fila en un plan.

**La ronda se cerró con la regla 4**, y la duración es el testigo que H-07 exige:

```
REQUIRE_DB=1 swift test  →  266 tests in 40 suites passed after 4.543 seconds
```

**4,54 s y no 0,1 s**, así que los niveles 3 y 4 corrieron de verdad.

### La ronda de arreglos de A-2, y qué enseñó del método

**Cuatro hallazgos corregidos, uno elevado, y la primera vez que el bloque encuentra algo que no venía a
buscar.**

- **Corregidos:** H-17 (los tres tests de nivel 3 que faltaban, más los cuatro `…Updated` de H-19), H-18 y H-20.
  Solo **H-20 tuvo rojo previo de verdad**, y salió como se pedía —de aserción y no de compilación—:
  `RFFMValue.venue("&nbsp;") → "&nbsp;"` y `venue("\u{00A0}") → " "`. Los otros dos son comentarios.
- **Elevado:** H-21, a la fase que abra la corrección de `OpponentClub`. La válvula de la regla 2 vuelve a
  disparar, y esta vez no por tamaño sino por **clase**: elegir otra clave de comparación para el paso 2 de la
  cadena es una decisión de diseño con tres salidas evaluadas, y una de ellas es migración. Lo que sí se
  corrigió en el acto es su mitad documental —el comentario de `matchingName` afirmaba lo contrario de lo
  medido—, y ahí queda el **ancla en el código** que A-1 dejó dicho que hace falta.

**Los tres tests de nivel 3 llegaron en verde**, que es deuda declarada (Plan §5.1), así que la garantía la da
la mutación. **Tres mutaciones, tres cazadas, y cada una por un test distinto:**

| Se rompe | Lo caza | Cómo se ve |
|---|---|---|
| `volatile` → `incoming` (pisar siempre) | `aSilentPassDestroysNothing` | `second.matchesUpdated → 1` y `home_score` a `NULL` |
| `descriptive` → `incoming ?? existing` | `aSilentPassDestroysNothing` | `opponentClubsUpdated → 2`, y el nombre, el corto y el escudo revertidos |
| `matching` → `existing` (sin relleno) | `theMatchingHoleIsFilledOnTheNextPass` | las tres claves a `nil` y los tres contadores a 0 |

**Y una superviviente con lectura**, que conviene dejar escrita: `matching` → `incoming ?? existing` —la
mutación *"la fuente pisa la clave"*— **no la caza ninguno de los tres nuevos**, porque en los dos casos que
recorren, `existing` e `incoming` nunca son los dos distintos a la vez. La caza el nivel 1
(*"un codacta distinto no reescribe el que ya emparejaba"*). No es un hueco: es que **esa rama no necesita
Postgres**, y pretender que el nivel 3 cubra todo lo que cubre el 1 es pagar dos veces por lo mismo — que es,
literalmente, el argumento con el que la *suite* de nivel 3 se había dejado fuera la política entera. La
diferencia está en cuál de las dos mitades se salta: **la que escribe un valor nuevo** vive en el tipo y el
nivel 1 la cierra; **la que conserva el que hay** cruza cuatro capas y solo se ve en la columna.

**Y el tropiezo de la ronda, que es información sobre §3.5 y no sobre el arreglo:** el primer intento de
`aSilentPassDestroysNothing` corregía los dos clubes con el **mismo** nombre y reventó contra
`uq:opponent_clubs.name` — con el `25P02` de rigor, porque las dos correcciones iban en el mismo ámbito. El
propio andamiaje lo tenía avisado (`TenantFixture`, punto 2), y aun así se cayó en él. Es la tercera vez que
esta advertencia se cobra algo.

**La ronda se cerró con la batería entera, y el testigo esta vez no es la duración:**

```
353 tests: 352 passed, 0 failed, 1 skipped        (plan de test de Xcode, con Postgres arriba)
```

El **1 omitido es el canario** —fuera de la batería por diseño (§5.5)—, así que **ningún test de BD se
omitió**: los niveles 3 y 4 corrieron. Es una señal más directa que la de H-07, porque el recuento de
omitidos sí distingue *"no probado"* de *"probado"*, y conviene anotarlo **como insumo para A-7**: el arnés que
ese bloque proponga puede exigir `skipped == 0` en vez de mirar el reloj.

**Los 353 no contradicen los 272 de `--list-tests`**: Xcode cuenta **un renglón por caso** de un `@Test`
parametrizado y `swift test --list-tests` cuenta **uno por función**. Los dos recuentos son correctos y miden
cosas distintas — apuntado aquí porque es exactamente la clase de cifra que H-03 y H-04 dejaron desfasarse.

**Y la regla 4, cumplida al pie de la letra** — el detalle que quedó pendiente en la primera redacción de este
renglón (la batería se había corrido desde el plan de test de Xcode y no desde la CLI) se cerró el
**2026-09-12**, antes de arrancar A-3:

```
REQUIRE_DB=1 swift test  →  6 test runs, 272 tests, 0 fallos, 1 omitido (el canario)
                            los dos targets de BD: 5,871 s y 2,799 s
```

**Ningún test de BD se omitió**, y las duraciones lo confirman por la vía de H-07: 5,87 s y 2,80 s, no 0,1 s.

> **Y la pasada de CLI destapó algo que H-07 no recoge, y es insumo para A-7.** Desde la CLI **no hay un
> renglón de resumen**: `swift test` imprime **seis**, uno por *target* de tests —7, 54, 50, 98, 45 y 18—, y el
> total de **272** hay que sumarlo a mano. H-07 está escrito como *"el renglón final dice lo mismo corriendo
> que omitiendo"*, y resulta que el problema es anterior: **ese renglón final no existe**. El `✔ Test run with
> 266 tests` que H-07 cita es el de un *target* suelto, no el de la batería. Consecuencia para el arnés que
> A-7 proponga: **la señal de "verde" no se puede leer del último renglón de la salida** —ni a ojo ni con
> `tail`—, y el `$?` sí es fiable. Junto al `skipped == 0` que ya le dejó apuntado esta ronda, son las dos
> condiciones que un CI debería exigir en vez de mirar texto.

**Y una cifra que esta ronda movió y se corrige en el acto** (§2, excepción documental): los tests pasan de
**266** a **272** —seis nuevos: tres de nivel 3, dos de nivel 1 y uno de nivel 2—, así que `AGENTS.md` y las
dos apariciones del `README` quedan al día. Las de **este** fichero **no** se tocan: son la foto del día en que
se midieron (H-06) o la reproducción de un hallazgo (H-07), y una bitácora se anota encima, no se reescribe
(`D-26`).

### La ronda de arreglos de A-3, y qué enseñó del método

**Tres hallazgos corregidos, cinco mutaciones cazadas, y la primera vez que la válvula de §3 regla 2 se
desactiva a sabiendas en vez de disparar.**

- **Corregidos** (`4d66aa0`): H-23 con la salida **(a)** —elegida por el desarrollador con las tres opciones y
  sus costes delante—, más H-24 y H-26.
- **La sonda en lugar de la taxonomía, que es la decisión de diseño de la ronda.** Lo natural habría sido
  clasificar el error —*"si es un `PSQLError` de conexión o un *pool* agotado, es infraestructura"*— y eso es
  una **lista de códigos de un sistema ajeno**, exactamente la clase de premisa que `D-84` enseñó a no
  heredar. En su lugar se le **pregunta a la base si sigue ahí** después de cada fallo. Cuesta una consulta y
  solo en el camino de error, no hay nada que mantener cuando Supabase cambie de *pooler*, y **degrada hacia el
  lado barato**: si la sonda se equivoca, aborta un recorrido cuyas competiciones no han movido su
  `last_synced_at` y entran enteras en el disparo siguiente.
- **Y la mitad que no se podía romper arreglando la otra.** Una guarda pasada de celosa habría incumplido
  `D-86` por el lado contrario —una coordenada caducada volviendo a llevarse por delante todo lo que va
  detrás—, así que el reverso tiene su propio test: *"con la base sana, un fallo de datos sigue sin detener el
  recorrido"*. Es la mutación M3 la que lo demuestra, y es la mutación que más rinde de las cinco.

**Cinco mutaciones, cinco cazadas**, y cada una por el test que le toca:

| Se rompe | Lo caza | Cómo se ve |
|---|---|---|
| Se quita el `break` (continúa aunque no haya base) | `aDatabaseOutageStopsTheTraversal` | `entries.count → 3` |
| La sonda dice **siempre que sí** | `aDatabaseOutageStopsTheTraversal` | `abortedByInfrastructure → false` y 3 entradas |
| La sonda dice **siempre que no** | `aDataFailureWithAHealthyDatabaseStillContinues` | el recorrido se para con la base sana |
| El comportamiento viejo de H-24 | `aWrittenPassIsNotRecordedAsFailed` | una fila `failed` de una pasada escrita |
| `String(describing:)` en vez de `String(reflecting:)` | `aRealConstraintViolationIsRecordedWithItsRealReason` | el motivo pierde el `23505` y el nombre de la restricción |

**La válvula de §3 regla 2, y por qué no se obedeció.** El arreglo toca **tres *targets*** y **añade casos a
una enumeración pública**, que es literalmente la definición de mini-fase que la regla da. Se siguió dentro de
la ronda porque **la decisión que la válvula existe para forzar ya estaba tomada**: la regla protege de que una
auditoría se convierta en refactor *sin que nadie lo haya decidido*, y aquí el desarrollador eligió entre tres
salidas con sus costes escritos. Queda anotado para que no siente precedente: **la válvula mide tamaño porque
el tamaño suele delatar una decisión no tomada; cuando la decisión está tomada, lo que hay que mirar es la
decisión.** El toque a `HTTPAdapter` no es alcance que se cuela — lo obliga el `switch` exhaustivo de
`ProblemMiddleware`, que existe justo para eso.

**Lo que se dejó fuera, y se dice para que no parezca hecho:** el **código de salida numérico distinto** para
*"falló la infraestructura"*. Hoy `main.swift` deja salir el error y el runtime sale con `1`; un código propio
exige un `exit(n)` explícito en el *target* `Run`, que sería el cuarto. Lo que sí hay es un **tipo de error
distinto**, testable y que el logger ya saca a `stderr`. Convertirlo en un número que el cron distinga es la
misma decisión de despliegue que **montar el cron**, y va con ella.

**Y lo que A-3 le deja a los bloques que vienen:**

- **A-4** — la ruta del `202` con la base caída: el cliente recibe su `202`, el trabajo falla, y la forma de
  enterarse (`GET /v1/ingestion-runs`) es justo la que no se puede escribir. Es la continuación natural de la
  pregunta 1 que A-4 ya tiene escrita.
- **A-5** — §9.3 hereda el argumento entero: si en las migraciones tampoco hay constancia, el criterio de
  `D-86` enmendada se aplica igual.
- **A-7** — `swift-metrics` está en el grafo de dependencias y **no se usa** (`grep` vacío en `Sources/`). Un
  contador de pasadas fallidas y un *gauge* de *"minutos desde la última pasada con éxito"* son la señal que no
  comparte suerte con la base.
- **F7** — `D-55` dice que la FCF publica **solo la clasificación vigente**, así que una ventana de ingesta
  perdida ahí es una jornada que **no se puede volver a pedir**. El coste de una caída no es uniforme: depende
  del calendario deportivo. `D-15` es la red, pero conviene que F7 lo sepa antes de escribir `StandingRow`.

**La ronda se cerró con la regla 4, desde la CLI:**

```
REQUIRE_DB=1 swift test  →  276 tests (7+55+50+98+48+18), 0 fallos, 1 omitido (el canario)
```

**272 → 276**, cuatro tests nuevos: tres de nivel 2 y uno de nivel 3. `AGENTS.md` y las dos apariciones del
`README` al día.

### La ronda de arreglos de A-4, y qué enseñó del método

**Dos hallazgos corregidos, seis mutaciones cazadas, y la primera vez que un arreglo tapa media pregunta y hay
que decir en voz alta cuál es la otra media.**

- **H-28** (`5c045f4`): la guarda del adaptador sube a `plannedCompetitions`. **Rojo de aserción** de libro
  —*"an error was expected but none was thrown"*— y **dos mutaciones**; la que rinde es la del reverso, porque
  una guarda pasada de celosa rompería el `202` de **todos** los clubes con adaptador, y eso lo cazan los tests
  de endpoint que ya existían.
- **H-27** (`77b2056`): el `_ = try? await …` pasa a ser un `do/catch` que mira el informe. **Dos tests**, el
  primero con rojo de aserción (`errors.first → nil`) y el segundo en verde —deuda declarada— sostenido por
  **cuatro mutaciones, cuatro cazadas**: volver al comportamiento viejo, no mirar la bandera del recorrido
  abortado, registrar a `warning` en vez de a `error`, y decir que falló **sin decir cuáles**.

**La pregunta que reencuadró el arreglo, y que no la hizo la auditoría sino el desarrollador:** *"¿cómo se
entera el backoffice, si no hay push?"*. **No se entera, y un log no lo arregla** — va al operador. La medición
que lo prueba ya estaba en H-27 y no se había leído así: `GET /v1/ingestion-runs` devuelve una pasada
`succeeded` **anterior a la petición que se perdió**, y `ingestionHealth` (`D-89`) dice `ok`. La causa es de
modelo: **`IngestionOutcome` solo tiene `succeeded` y `failed`**, así que entre el `202` y el final del trabajo
no existe fila ninguna, y si el trabajo muere no queda un hueco — queda el estado anterior con cara de sano.

> **La lección, que es de método y no de este hallazgo:** un arreglo puede ser correcto y **contestar otra
> pregunta distinta de la que hizo falta**. Aquí la severidad y la fase estaban bien puestas, pero el *destinatario*
> de la señal no se había escrito en ningún sitio — y hasta que alguien preguntó *"¿quién lee esto?"*, el
> arreglo parecía completo. **Al proponer una señal, decir a quién llega**; si el hallazgo no lo dice, no está
> terminado de escribir.

Por eso el arreglo lleva **el límite escrito en el propio código** —`runAccepted` explica lo que **no** tapa— y
la otra mitad va al **Plan de desarrollo, en la fila de F10**, con sus dos salidas y el precio de cada una. Es
la regla que A-1 dejó dicha: *un hallazgo aplazado necesita un ancla en el código que la fase siguiente va a
tocar*, y F10 abrirá `IngestionHandler.swift` el primer día.

**Y una nota de dependencias que no es burocracia:** `swift-log` pasa a declararse en `Package.swift` con el
mismo argumento con que F5 declaró `async-http-client` — ya estaba en el grafo, Vapor incluso lo **re-exporta**,
y aun así se declara. Aquí además el compilador obligó: `MemberImportVisibility` **no acepta miembros llegados
por re-export**, así que `logger.error(…)` no compila sin el `import`. La regla escrita en la cabecera del
manifiesto tenía razón, y ahora tiene también un caso en que el compilador la respalda.

**La ronda se cerró con la regla 4, desde la CLI:**

```
REQUIRE_DB=1 swift test  →  279 tests (7+55+50+98+49+20), 0 fallos
                            los dos targets de BD: 6,05 s y 2,94 s
```

**277 → 279**, dos tests nuevos, los dos de nivel 4. `AGENTS.md` y las dos apariciones del `README` al día.

**Y la comprobación que ninguna batería puede hacer**, porque el arnés no alcanza `DetachedBackgroundWork`:
contra el servidor de verdad, con Postgres parado a los 5 s de un `202`, el log dice ahora

```
[ ERROR ] El recorrido aceptado con 202 se paró: la base dejó de responder
          [club: atleti, intentadas: 2, sin-intentar: ninguna]
```

donde antes había **una sola línea y era de Vapor**.

### El canal de traspaso, y el agujero que se vio al ir a arrancar A-4

**Lo que A-3 le dejó a A-4 estaba escrito, y aun así no le habría llegado.** Al preparar la sesión de A-4 se
vio que el deber —*la ruta del `202` con la base caída*— vivía en **dos sitios y los dos dentro de §7**: la
columna «Hallazgos» de su fila en la tabla de estado, y el apartado *«lo que A-3 le deja a los bloques que
vienen»*. Y **§7 no está en la base común de §4-bis**, que es *«este fichero, §0 a §4 y §6»*; en la plantilla
del prompt, §7 aparece una sola vez y como sitio donde **escribir** al terminar, nunca donde leer. La sesión
de A-4 habría abierto el plan, leído **tres** preguntas, contestado tres, y cerrado el bloque en falso — que
es la forma de H-11, esta vez vista antes de que ocurriera.

**Por qué se escapó, teniendo el plan un canal justo para esto.** La regla 2 de §3 lo tiene resuelto —*«el
libro de hallazgos es el traspaso … por eso §6 va en la base común»*— pero lo resuelve **para hallazgos**. Lo
que A-3 traspasó no es un hallazgo: no tiene `H-nn`, ni severidad, ni reproducción. **Es una pregunta**, no
cabía en §6, y acabó en el único sitio donde cabía, que está fuera del canal.

**La regla que se añade, y es la de A-1 un piso más abajo.** A-1 dejó escrito que *«un hallazgo aplazado
necesita un ancla en el código que la fase siguiente va a tocar»*; esto es lo mismo entre bloques: **una
pregunta heredada necesita un ancla en el bloque que la va a ejecutar** —una fila más en su tabla de §5— **y
no solo un renglón en la tabla de estado**. Cuesta diez líneas y se hace al cerrar el bloque que la lega, no
al abrir el que la recibe.

**Y lo segundo que la preparación destapó: un «Leer antes» caduca.** El de A-4 se escribió el 2026-09-03 y
`4d66aa0` cambió el 09-12 el comportamiento del camino que corre detrás del `202`. Los «Leer antes» se han
venido ampliando *al cerrar* un bloque —*«lo que este bloque necesitó y no estaba en su lista»*—; éste es el
primer caso de la ampliación contraria: **el código se movió debajo de un bloque que aún no ha corrido**. Al
cerrar una ronda de arreglos, mirar qué bloques pendientes tocan los ficheros que la ronda cambió.

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
