# Plan de auditoría-002 · El backend antes del backoffice

> Abierto el **2026-09-25**, con **la ingesta entregada de punta a punta** —F0–F8, F6-bis, F6-ter, F9-bis,
> F10, F10-bis y F10-ter; **F9 aplazada sin código** (`D-95`)— y **541 tests** (medido por A-8 con `REQUIRE_DB=1` y leído del XML, H-07:
> 540 corren y el canario se omite).
>
> **Es la continuación del [Plan de auditoría-001](./Plan%20de%20auditor%C3%ADa-001.md)**, que auditó F0–F6
> y cerró el 2026-09-14 con ocho bloques, cero S1 y 50 hallazgos. Éste audita **lo que se construyó después**
> —F6-bis en adelante— **y lo que esas fases cambiaron debajo de lo que 001 dio por bueno**.
>
> Convención, la misma del resto del proyecto: **`§x` remite al [LLD-001](../docs/API_y_BBDD%20LLD-001.md)**,
> `D-nn` a la [bitácora de decisiones](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md), `Plan §x`
> al [Plan de desarrollo-001](../docs/Plan%20de%20desarrollo-001.md) y `C-n.m` al
> [Plan F10-001](./Plan%20F10-001.md). **La numeración sigue la de 001 y no se reinicia**: los bloques de este
> fichero van de **A-8** en adelante y los hallazgos de **H-51** en adelante, para que `A-3` o `H-23` sigan
> significando una sola cosa en todo el repositorio.
>
> **Este fichero es plan y libro a la vez**, como 001: los bloques de §5 se ejecutan de uno en uno y cada uno
> escribe su resultado en §6, aunque el resultado sea *"nada"*. Un bloque sin renglón en §6 **no está hecho**.

---

## 0. Qué es esto, y sobre todo qué no

**Sigue sin ser una caza de bugs.** La premisa es la misma que en 001: el código funciona, y lo que se audita
son **las decisiones ya tomadas sobre las que lo siguiente se va a apoyar**. El criterio que ordena el plan
tampoco cambia:

> **Coste de descubrirlo tarde**, no gravedad, no tamaño, no en qué capa vive.

**Lo que sí cambia es *qué* viene detrás, y con ello qué es "tarde".** 001 se escribió con cuatro fases de
ingesta por delante, que **ampliaban** cosas existentes. Lo que viene ahora ([borrador del
backoffice](../docs/backoffice_initial_draft.md)) es distinto en tres sentidos, y los tres suben el precio de
un error de base:

1. **La ingesta va a correr sola.** El prerrequisito del backoffice es `launchd` disparando `ingest` cada
   semana en el Mac. Hasta hoy **cada pasada la ha lanzado y mirado alguien**; a partir de ahí, una regla que
   destruya datos en silencio lo hará **sin testigo** y, por `D-55`, **la semana perdida no se recupera**.
2. **La frontera HTTP se va a multiplicar.** Hoy son **6** operaciones de las 83 del *spec*. El backoffice
   trabaja por **rebanadas verticales** —una pantalla con sus endpoints—, así que la forma de un *handler*,
   de un mapeo DTO↔dominio o de una aserción de `Problem` **se va a copiar decenas de veces**. Es la misma
   situación que A-1 tenía con el puerto antes de F7 y F8, un piso más arriba.
3. **Llega la primera escritura desde fuera.** La rebanada 2 es `POST /v1/teams` + inscripciones: la **otra
   puerta** que afirma a mano la correspondencia equipo↔competición (`C-A.3`, `C-C.15`). Y la autenticación
   va **al final**, con la costura de `ActorResolver` como único seguro de que no habrá que rehacer nada.

**El tamaño de lo que se audita**, para calibrar el esfuerzo — y para ver cuánto ha crecido desde 001:

| | 001 (2026-09-03) | Hoy (2026-09-25) |
|---|---|---|
| Líneas en `Sources/` | ~8.760 (428 `TestSupport`) | **~15.870** (433 `TestSupport`) |
| Líneas en `Tests/` | ~7.620 | **~18.150** |
| Tests | 266 | **~541** (H-51) |
| Migraciones | 9 | **17** (16 por tenant + `CreateTenants`) |
| Operaciones generadas | 4 de 83 | **6 de 83** |
| Decisiones en la bitácora | hasta `D-89` | hasta **`D-97`** |

**Casi el 60 % del código de hoy no lo ha visto ninguna auditoría.** `git diff --stat db5f5ee..HEAD -- Sources
Tests` —desde el cierre de 001— da **95 ficheros y ~19.900 líneas añadidas**.

---

## 1. La premisa está escrita para poder ser falsa

Igual que 001, y con la misma regla:

> Si **A-8** y **A-10** juntos producen **más de dos hallazgos S1**, este documento deja de ser una auditoría
> y se convierte en una **fase de reparación previa al backoffice**, con su entrada en el Plan de desarrollo.

**Por qué A-10 y no el segundo bloque en orden.** En 001 la pareja era *"la vara de medir"* más *"el puerto"*,
porque el puerto era lo que las fases siguientes iban a copiar. Aquí lo más caro de descubrir tarde es otra
cosa: **la única regla de toda la salida de la ingesta que borra filas** (`D-94`), a punto de ejecutarse sin
nadie delante.

**Y una razón más para dudar de la premisa, que 001 no tenía.** Las fases posteriores a 001 se entregaron
**con mucha más velocidad** —F10 fueron 47 ciclos en cinco días, y en el mismo intervalo salieron tres
mini-fases— y **cada una de ellas encontró algo de la anterior**: F10-bis encontró que nadie cerraba la fila
`accepted` de F10; F10-ter, que 14 de 28 salidas escribían mal un identificador; el repaso de arnés, cuatro
campos del contrato sin una sola aserción. Eso no dice que el código esté mal, pero sí que **"entregada con
todas sus mutaciones cazadas" no ha sido, hasta ahora, lo mismo que "sin nada pendiente"**.

---

## 2. Cómo se mide un hallazgo

La escala es **la de 001 §2, sin cambios**: la severidad es *qué cuesta arreglarlo después*.

| | Severidad | Qué significa | Cuándo se arregla |
|---|---|---|---|
| **S1** | **Cimiento** | Arreglarlo después obliga a **rehacer código ya entregado** — o, desde que la ingesta corre sola, **pierde datos que no vuelven** | **Antes de montar `launchd` o de abrir la rebanada que lo toque**, según §6-bis |
| **S2** | **Coste creciente** | Cuesta en proporción a lo que se haya construido encima | En la rebanada o mini-fase que lo toque, **y se apunta cuál** |
| **S3** | **Local** | Se arregla donde está, sin arrastrar nada | Al cerrar el bloque. **Si es documental, en el acto** |
| **S4** | **Nota** | Cierto, comprobado, y no hay que hacer nada hoy | Nunca; queda escrito para que no se vuelva a descubrir |

**La única ampliación, y es de la columna S1:** en 001 el daño irrecuperable era hipotético porque cada pasada
la miraba alguien. Con `launchd`, **perder datos sin fila fallida que lo cuente** pasa a ser cimiento aunque
el arreglo sea una línea — lo que se pierde no es código, es la semana.

**"Fase" ya no significa solo `Fn`.** El Plan de desarrollo cubre la ingesta y está terminado; lo que viene
son **rebanadas del backoffice** (sin numerar todavía) y **deberes de despliegue** (el cron, el CI y la auth
van juntos en Fly.io). Un S2 se asigna a una de esas tres cosas, o a una mini-fase con nombre.

---

## 3. Las reglas del juego

**Las seis de 001 §3 siguen en vigor** y no se repiten aquí enteras: reproducción o *sospecha* (1); auditar,
cerrar, *entonces* arreglar, con commits separados y la válvula de la mini-fase (2); todo arreglo entra por
el bucle de Plan §5.1 con esqueleto y rojo de aserción (3); la batería se cierra con **`REQUIRE_DB=1 swift
test`** y, desde A-7, **`--xunit-output`** (4); si código y diseño discrepan, se dice cuál está mal (5); la
auditoría no amplía el alcance ni toca el `filter` (6).

**Y cuatro más, que son lo que 001 aprendió ejecutándose.** Ninguna es nueva: todas están escritas en su §7 o
en el Plan de desarrollo, pero dispersas, y una sesión nueva no las leería.

7. **Lo que contesta *"¿lo prueba algo?"* es romperlo y mirar, no buscarlo.** `grep` demuestra que algo
   *está*, no que haga lo que dice (H-40); y lo que `grep` no encuentra no prueba que falte (H-47). Un
   hallazgo del tipo *"esto no tiene test"* **se confirma con una mutación** antes de escribirse.
8. **Una medición se vuelve a leer cuando se construye algo encima** (`D-91`, tercera vez). Y su corolario de
   001 §7: **un "Leer antes" caduca** si el código se movió debajo del bloque. Aquí es la regla que justifica
   la segunda mitad de A-8.
9. **Ejecutarlo contra la base de trabajo y mirar la tabla.** Los defectos de F6, F8, F10 (`C-E.10`) y
   F10-bis salieron **ejecutando el sistema**, nunca de la batería, porque los niveles 2 y 3 corren con reloj
   fijo, dobles sin restricciones y montajes limpios. **Un bloque de este plan que toque Persistencia o HTTP
   no se cierra sin haberlo ejecutado una vez contra `club_atleti`.**
10. **Un inventario que se hace mirando un fichero no es un inventario** (F10-ter: *"los diez de
    `Identifiers.swift`"* eran once). Cuando un bloque cuente algo —casos, sitios, campos—, cuenta **el
    árbol**, y dice con qué comando.

---

## 4. El orden, y por qué es ése

| Bloque | La pregunta que contesta | Bloquea a | Coste |
|---|---|---|---|
| **A-8** | ¿Los documentos dicen la verdad, y qué de lo que 001 dio por bueno se ha movido debajo? | *(a todo)* | ½ sesión |
| **A-10** | La única regla que borra, ¿puede vaciar una tabla con éxito? | **`launchd`** | 1 sesión |
| **A-11** | La fila que transita (`accepted`), ¿cierra siempre, y sigue valiendo lo que A-3 midió? | **`launchd`**, rebanada 1 | 1 sesión |
| **A-12** | El enganche, ¿aguanta lo que no es el camino feliz? | **rebanada 2** | 1 sesión |
| **A-14** | La frontera HTTP, ¿es un patrón que se pueda copiar treinta veces? | **rebanada 1** | 1 sesión |
| **A-13** | Con el esquema duplicado, ¿siguen valiendo las garantías de A-5? | rebanada 2 | ½ sesión |
| **A-15** | Con el doble de tests, ¿qué significa hoy "N/N mutaciones"? | *(a todo)* | ½ sesión |
| **A-9** | El puerto de federación, ¿sigue abstrayendo una federación sin tener segunda implementación? | reapertura de F9 | ½ sesión |

**Seis sesiones.** El orden de la tabla es el recomendado, no el obligatorio: como en 001, **solo dos
restricciones son duras**.

- **A-8 va primero**, por lo mismo que A-0: medir con la vara torcida no sirve. Y aquí con un motivo añadido:
  su segunda mitad —*el mapa de caducidad*— **reescribe los «Leer antes» de los demás bloques**.
- **A-10 y A-11 van antes de montar `launchd`.** El borrador del backoffice lo pone *primero* porque *"es lo
  único que paga por empezarlo pronto"*, y es verdad; pero lo que paga es **dato real acumulándose**, y eso
  solo es bueno si la pasada que lo acumula no puede destruirlo. Son dos sesiones, y montar `launchd` sin
  ellas es apostar la semana.

**Por qué A-9 va el último, siendo en 001 el más importante.** En 001, F7 y F8 iban a añadirle dos métodos al
puerto en cuestión de días; el coste de una forma equivocada crecía cada semana. Hoy **F9 está aplazada**
(`D-95`) y su reapertura depende de que la FCF arregle su clasificación, así que **nada nuevo se va a colgar
del puerto hasta entonces**: el coste de descubrirlo tarde es constante. Se audita porque el puerto ha pasado
de 236 a **717 líneas** sin segunda implementación ni ensayo en seco, no porque urja.

**Por qué A-14 va antes que A-12 aunque se numere después.** La rebanada 1 —la portada, **de solo lectura**—
es la primera y no toca el enganche; lo que sí hereda es **la forma de un *handler***. A-12 solo bloquea la
rebanada 2.

---

## 4-bis. Cómo se arranca una sesión de auditoría

**Un bloque, una sesión, y el contexto se tira al terminar** — como en 001. La diferencia es que ponerse al
día cuesta el doble: `AGENTS.md` ha pasado de 409 líneas a **~750**, y su sección del backend de ~150 a
**~380**. Leerla entera ya no es *"el mapa"*.

### La base común, igual para todos los bloques

| Qué | Por qué |
|---|---|
| **Este fichero, §0 a §4 y §6** — incluida la tabla de §6 de **001**, pero solo sus columnas *#*, *Severidad* y *Estado* | El encuadre, la escala, las reglas y lo ya encontrado. **Los `H-nn` de 001 se consultan por `grep` cuando un bloque los cite**, no se leen de corrido: son 50 filas de ancho considerable |
| `AGENTS.md`, sección **«El backend: cómo está montado y cómo se trabaja»**, **solo hasta el bloque de comandos incluido** y la lista **«Cinco cosas que hay que saber antes de tocar este código»** | El grafo de capas, la tabla de *targets*, los comandos y los avisos. Lo que viene detrás —F9, F7, F8, las lecciones de fase— es historia, y el bloque que la necesite la tiene en su «Leer antes» |

Eso son ~250 líneas más las de este fichero. **Lo demás lo pone el «Leer antes» del bloque, y nada más.**

### La plantilla del prompt de entrada

```
Ejecuta el bloque A-n del plan de auditoría en `backend/Plan de auditoría-002.md`.

Lee primero la base común de §4-bis y el «Leer antes» de tu bloque. No leas el
resto del LLD, del README ni del Plan de auditoría-001 salvo que el bloque lo pida.

Cuatro límites:
  1. Audita SOLO tu bloque. Si tropiezas con algo de otro, lo apuntas en §6 con
     el bloque al que pertenece y sigues con el tuyo.
  2. NO arregles nada. Ni el hallazgo ni lo que veas de camino. (Regla 2 de §3.)
  3. Todo hallazgo va con su reproducción; sin ella se escribe como *sospecha* y
     se dice que lo es. (Regla 1.) Un «no tiene test» se confirma mutando. (Regla 7.)
  4. Si tu bloque toca Persistencia o HTTP, ejecútalo contra la base de trabajo
     antes de cerrarlo. (Regla 9.)

Al terminar: añade tus hallazgos a §6 con su severidad de §2 —aunque no encuentres
nada, que también se escribe—, pon tu bloque al día en §7 y, si dejas una pregunta
a otro bloque, escríbela como fila en SU tabla de §5, no solo en §7.
```

La última línea es la regla que 001 añadió en su §7 (*"el canal de traspaso"*): **una pregunta heredada
necesita un ancla en el bloque que la va a ejecutar**, porque §7 no está en la base común.

### Las dos cosas que la troceabilidad no arregla, heredadas de 001

- **El orden importa en dos sitios, no en los ocho** (§4).
- **Dos bloques en paralelo chocan en §6 y §7.** En serie no hay problema; si se paralelizan, cada sesión
  escribe en un `Hallazgos-A-n.md` aparte y se consolidan a mano.

---

## 5. Los bloques

Cada uno lleva **la pregunta**, **dónde mirar**, **cómo se decide**, **qué sale** y su **«Leer antes»**.
Las *sospechas* de partida son eso: puntos de partida, **sin verificar** salvo que se diga lo contrario.

---

### A-8 · La vara de medir, y el mapa de caducidad de 001 · ½ sesión

> **Leer antes:** nada más que la base común. Como A-0, **este bloque no lee documentos: los indexa**, con
> `grep` sobre `docs/`, `backend/*.md`, `AGENTS.md`, `Sources/` y `Tests/`. Para la segunda mitad, **la
> tabla de §6 de 001 entera** —aquí sí, es el material— y `git log` / `git diff --stat db5f5ee..HEAD`.

**Pregunta.** Dos, una por mitad: ¿los documentos dicen lo que el código hace hoy? Y ¿qué de lo que 001 cerró
como bueno se apoya en código que ha cambiado desde entonces?

**Primera mitad · la vara.** Lo mismo que A-0, contra el estado de hoy:

- Cada `D-nn` citado en `Sources/` y `Tests/` existe en la bitácora (ahora hasta `D-97`); cada `§x`, en el
  LLD; cada `C-n.m`, en el Plan F10.
- **Las cifras**, una por una, con su comando: tests, migraciones, operaciones del `filter`, motivos de
  `IngestionSkip.Reason`, identificadores que conforman `TypedIdentifier`, códigos `Problem` afirmados por
  código (*"17 de 30"* en `AGENTS.md`, *"15 de 30"* en Plan §4.1 — ¿es una cifra que avanzó o dos que no
  casan?).
- **Los rótulos de estado**: `AGENTS.md`, el README, el Plan de desarrollo y el Plan F10 tienen que decir lo
  mismo de F10. Ver **H-51**, que es la prueba de que no lo dicen.

**Segunda mitad · el mapa de caducidad, que es lo nuevo.** 001 dejó **diez S4** —*"cierto, comprobado, y no
hay que hacer nada"*— y una docena de hallazgos **cerrados con su `sha`**. Varios se midieron sobre código que
las fases siguientes reescribieron. Ejemplos que ya se ven desde fuera, sin abrir nada:

| Hallazgo de 001 | Qué midió | Qué cambió debajo |
|---|---|---|
| **H-25** (S4) | `D-83`/`D-85` aguantan un fallo real: el ámbito 3 escribe | F10-bis cambió `record` de *"solo inserta"* a ***upsert* por `id`** |
| **H-29** (S4) | El *pool* sobrevive a la respuesta del `202` | Hay un **segundo** `202` (`/federation-link`) con su propia cascada delante |
| **H-30** (S4) | Cuatro caminos, un `md5`, con 9 migraciones | Son **16** por tenant (17 con `CreateTenants`), y dos rehacen `CHECK`s |
| **H-22** (S4) | El cableado de la política de *upsert* en `CalendarPass` | `CalendarPass` creció un 17 % y adopta filas `accepted` |
| **H-44** (S4) | El enumerador de tenants lo tapa una restricción | Hay **404 nuevos** (`teamNotFound`) en rutas de tenant |

**El método:** para cada fila de §6 de 001 en estado **S4** o **cerrado**, cruzar los ficheros que cita contra
`git diff --name-only db5f5ee..HEAD`. **No se vuelve a medir aquí** —eso lo hace el bloque al que pertenezca—:
se produce **la lista**, y cada entrada va como **fila nueva en la tabla del bloque que la herede** (regla del
canal de traspaso). Una garantía de 001 sin bloque que la reciba se apunta en §6 como S3.

**Cómo se decide.** Como en A-0: cita rota o cifra desfasada, **S3** y se corrige en el acto; afirmación que
dice lo contrario del código, **S2**. Una garantía de 001 cuyo código cambió **no es un hallazgo en sí**: es
una fila en otro bloque.

**Qué sale.** Las correcciones documentales hechas, la respuesta a si la deriva sigue siendo sistemática —001
dijo que las citas se sostenían y las cifras derivaban—, y **el mapa de caducidad** repartido por los bloques.

---

### A-9 · El puerto de federación, sin segunda implementación que lo contradiga · ½ sesión

> **Leer antes:**
> **`D-95`** (el aplazamiento y su condición de reapertura) y **`D-97`** (el adaptador es dueño de su
> universo; el criterio para admitir un método en el puerto) · **Anexo FCF §C.12 entero** —§C.10 solo para
> §C.10.6 y §C.10.7, clasificación y goleadores— · **Anexo RFFM §F.8, §F.13 y §F.19** · de 001, **H-08, H-09 y
> H-13**, y la nota *«Lo que A-1 entrega»* · **Plan §4.9 y §4.10**, las tablas *«Qué entrega»*.
> Nada de migraciones, tenancy, HTTP ni auth.

**Pregunta.** F6-bis arregló el sobre del calendario *"antes de que F7 y F8 lo copien"*, y F7 y F8 le
añadieron `fetchStandings` y `fetchScorers` con el aviso delante. ¿Lo cumplieron? Y `D-97` añadió
`coordinate(fromCalendarURL:)` con un criterio escrito: ¿todo lo que hay en el puerto hoy lo pasa?

**Dónde mirar.** `Sources/Application/FederationClient.swift` (**717 líneas**, era 236),
`FederationError.swift`, `FederationClientProvider.swift`, `Sources/App/FederationCatalog.swift` y
`Sources/Federation/` entero.

**El método: el ensayo en seco de A-1, repetido sobre lo nuevo.** Recorrer §C.10.6, §C.10.7 y §C.12 campo a
campo contra `FederationStandingTable`, `FederationScorerTable` y sus filas, y apuntar lo mismo que A-1:
campos sin sitio, opcionalidades al revés y supuestos de la RFFM con nombre genérico. **Con el anexo delante**:
§C.12 es de 2026-09-20 y ya dice que la forma cambió en 23 días.

**Sospechas de partida:**

| # | Sospecha | Por qué importa |
|---|---|---|
| 1 | `FederationScorerTable` lleva **un** campo (Plan §4.10) y la guarda de `D-84` se le aplica igual (`IngestScorers.swift`: `requireSameSource(as: published.competitionName)`). **Si ese campo es el nombre, en la FCF no existe** —su goleadores es un *array* pelado— y la guarda se apaga | Es **H-09 copiado una vez más**, que es exactamente lo que F6-bis existía para impedir. Y en esta pasada es peor que en el calendario: la de goleadores **borra** (A-10) |
| 2 | `FederationCapabilities` sigue declarando las de la FCF y el proveedor devuelve `nil` (`D-95`). ¿Hay algún camino que lea capacidades **sin** pasar antes por el proveedor? | Si lo hay, una capacidad declarada de una federación sin adaptador decide algo en tiempo de ejecución |
| 3 | `coordinate(fromCalendarURL:)` devuelve `DomainError` y no su error interno (`D-97`). ¿Lo hacen también `fetchStandings`/`fetchScorers`, o cada método del puerto tiene su propia política de errores? | Un puerto con tres políticas de error es un puerto que el segundo adaptador implementará con una cuarta |
| 4 | **H-09 no tiene fase** desde el aplazamiento (excepción sobrevenida de 001 §6-bis) | Sigue sin poder hacer daño **mientras no haya adaptador catalán**. Comprobar que es verdad: que ninguna ruta hoy alcance la FCF |
| 5 | **H-13 remedido** (mapa de caducidad de A-8). H-13 limpió tres campos del puerto que se explicaban por el mecanismo de la RFFM. Desde `db5f5ee`, `FederationClient.swift` suma +397/−3 y sus menciones a la RFFM pasan de **23 a 39** (`grep -c RFFM`) | Nombrar la RFFM en un comentario no es defecto; **justificar con ella un campo o una opcionalidad del puerto** sí (p. ej. `:323`, *"anulable porque es un campo de la RFFM"*). Cada caso así es H-13 otra vez |

**Cómo se decide.** El listón de A-1, con el coste recalculado: hoy cambiar la forma del puerto cuesta **un
adaptador y los dobles de tres suites**, y **no va a subir** hasta que F9 reabra. Así que un campo que solo se
explica nombrando la RFFM es **S2 con fase *"reapertura de F9"***, salvo que alimente una regla que **borra**,
que entonces es de A-10 y se decide allí.

**Qué sale.** El ensayo en seco escrito —para que la sesión que reabra F9 no lo repita— y la lista de lo que el
adaptador catalán tendría que resolver **sin tocar el puerto**, que es la promesa de `D-97`.

---

### A-10 · La única regla que borra, de punta a punta · 1 sesión · **bloquea `launchd`**

> **Leer antes:**
> **`D-94`** (la retirada y su condición: *"estado vigente y no histórico"*), **`D-75`** (qué se pierde y por
> qué los dos errores no cuestan lo mismo), **`D-93`** (la clave de `LeagueScorer`), **`D-48`** (la
> capacidad), **`D-15`** y **`D-92`** (las dos fuentes de `StandingRow`) · **Anexo RFFM §F.19** —las tres
> cosas de `/api/scorers` **sin observar**— · **Plan §4.9 y §4.10** enteros · de 001, **A-2 en §5** y **H-17**
> —el método de este bloque es el suyo— · **LLD §6.2**, el aviso del ámbito transaccional.
> Nada de HTTP ni de auth.

**Pregunta.** `D-94` es la única excepción a *"lo que la fuente deja de publicar no se destruye"*. ¿Puede
vaciar la tabla de goleadores de una competición **con éxito**, es decir, sin fila `failed` que lo cuente?

**Por qué este bloque es el S1 potencial del plan.** Lo que `D-94` protege está bien pensado: la retirada va
**por marca** y **en el mismo ámbito** que la escritura, así que una caída a mitad no deja la tabla vacía. Lo
que protege es **la atomicidad**. Lo que este bloque pregunta es otra cosa: **una pasada atómica y correcta que
recibe una lista vacía retira todo, y lo hace bien**.

**Dónde mirar.** `Sources/Application/IngestScorers.swift` (299 líneas), `Sources/Domain/LeagueScorer.swift`,
el `retire` de `Sources/Persistence/FluentIngestionRepositories.swift` y `Sources/Federation/RFFMScorersParser.swift`.

**Sospechas de partida** — leídas en el código al preparar este plan, **no verificadas**:

| # | Sospecha | Por qué no es teórica |
|---|---|---|
| 1 | Entre `fetchScorers` y `write(...)` **no hay ninguna guarda de lista vacía**. Una respuesta vacía llega a `retire(keepingMark:)` con cero filas escritas, y todas las existentes llevan otra marca | §F.19 dejó **sin observar** *"qué devuelve un grupo sin goles todavía"*; y §C.12 midió que la FCF dice que no **con el contenedor vacío**. `D-95` usó eso como argumento para aplazar F9 — ¿lo cubre algo en la RFFM? |
| 2 | Si **todas** las filas publicadas acaban en `skipped` (`unidentifiedScorer`), la lista que se escribe también es vacía | Es el caso *"la fuente ha cambiado"*: el día que la RFFM renombre `codigo_jugador`, el ranking entero se retira en la primera pasada, y la fila dirá `succeeded` con N descartes |
| 3 | La guarda de `D-84` es lo único entre la red y la retirada, y **sus silencios no paran nada a propósito** (H-09) | Si la respuesta vacía trae el nombre vacío o ausente, la guarda **tampoco** dice nada. Las dos protecciones se apagan con la misma entrada |
| 4 | **`StandingRow`**, la otra salida nueva: dos fuentes para la misma fila (`D-15`). ¿Puede una fila **calculada** pisar una **ingerida** de la misma jornada? | La oficial lleva `puntos_sancion` y la calculada no (Plan §4.9, decisión 1). Si el plan de sincronización cambia de fuente para una jornada ya escrita, se sobrescribe la tabla oficial con una aritméticamente limpia y **falsa** |
| 5 | ¿Aplica `StandingRow` la política de `D-56` (*"ausente o vacío nunca sobrescribe"*) en el `UPDATE`, **medido contra Postgres**? | Es H-17 —el único S1 de 001— para la entidad que F7 trajo *"con la misma política"*. 001 dejó el test para `Match`; nadie ha dicho que exista para `StandingRow` |
| 6 | **H-17, H-19 y H-22 remedidos** (mapa de A-8). Los tres tests de nivel 3 de H-17 y los cuatro `…Updated == 0` de H-19 siguen en el árbol —en `Tests/` no se ha borrado un solo `@Test` desde `db5f5ee`—, pero debajo `CalendarPass` suma +43/−3 y `FluentIngestionRepositories` +392/−16, y la pasada **adopta** ahora filas `accepted` | Que el test siga no dice que siga alcanzando la rama: ¿el `UPDATE` de `Match` que H-17 afirma es el mismo camino con la adopción delante? Una mutación de la política dentro de `CalendarPass` lo contesta (regla 7). H-18 sigue en pie: el `guard let date` está en `CalendarPass.swift:159` |

**El método: el de A-2, cobertura diferencial, más provocar las entradas.** Para cada sospecha, primero
**provocarla** —un doble que devuelva `[]`, una tabla de volcado con el código de jugador renombrado— y mirar
la tabla **después**, en su propio ámbito (§6.2). Después, preguntar si **algún test de nivel 3** la alcanza.
Y **una vez contra la RFFM viva** (regla 9): pedir `/api/scorers` de un grupo que aún no haya jugado, que es
la mitad de §F.19 que se puede observar hoy mismo — la temporada 26-27 acaba de empezar.

**Cómo se decide.** Si la sospecha 1 o la 2 se reproducen, **S1**: es literalmente la clase de fallo que §2
amplía, y la tabla no vuelve hasta la pasada siguiente **si** la fuente vuelve a publicar — y por `D-55` la
foto intermedia no se puede pedir hacia atrás. El arreglo no se decide aquí (regla 2), pero la forma de la
decisión sí queda escrita: es la misma que §C.12 dejó abierta para la FCF —*"¿tratar el `[]` como coordenada
mala?"*—, **y ahora con los dos proveedores delante**.

**Qué sale.** El mapa rama-a-test de `IngestScorers` y de la escritura de `StandingRow`, las mutaciones que
falten, y la respuesta de la RFFM al grupo vacío **guardada como volcado con su código HTTP**, que es lo que
§C.12 hizo bien y §F.x no.

---

### A-11 · La fila que transita, y lo que A-3 medía antes de que transitara · 1 sesión · **bloquea `launchd`**

> **Leer antes:**
> **`D-96`** (la fila `accepted`), **`D-85`** y **`D-86`** enmendadas, **`D-83`** y **`D-89`** (el resumen de
> lectura) · **Plan §4.1, la fila y el detalle de F10-bis** —es la sustancia del bloque— · de **AGENTS.md**, las
> dos viñetas *«Y la abre el `202`, la cierra la pasada»* y *«La fila `accepted` de `D-96` va DENTRO del ámbito
> de su cascada»* · de 001, **A-3 en §5**, **H-23, H-24, H-25, H-27** y la nota *«Lo que A-3 entrega: el mapa
> fallo-a-garantía»* · **LLD §6.2 y §6.4**.
> Nada de federación ni de auth.

**Pregunta.** F10-bis hizo que una pasada **adopte** la fila que el `202` dejó abierta, y para eso cambió
`record` de *"solo inserta"* a ***upsert* por `id`**. ¿Cierra la fila siempre? ¿Y lo que A-3 midió sobre un
`record` que solo insertaba sigue siendo cierto?

**Dónde mirar.** `Sources/Domain/IngestionRun.swift` (**558 líneas**, el fichero del Dominio más grande), el
`record` y el `findAccepted` de `FluentIngestionRepositories.swift`, `IngestCalendar.swift`,
`IngestClubCalendars.swift`, `IngestStandings.swift`, `IngestScorers.swift` e `IngestionRunRecord.swift`.

**Lo que F10-bis ya deja cerrado, para no auditarlo dos veces.** La adopción conserva `id`, `startedAt` y
contadores (`B-3`); el fallo adopta igual (`B-4`); `findAccepted` filtra por `outcome` **y** por `kind`, con
la mutación `M14` cazada por el test del adaptador; el `CHECK` de `outcome` rehecho tiene su test de *schema*
viejo (`M2`). Y está verificado contra la base de trabajo con dos filas reales.

**Lo que no establece, que es este bloque:**

| # | Pregunta | Por qué no es teórica |
|---|---|---|
| 1 | **Dos pasadas adoptan la misma fila**: el cron y el trabajo de un `202` sobre la misma competición, a la vez. ¿Qué escribe el segundo `record`? | Con *"solo inserta"* la carrera daba dos filas; con *upsert* por `id` **la segunda pisa a la primera**, contadores incluidos. `D-87` hace inofensivo *un disparo de más*, no dos concurrentes |
| 2 | **La propiedad autocurativa** —*"si el proceso muere entre el `202` y la pasada, la siguiente del cron la cierra"*— ¿sobrevive al antirrebote? | La competición que **nunca se sincronizó** entra siempre (`D-87`); la que se sincronizó hace menos de 6 h **no entra**. Una fila `accepted` sobre una competición recién sincronizada ¿queda abierta hasta el disparo siguiente, o para siempre? |
| 3 | Solo `IngestCalendar` e `IngestClubCalendars` llaman a `findAccepted` (medido con `grep` al preparar este plan). Las pasadas de **clasificación y goleadores** escriben fila propia | Correcto si el `202` solo acepta `kind: calendar`. Comprobar **qué** `kind` lleva la fila que escriben las dos puertas, y qué ve `GET /v1/ingestion-runs` tras un `202` de temporada con once pasadas por competición |
| 4 | **H-25 remedido** (mapa de caducidad de A-8): con una violación de restricción real en el ámbito 2, ¿el ámbito 3 —ahora un *upsert*— sigue escribiendo la fila `failed`, y con el `id` adoptado? | El `ON CONFLICT` de un *upsert* es una sentencia distinta de un `INSERT`; lo que A-3 midió no se hereda (regla 8) |
| 5 | **`D-89` con tres clases de pasada**: F7 y F8 lo dejaron *"sin bloquear nada hasta que el backoffice lea esos campos"* | **La rebanada 1 del backoffice es exactamente eso**: la portada lee `ingestionHealth`. Deja de ser una nota y pasa a ser una decisión de lectura con fecha |
| 6 | **La pasada desatendida**: con `launchd`, ¿qué señal le queda a alguien de que el disparo del lunes falló? **Y ¿a qué hora dispara?** A-10 encontró la RFFM saturada el primer día de competición (`504` tras 60 s en `/api/scorers`): una cadencia que caiga en día de partido pide a la fuente cuando peor contesta | `exit(1)` lo ve `launchd`, no una persona. A-4 cerró la ceguera del operador **con un log**; el log de un `launchd` sin nadie leyéndolo es la misma ceguera con otro nombre |
| 7 | **H-23, H-24 y H-26 remedidos** (mapa de A-8). `IngestCalendar` +58/−17, `IngestClubCalendars` +80/−5, `IngestCommand` +75/−24 desde `db5f5ee` | H-24 sacó el `record` del éxito fuera del `do`, y F10-bis rehízo ese camino para adoptar la fila: ¿sigue fuera? H-23 cerró la parada por infraestructura **preguntando** por ella: ¿la pregunta sigue delante de la adopción? Y el test de H-26, con su `23505` real, ¿recorre hoy el camino de fila adoptada o solo el de fila nueva? |

**Cómo se decide.** Provocándolo, como A-3: la carrera de la pregunta 1 con dos procesos reales contra
`club_atleti` —un `swift run Run ingest --force` mientras un `curl` al `202` está en curso—, y la 2 matando el
servidor entre el `202` y el trabajo. **La 6 no se mide: se decide**, y es del desarrollador; el bloque solo
dice cuáles son las salidas que existen hoy.

**Qué sale.** El mapa fallo-a-garantía de A-3 **reescrito para un `record` que actualiza**, la respuesta a la
propiedad autocurativa con su borde medido, y `D-89` convertido en decisión pendiente **con dueño**: la
rebanada 1.

---

### A-12 · El enganche, fuera del camino feliz · 1 sesión · **bloquea la rebanada 2**

> **Leer antes:**
> **`D-66`, `D-67`, `D-68`** (con su enmienda) y **`D-58`** (la identidad por tres) · **LLD §3.2 y §3.5** (la
> unicidad de `Team` y el `UNIQUE … NULLS NOT DISTINCT` de `TeamRegistration`) · del **Plan F10-001, §1 y los
> renglones de §5 de los bloques C, D y E** —no el detalle de cada ciclo— y **§7** entero · del **README,
> §4.2** (los `curl` del enganche y sus ocho errores) · de 001, **H-27, H-28 y H-29**.

**Pregunta.** Los 47 ciclos de F10 prueban el enganche en su camino y en cada error declarado. ¿Qué pasa en
los caminos que ningún montaje provoca — dos a la vez, dos veces, o a medias?

**Dónde mirar.** `Sources/Application/LinkTeamToFederation.swift` (347 líneas),
`PreviewFederationLink.swift`, `Sources/HTTPAdapter/FederationLinkHandler.swift`,
`Sources/Domain/Team.swift` y `TeamRegistration.swift`, y `TeamRegistrationRecord.swift`.

**La lección de F10 que fija el método de este bloque.** La tercera causa del 409 —*"ese `federationTeamId`
ya pertenece a otro equipo"*, `C-E.10`— es **el desenlace normal de enganchar tarde**, y daba un 500 con el
SQL en crudo. **Ningún test podía verlo porque en todos los montajes el código estaba libre** (regla 9). Este
bloque busca los hermanos de ese caso.

| # | Pregunta | Por qué |
|---|---|---|
| 1 | **Dos enganches del mismo equipo a la vez.** La comprobación *"¿está libre?"* y la escritura, ¿están en el mismo ámbito, y el perdedor de la carrera recibe **409** o **500**? | `C-E.10` traduce la violación que **se comprueba antes**; la que salta en el `INSERT` porque otro ganó entre medias es otra ruta |
| 2 | **Enganchar un equipo ya enganchado.** ¿Idempotente, 409, o una segunda cascada? | `D-66`: la fila enganchada **tiene segundo escritor**. Enganchar dos veces con coordenadas distintas cambia de qué competición es el equipo |
| 3 | **La cascada con la temporada ya creada por otro equipo** y la competición ya existente con otra identidad (`D-58`, *"el Cadete A a la juvenil"*) | Es el caso para el que `requireIdentityMatches` vive en el Dominio. Comprobar que **el orden** de las guardas no escribe la `Season` antes de rechazar |
| 4 | **El `/preview` llama a la federación dentro de la petición.** ¿Qué *timeout* manda, el del transporte o el del servidor, y qué recibe el cliente cuando vence el que no es? | `transportFailure` → **504** está medido; que el servidor corte antes y devuelva otra cosa, no |
| 5 | **El club catalán** (`D-95`): ¿qué ve un administrador de un club FCF en el `/preview`? | Plan §4.11 dejó a F10 *"cómo se lo cuenta el `/preview`"*. Comprobar que es un **501** con `Problem` y no un 500, y que **no escribe nada** |
| 6 | **H-29 remedido** (mapa de A-8): el `202` de `/federation-link` encola **detrás de una cascada**. ¿El trabajo de fondo ve lo que la cascada escribió, o puede arrancar antes del *commit*? | A-4 midió el `202` de `/ingestion-runs`, que **no escribe nada antes de encolar**. Éste sí |
| 7 | **H-28 remedido** (mapa de A-8). La guarda de `federationAdapterMissing` pasó a `plannedCompetitions` (`5c045f4`), y `IngestClubCalendars` suma +80/−5 desde entonces | Es la mitad de la pregunta 5 que sí estaba medida: la **otra** puerta, `/ingestion-runs`. Comprobar que sigue dando **501** y no un `202` mudo, con el mismo club catalán |

**Y lo que la rebanada 2 hereda directamente, que se comprueba pero no se arregla aquí:** `POST /v1/teams` +
`PUT /registrations` es **la otra puerta** del agujero de `C-A.3`. La guarda está en el Dominio para que se
reutilice (`Team.requireIdentityMatches`); el bloque comprueba que se puede llamar **sin** pasar por
`LinkTeamToFederation` —que no tiene dependencias ocultas de la cascada—, porque si no, la rebanada 2 la
reescribirá.

**Cómo se decide.** Las preguntas 1, 2 y 6 **contra la base de trabajo con dos `curl` concurrentes**; la 4 con
un transporte lento de verdad (`tc`, o un servidor local que no conteste). Una carrera que termina en **500**
es **S2** con dueño *rebanada 2* —el backoffice va a poner un botón delante—; una que deja **dos cascadas**, S1.

**Qué sale.** La tabla de caminos no felices del enganche con su código HTTP medido, y la respuesta sobre la
reutilizabilidad de la guarda de identidad.

---

### A-13 · Las migraciones, ahora que el esquema se ha duplicado · ½ sesión

> **Leer antes:**
> **`D-90`** y **`D-02`** · **LLD §4.6, §4.7 y §9.3** —esta última, **decidida** por A-5— · de 001, **A-5 en
> §5**, **H-30, H-31, H-35, H-36, H-38** y la nota *«Lo que A-5 entrega»* · de **AGENTS.md**, el comentario
> largo del bloque de comandos que enumera **las dieciséis** migraciones por tenant, y la viñeta sobre F8 y el
> `CHECK` que *"no se mantiene solo"* · del **README, §3.1 y §6**. Los avisos de herramienta de A-5 (`\restrict`
> del `pg_dump` 18, `-f backend/docker-compose.yml`) siguen valiendo.

**Pregunta.** A-5 midió con 9 migraciones que el esquema no depende de cuándo se dio de alta un club, y dejó un
test que lo guarda (H-38). Con **16**, dos de ellas rehaciendo `CHECK`s de *schemas* viejos, ¿sigue siendo
verdad, y lo sigue guardando el test?

**Dónde mirar.** `Sources/App/TenantMigrations.swift`, `Sources/Persistence/SQLHelpers.swift` (**+187 líneas
desde 001**: ahí vive `replaceCheckConstraint`), las migraciones nuevas de `IngestionRunRecord.swift`,
`StandingRowRecord.swift`, `LeagueScorerRecord.swift` y `TeamRegistrationRecord.swift`, y
`MigrationIntegrityTests`.

**Qué comprobar:**

- **H-30 remedido**: los cuatro caminos, un `md5`. `club_atleti` es ahora el mejor camino B posible —migrado
  en **más** lotes que cuando A-5 lo usó—. Dos comandos.
- **Que el test de H-38 conozca las 16.** Un test de *"los dos caminos dan lo mismo"* que enumere las
  migraciones a mano es un inventario por fichero (regla 10); uno que las derive de la lista, no.
- **Los `revert` que destruyen.** `AllowAcceptedIngestionRun.revert` **borra las filas `accepted`** para poder
  volver a `NOT NULL`, y lo razona bien. ¿Lo sabe quien lanza `migrate-tenants --revert`? H-32 le puso una
  guarda de `--yes` al *revert*; el mensaje ¿dice que se pierden datos, o solo tablas?
- **El patrón `replaceCheckConstraint`, generalizado en F10-bis** con *"dos consultas idénticas con el nombre
  cambiado se desincronizan"*. ¿Queda algún `CHECK` derivado de un enumerado que haya ganado casos desde su
  migración **sin** su migración gemela? Se cuenta con `CaseIterable` contra `pg_get_constraintdef`, no
  leyendo.
- **Los dos deberes de operación de §9.3** que A-5 dejó en el Plan: cerrar el *pool* de cada club y poder
  preguntar la versión de cada uno. Solo su **estado**: siguen sin hacer, ¿y `launchd` los cambia de precio?
- **El mapa de caducidad de A-8**, tres filas además de H-30 y H-38. **H-31** —`TenantMigrations.swift`
  +52/−3 desde `db5f5ee`—: comprobar con `git log -p db5f5ee..HEAD` que ningún `prepare` que existiera entonces
  se ha editado. **H-33** —`IngestCommand.swift` +75/−24—: ¿el fallo a mitad de `migrate-tenants` sigue
  atribuido a su club? **H-35** —`SQLHelpers.swift` +187—: los ayudantes nuevos (`replaceCheckConstraint` y
  compañía), ¿lanzan sobre una base no SQL como los tres que H-35 arregló, o vuelven a callarse?

**Cómo se decide.** Con `pg_dump` y `diff`, como A-5. Un `diff` con algo más que el nombre del *schema*, **S1**.
Un `CHECK` derivado sin su gemela, **S2** con dueño *la próxima migración*: es un `23514` esperando a un club
vivo.

**Qué sale.** H-30 y H-38 confirmados o reabiertos, y la lista de *reverts* que borran datos, cada uno con su
aviso o sin él.

---

### A-14 · La frontera HTTP, antes de que la copien treinta veces · 1 sesión · **bloquea la rebanada 1**

> **Leer antes:**
> **LLD §5.5** (el reparto de validación entre Dominio y *handler*), **§7.3–§7.5** (rol elevado, dónde vive la
> decisión, 403 y no 404) y **§6.1** · **`D-59`, `D-61`, `D-64`, `D-65`, `D-69`** · de **AGENTS.md**, las
> viñetas de **«Lo que F10 deja puesto»** (la traducción tiene UN sitio, el desenvoltorio de `ServerError`,
> `ActorResolver`) y las tres últimas de **«Cinco cosas que hay que saber»** (el identificador, lo que se
> queda sin arnés, los valores distintos) · de 001, **A-6 en §5** y **H-40 a H-46** · del **README, §4**.
> **Ni Supabase ni JWKS**: como A-6, este bloque mide costuras, no implementa auth.

**Pregunta.** La rebanada 1 va a escribir el primer *handler* de lectura del backoffice, y las siguientes
copiarán el suyo. ¿Qué cuesta **añadir un endpoint** hoy, y qué cuesta **encender la auth** después de que
haya treinta?

**Dónde mirar.** `Sources/HTTPAdapter/` entero (**1.575 líneas**): `ProblemMiddleware.swift` (529),
`IngestionHandler.swift`, `FederationLinkHandler.swift`, `ClubHandler.swift`; `Sources/Application/ActorResolver.swift`
y `ActorContext.swift`; `Sources/Tenancy/TenantResolutionMiddleware.swift`; y el código generado —**con un
`swift build` primero**, como descubrió A-6—.

**Las dos cuentas que el bloque tiene que devolver en número de ficheros:**

1. **Añadir un endpoint.** A-6 contó *"cinco ficheros, una línea cada uno"* para **poner §7 en marcha**. La
   pregunta hermana, que nadie ha contado: ¿cuántos sitios hay que tocar para añadir una operación **y dejarla
   afirmada**? `filter`, *handler*, mapeo DTO, enumerados espejo (`ContractEnumTests`), la lista de
   desenvoltorio de `ServerError` si trae un error nuevo, el `switch` de `ProblemMiddleware`, el renglón de
   `IdentifierTextTests` si trae un identificador… **Cada sitio que el compilador no exige es un sitio que la
   rebanada 7 olvidará.**
2. **Encender la auth.** Recontar la de A-6 **con el código de hoy**: `C-E.2` sacó el actor a un puerto y el
   borrador del backoffice dice que montar la auth es *"cambiar el adaptador de producción"*. ¿Sigue siendo
   una línea en cinco ficheros, o F10 añadió sitios?

**Sospechas de partida:**

| # | Sospecha | Por qué importa |
|---|---|---|
| 1 | Hay **dos** `TODO(§7)` en `Sources/` (`UpdateClub.swift:21`, `IngestClubCalendars.swift:42`) — medido con `grep` al preparar este plan. **`LinkTeamToFederation` y `PreviewFederationLink` no tienen el suyo**, y el *spec* marca **rol elevado** en cinco operaciones | Es la costura 3 de A-6 (*"¿tiene dónde caer la comprobación de ámbito?"*) aplicada a los casos de uso que F10 escribió. Y **H-41** (el rol elevado sin sitio) está asignado a F10: ¿se cerró o se heredó? |
| 2 | `teamNotFound` es un **404 dentro de un tenant**. ¿Distingue *"el equipo no existe"* de *"el club no existe"* sin credenciales? | Es **H-44** (S4 en 001) con superficie nueva. §7.5 dice 403, no 404, cuando no hay permiso; hoy no hay permiso que comprobar |
| 3 | **17 de 30** códigos `Problem` afirmados por código; los trece que faltan están listados por nombre en la fila de H-46 | ¿Cuántos de esos trece puede emitir **una operación de lectura**? Son los que la rebanada 1 hereda sin testigo |
| 4 | Los **13 contadores** de `IngestionRunResponse` se mapean a mano (F10-ter). El backoffice va a mapear DTOs de **veinte** entidades | ¿Es el mapeo a mano el patrón, o hay un sitio donde el compilador pueda obligar? Si es el patrón, la regla *"valores distintos entre sí"* tiene que ir a la plantilla de test, no a la memoria |
| 5 | **El método de los campos sin afirmar** (AGENTS.md, F10-ter): *"52 campos, 0 sin afirmar"* | Repetirlo es literalmente lo que la nota pide *"cuando el spec crezca"*, y es el último momento barato: después de la rebanada 1 crece |
| 6 | **H-40, H-42 y H-43 remedidos** (mapa de A-8). Desde `db5f5ee`: `ProblemMiddleware.swift` +211/−1, `IngestionHandler.swift` +49/−10, `ClubHandler.swift` +32/−9, `TenantResolutionMiddleware.swift` +10/−5, `FluentTenantUnitOfWork.swift` +21/−7 | H-43 dejó *"el motivo verdadero en el cuerpo y en el log"* para lo no clasificado: ¿lo cumplen las ramas nuevas de F10 y el desenvoltorio de `ServerError`? H-40 corrigió comentarios que negaban lo medido: ¿dice lo mismo `FederationLinkHandler.swift`? Y H-42 dejó **puerta y cinturón**: ¿siguen los dos? |

**Cómo se decide.** El listón de A-6, con las dos cuentas: si **añadir un endpoint** exige tocar sitios que el
compilador no exige y **no hay una lista que los nombre**, **S2** con dueño *rebanada 1* — la lista es el
entregable. Si **encender la auth** ya no es un adaptador, **S1**. Y las sospechas 1 y 2 **con el servidor
levantado** (regla 9; A-6 encontró sus tres afirmaciones falsas así y solo así).

**Qué sale.** **La lista de comprobación de "añadir un endpoint"**, con los sitios que el compilador vigila y
los que no, para que la rebanada 1 la use y la rebanada 2 la corrija. Y el recuento de la auth actualizado.

---

### A-15 · El arnés con el doble de tests: ¿qué significa hoy "N/N mutaciones"? · ½ sesión

> **Leer antes:**
> de 001, **A-7 en §5**, **H-07, H-45, H-46, H-47, H-48 y H-49**, y la nota *«Lo que A-7 entrega»* · de
> **AGENTS.md**, los párrafos *«La vara de medir sigue siendo la misma, y va subiendo»* y *«Y una lección de F7
> sobre el propio instrumento de medir»* · **Plan §4.1**, lo que F10-bis cuenta del **guion** de mutación · del
> **README, §5 entero** · **Plan §5.1** y **§9**.

**Pregunta.** El proyecto se mide con dos instrumentos: la batería (`REQUIRE_DB=1 swift test --xunit-output`)
y la comprobación de mutación, cuyos resultados —*"57/57"*, *"14/14"*, *"6/6"*— sostienen el cierre de cada
fase. A-7 auditó el primero. **¿Quién audita el segundo?**

**El hallazgo de partida, medido al preparar este plan.** **El guion de mutación no está en el repositorio**:
`git ls-files` no devuelve ningún `.sh`, `.py` ni `.pl`, ni nada con *mutat* en el nombre. Y el propio
proyecto documenta que ese guion **falló cinco veces, por cinco motivos distintos, y cada vez el fallo se leyó
como un resultado**: tres en F7 (un `$0` sin escapar, `error:` antes que `✘`, un patrón que no casaba) y dos en
F10-bis (clasificar como *"inválida"* toda pasada con `error:` en los logs, que escondió **dos supervivientes
reales**). La consecuencia es precisa: **ninguna de las cifras de mutación del proyecto es reproducible**, y
las correcciones del guion viven solo en la sesión que las hizo. Es **H-52**, pendiente de confirmar —puede
existir fuera del repositorio—.

**Qué comprobar:**

1. **El instrumento.** Si el guion existe fuera, dónde y en qué versión. Si no existe, **qué haría falta para
   que una cifra de mutación fuese una afirmación verificable**: el guion versionado, con las cinco
   correcciones como tests de sí mismo —*"una mutación que no compila no sobrevive"*, *"manda el `✘`"*—.
2. **H-07 y H-49, el CI que no existe.** Siguen abiertos y sin fase (001 §6-bis, *"deber de despliegue"*). Con
   `launchd` en local **delante** de Fly.io, ¿cambia algo? La respuesta puede ser *"no"*, pero escrita.
3. **La contaminación entre suites**, la lección de F6: *"un test que enumera algo compartido en una batería
   paralela es una carrera"*. Hay suites de nivel 3 nuevas (`TeamRegistrationPersistenceTests`,
   `TenantTraversalTests` rehecha): ¿alguna enumera `public.tenants` o *schemas* ajenos?
4. **Lo que ningún montaje ejerce**, generalizado. F10-ter lo encontró en los anulables que las *fixtures*
   dejan en nulo. La pregunta hermana, que nadie ha hecho: **¿qué valores fijan todas las *fixtures*?** Si
   todas siembran `masculino`, `futbol_11` o la misma temporada, las reglas de identidad de `D-58` solo se
   ejercen por un lado. Se cuenta, no se lee (regla 10).
5. **La categoría *"fuera del arnés"*** que H-48 dejó con dos bordes: la `M5` de F6-ter (el cable de
   `stopsTraversal`), `DetachedBackgroundWork`, los códigos de salida. ¿Ha entrado algo nuevo sin decirlo?
   `launchd` entra por construcción; conviene que tenga su renglón.
6. **El mapa de caducidad de A-8.** **H-45**: el freno de la sonda del ámbito 1 cruza `IngestClubCalendars`
   (+80/−5) e `IngestCommand` (+75/−24); ¿el test de F6-ter que fija el par sigue cazando su mutación?
   **H-48**: `TestEnvironment.swift` +6/−1; ¿se mueven los bordes de la categoría? Y **H-01**:
   `RFFMCanaryTests.swift` +10/−8, y el canario **se omite** en la batería (pide `FEDERATION_LIVE=1`): que
   compile no dice que siga casando con la RFFM viva.

**Cómo se decide.** Si el guion no existe en ningún sitio versionado, **S2** con dueño *deber de despliegue*
—va con el CI, porque es la otra mitad de *"qué significa verde"*—; no es S1 porque las mutaciones que se
hicieron se hicieron, pero **no se pueden volver a hacer**, y cada fase siguiente cita una cifra que nadie
puede comprobar. Las demás, con la escala normal.

**Qué sale.** El estado del instrumento de mutación y lo que haría falta para versionarlo, la lista de valores
que ninguna *fixture* varía, y la categoría *"fuera del arnés"* al día.

---

## 6. Libro de hallazgos

Numeración **`H-nn` correlativa con la de 001** —la última allí es **H-50**— y sin reutilizar. **Se escribe
aquí incluso cuando el bloque no encuentra nada.**

| # | Bloque | Severidad | Hallazgo | Reproducción | Estado |
|---|---|---|---|---|---|
| **H-51** | A-8 | **S3** *documental* | **`AGENTS.md` se contradice sobre F10 dentro del mismo fichero, y no es la única cifra que deriva.** Su lista de documentación clave presenta el Plan F10 como *"la fase en curso"* (línea 19), y la sección *«Estado actual»* dice *"Y **F10, en curso**"*, *"Quedan los bloques **C, D y E**"* y *"**476 tests**"*; unas 250 líneas más abajo el mismo fichero dice que F10 está **entregada**, con **541 tests**, y el Plan de desarrollo la marca ✅ desde el 2026-09-24. El párrafo *«De F0 a F5 no se añadió un solo endpoint»* sigue diciendo que *"las siguientes llegan en F10"*, en futuro. Y el **Plan F10-001 §7** habla de *"los **once** `IngestionSkip.Reason`"* cuando son **diez** —`AGENTS.md` ya lo corrigió para sí mismo el 2026-09-24, pero no en el plan de F10—. Además, *"17 de 30"* códigos `Problem` (`AGENTS.md`) frente a *"15 de 30"* (Plan §4.1, F10-ter): puede ser una cifra que avanzó en `6a837ab` y no dos que no casan, y eso es lo que A-8 tiene que decir | Desde la raíz del repositorio: `grep -n "en curso\|476 tests\|541 tests" AGENTS.md` · `grep -n "los once" "backend/Plan F10-001.md"` (líneas 834 y 839) · `sed -n '/enum Reason/,/^    }/p' backend/Sources/Domain/IngestionRun.swift \| grep -c "^ *case "` → **10** · y `grep -n "de 30\|de 14" AGENTS.md "docs/Plan de desarrollo-001.md"` | **Corregido** el 2026-09-25 (A-8, primera mitad). Los rótulos de F10 en `AGENTS.md`, el README y el Plan F10 dicen ya *entregada*; **541 tests** en los tres; *"los once"* → *diez* en Plan F10 §7. **Y lo que el hallazgo no listaba**: el *"motivo número once"* de F9-bis en `AGENTS.md` (es el décimo); su *"entidad 22"* para `StandingRow`, resto de la errata de Plan §4.10 (es la 9ª de §3.2); el README, parado en F8 —446 tests, *"las otras 79"* (son 77), 6.644 líneas (6.739), diez tablas por club (once) y sin filtros de F10 en §5—; y dos comentarios de código que daban `TeamRegistration` por inexistente (`TenantMigrations.swift`, `CompetitionRecord.swift`). **El 17 contra 15 no es contradicción**: `6a837ab` movió la cifra, y Plan §4.1 lo apunta ahora. Citas `D-nn` y `C-x.n`, limpias (los dos falsos positivos de 001). **Y en la segunda mitad, dos más**: `AGENTS.md` decía *"los quince que faltan"* junto a *"17 de 30"* (son **trece**, contados con `grep` sobre `Tests/`), y A-13 decía *"con 17"* migraciones |
| **H-52** | A-15 | *sospecha* — **S2** si se confirma | **El guion de mutación no está versionado, y el proyecto documenta cinco fallos suyos que se leyeron como resultados.** Ver A-15 | `git ls-files \| grep -iE "\.(sh\|py\|pl)$\|mutat"` → vacío | **Pendiente de confirmar** en A-15 |
| **H-53** | A-10 | **S1** · **bloquea `launchd`** | **La pasada de goleadores vacía la tabla de una competición con éxito, y lo registra como `succeeded`.** `IngestScorers.write` no tiene ninguna guarda de lista vacía: con cero filas que escribir, `retire(keepingMark:)` se lleva **todas** las de la competición, porque ninguna lleva la marca de esta pasada. Se llega por **tres** entradas, las tres reproducidas: **(1)** la fuente contesta el ranking vacío con su nombre —que la guarda de `D-84` da por bueno, porque el nombre casa—; **(2)** la fuente publica las 218 filas pero renombra `codigo_jugador`, y las 218 caen en `unidentifiedScorer`; **(3)** vacío y **sin** nombre, donde la guarda de `D-84` calla por diseño (`Competition.swift:277`, `guard let … incoming`). Y el único test de lista vacía, `anEmptyRankingIsASuccess` (`IngestScorersTests.swift:530`), **siembra la tabla vacía**: afirma *"vacío ⇒ éxito"* y no mira nunca qué le hace a lo que ya había. No hay un solo test, a ningún nivel, de una segunda pasada que traiga **menos** que la primera. La tabla no vuelve hasta que la fuente republique, y por `D-55` la foto intermedia no se puede pedir hacia atrás | Sonda de nivel 3 **no versionada**: dos pasadas de `IngestScorers` sobre `FluentTenantUnitOfWork` y `RFFMFederationClient` reales, la primera con `RFFM-scorers-group-24037549.txt` y la segunda una semana después con el cuerpo hostil. Resultado: **(1)** `{"competicion":"PRIMERA DIVISION AUTONOMICA CADETE","goles":[]}` → `succeeded retired=218` · filas **218 → 0**; **(2)** el volcado con `"codigo_jugador"`→`"id_jugador"` → `succeeded retired=218 skipped=218` · **218 → 0**; **(3)** `{"goles":[]}` → `succeeded retired=218` · **218 → 0**. Controles: cuerpo `null` → `failed`, **218** intactas; nombre ajeno → `failed`, **218** intactas | **Arreglado** (2026-09-29, ronda de arreglos de A-10), en dos pasos. **1** (`5e86f3f`): una pasada que no deja nada que conservar sobre una competición con goleadores falla y no retira. **2**, decidido por el desarrollador tras ver que esa guarda dejaba pasar la caída **parcial** (218 publicadas, 5 construibles → 213 retiradas): **el total de goles de la competición no puede bajar** (`IngestScorers.requireGoalsDoNotDecrease`). Si baja, la pasada no escribe ni retira nada y queda `failed` en `ingestion_runs` con las dos cifras. Cubre las tres entradas y la parcial; admite la liga que empieza (total guardado 0) y el goleador que sale porque sus goles se apuntan a otro (total igual). Sale como `malformedResponse`, sin caso nuevo en ninguna enumeración pública: arreglo y no mini-fase. **Es regla de la RFFM**, que publica a todo el que ha marcado y sin tope (§F.19); en la FCF no se sostiene —*top*-50 y un histórico que bajó—, y queda escrito en el código para quien reabra F9. Tests: tres de nivel 2 (vacío, todo descartado, parcial con las cifras en el motivo), el de nivel 3 con el `retire` real, y el de `D-94` reescrito para que el total no baje (10+9 → 11+8). **3/3 mutaciones** (sin la llamada; `<` por `<=`; sin lo guardado). **545 tests**; regla 9 contra `club_atleti`: 0 retirados, 426 filas y 1.844 goles intactos |
| **H-54** | A-10 | **S3** | **La guarda que hace inaplicable `D-56` a `StandingRow` es correcta y no tiene testigo.** `StandingRow` se refresca **pisándola entera** (`IngestStandings.write`), y es seguro porque el parser **exige** los ocho contadores y tira la tabla con `malformedResponse` si falta uno (`RFFMStandingsParser.swift:80-87`). Ningún test lo provoca: los ocho de `RFFMStandingsParserTests` son del camino bueno, del `null` y del no-JSON. Si esa guarda se relajase —la tentación es la del calendario, *"vacío es `nil`"*—, un `puntos: ""` escribiría **0 sobre los puntos de verdad**, que es exactamente el borrado que `D-56` existe para impedir | Mutante: `return 0` en lugar del `throw` de `number(_:_:)` → **546/546 en verde** con `REQUIRE_DB=1` (los 541 más los 5 de la sonda). Restaurado | **Arreglado** (2026-09-29, ronda de arreglos de A-10). Solo test, sin tocar el parser: `RFFMStandingsParserTests.aSilentCounterRejectsTheTable`, parametrizado sobre el volcado real de la jornada 30 con **los puntos del líder** estropeados de las tres formas en que la fuente calla (`D-75`, §F.11) —en blanco, ausente, `&nbsp;`—, y exige `malformedResponse` **con la casilla**: `clasificacion[0].puntos`. **2/2 mutaciones**: el mutante de A-10 (`return 0`) cae en los tres casos, y un `field` sin fila ni casilla, en los tres. **546 tests** |

### Nota de cierre de A-8 · ¿la deriva sigue siendo sistemática, y qué se movió debajo de 001?

**La deriva sigue siendo la de 001, con una variante nueva.** Las citas se sostienen: los 97 `D-nn` de
`Sources/`, `Tests/` y los documentos resuelven —los dos que no, `D-001` y `D-266`, son los falsos positivos
que 001 ya documentó—, y los `C-x.n` del código existen todos en el Plan F10. **Las cifras derivan**, como en
001. Y aparece lo nuevo: **derivan los rótulos de estado**, no solo los números — *"F10 en curso"* cuatro
secciones por encima de *"F10 entregada"*. El patrón es reconocible: **se deriva lo que el cierre de fase no
toca**. Cada cierre escribe su detalle en el Plan y su lección al final de `AGENTS.md`; nadie vuelve a la
cabecera del README (parado en F8: seis cifras), a «Estado actual» ni a los rótulos de los bloques del Plan F10.
Y el propio plan de auditoría cayó dos veces (*"17"* migraciones, que son 16 por tenant). Todo S3, todo
corregido: ver H-51.

**El mapa de caducidad.** Se cruzaron las filas de 001 en **S4** o **cerradas** contra
`git diff --name-only db5f5ee..HEAD` (96 ficheros de `Sources/` y `Tests/`). Ninguna garantía queda sin bloque
que la reciba, así que **no hay S3 de huérfanos**. En `Tests/` no se ha borrado un solo `@Test` desde
`db5f5ee` —el único que desaparece del `diff` es un cambio de rótulo (`1aaca55`)—, así que los testigos de
001 **siguen existiendo**; lo que el mapa pregunta es si siguen **alcanzando** lo que afirmaban.

| Bloque | Remide | Lo que se movió debajo |
|---|---|---|
| **A-9** | H-13 (fila 5) | El puerto, 236 → 717 líneas; menciones a la RFFM, 23 → 39 |
| **A-10** | H-17, H-19, H-22 (fila 6) | `CalendarPass` adopta filas `accepted`; el repositorio de ingesta, +392 |
| **A-11** | H-25 (fila 4) · H-23, H-24, H-26 (fila 7) | `record` pasa a *upsert*; las dos pasadas y el comando, reescritos en parte |
| **A-12** | H-29 (fila 6) · H-28 (fila 7) | El segundo `202`, con cascada delante; el recorrido, +80 |
| **A-13** | H-30, H-38 (ya en el bloque) · H-31, H-33, H-35 (viñeta nueva) | 9 → 16 migraciones por tenant; `SQLHelpers`, +187 |
| **A-14** | H-44 (sospecha 2) · H-40, H-42, H-43 (fila 6) | `ProblemMiddleware`, +211; un *handler* nuevo |
| **A-15** | H-45, H-48, H-01 (punto 6) | El recorrido y el comando; `TestEnvironment`; el canario, que no corre |

**Se sostienen sin tocar, porque su código no se ha movido:** H-02, H-12, H-14, H-16, H-20 y H-50. **Y los
documentales de A-0 se han vuelto a medir aquí mismo**, que es la primera mitad del bloque: H-03 y H-04 habían
vuelto a derivar (README, corregido); H-05, H-06 y H-11 se sostienen —`"rffm"` y `"fcf"` siguen en un solo
fichero, los filtros del README casan todos, y la frase contradictoria de `Competition.swift` no ha vuelto—.

**Lo que no es de este mapa**: las filas de 001 que quedaron **abiertas** con fase (H-08, H-09, H-10, H-15,
H-21, H-27, H-36, H-41, H-46, H-49…). Si su fase las cerró o no lo comprueba el bloque que ya las cita en su
«Leer antes»; no son garantías que caduquen, son deudas que se cobran.


### Nota de cierre de A-10 · ¿puede vaciar la tabla con éxito?

**Sí, y por tres entradas** (H-53). Es el S1 que el plan anticipaba: lo que `D-94` protege —la atomicidad— está
bien, y medido; lo que no protege es que una pasada **atómica y correcta** reciba menos de lo que había. La
sonda lo enseña sin ambigüedad: 218 filas, una semana después cero, y el registro dice `succeeded`. **Nadie se
entera**, porque lo único que avisaría —una fila `failed`— no se escribe.

**La observación viva, en dos intentos.** El 2026-09-27 `/api/scorers` devolvió **`504` tras 60 s** para el
grupo sin empezar **y** para el grupo jugado de control, mientras el resto del sitio contestaba. **El
2026-09-28 contestó**: el grupo sin goles llega con **`200`, el sobre entero y `"goles": []`**, con el nombre
de la competición —**no** `null`— (`RFFM-scorers-grupo-sin-goles.txt`, Anexo RFFM §F.19 al día). Es
**la entrada (1) de H-53, servida por la fuente de verdad**, y descarta una de las salidas que §C.12 dejaba
abierta: **tratar el `[]` como coordenada mala sería falso**, porque es la respuesta normal de todo grupo al
empezar la temporada. La guarda que haga falta tiene que mirar **lo que había**, no lo que llega.

Lo que sigue es el texto del primer intento, que se conserva porque la fecha límite era real: El
grupo elegido es **PRIMERA DIVISIÓN AUTONÓMICA ALEVÍN, Grupo 1** (`idCompetition=26737845`,
`idGroup=26737846`), que **empieza el 2026-10-10**: la observación hay que hacerla **antes** de esa fecha o
buscar otro. **No cambia la severidad de H-53**: las entradas (2) y (3) no dependen de lo que conteste un grupo
vacío, y la (1) es justo la que §F.19 dice que se espera (`"goles": []`). Lo que sí decide es **cuál de las
salidas** es la buena: si un grupo vacío llega a `null`, un `[]` real sería otra cosa que un grupo sin goles.

**Y un `504` es inofensivo**, que es de lo poco bueno que dejó el intento: llega al adaptador como
`unexpectedStatus`, la pasada falla y la tabla no se toca —el mismo camino que el control `null`—.

**Y el porqué del `504`, que cambia de precio a H-53.** El 2026-09-27 era **el primer día de competición**
de muchas categorías de la temporada 26-27, y el portal entero iba saturado. Dos consecuencias, ninguna
medida todavía: **(a)** una pasada programada en día de partido pide a la fuente justo cuando peor contesta
—y un servidor saturado no solo da `504`: también puede servir un `200` con el cuerpo truncado o vacío, que
es la entrada (1) de H-53—; **(b)** la cadencia de `launchd` deja de ser un detalle de despliegue y pasa a ser
una decisión con consecuencia. Va como nota a **A-11**, pregunta 6.

**El mapa rama-a-test de la pasada de goleadores**, que es lo que el bloque tenía que entregar:

| Rama | Nivel 2 | Nivel 3 | Si se rompe |
|---|---|---|---|
| Sin capacidad (`D-48`): ni pide ni retira | `IngestScorersTests:383, :407` | — | Se vacía el ranking al apagar la capacidad |
| `null` → `coordinateNotFound` → `failed` | `:466` | la sonda (control) | — |
| Nombre ajeno → `D-84` → `failed` | `:434, :449` | la sonda (control) | Ranking de otra competición |
| Nombre ausente → la guarda **calla** | — | la sonda (3) | **H-53** |
| Fila sin id o sin goles → `unidentifiedScorer` | `:482, :509` | — | — |
| **Todas** las filas descartadas → lista vacía | — | la sonda (2) | **H-53** |
| Lista vacía **sobre tabla con filas** | — | la sonda (1) | **H-53** |
| Retirada por marca, solo en su competición | `:315, :342, :365` | `LeagueScorerPersistenceTests:207, :233, :268` | — |

**Las sospechas de `StandingRow`, cerradas sin hallazgo propio.** La **4** no se sostiene: una jornada con
*snapshot* no se vuelve a calcular y la última se refresca siempre **pidiéndola** (`StandingsSyncPlan.steps`),
con test de las dos cosas (`StandingsSyncPlanTests:67, :86`); una fila calculada no puede pisar una ingerida.
La **5** no aplica por construcción: los ocho contadores son obligatorios y la tabla entera se rechaza si
falta uno, así que ningún silencio de la fuente llega al `UPDATE` — **y eso es justo lo que no tiene testigo**
(H-54). El único anulable, `previousPosition`, lo calculamos nosotros.

**Fila 6 del mapa de caducidad, contestada.** H-17 sigue alcanzando lo que afirmaba: con la política del
marcador de `Match.merging` cambiada por una sobrescritura ciega, **solo la suite de nivel 3**
(`CalendarIngestionEndToEndTests`) la caza, en `:532`, con cuatro aserciones —entre ellas el
`matchesUpdated == 0` de **H-19**—, y pasando por `CalendarPass` con la adopción delante (**H-22**). H-18 sigue
en pie (`CalendarPass.swift:159`).

**La regla 9, cumplida el 2026-09-28.** La sonda corrió contra `tfm_test`; reproducir H-53 contra la base de
trabajo **borraría sus 426 goleadores**, así que lo que se ejecutó allí es **una pasada normal**, con la tabla
respaldada antes (`pg_dump --data-only -t club_atleti.league_scorers`, por si la RFFM servía un `[]` a
destiempo): `swift run Run ingest -t atleti -c <las dos> --force` → *"2 competición(es) sincronizada(s), 0 con
fallo"*. Goleadores: **0 creados, 218 y 208 actualizados, 0 retirados**, con duración medida (0,80 s y
1,46 s); las **426** filas intactas. El camino bueno contra el `UNIQUE` de verdad sigue en pie; el malo es H-53.

---

## 6-bis. La puerta: cuándo se puede montar `launchd` y abrir la primera rebanada

Como en 001: la auditoría termina cuando **el libro no tiene deuda que bloquee**. Aquí hay **dos puertas y no
una**, porque lo que viene detrás son dos cosas que se pueden empezar por separado:

| Puerta | Condición | Bloques que la abren |
|---|---|---|
| **`launchd`** | Cero S1 abiertos en **A-10 y A-11**, y `D-89` con decisión o con dueño | A-8, A-10, A-11 |
| **Rebanada 1** (la portada) | Lo anterior, **más** cero S1 en **A-14** y su lista de *"añadir un endpoint"* escrita | + A-14 |
| **Rebanada 2** (alta de equipo) | Lo anterior, **más** cero S1 en **A-12** y **A-13** | + A-12, A-13 |

Y para todas, las tres condiciones de 001 §6-bis:

| Condición | Cómo se comprueba |
|---|---|
| **Cada S2 tiene dueño** | Su fila dice qué rebanada, qué mini-fase o qué deber de despliegue lo arregla. **Un S2 sin dueño cuenta como S1** |
| **Los S3 documentales, corregidos** | No se aplazan (§2) |
| **La batería en verde y el recuento al día** | `REQUIRE_DB=1 swift test --xunit-output` y el recuento **leído del XML** (H-07) |

**A-9 y A-15 no bloquean ninguna puerta**: A-9, porque su coste no crece hasta que F9 reabra; A-15, porque lo
que puede encontrar es de despliegue. **Pero no se cierra la auditoría sin ellos**, igual que 001 no se cerró
sin A-7.

---

## 7. Estado

| Bloque | Estado | Sesión | Hallazgos |
|---|---|---|---|
| **A-8** · La vara de medir y el mapa de caducidad | ✅ **cerrado** — la vara al día (H-51 corregido) y el mapa repartido en A-9…A-15; ver su nota de cierre en §6 | 2026-09-25 | H-51 |
| **A-9** · El puerto sin segunda implementación | ○ pendiente | | |
| **A-10** · La única regla que borra | ✅ **cerrado, y su ronda de arreglos también** — H-53 (S1) y H-54 (S3) arreglados el 2026-09-29. Por A-10, la puerta de `launchd` ya no está cerrada: falta A-11 | 2026-09-27/29 | H-53, H-54 |
| **A-11** · La fila que transita | ○ pendiente | | |
| **A-12** · El enganche fuera del camino feliz | ○ pendiente | | |
| **A-13** · Las migraciones, con el esquema duplicado | ○ pendiente | | |
| **A-14** · La frontera HTTP antes de copiarla | ○ pendiente | | |
| **A-15** · El arnés y el instrumento de mutación | ○ pendiente | | H-52 (*sospecha*) |

---

## 8. Lo que esta auditoría deja fuera, y por qué

Todo lo que 001 §8 dejó fuera **sigue fuera, por las mismas razones**: rendimiento y escala (§6.5), la forma
del *tier* dedicado (§9.2), la política de retención RGPD (§9.4), **implementar §7** y la forma del *spec* más
allá de lo generado. Y además:

| Fuera de alcance | Por qué |
|---|---|
| **El adaptador de la FCF** | Aplazado por `D-95` con condición de reapertura. A-9 audita **el puerto**, y deja escrito el ensayo en seco para quien reabra |
| **El *stack* y el diseño del backoffice** | Sin ADR ni LLD todavía (borrador §4). La auditoría mira **lo que el backoffice va a heredar**, no lo que va a construir |
| **La vista derivada de §9.12** | Resuelta en el modelo por `D-68`; servirla es de la rebanada 1 |
| **El desempate de `D-92`** (enfrentamiento directo) | Anotado y sin aplicar a propósito (Plan §4.9); es una regla que falta, no una mal puesta |
| **El umbral de `D-89`** | Se decide con datos de pasadas reales (Plan F10 §6). A-11 audita **la regla de lectura** con tres clases de pasada, que es otra cosa |
| **Montar el CI, el cron de verdad y la auth** | Deberes de despliegue que van juntos en Fly.io. A-15 audita **qué significa verde** mientras no existan |

Y la cláusula que no se negocia, heredada entera: **la auditoría no cambia el alcance entregado**. El `filter`
de `openapi-generator-config.yaml` sigue siendo `D-69`.
