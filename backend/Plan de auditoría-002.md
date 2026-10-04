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
| 6 | **Heredada de A-11 (H-61).** El 2026-09-30 a las 17:44 UTC, `/api/scorers` devolvió **`null`** para el grupo **existente** de PRIMERA AUTONÓMICA CADETE —dos peticiones simultáneas, las dos igual— y dos minutos después, **200 con sus 218 filas**. El adaptador lo traduce a `coordinateNotFound` con el texto *"ese par idGroup+idCompetition no existe"*, que es **falso** para un `null` pasajero | La pasada hace lo correcto —falla y no toca la tabla—, pero **el motivo guardado manda a depurar al sitio equivocado**, que es H-24 un piso más abajo. Es la sospecha 3 de este bloque con un caso medido: ¿*"no existe"* es conocimiento del adaptador, o es una conclusión que no puede sacar de un `null`? |

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
| 8 | **Heredada de A-11 (H-62, *sospecha*).** El enganche escribe su fila `accepted` **sin mirar si ya hay una abierta** (`LinkTeamToFederation.swift:281-287`), al revés que `accept` (`IngestClubCalendars.swift:242`); y `findAccepted` cierra **la más antigua**. Si la competición ya existe y tiene una aceptada abierta —la de un `202` cuyo proceso murió, que A-11 midió que puede quedarse así—, la pasada del enganche cierra **aquélla** y deja abierta **la del `jobId` que se acaba de devolver** | El cliente sigue su `jobId` y lo ve `accepted` hasta la pasada siguiente de esa competición, que por H-57 puede no llegar. Provocarlo: fila `accepted` a mano sobre una competición existente, enganche de un segundo equipo a ella, y mirar **las dos** filas después |
| 9 | **Heredada de A-14 (H-66).** `PreviewFederationLink` y `LinkTeamToFederation` **no tenían `TODO(§7)`** (puesto en la ronda de A-14), aunque el *spec* les pide rol elevado, y el enganche encola una ingesta **con el actor de la persona** (`FederationLinkHandler.swift:154-157`) | Es H-41 un nivel más allá, y A-12 es el bloque que comprueba qué hereda la rebanada 2. La decisión de H-41 es de la auth; poner las dos anclas es de la rebanada 2, que trae las escrituras con rol elevado. Comprobar que no hay **otra** escritura del enganche que también se quede sin ancla |

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
7. **Heredada de A-14 (H-72).** Los dos cruces que sostienen el cierre de F10-ter —campos del contrato contra
   `Tests/` y códigos `Problem` afirmados por código— **tampoco están versionados**, igual que el guion de H-52.
   A-14 los rehízo a mano con `ruby -ryaml` y `grep`, y le salieron **61** campos donde F10-ter había contado
   **52**, sin poder saber por qué, porque el método no dice con qué comando se contó. ¿Van con el guion?

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
| **H-52** | A-15 | **S2** — **confirmado** (2026-10-03) | **El guion de mutación no está versionado, y el proyecto documenta cinco fallos suyos que se leyeron como resultados.** Ver A-15. **Confirmado por el desarrollador: no existe fuera del repositorio.** Ninguna cifra de mutación anterior a este arreglo se puede repetir: los catálogos de F1 a A-14 no se escribieron nunca, solo sus resultados | `git ls-files \| grep -iE "\.(sh\|py\|pl)$\|mutat"` → vacío | **Arreglado** (2026-10-03), **adelantado al cierre de A-15 por decisión del desarrollador**. El guion vive en `backend/Tools/Mutate/`, paquete Swift aparte para que sus tests no muevan el recuento de la batería. Cada cifra se afirma con **un catálogo JSON versionado**: qué se rompe, dónde, y qué filtro tiene que caer. **Las cinco correcciones son tests del guion** (36, en `Tools/Mutate/Tests/`): reemplazo literal, una sola coincidencia, lo que no compila es inválido, manda el código de salida con el `✘` o el XML, `error:` no se lee nunca, cero tests ejecutados no es sobrevivir. A eso se suma la batería sin mutar **al empezar y al acabar**. **Y los tests del guion, sostenidos por mutación**: `Catalogs/self.json` vuelve a meter cada fallo histórico en el guion, **14/14 cazadas**. **Y un sexto fallo, encontrado al estrenarlo contra la batería entera**: en el XML de swift-testing el atributo `tests` **ya excluye** los omitidos (`tests="82" skipped="1"` con 83 `<testcase>`), y el guion los restaba otra vez. Un filtro con un test y el canario habría dado *"ningún test ejecutado"*, una inválida falsa. Iba en la dirección prudente, pero era un fallo. Ahora se cuenta por `<testcase>`, con su test (rojo de aserción antes del arreglo) y su mutación (`S14`). La contraprueba también da lo que debe: una mutación de comentario **sobrevive**, un patrón que no casa y otra que no compila salen **inválidas**, y la equivalente declarada sale **equivalente**. Ctrl-C a mitad restaura el fichero. **La primera cifra repetible**: `Catalogs/A-13.json` reproduce la ronda de A-13, **6/6**, cada una cazada por el test que la ronda documenta. **Lo que no arregla**: los dos cruces de H-72 siguen sin versionar (punto 7 de A-15) |
| **H-53** | A-10 | **S1** · **bloquea `launchd`** | **La pasada de goleadores vacía la tabla de una competición con éxito, y lo registra como `succeeded`.** `IngestScorers.write` no tiene ninguna guarda de lista vacía: con cero filas que escribir, `retire(keepingMark:)` se lleva **todas** las de la competición, porque ninguna lleva la marca de esta pasada. Se llega por **tres** entradas, las tres reproducidas: **(1)** la fuente contesta el ranking vacío con su nombre —que la guarda de `D-84` da por bueno, porque el nombre casa—; **(2)** la fuente publica las 218 filas pero renombra `codigo_jugador`, y las 218 caen en `unidentifiedScorer`; **(3)** vacío y **sin** nombre, donde la guarda de `D-84` calla por diseño (`Competition.swift:277`, `guard let … incoming`). Y el único test de lista vacía, `anEmptyRankingIsASuccess` (`IngestScorersTests.swift:530`), **siembra la tabla vacía**: afirma *"vacío ⇒ éxito"* y no mira nunca qué le hace a lo que ya había. No hay un solo test, a ningún nivel, de una segunda pasada que traiga **menos** que la primera. La tabla no vuelve hasta que la fuente republique, y por `D-55` la foto intermedia no se puede pedir hacia atrás | Sonda de nivel 3 **no versionada**: dos pasadas de `IngestScorers` sobre `FluentTenantUnitOfWork` y `RFFMFederationClient` reales, la primera con `RFFM-scorers-group-24037549.txt` y la segunda una semana después con el cuerpo hostil. Resultado: **(1)** `{"competicion":"PRIMERA DIVISION AUTONOMICA CADETE","goles":[]}` → `succeeded retired=218` · filas **218 → 0**; **(2)** el volcado con `"codigo_jugador"`→`"id_jugador"` → `succeeded retired=218 skipped=218` · **218 → 0**; **(3)** `{"goles":[]}` → `succeeded retired=218` · **218 → 0**. Controles: cuerpo `null` → `failed`, **218** intactas; nombre ajeno → `failed`, **218** intactas | **Arreglado** (2026-09-29, ronda de arreglos de A-10), en dos pasos. **1** (`5e86f3f`): una pasada que no deja nada que conservar sobre una competición con goleadores falla y no retira. **2**, decidido por el desarrollador tras ver que esa guarda dejaba pasar la caída **parcial** (218 publicadas, 5 construibles → 213 retiradas): **el total de goles de la competición no puede bajar** (`IngestScorers.requireGoalsDoNotDecrease`). Si baja, la pasada no escribe ni retira nada y queda `failed` en `ingestion_runs` con las dos cifras. Cubre las tres entradas y la parcial; admite la liga que empieza (total guardado 0) y el goleador que sale porque sus goles se apuntan a otro (total igual). Sale como `malformedResponse`, sin caso nuevo en ninguna enumeración pública: arreglo y no mini-fase. **Es regla de la RFFM**, que publica a todo el que ha marcado y sin tope (§F.19); en la FCF no se sostiene —*top*-50 y un histórico que bajó—, y queda escrito en el código para quien reabra F9. Tests: tres de nivel 2 (vacío, todo descartado, parcial con las cifras en el motivo), el de nivel 3 con el `retire` real, y el de `D-94` reescrito para que el total no baje (10+9 → 11+8). **3/3 mutaciones** (sin la llamada; `<` por `<=`; sin lo guardado). **545 tests**; regla 9 contra `club_atleti`: 0 retirados, 426 filas y 1.844 goles intactos |
| **H-54** | A-10 | **S3** | **La guarda que hace inaplicable `D-56` a `StandingRow` es correcta y no tiene testigo.** `StandingRow` se refresca **pisándola entera** (`IngestStandings.write`), y es seguro porque el parser **exige** los ocho contadores y tira la tabla con `malformedResponse` si falta uno (`RFFMStandingsParser.swift:80-87`). Ningún test lo provoca: los ocho de `RFFMStandingsParserTests` son del camino bueno, del `null` y del no-JSON. Si esa guarda se relajase —la tentación es la del calendario, *"vacío es `nil`"*—, un `puntos: ""` escribiría **0 sobre los puntos de verdad**, que es exactamente el borrado que `D-56` existe para impedir | Mutante: `return 0` en lugar del `throw` de `number(_:_:)` → **546/546 en verde** con `REQUIRE_DB=1` (los 541 más los 5 de la sonda). Restaurado | **Arreglado** (2026-09-29, ronda de arreglos de A-10). Solo test, sin tocar el parser: `RFFMStandingsParserTests.aSilentCounterRejectsTheTable`, parametrizado sobre el volcado real de la jornada 30 con **los puntos del líder** estropeados de las tres formas en que la fuente calla (`D-75`, §F.11) —en blanco, ausente, `&nbsp;`—, y exige `malformedResponse` **con la casilla**: `clasificacion[0].puntos`. **2/2 mutaciones**: el mutante de A-10 (`return 0`) cae en los tres casos, y un `field` sin fila ni casilla, en los tres. **546 tests** |
| **H-55** | A-11 | **S2** · dueño: **ronda de arreglos de A-11**, decidido por el desarrollador | **Dos pasadas que adoptan la misma fila escriben las dos en ella, y gana la última, aunque sea la que falló.** `record` es `find` + `update` **sin condición** (`FluentIngestionRepositories.swift:314-324`): no mira si la fila sigue `accepted`, así que la segunda pasada pisa lo que cerró la primera, contadores incluidos. `closed(as:)` sí lo exige, pero sobre la copia en memoria que cada pasada leyó en su ámbito 1. Y la carrera no es teórica: **`accept` deduplica la fila, pero no el trabajo**. Con `findAccepted != nil` hace `continue` y devuelve igualmente todas las competiciones, y el *handler* encola `runAccepted` por todas (`IngestClubCalendars.swift:242-251`, `IngestionHandler.swift:181-185`). Un doble clic en el botón son **dos trabajos sobre una sola fila**. Es **H-24 resucitado por concurrencia**: una fila `failed` de una pasada cuyos datos están escritos y cuyo `last_synced_at` se ha movido | **Sonda de nivel 3, no versionada** (dos `IngestCalendar` reales sobre `FluentTenantUnitOfWork` y una compuerta en el cliente que las retiene hasta que las dos han pasado el ámbito 1): **(a)** A va bien y B falla después → la fila pasa de `succeeded matches+=1` a **`failed matches+=0`**, con **1 partido escrito** y `last_synced_at` puesto; **(b)** las dos van bien sobre una primera sincronización → A choca con `23505` en `uq:rounds.competition_id+rounds.number` al insertar a la vez, B escribe, y **la fila final dice `failed`** con el partido escrito. **Contra `club_atleti`** (regla 9): dos `POST /v1/ingestion-runs {"seasonId"}` seguidos → **2** filas `accepted` (una por competición), **4** de clasificación y **4** de goleadores (dos trabajos) y **2** de calendario al final: la segunda pasada de calendario de cada competición **escribió en la fila de la primera**. Con los dos `POST` en paralelo, lo mismo | **Arreglado** (2026-09-30, ronda de arreglos de A-11) con las tres salidas que eligió el desarrollador. **A** — `record` bloquea la fila (`FOR UPDATE`) y, si ya no está `accepted`, **no la toca** y devuelve `.alreadyClosed`; la pasada que llegó tarde escribe **la suya**, con su propio `startedAt` (`IngestionRun.reidentified`). **D** — el ámbito que escribe de las **tres** pasadas empieza con `CompetitionRepository.lock`, así que dos pasadas de la misma competición escriben una detrás de otra y el `23505` de la coincidencia desaparece. **B** — el `202` no encola lo que **este proceso** ya tiene en marcha (`IngestionsInFlight`). Se hizo en memoria y no mirando la fila abierta porque la forma propuesta al principio —*"encolar solo lo recién aceptado"*— dejaba una huérfana (H-57) **sin poder reintentarse** desde el botón. Tests: 2 de nivel 3 del repositorio (el cierre ya cerrado; dos cierres **a la vez**), 2 de nivel 3 con compuerta y Postgres (la tardía que falla; dos primeras sincronizaciones simultáneas), 3 de nivel 2 del calendario, 1 de clasificación, 1 de goleadores y 2 de nivel 4 (el doble clic; la huérfana tras un reinicio). **11/11 mutaciones**, entre ellas quitar cada `FOR UPDATE` y cada `lock`. **557 tests.** Regla 9 contra `club_atleti`: dos `POST` seguidos → **un** trabajo (2 filas de clasificación y 2 de goleadores, antes 4 y 4); cron encima del `202` → cuatro filas de calendario `succeeded`, una por pasada; 0 abiertas, 426 goleadores y 1.844 goles intactos |
| **H-56** | A-11 | **S2** (por la regla del propio H-24: *"S2 si llega a F7 sin arreglar"*) · dueño: **ronda de arreglos de A-11**, confirmado por el desarrollador | **H-24 está copiado dos veces: la clasificación y los goleadores tienen la forma de antes del arreglo.** `IngestStandings.swift:109` e `IngestScorers.swift:125` hacen el `record` del éxito **dentro** del `do`. Un fallo **solo al apuntar**, con el ámbito 2 ya comprometido, cae en el `catch`, que escribe una fila `failed` con el motivo **del apunte**. Y el `record` del `catch` (`:125` y `:136`) **no está protegido**, al revés que el del calendario (`IngestCalendar.swift:106`), así que si también falla **tapa el error original**, que es lo contrario de lo que `D-85` pide. F7 y F8 se escribieron **después** de `4d66aa0` y copiaron el método de antes: es literalmente lo que la nota *«Lo que A-3 entrega»* de 001 avisaba (*"lo que se decida en H-24 hay que decidirlo antes, no después de copiarlo dos veces"*). En goleadores tiene un agravante: la única fila que cuenta una **retirada** (`D-94`) puede quedar diciendo `failed, retired=0` de una pasada que sí retiró | **Sonda de nivel 2, no versionada**, con un `TenantUnitOfWork` que revienta **solo** en el 3.er ámbito: **goleadores** → 2 filas escritas, 1 fila de registro `failed` con motivo `FakeOutage()`, y el llamante recibe `FakeOutage`, no `runNotRecorded`; **clasificación** → exactamente lo mismo. Y revienta en el 2.º ámbito de una pasada que ya iba a fallar por `D-84` → el llamante recibe `FakeOutage` y **el error de `D-84` se pierde** | **Arreglado** (2026-10-01, ronda de arreglos de A-11): la forma de `4d66aa0` en las dos pasadas. El `record` del éxito sale **fuera** del `do` y, si falla, lanza `runNotRecorded` en vez de escribir un `failed` falso; el del `catch` va en `do { … } catch {}`, así que **manda el error original**. Tests: dos por pasada, de nivel 2, convertidos de la sonda (`FailOnNthScope` en el 3.er ámbito → `runNotRecorded`, los datos escritos y **ninguna** fila de registro; en el 2.º, con una pasada que ya iba a fallar → llega **su** error, `DomainError` o `FederationError`). **4/4 mutaciones**. **561 tests**. Regla 9 contra `club_atleti`: una pasada normal de las dos competiciones → 2+2+2 filas `succeeded`, 0 abiertas, 426 goleadores y 1.844 goles |
| **H-57** | A-11 | **S3** *documental* | **La propiedad autocurativa de F10-bis no es incondicional, y tres sitios la daban por tal.** Lo que cierra una fila `accepted` huérfana es la siguiente pasada **de esa competición**, no *"la siguiente del cron"*. Y hay dos bordes: **(a)** el antirrebote la aplaza hasta el primer disparo que llegue ≥ 6 h después del último éxito; **(b)** una competición que no es de la temporada vigente **no la recorre el cron nunca**, así que su fila se queda abierta hasta que alguien la pida por `-c`. Y **(b) es el estado de hoy de la base de trabajo**: su única temporada, 2025/26, terminó el 2026-06-30 | Contra `club_atleti`: `POST {"seasonId"}` → `202` y `kill -9` del servidor al instante → **2 filas `accepted`**. Después, `ingest` sin argumentos (como lo lanzaría `launchd`) → *"0 competición(es) sincronizada(s)"*, `exit 0`, **las 2 siguen abiertas**. `ingest -t atleti -c <las dos>` con el antirrebote → *"0"*, `exit 0`, **siguen abiertas**. Solo `--force` las cierra, **con el mismo `id`** y el `started_at` intacto | **Corregido** en el acto: `AGENTS.md` (viñeta *«Y la abre el 202…»*), Plan de desarrollo §4.1 F10-bis (enmienda fechada) y el comentario de `DetachedBackgroundWork` |
| **H-58** | A-11 | **S2** · dueño: **rebanada 1** | **`D-89` no sabe leer la fila que transita, ni las tres clases de pasada.** Es la decisión que F7 y F8 dejaron *"sin bloquear nada hasta que el backoffice lea esos campos"*, y la rebanada 1 es exactamente eso. Lo que queda por decidir, medido: **(1)** `IngestionHealth` no tiene caso para `accepted`: evalúa `failing · never · stale · ok` y una fila `accepted` no es `failed`, así que **una aceptada huérfana se lee `ok`** si el último éxito tiene menos de una semana. Es el caso de H-27 que `D-96` existía para hacer visible; `D-96` ya lo decía (*"[D-89] tiene que decidir a partir de cuándo una aceptada es sospechosa"*), y no hay nada que lo decida. **(2)** Un disparo deja 1 fila de calendario, k de clasificación y 1 de goleadores, y *"la última pasada"* no dice de qué clase. **(3)** El texto de `D-89` deriva con `DISTINCT ON … ORDER BY finished_at DESC`, y el registro ordena por `started_at` desde `C-D.6`. Con `DESC` Postgres pone los `NULL` primero, así que los dos ejes dan respuestas distintas **justo** para la fila `accepted`. **(4)** La fila adoptada conserva el `startedAt` de **cuando se pidió**, así que por ese eje queda **por debajo** de las de clasificación y goleadores de su propio disparo. **(5)** El umbral de la aceptada sospechosa: medido, **la adopción cierra entre 1 y 5 s** después de pedirse con la RFFM sana (una pasada completa de dos competiciones, ~6 s) | `GET /v1/ingestion-runs?competitionId=db679b16…&limit=8` tras los disparos de este bloque: el orden sale **goleadores · clasificación · calendario** por disparo, y el calendario adoptado del `202` lleva `startedAt 17:49:03` y `finishedAt 17:49:53`. Y `sed -n '/IngestionHealth:/,/enum:/p' Sources/APIContract/openapi.yaml`: cuatro valores, ninguno para *"pedida y sin cerrar"* | **Abierto**, con dueño |
| **H-59** | A-11 | **S2** · dueño: **deber de despliegue `launchd`** — **la decisión es del desarrollador** (pregunta 6 del bloque) | **Con `launchd`, las salidas que existen hoy no las lee nadie, y hay un éxito que no se distingue de no haber hecho nada.** Salidas de una pasada desatendida: **el código de salida** (lo ve `launchd` y no avisa), **la consola** (va a donde diga `StandardOutPath`, si se configura), **`ingestion_runs`** (solo mientras la base responda, `D-85`; y la lectura que lo haría visible, `ingestionHealth`, no existe hasta la rebanada 1: H-58) y **el log del servidor**, que es de la ruta del `202` y no de `launchd`. **Un plan vacío es un éxito**: *"0 competición(es) sincronizada(s), 0 con fallo · 1 club(es) sincronizados"* y `exit 0`. Y es **el estado de la base de trabajo hoy** (H-57): montado ahora, `launchd` recorrería cada semana **cero** competiciones, en verde, sin acumular un solo dato. **La hora**: A-10 midió la RFFM saturada el primer día de competición (`504` tras 60 s, un domingo), y este bloque vio un `null` pasajero **un miércoles a las 17:44 UTC** (H-61), así que la fuente también falla fuera de los días de partido | `.build/debug/Run ingest; echo $?` → *"0 competición(es)…"*, **`0`** · `select label from club_atleti.seasons` → solo `2025/26`, y `SeasonLabel.endDate` = 30 de junio (`SeasonLabel.swift:94`) | **Abierto**: se decide al montar `launchd` |
| **H-60** | A-11 | **S3** · dueño: **ronda de arreglos de A-11** | **H-25 se sostiene con la fila adoptada, y no hay test que lo afirme.** Con un `23505` real en el ámbito 2 y una fila `accepted` delante, el ámbito 3 (ahora la rama `update` del *upsert*) **escribe `failed` con el `id` y el `startedAt` adoptados y el motivo verdadero**: H-25 hereda entero. Pero el test de H-26 (`CalendarIngestionEndToEndTests.swift:384`) siembra la segunda competición **sin** fila aceptada, así que recorre **solo la rama `create`**, y el de la adopción fallida (`IngestCalendarTests.swift:1142`) es de nivel 2, con el repositorio doble. **Ningún test junta las dos cosas** | Sonda de nivel 3: `aRealConstraintViolationIsRecordedWithItsRealReason` con una `accepted` sembrada antes → `filas=1`, `outcome=failed`, **mismo id**, **`startedAt` conservado**, motivo con `23505` y `federation_match_id`, `partidos=0`, `last_synced_at=nil`. **Mutante** en `record`: `if run.outcome == .failed { return }` en la rama `update` → **546/546 en verde** con `REQUIRE_DB=1`, mientras la sonda enseña la fila **quedándose `accepted`**. Restaurado | **Arreglado** (2026-10-01, ronda de arreglos de A-11). Solo test, sin tocar código, como H-54: `CalendarIngestionEndToEndTests.aRealConstraintViolationClosesTheAdoptedRow`, el de H-26 con una fila `accepted` sembrada antes. Afirma **una** fila, la adoptada —mismo `id` y `startedAt`—, cerrada a `failed` con `23505` y `federation_match_id` en el motivo, y `D-83` en pie. **2/2 mutaciones**: el mutante de A-11 (`record` que no cierra la adoptada cuando falla), que sobrevivía también a los 561 de después de H-55, y el `catch` de `IngestCalendar` escribiendo con `id` nuevo. **562 tests** |
| **H-61** | A-11 → **A-9** | **S4** *observación de tercero* | **La RFFM sirve `null` pasajero en `/api/scorers` para un grupo que existe, y el adaptador lo llama *"no existe"*.** Ver la fila 6 de A-9 | `select … from club_atleti.ingestion_runs where kind='scorers' and started_at between '2026-09-30 17:44' and '17:45'` → dos `failed` con `coordinateNotFound(detail: "la respuesta llegó a null: ese par idGroup+idCompetition no existe")`; a las 17:46, las mismas **`succeeded` con 218** · **Y en `/api/standings` también** (A-15·H-86, 2026-10-03, ~23:20): `FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests` cinco veces seguidas → **2** con `null` en clasificación **y** goleadores a la vez (*"ese idGroup no existe"* / *"ese par idGroup+idCompetition no existe"*), **3** en verde con los mismos datos. El calendario del mismo grupo, en verde las cinco. Ocurre fuera de días de partido, y las dos rutas fallan juntas | Traspasado a **A-9** → ver **H-91** (lo que el adaptador dice) y **H-92** (el reintento) |
| **H-62** | A-11 → **A-12** | *sospecha* — **S3** si se confirma | **El enganche abre fila `accepted` sin mirar si ya hay una, y la pasada cierra la más antigua.** Ver la fila 8 de A-12 | Lectura: `LinkTeamToFederation.swift:281-287` frente a `IngestClubCalendars.swift:242` y `FluentIngestionRepositories.swift:363` (`.sort(\.$startedAt, .ascending)`). **Sin reproducir** | Traspasado a **A-12**. **Confirmado por A-12 (2026-10-03), y sin el proceso muerto que la sospecha suponía: basta el camino canónico de `D-67`** —el A y el B del mismo club enganchados al mismo grupo—. Medido en un *tenant* de sonda de la base de trabajo, con la RFFM real: dos `POST …/federation-link` a la vez → **dos** filas `accepted` (`966a575d…`, `26ddd9c0…`) y **dos** trabajos. Los dos adoptan **la más antigua** en su ámbito 1; el primero la cierra, el segundo recibe `.alreadyClosed` y escribe **la suya** (`61ba4686…`, H-55 A). **El `jobId` del 202 del A, `26ddd9c0…`, se queda `accepted`** hasta la siguiente pasada de esa competición, que por H-57 puede no llegar. Lo mismo con el doble clic sobre un equipo ya enganchado (sonda de nivel 3, escenario *e*: tres filas, dos abiertas tras el 202). **S3**, dueño: **ronda de arreglos de A-12**. **Arreglado** (2026-10-03, ronda de arreglos de A-12) con la salida que eligió el desarrollador: **si la competición ya tiene una fila `accepted` abierta, el enganche la devuelve como `jobId`** y no abre otra. Es lo que `IngestClubCalendars.accept` hace en la otra puerta del 202, así que las dos aceptan igual. Es local a `LinkTeamToFederation`. La alternativa descartada, pasar a la pasada *qué* fila cerrar, tocaba cuatro sitios y es lo que F10-bis ya había rechazado como parámetro. **Lo que se asume**: si la abierta es una huérfana antigua, el `jobId` hereda su `startedAt` (H-58, punto 4). **Tests**: de nivel 2, `FederationLinkTests.anOpenAcceptedRunIsTheJob` (con una abierta sembrada, el `jobId` es ésa y no se escribe ninguna fila). De nivel 4, `FederationLinkEndpointTests.twoLinksToTheSameGroupBothClose`: el caso canónico, con el trabajo de fondo **retenido** hasta tener los dos 202; los dos `jobId` cierran `succeeded`. Los dos salieron **rojos de aserción** antes del arreglo. **3/3 mutaciones**: sin reutilizar (el defecto), buscar la abierta con otro `kind` y reutilizarla pero escribir otra igual. **571 tests**. Regla 9 contra la RFFM real, en un *tenant* de sonda (`club_a12b`, retirado después): el A y el B a la vez → **el mismo `jobId`** en los dos 202, cerrado `succeeded` y **0 `accepted`**. Dos pasadas de clasificación salieron `failed` con el `null` pasajero de la RFFM en la jornada 11, que es H-61 y no esto |
| **H-63** | A-14 | **S2** · dueño: **rebanada 1** | **Hay tres formas de escribir un *handler*, y la rebanada 1 copiará una al azar.** **(a)** `getClub` y las dos de F10 **lanzan** y dejan traducir al middleware; solo atrapan lo que el propio *handler* decodifica (`InvalidUUID`, `seasonLabel`). **(b)** `updateClub` atrapa `DomainError` y **reconstruye** el 422 que el middleware ya produce. **(c)** Los dos de ingesta atrapan casos de `ApplicationError` **uno a uno** y reconstruyen 404, 404 y 501 idénticos a los del middleware, más el `catch` del actor (H-64). Es lo que la regla de H-40 dice que no se haga —*"enumerar el resto a mano duplica el `switch` del middleware"*—, y `AGENTS.md` dice que la traducción tiene **un** sitio. **Cifras**: 18 `Self.problem(` en *handlers*. 10 son decodificación propia del *handler* (`BAD_REQUEST`, `EMPTY_PATCH`, `INVALID_UUID` ×4, `EMPTY_SELECTION`, `INVALID_LIMIT`, `INGESTION_FAILED` ×2). **8 duplican una traducción del middleware**: `INVALID_VALUE` ×2, `COMPETITION_NOT_FOUND` ×2, `SEASON_NOT_FOUND`, `FEDERATION_ADAPTER_MISSING` y `TENANT_NOT_RESOLVED` ×2. **Y una ya divergió**: `INVALID_VALUE` es 422 en el club y 400 en el enganche (este último a propósito, `C-0.5`), con un `detail` que en el enganche es el volcado del enumerado. Además, el bloque de `INVALID_UUID` está copiado **cuatro veces en tres ficheros** | `grep -rn -A1 "Self.problem(status:" Sources/HTTPAdapter/*Handler.swift`. **M5**: quitar los tres `catch` de `triggerIngestion` → **34/34 en verde** (`IngestionEndpointTests` + `FederationLinkEndpointTests`): el middleware da la misma respuesta. `curl` contra `atleti`: `PATCH /v1/club {"name":"   "}` → 422, `"detail":"name: no puede estar vacío"`; `POST …/federation-link` con `"seasonLabel":"zz"` → 400, `"detail":"seasonLabel: invalidValue(field: \"label\", reason: …)"` | **Arreglado** (2026-10-02, ronda de arreglos de A-14). Queda **una sola forma**, la **(a)**: fuera el `catch` de `updateClub` y los cuatro de ingesta (los dos de H-64 ya habían salido), y el bloque de `INVALID_UUID` pasa a `APIHandler.invalidUUID(_:)`. De 18 `Problem` construidos en *handlers* quedan **8**, y ninguno duplica al middleware. El 400 de `seasonLabel` se queda en el *handler* porque la ruta no declara 422 (`C-0.5`), y su `detail` pasa a `seasonLabel: <motivo>`. **Tests**: antes de quitar nada se fijaron por **código** los cuatro casos que pasaban a tener un solo sitio. Se fortalecieron dos tests de *status* (`COMPETITION_NOT_FOUND` del `GET` y `SEASON_NOT_FOUND`) y se escribieron dos nuevos: la competición inexistente pedida sola, y el **501 de `/ingestion-runs`** para un club FCF, que no tenía test por HTTP (H-28; ver A-12, fila 7). Los cuatro pasaron en verde con el código de antes, como corresponde a un test de caracterización. Uno nuevo sí salió **rojo de aserción**: el `detail` del enganche. **5/5 mutaciones** sobre el único sitio que queda, el middleware: el código de `unknownSeason`, el 501→500, el `detail` de `competitionNotFound`, el 422→400 de `invalidValue` y el `detail` del enganche. Con los duplicados delante, las tres primeras las habría tapado el *handler* en `triggerIngestion`. **566 tests**. Regla 9 contra `atleti`: 422, 400 legible, 404 ×2 y `INVALID_UUID`, los mismos cuerpos que antes salvo el `detail` corregido |
| **H-64** | A-14 | **S2** · dueño: **rebanada 1** | **Los dos *handlers* de ingesta convierten cualquier error del actor en `400 TENANT_NOT_RESOLVED`, y no lo registran.** `IngestionHandler.swift:43` y `:94` hacen `do { actor = try actors.currentActor() } catch { return … 400 … }`. Hoy es **código muerto**: una petición sin club la corta antes `TenantResolutionMiddleware`, que da el mismo 400 por su cuenta. Con la auth, el resolutor lanzará los errores de credencial y de discrepancia, y **estas dos puertas los servirán como *"no identifica ningún club"***, sin línea en el log; las otras cuatro, con su código. Es exactamente la rama *"además, cada *handler*"* de A-6, en dos de seis | **Sonda de nivel 4, no versionada**: un `ActorResolver` que lanza `tenantMismatch` contra las seis operaciones. `getClub`, `updateClub`, `previewFederationLink` y `linkTeamToFederation` → **403 `TENANT_MISMATCH`**, con su línea en el log. `listIngestionRuns` y `triggerIngestion` → **400 `TENANT_NOT_RESOLVED`**, sin ninguna línea. **M4**: quitar los dos `catch` → **27/27 en verde** (`IngestionEndpointTests`, `ErrorBoundaryTests`, `ActorSeamTests`, `ClubEndpointTests`) | **Arreglado** (2026-10-01, ronda de arreglos de A-14): fuera los dos `catch`, y el error lo traduce el middleware igual que en las otras cuatro puertas. Test: `ActorSeamTests.theResolverErrorIsTheSameThroughEveryDoor`, parametrizado sobre **las seis** operaciones del `filter` con un resolutor que lanza, y exige 403 `TENANT_MISMATCH` en todas. Salió rojo de aserción **solo** en las dos de ingesta. **2/2 mutaciones**: vuelve el `catch` de cualquiera de las dos y cae su fila. **563 tests**. Regla 9: sin club, `GET /v1/ingestion-runs` sigue dando el mismo 400, ahora desde el middleware |
| **H-65** | A-14 | **S2** · dueño: **rebanada 1** — **la decisión es del desarrollador** | **`ActorResolver` promete lo que su firma no deja hacer.** La firma es `func currentActor() throws -> ActorContext`: síncrona y sin argumentos. Su documentación (`ActorResolver.swift:26-29`) dice que, cuando llegue §7, *"es el adaptador de este puerto quien carga además el `StaffMember` y sus asignaciones vigentes — y la firma de los casos de uso no cambia"*. Cargar eso es E/S contra el *schema* del club, y una función síncrona no puede hacer `await`. Cumplir lo escrito obliga a cambiar el puerto: hoy son **6 llamadas en 3 ficheros de *handler*** más el doble de test, y cada *handler* nuevo añade una. **La otra mitad, que no se ve en la firma**: el *claim* llega al adaptador por el ambiente, no por un parámetro. `swift-openapi-vapor` pide que el middleware que fija un `@TaskLocal` vaya **el último**, y ese sitio ya lo ocupa `TenantResolutionMiddleware`. Así que el middleware de auth, que va **por fuera** (H-44), no puede publicar el *claim* así: lo deja en la petición y lo levanta el de tenancy. Ahí es también donde va la puerta (H-42) | Lectura, que aquí basta porque es la forma de un puerto: `ActorResolver.swift:26-33`; `.build/checkouts/swift-openapi-vapor/Sources/OpenAPIVapor/Documentation.docc/Tutorials/RequestInjection.tutorial:38` (*"Prefer to use this middleware as the last middleware … to avoid possible known problems with `@TaskLocal`"*); `Configure.swift:92-95`. `grep -rn "currentActor()" Sources/` → 6 llamadas | **Decidido** (2026-10-02, por el desarrollador): la salida **(2)**, escrita como **`D-98`**. El actor lleva **lo que dice el token**, y la plantilla y sus asignaciones las carga **el caso de uso dentro de su ámbito** (§7.4), con la transacción y el *schema* que ya tiene abiertos. La **(1)** se descartó porque obligaba al adaptador a abrir un acceso propio al *schema* del club antes del ámbito. **La firma no cambia y ningún *handler* se toca.** Se reescribe lo que prometía lo contrario: la documentación de `ActorResolver` y `ActorContext`, una línea del LLD §7.4 y una enmienda fechada en `D-63`. La fila de la auditoría 001 que decía lo mismo (A-6, tabla de costuras) es un registro fechado y no se toca. Solo documentación: **567 tests** |
| **H-66** | A-14 → **A-12** | **S2** · dueño: **rebanada 2** las anclas; **la auth**, la decisión | **H-41 se heredó sin decidir, y ha crecido.** 001 lo dejó *"Anclado; la decisión va a F10"*, y el Plan F10 **no lo menciona ni una vez**. Hoy, **4 de las 6** operaciones del `filter` piden *"rol elevado (§7.3)"* en el *spec* y declaran 403: `updateClub`, `triggerIngestion`, `previewFederationLink` y `linkTeamToFederation`. Solo **2** tienen ancla (`UpdateClub.swift:21`, `IngestClubCalendars.swift:42`). Los dos casos de uso de F10 no tienen `TODO(§7)`. Y el enganche hace exactamente lo que H-41 anticipaba *"un nivel más allá"*: **encola una ingesta con el actor de la persona** (`FederationLinkHandler.swift:154-157`), que escribe `Team` y `Match`, y §7.3 asigna eso al actor de sistema. `isSystem` sigue escribiéndose en tres comandos y **no lo lee nadie**. La rebanada 1 no lo necesita, porque las lecturas no llevan ámbito (§7.3); la 2 sí, porque trae escrituras con rol elevado | `grep -c "H-41" "Plan F10-001.md"` → **0** · `grep -rn "TODO(§7)" Sources/` → 2 · el rol elevado por operación, leído en el *spec* · `grep -rn "isSystem" Sources/` → 3 escrituras, 0 lecturas | **Anclado** (2026-10-02, ronda de arreglos de A-14), y **la decisión sigue con la auth**. `PreviewFederationLink` y `LinkTeamToFederation` tienen ya su `TODO(§7)`: **4 anclas para 4 operaciones**. Cada ancla dice lo suyo. La del `/preview`: la comprobación va **antes** de leer el equipo, porque decide si un actor sin permiso recibe 404 o 403 y porque, si no, se le gasta una petición a la federación. La del enganche: es **el caso de H-41 y no el de `UpdateClub`**, y se decide a la vez que el de `IngestClubCalendars`. Solo comentarios: no hay test, igual que el ancla que A-6 puso a H-41. **567 tests**. Sigue anclado también en A-12 (fila 9) |
| **H-67** | A-14 | **S2** · dueño: **rebanada 1** — **la decisión es del desarrollador** | **El middleware traduce por tipo de error, no por ruta, y nada compara lo que emite con lo que la ruta declara.** La regla del proyecto —*"un código que el contrato no declara no lo sabe leer un cliente generado"*— la aplican los *handlers*, pero no el middleware. Medido sobre la lectura que la rebanada 1 va a copiar: `getClub` declara **200 y 401** (el `Output` generado: `ok`, `unauthorized`, `undocumented`), y emite **400** `TENANT_NOT_RESOLVED`, **404** `UNKNOWN_TENANT` y **403** `TENANT_MISMATCH`. Este último lo afirma precisamente `ActorSeamTests` sobre `GET /v1/club`. Y en todo el *spec*, **0 de 83** operaciones declaran 500 o 503, aunque el middleware puede emitir `TENANT_NOT_PROVISIONED`, `INTERNAL` y `DATABASE_UNAVAILABLE` en cualquiera. Para un cliente generado son `.undocumented(statusCode:)` | `curl http://localhost:8080/v1/club` → 400; `curl http://noexiste.localhost:8080/v1/club` → 404 (H-44); la sonda de H-64 → 403 en `getClub`. `grep -c "^        '500':\|^        '503':" Sources/APIContract/openapi.yaml` → **0** | **Decidido y hecho** (2026-10-02, por el desarrollador), escrito como **`D-99`**. Las **83** operaciones del *spec* declaran `default: { $ref: '#/components/responses/DefaultProblem' }`, y la respuesta común nombra los códigos que cubre y dice que se ramifica por `code`. Lo propio de cada ruta sigue declarado en ella. Las 6 del `filter` ganan su caso `` .`default` `` en el código generado, y ningún *handler* cambia. **Tests**: `SpecConventionTests` lee el YAML y exige el `default` en cada bloque de respuestas, porque el compilador solo ve las 6 del `filter`. Y `ClubEndpointTests` afirma ya **por código** `TENANT_NOT_RESOLVED` y `UNKNOWN_TENANT`, los dos que emite cualquier ruta. **3/3 mutaciones**: quitar un `default`, y cambiar el código de cada uno de los dos. El test del *spec* se escribió después de editar el YAML, así que su rojo se demostró con la mutación y no antes. **`npx @redocly/cli lint`: válido, sin avisos.** Ojo al pasarlo desde Xcode: Node está instalado con `nvm`, y su `PATH` solo lo carga el shell interactivo. LLD §5.4 y `AGENTS.md`, al día. Códigos afirmados por código: **22 de 31**. **568 tests** |
| **H-68** | A-14 | **S3** | **Una ruta que no existe responde con el JSON de Vapor, no con `problem+json`.** `ProblemMiddleware` cuelga del grupo (`Configure.swift:105-124`), y el middleware de un grupo solo corre cuando la ruta casa. Así que lo que **no** casa —una ruta fuera del `filter`, o una errata— lo sirve Vapor con el cuerpo que el propio `ProblemMiddleware` dice existir para evitar (*"Sin esto, Vapor sirve su propio `{"error":true,"reason":"…"}"`*). Y la rama `AbortError` que emite `NOT_FOUND` **no la alcanza nadie**: no hay un solo `Abort(` en `Sources/`. Durante la rebanada 1, el backoffice va a pedir rutas que todavía no están | `curl -i http://atleti.localhost:8080/v1/teams` (fuera del `filter`) y `…/v1/nada` → **404** `application/json`, `{"reason":"Not Found","error":true}` · `grep -rn "Abort(" Sources/` → 0 | **Arreglado** (2026-10-02, ronda de arreglos de A-14): una instancia más de `ProblemMiddleware` en la cadena **global**, añadida al final, o sea **por dentro** del `ErrorMiddleware` de Vapor, que se queda como red de último recurso. La del grupo no se toca, para que `RequestTraceMiddleware` siga viendo la respuesta traducida. Es la misma traducción en un sitio más alto, no un segundo `switch`. `NOT_FOUND` pasa a ser **alcanzable**, así que el universo de H-72 son 31 códigos de verdad. Test: `ErrorBoundaryTests.anUnknownRouteIsAProblem`, ruta fuera del `filter` y ruta inexistente, con club y sin él. Salió **rojo de aserción** en los cuatro casos. **2/2 mutaciones**: sin la línea, y con la instancia **por fuera** del `ErrorMiddleware` (`at: .beginning`), que la deja sin efecto. **567 tests**. Regla 9: `/v1/teams`, `/v1/nada` y `/nada` → 404 `application/problem+json` con `NOT_FOUND`; `/v1/club` → 200 |
| **H-69** | A-14 | **S3** *documental* | **La *"puerta"* de H-42 no existe, y tres sitios dicen que `C-E.2` la puso.** H-42 dejó *puerta* = la comparación en `TenantResolutionMiddleware` (corta antes de tocar datos y cubre cualquier *endpoint*) y *cinturón* = la de `FluentTenantUnitOfWork`. Lo que hizo `C-E.2` fue que **el cinturón** se pudiera alcanzar por HTTP; el middleware no compara nada. Aun así, `FluentTenantUnitOfWork.swift:66-68` llama a `ActorSeamTests` *"la puerta"*, y el Plan F10 dice *"`C-E.2` puso la puerta"* (§5) y *"deja la puerta puesta"* (§6). Leído así, quien monte la auth puede dar por escrita una comparación que falta | **M1**: anular la guarda del `UnitOfWork` (`guard true`) → caen **los dos** tests, el de *"cinturón"* (`ErrorBoundaryTests:224`) y el de *"puerta"* (`ActorSeamTests:300`). Hay **una** guarda | **Corregido** en el acto: los tres sitios dicen *cinturón* y que la puerta llega con el *claim* |
| **H-70** | A-14 | **S3** *documental* | **Tres comentarios de la frontera describen el código de antes**, que es la clase de defecto de H-40. **(1)** `IngestionHandler.swift:236-243` dice que *"hoy `IngestionOutcome` solo tiene `succeeded` y `failed`"* y que la fila del `202` *"va a F10"*. `D-96` la hizo, y el caso `accepted` está cuatro *switch* más abajo. **(2)** `ProblemMiddleware.swift:234-238` dice que `competitionNotFound` y `seasonNotFound` *"los levanta la pasada, que no pasa por HTTP"* y que *"el `/preview` la ejecuta en línea"*. Hoy `triggerIngestion` y `listIngestionRuns` los lanzan dentro de la petición, y el `/preview` no ejecuta ninguna ingesta. **(3)** `ClubHandler.swift:116-118` explica la minúscula del `id` junto a una interpolación que ya no la hace: desde F10-ter la hace `TypedIdentifier` | Lectura, contrastada con `IngestionOutcome` (tres casos), con `IngestionHandler.swift:77` y `:181`, y con `IdentifierTextTests` | **Corregido** en el acto |
| **H-71** | A-14 | **S4** — la respuesta a la sospecha 2 | **`TEAM_NOT_FOUND` y `UNKNOWN_TENANT` se distinguen sin credenciales, y es H-44 con más superficie, no un hallazgo nuevo.** El 404 del equipo es literal y dentro del club no filtra nada, porque las lecturas son abiertas a todo el club (`D-64`). Lo que sí filtra hoy, *"existe este club"* y *"existe este equipo"*, es la deuda de F0, y la cierra el orden **forzado** de la cadena: la auth va por fuera y responde 401 antes de consultar `public.tenants`. Ese orden sigue en `Configure.swift:105-124` sin cambios. Y el `/preview` de un equipo inexistente **no llega a llamar a la federación**: el caso de uso lee el equipo primero | `curl -X POST …/v1/teams/<uuid inexistente>/federation-link/preview` en `atleti` → 404 `TEAM_NOT_FOUND`; en `noexiste` → 404 `UNKNOWN_TENANT`; sin club → 400 `TENANT_NOT_RESOLVED` | **Nota** |
| **H-72** | A-14 | **S4** — lo que se sostiene, para no volver a medirlo | **Los recuentos de F10-ter siguen valiendo, contados sobre el árbol.** **Códigos `Problem`: 17 de 31** afirmados por código. Son los *"17 de 30"* más `NOT_FOUND`, que no se alcanza (H-68). Los 14 que faltan son los 13 de la fila de H-46 y `NOT_FOUND`. **De esos, siete los puede emitir una lectura**: `TENANT_NOT_RESOLVED`, `UNKNOWN_TENANT`, `INVALID_UUID`, `INVALID_LIMIT`, `COMPETITION_NOT_FOUND`, `BAD_REQUEST` y `SEASON_NOT_FOUND` (el 500). Los dos de tenancy los emite **cualquier** ruta: con un test por código queda cubierta toda la API. **Campos**: 61 alcanzables desde las respuestas 2xx de las seis operaciones (contando los anidados; el *"52"* de F10-ter no dice con qué comando se contó), y **0 sin afirmar**, salvo `ClubResponse.settings`, que no es un hueco. **Identificadores**: 11 conformes a `TypedIdentifier` y 11 renglones en `IdentifierTextTests`. **Enumerados espejo**: 8 traducciones y 8 tests en `ContractEnumTests`. Y la sospecha 4, contestada: el `init` generado da `= nil` por omisión a todo campo opcional **o anulable**, así que el compilador exige **185 de los 220** campos de las 26 respuestas del *spec*. Los otros 35 son trabajo de un test (**M2**: quitar `roundId:` del mapeo **compila**, y lo caza el test que F10-ter escribió para eso) | Códigos: `grep -rhoE 'code: "[A-Z_]+"' Sources/` contra `grep -rn '"<código>"' Tests/`. Campos: el *spec* pasado a JSON con `ruby -ryaml`, recorriendo los `$ref` desde las respuestas 2xx del `filter`, contra `Tests/APITests/`. Opcionales: `grep -c "? = nil"` en `Types.swift` y `required`/`null` en el *spec* | **Nota**. Los dos cruces no están versionados, igual que el guion de H-52: anclado en A-15. **Versionados** (A-15, punto 7, 2026-10-04): `backend/Tools/Census`, con el método regla a regla en su README y un trinquete (`known-gaps.json`, cada hueco con su motivo comprobado). **Las dos cifras de este renglón se reproducen** con la historia en la mano: **17 de 31** códigos el 2026-10-01, y **22 de 31** hoy, porque la ronda de A-14 escribió los tests de cinco (`TENANT_NOT_RESOLVED`, `UNKNOWN_TENANT`, `COMPETITION_NOT_FOUND`, `SEASON_NOT_FOUND` y `NOT_FOUND`; `git log -S`). **61 campos** el 2026-10-01, y **62** hoy, por `ageCategoryChecked` (H-75). El *"0 sin afirmar salvo `settings`"* era un criterio más laxo: nombrar la palabra en cualquier sitio. Con el del censo (leída como miembro o clave) salen **4**: `ClubResponse.createdAt`/`updatedAt`/`settings` e `IngestionRunResponse.startedAt`, que en `Tests/APITests/` solo aparecen como etiqueta al sembrar. Son obligatorios, así que el decodificador exige que estén; su **valor** no lo afirma nadie. **El 52 de F10-ter sigue sin explicación**, porque no dejó método |
| **H-73** | A-12 | **S1** · **bloquea la rebanada 2** | **El equipo se lee antes de la llamada a la federación y se escribe después sin releerlo: dos enganches del mismo equipo a la vez dejan dos cascadas.** `LinkTeamToFederation` lee el `Team` en el ámbito 1 (`:47-55`), llama a la federación fuera de todo ámbito (`:76`, de 0,4 a 20 s) y en el ámbito 2 decide con **esa copia**: `found.team.linked(…)` (`:272`) solo rechaza si la copia ya tenía código, y `teams.save` es un `UPDATE` sin condición (`FluentIngestionRepositories.swift:64-74`). La guarda de `C-E.10` tampoco lo ve, porque excluye al propio equipo (`:265`). **La ventana es toda la llamada a la federación**, no un solape de transacciones: basta con que la segunda petición lea el equipo antes de que la primera confirme. Es la regla de §5 de este bloque, literal: *"una que deja dos cascadas, S1"*. Y lo que deja **no se arregla después sin la fusión de §9.5**, que sigue sin diseñar | **Contra la RFFM real**, en un *tenant* de sonda (`club_a12`) de la base de trabajo: el Cadete C, sin enganchar, con dos `POST …/federation-link` lanzados a la vez, uno al grupo `24037566` (código `631`) y otro al `24037649` (código `334274`) → **202 y 202**. Después: el equipo con `federation_team_id = 631`, **inscrito en las dos competiciones**, las dos ingeridas (**240 partidos cada una**) y el código `334274` que se le prometió en el segundo 202 **dado de alta como rival** (`A.D. COLMENAR VIEJO`, "cadete D"). **Control** en serie: el mismo equipo, ya enganchado, contra otro código → **409 `ALREADY_LINKED_TO_FEDERATION`**. Y la variante en el mismo grupo (sonda de nivel 3, *f*): dos 202 con códigos distintos y **gana el último en confirmar**, así que uno de los dos clientes tiene un 202 con un código que no es el que quedó escrito | **Arreglado** (2026-10-03, ronda de arreglos de A-12). El ámbito que escribe **empieza bloqueando y releyendo el equipo** (`TeamRepository.lock(_:)`, `SELECT … FOR UPDATE`: `CompetitionRepository.lock` de H-55 D aplicado a `Team`), y todo lo que se decide con él se decide con **esa** copia: la edad de la competición nueva, la identidad, la inscripción, la guarda de `C-E.10` y el enganche. La transición (`linked(…)`) se comprueba **lo primero**, antes de escribir temporada ni competición. El ámbito 1 sigue leyendo el equipo, pero solo para dar el 404 antes de llamar a la federación. Es un método más en un puerto, su adaptador y su doble, con el precedente de H-55 D: arreglo y no mini-fase. **Tests**: de nivel 2, `FederationLinkTests.aLinkWrittenMeanwhileWins`, con un cliente que **mientras está en la red** deja que otro enganche escriba su código. Salió **rojo en seis aserciones** con el código de antes, que es la escritura perdida medida: ningún error y el código del otro pisado. En verde da 409 `alreadyLinkedToFederation`, no escribe nada y pide el bloqueo. De nivel 3, `IngestionPersistenceTests.lockBringsTheDesignatedTeam`, contra el `FOR UPDATE` de verdad. **3/4 mutaciones**: la copia de antes (el defecto), `find` en vez de `lock` y la transición al final de la cascada. **La cuarta sobrevive, y es H-77 otra vez**: quitar el `FOR UPDATE` deja todo en verde, porque con el *pool* de una conexión no hay con quién competir. Queda dicho en el test. **573 tests**. **Regla 9, la sonda 2 repetida contra la RFFM real** en un *tenant* de sonda (`club_a12c`, retirado después): el mismo equipo a los dos grupos a la vez → **202 y 409 `ALREADY_LINKED_TO_FEDERATION`**, **una** competición y **una** inscripción, y el código que queda es el del 202. Contra `club_atleti`, sin escribir: 409 `FEDERATION_TEAM_ID_TAKEN` y 404 `TEAM_NOT_FOUND`, como antes |
| **H-74** | A-12 | **S2** · dueño: **rebanada 2** | **`ownTeamFederationId` no se comprueba contra el calendario que la propia petición acaba de descargar.** El enganche tiene la lista en la mano (`calendar`, `:76`), y `D-67` hizo el campo obligatorio precisamente para que *"el caso no llegue a existir"*: el equipo propio que la primera pasada da de alta como rival. Con un código que no está en el grupo —un dígito mal, o el de otro grupo—, el enganche responde **202**, la pasada no reconoce al equipo propio en ningún partido y **los dieciséis nacen rivales**. Es el desenlace que `D-66` describe como *"`/ownership` más una fusión"*. El selector del backoffice lo hará difícil, pero el contrato es el *endpoint* | En `club_a12`, el Infantil A al grupo `26737755` con `"ownTeamFederationId":"55555"`, que no aparece en `teams[]` → **202**. Tras la pasada: 240 partidos, **0 del equipo propio**, 16 rivales creados, y el equipo con `federation_team_id = 55555` | **Arreglado** (2026-10-03, adelantado a la ronda de arreglos de A-12 por decisión del desarrollador: *"la web no mostrará el código, solo el nombre, pero la API hay que asegurarla"*). Nada más descargar el calendario, y antes de abrir el ámbito que escribe, el enganche exige que `ownTeamFederationId` sea el código de **alguno** de sus equipos, de casa o de fuera. El que la fuente publica sin código no cuenta. Si no, **409 `OWN_TEAM_NOT_IN_CALENDAR`**, con el código y el grupo en el `detail`. Es la **cuarta causa** del 409 de la ruta: no es 422 porque la ruta no lo declara (`C-0.5`), ni 400, que es para lo que no se pudo decodificar. Caso nuevo `DomainError.ownTeamNotInCalendar` y su renglón en `ProblemMiddleware`. El *spec* lo dice en el 409 y en la descripción de `ownTeamFederationId`; **Redocly: válido, sin avisos**. **Tests**: de nivel 2, `FederationLinkTests.aCodeOutsideTheCalendarIsRejected` (un código ajeno se rechaza sin escribir nada; uno que solo juega **fuera** se acepta). De nivel 4, `FederationLinkEndpointTests.aCodeOutsideTheCalendarIsAConflict`, que afirma **por código**, y 0 filas. Los dos salieron **rojos de aserción** antes del arreglo: 202 donde se esperaba 409. **4/4 mutaciones**: sin la guarda (el defecto), solo los de casa, 400 en vez de 409, y otro `code`. Códigos `Problem` afirmados por código: **23 de 32**. **575 tests**. Regla 9: contra `club_atleti`, `55555` → 409 `OWN_TEAM_NOT_IN_CALENDAR`, y después 0 inscripciones, 0 `accepted` y el equipo sin código. En un *tenant* de sonda (`club_a12d`, retirado), `55555` → 409, y `198`, que es del grupo, → 202 con **30 partidos del equipo propio** |
| **H-75** | A-12 | **S2** · dueño: **rebanada 2** — **la decisión es del desarrollador** | **Con la competición nueva, la edad no se comprueba: se copia del equipo, así que `C-C.15` solo protege la edad cuando la competición ya existía.** La cascada crea la `Competition` con `ageCategory: found.team.category` (`:182`), y el `/preview` propone lo mismo (`PreviewFederationLink.swift:116-119`). La identidad cuadra **por construcción**. El código lo dice a propósito (*"la edad cuadra por construcción"*), pero es exactamente el caso de `D-58` —*"el Cadete A a la juvenil"*— para el que existe `requireIdentityMatches`, y en el sentido que más daño hace: **la competición nace con la edad equivocada y la ingesta la hereda en cada rival que crea** (`D-07`). El género, en cambio, **sí** se infiere del nombre (`Gender.proposed`), y la fuente rotula la edad en ese mismo nombre (*"PRIMERA INFANTIL"*, *"PRIMERA CADETE"*). La pregunta para el desarrollador: inferir la edad del nombre igual que el género y que la confirme el humano, o aceptar el hueco y decirlo en el `/preview` | `/preview` del Infantil A contra *"PRIMERA CADETE"* (`26737755`) → `ageCategory: infantil`, **`identityMatches: true`**. Confirmado → **202**, la competición guardada con `age_category = infantil` y **16 rivales "infantil"** de una liga cadete. El mismo efecto en H-73: *"PRIMERA INFANTIL"* guardada como `cadete` | **Arreglado** (2026-10-03, adelantado a la ronda de arreglos de A-12) con la salida que eligió el desarrollador: **inferir del nombre, y avisar cuando no se puede**. **A** — `TeamCategory.proposed(fromFederationName:)`, hermano de `Gender.proposed`, devuelve la edad que dice el nombre, o **`nil`** si no dice ninguna o dice dos. A diferencia del género, la edad no tiene un valor por defecto honesto. `AFICIONADO` cuenta como sénior, y prebenjamín se mira antes que benjamín. La cascada crea la competición nueva con esa edad, y con la del equipo solo si no hay, así que `C-C.15` ya **ve** al Infantil A contra *"PRIMERA CADETE"*. El `/preview` propone lo mismo. **B** — campo nuevo y obligatorio en `FederationLinkPreviewResponse`, **`ageCategoryChecked`**: es `false` cuando la competición no existe y su nombre no dice la edad, de modo que la que viaja es la del equipo. Va junto a `identityMatches` y no en `CompetitionPreviewResponse`, que comparte `/competitions/preview`, donde no hay equipo del que copiar. *Spec* al día (y `ageCategory` con su descripción); **Redocly: válido**. **Tests**: de nivel 1, `AgeCategoryProposalTests`, sobre **las 30 competiciones del volcado de §F.14**, cada una con lo que dice su nombre (24 con edad y 6 sin ella), más prebenjamín y el nombre con dos edades. De nivel 2, el `/preview` (edad del nombre, del equipo con aviso, y la de la fila cuando existe) y la cascada (409 contra *"PRIMERA CADETE"*; del equipo cuando el nombre calla). De nivel 4, `ageCategoryChecked` en los dos valores y el 409 por HTTP. Los de nivel 1 y 2 salieron **rojos de aserción** contra el esqueleto y el código de antes. **6/6 mutaciones**: la cascada con la edad del equipo, el `/preview` sin el nombre, el campo siempre `true`, prebenjamín sin quitar, la primera de dos edades y sin `AFICIONADO`. **582 tests**. Regla 9 contra la RFFM real, en un *tenant* de sonda (`club_a12e`, retirado): el Infantil A contra *"PRIMERA CADETE"* → `/preview` con `ageCategory: cadete`, `identityMatches: false` y `ageCategoryChecked: true`; el enganche → **409 `COMPETITION_IDENTITY_MISMATCH`**, con 0 filas. Contra *"PRIMERA INFANTIL"*, cuadra. En `club_atleti`, el `/preview` del cadete sobre su grupo queda igual que antes |
| **H-76** | A-12 → **ronda de arreglos de A-12** | **S3** | **H-55 D no cubre la primera pasada de goleadores: el bloqueo está, pero los `id` salen de antes del bloqueo.** `IngestScorers.write` bloquea la competición (`:358`), pero los goleadores que escribe llevan los `id` de `plan.existing`, leído en el ámbito 1 **sin** bloqueo (`:330-333`). Dos primeras pasadas a la vez ven *"no hay ninguno"*, las dos inventan `id`, y la segunda, al entrar, inserta otra fila con la misma `(competition_id, federation_player_id)`. El enganche lo hace alcanzable porque **su 202 no pasa por `IngestionsInFlight`** (H-55 B): dos equipos del mismo grupo son dos trabajos | El caso canónico de H-62, contra la RFFM real: de las dos pasadas de goleadores de `67429282…`, una **`failed`** con `23505` en `uq:league_scorers.competition_id+league_scorers.federation_player_id` (`11322891`) y la otra `succeeded`. No se pierde nada: los datos son los de la que ganó, y se cura sola en la pasada siguiente | **Arreglado** (2026-10-03, ronda de arreglos de A-12). `IngestScorers.write` recibe lo publicado y construye las filas **dentro** del ámbito 2, contra lo que hay **con la competición ya bloqueada**: los `id` reutilizados y el total que la guarda de H-53 no deja bajar son los de ese momento. `Plan.existing` desaparece. Es la forma que ya tenía la clasificación (`IngestStandings.write`), así que las tres pasadas leen ahora detrás del `lock`. **Test** de nivel 3, `LeagueScorerPersistenceTests.twoFirstPassesAtOnceDoNotCollide`: dos primeras pasadas retenidas con la `Gate` de H-55 después del ámbito 1. Salió **rojo de aserción** con el `23505` medido, y en verde las dos acaban `succeeded` con dos goleadores. **3/4 mutaciones**: los `id` del plan (el defecto), la guarda contra un total vacío (caen cuatro tests de H-53, de los niveles 2 y 3) y no reutilizar ningún `id`. **La cuarta sobrevive, y es H-77**: leer lo existente **antes** del `lock`, pero en el mismo ámbito, da lo mismo mientras el *pool* de tenant sea de una conexión. Queda dicho en el código. **569 tests**. Regla 9 contra `club_atleti`: `ingest --force` de la competición cadete → `succeeded`, **0 creados, 218 actualizados**, 0 retirados; 426 filas y 1.844 goles intactos |
| **H-77** | A-12 | **S2** · dueño: **deber de despliegue** (el *pool*) | **Las preguntas 1 y 2 no dan 500 hoy, y no por diseño: dos ámbitos de tenant no pueden estar abiertos a la vez.** La raíz de composición construye **un** `FluentTenantUnitOfWork` sobre **un** `app.db(.control)` (`Configure.swift:81`). Fluent lo ata a un solo *event loop* (`eventLoopGroup.any()`), y el *pool* de `fluent-postgres-driver` es de **una** conexión por *loop* por defecto (`maxConnectionsPerEventLoop: Int = 1`). Así que todas las transacciones de tenant del proceso **se ponen en fila**, de todos los clubes y también la pasada de ingesta. Por eso la carrera *"¿está libre?"* + `INSERT` de `Season`, `Competition` o `TeamRegistration` **no llega a producirse**. **Es una garantía que nadie escribió y que se pierde subiendo una cifra**: cuando el despliegue ajuste el *pool* por rendimiento, esas tres carreras vuelven como `23505` en un **500** (`ProblemMiddleware`, rama `default`), que es lo que `C-E.10` corrigió para su causa. Y en la otra cara, el rendimiento queda fuera de esta auditoría (§8), pero **una pasada de ingesta retiene a todos los clubes** mientras escribe | **Sonda de nivel 3, no versionada**: `LinkTeamToFederation` real sobre `FluentTenantUnitOfWork(controlDatabase: app.db(.control))` —la construcción de `Configure.swift:81`— con una compuerta **dentro** de la transacción del ámbito 2 que espera a que los dos ámbitos estén abiertos. En los **seis** escenarios (A y B al mismo grupo con temporada nueva o ya existente, doble clic con todo nuevo, con competición, sobre un equipo ya enganchado, y dos equipos pidiendo el mismo código) → **"compuerta vencida: el otro ámbito no llegó a abrirse"** a los 2 s, y **ningún 23505**. Sin plazo, la sonda se queda colgada indefinidamente. El servidor en marcha tiene 10 conexiones, de los demás caminos (`request.db` en los middlewares) | **Decidido y hecho** (2026-10-03, por el desarrollador), escrito como **`D-100`**: la salida **A**, *escribir la garantía*. La **B** —hacer seguras las tres carreras y subir el *pool*— queda para cuando el rendimiento la pida, y se reabre con un número. **Medido antes de decidir** (servidor local, `club_atleti`): tres `/preview` a la vez tardan lo mismo que uno (0,4–1,1 s, que es la RFFM; la llamada va fuera de todo ámbito). Con una ingesta escribiendo, un `GET /v1/club` tarda 12 ms de mediana y **529 ms en el peor caso** (6 de 358 peticiones por encima de 100 ms). El `ingest` del cron es otro proceso y no hace esperar al servidor. **Lo hecho**: `maxConnectionsPerEventLoop: 1` **escrito** en `configure`, y el acceso de tenant construido **una sola vez** (`app.tenantUnitOfWork`), compartido por el servidor y los tres comandos; antes se construía en **cuatro** sitios, cada uno con su `db(.control)`. Y `TenantUnitOfWorkTests` (nivel 3): un segundo ámbito no se abre mientras el primero vive. Es un test de caracterización: en verde con lo que había. **2/2 mutaciones**, que son las dos formas de romper la garantía sin darse cuenta: subir la cifra a 2, y volver a construir el acceso en cada llamada (cada `db(.control)` cae en otro *loop* con su propia conexión, medido así). LLD §6.4, `AGENTS.md` y los cuatro comentarios que la daban por accidental, al día. Las dos mutaciones supervivientes de H-73 y H-76 **siguen sobreviviendo, y ahora por diseño**: lo dice su comentario. **583 tests** |
| **H-78** | A-12 | **S3** *documental* | **`D-67` dice que el enganche llama a la federación "fuera de la petición", y la llama dentro.** El texto: *"El `preview` sigue siendo la única que llama **sin persistir**; el enganche llama y persiste, pero **fuera de la petición**"*. Desde `C-C.13` y `C-C.14` el caso de uso descarga el calendario **antes** de responder (`LinkTeamToFederation.swift:76`), porque las guardas de `D-84` y `D-91` lo necesitan. Así que **las dos puertas** tienen latencia de terceros en línea, y el 202 puede tardar hasta el *timeout* del transporte (20 s) | 202 medidos contra la RFFM: 0,39 a 0,72 s, que es la llamada. Con un servidor que no contesta, el transporte corta a los **20,0 s** (pregunta 4) | **Corregido** en el acto: enmienda fechada en `D-67` |
| **H-79** | A-12 | **S4** — lo que se sostiene | **El resto de la tabla de A-12 sale bien, y queda medido.** **(2)** Volver a enganchar con el **mismo** código es idempotente (sin segunda inscripción) y **cada vez** abre una fila `accepted` y un trabajo nuevos (el vector de H-62). Con **otro** código: **409 `ALREADY_LINKED_TO_FEDERATION`**. Con el mismo código a **otro** grupo, inscripción aditiva: es la copa de `D-12`, por diseño. **(3)** El orden de las guardas no deja nada escrito: la `Season` 2026/27 creada **antes** de que salte la identidad se va con el `rollback`. **(4)** El *timeout* lo pone **el transporte**, 20 s (`HTTPFederationTransport`), porque el servidor no tiene ninguno: el `idleTimeout` de Vapor es `nil` por defecto y `Configure.swift` no lo fija. Sale `transportFailure`, que es **504** (`C-E.1`). El proxy de Fly.io, si tiene otro, es del despliegue. **(5) y (7)** Club FCF: `/preview`, `/federation-link`, y `/ingestion-runs` con `seasonId` y con `competitionIds` → **501 `FEDERATION_ADAPTER_MISSING`** con `Problem` en los cuatro, y **0 filas** escritas. **(6)** El trabajo se encola **después** de que `execute` devuelva, o sea después del *commit*: las pasadas de todos los enganches de este bloque encontraron su competición. **(9)** El enganche no tiene **otra** escritura sin ancla: escribe `Season`, `Competition`, `TeamRegistration`, `Team` e `IngestionRun` dentro de `LinkTeamToFederation`, que tiene su `TODO(§7)`, y la ingesta que encola entra por `IngestClubCalendars`, que tiene el suyo. **La guarda de identidad es reutilizable**: `Team.requireIdentityMatches(_:)` es Dominio puro sobre `CompetitionScope`, sin dependencias de la cascada. La rebanada 2 la puede llamar desde `PUT /registrations` tal cual, y allí **la competición ya existe**, así que H-75 no le afecta | (2) sondas de nivel 3 *d* y *e*, y el control de H-73 · (3) `club_a12`: 409 `COMPETITION_IDENTITY_MISMATCH`, `seasons` 1 → 1 · (4) sonda contra un *socket* que acepta y no contesta: `transportFailure … deadlineExceeded` a los 20,0 s · (5)(7) `club_a12` con `federation='fcf'`, restaurado · (6) `ingestion_runs` de `club_a12` · **Regla 9 en `club_atleti`**, sin escribir: `/preview` 200 (16 equipos, `identityMatches: true`), enganche → 409 `FEDERATION_TEAM_ID_TAKEN` (`C-E.10` sigue en pie), y después 0 inscripciones, el equipo sin código y 0 `accepted` | **Nota** |
| **H-80** | **A-13** | **S3** — **reabre H-32** | **`migrate-tenants --revert --yes` no revierte nunca: ConsoleKit se come el `--yes` antes de que llegue al comando.** `GlobalSignature` (`console-kit/…/Console+Run.swift:32-39`) consume `--yes`/`-y` y `--no`/`-n` de la entrada **antes** de parsear la firma del comando y los traduce a `console.confirmOverride`, así que el `@Flag(name: "yes", short: "y")` de `MigrateTenantsCommand.Signature` (`TenantCommands.swift:30`) **vale siempre `false`**. La guarda de H-32 funciona —y por eso el fallo es seguro: **no borra nada**—, pero **no tiene salida**: el comando que el README §6 (línea 378) y `AGENTS.md` (línea 478) documentan sale con el aviso y código `1` sea cual sea la posición de la bandera. Hoy no hay ninguna vía de línea de comandos para revertir un club. **Por qué no lo vio nadie**: el test de H-32 prueba la función pura `authorizeRevert(revert:confirmed:)` y **nunca pasa por el parser**; y la comprobación a mano de la ronda de A-5 (H-39) midió que la guarda **salta**, no que `--yes` la **abra**. Es el primer borde de H-48 —*la observación exige la frontera del proceso*— en su forma más pura | `./.build/debug/Run migrate-tenants -t a13rt --revert --yes; echo $?` → aviso *"repítelo con --yes"* y **`1`**; igual con `-y` y con `--yes --revert`. `select count(*) from club_a13rt._fluent_migrations` → **16**, intacto. Con `confirmed: signature.yes \|\| context.console.confirmOverride == true` (parche **temporal**, no commiteado) el mismo comando revierte: **0** | **Arreglado** (ronda de A-13, 2026-10-03) — el comando lee `context.console.confirmOverride`, que es donde ConsoleKit deja el `--yes`, y la bandera propia —que nunca recibía valor— se retira. **El test cruza el parser**: `revertWithYesRevertsThroughTheParser` ejecuta `migrate-tenants -t … --revert [--yes]` por el grupo de comandos de la aplicación, como `Run`, y mira los lotes en la base. **Rojo de aserción** (*"an error was thrown when none was expected"* y `batches == 0`) y **dos mutaciones, dos cazadas**: volver a la bandera propia, y una guarda laxa (`confirmOverride != false`) que dejaría pasar el `--revert` a secas. A mano: sin `--yes` → `1` y 16 migraciones; con `--yes` o `-y` → `0` y 0; volver a migrar → 16 |
| **H-81** | **A-13** | **S3** | **El camino B del test de H-38 aplica las migraciones en el mismo orden que el camino A, así que no mide la convergencia que su nombre promete.** `bothPathsConvergeOnTheSameSchema` aplica `TenantMigrations.all().prefix(2)` y luego el resto: `Club, Season` + `OpponentClub, Team, Competition…` es **exactamente** la lista de registro partida en dos lotes. Su propio comentario dice *"primero las tres de F0/F1 … que en la lista van intercaladas antes de `CreateCompetition`, así que se aplican en un orden distinto del de registro"*, y con `prefix(2)` **`CreateCompetition` no está en el primer lote**: el orden no cambia. El club vivo sí lo cambió —`club_atleti` aplicó `CreateCompetition` en el lote 2 y `CreateOpponentClub`/`CreateTeam` en el 3, **al revés** que la lista—, y eso es lo que el test decía reproducir. **Hoy no muerde** porque el `md5` de los cuatro caminos sale igual (H-30); lo que falta es que el test lo **guarde**. Confirmado con mutación (regla 7) | Mutación **M-A13-1** · `CreateTeam.prepare` crea `idx_a13_mutante` **solo si `to_regclass('competitions')` no es nulo** —un `prepare` que depende del orden, que es la divergencia que el test existe para cazar— → `REQUIRE_DB=1 swift test --filter MigrationIntegrityTests` **10/10 en verde**: sobrevive. Con el camino de `club_atleti` (`Club, Season, Competition` primero) el índice existiría en B y no en A | **Arreglado** (ronda de A-13, 2026-10-03) — el camino B reproduce **los tres primeros lotes de `club_atleti`**: `[Club]`, `[Season, Competition]` y el resto, sacados de `TenantMigrations.all()` por nombre con `#require`, no tecleados. Con **testigo de la inversión** —`Competition` en un lote anterior a `Team`, leído de `_fluent_migrations`— para que no pueda volver a pasar por el motivo equivocado. **Verde desde el principio** (deuda declarada, el código era bueno) y sostenido por **dos mutaciones, dos cazadas**: `M-A13-1`, la que sobrevivía, ahora rompe la convergencia (`inventoryA == inventoryB`); y devolver el segundo lote a `[Club, Season]` dispara el testigo (`competition < team`). El comentario del test dice ya lo que hace |
| **H-82** | **A-13** | **S3** | **De los 10 `CHECK` de enumerado, solo 2 tienen algo que se ponga rojo cuando el enumerado gana un caso.** F8 y F10-bis dejaron un test por columna —`theKindCheckAdmitsEveryCase` y `theOutcomeCheckAdmitsEveryCase`— que fabrica el club vivo y exige la migración gemela. Los otros **ocho** (`FederationCode`, `MatchStatus`, y `TeamCategory`, `Gender` y `Modality` dos veces cada uno, en `teams` y `competitions`) **no tienen guarda**: un caso nuevo en cualquiera de ellos pasa la batería entera, porque en los tests cada tenant nace limpio y deriva el `CHECK` con el enumerado de hoy (la misma razón por la que la mutación de F10-bis sobrevivía), y el club vivo rechaza la fila con un `23514`. **Hoy no hay ninguna gemela que falte** —medido, ver la nota de cierre—, así que no es el S2 que §5 prevé para *"un `CHECK` derivado sin su gemela"*: es la guarda que avisaría de él. `MatchStatus` y `FederationCode` son los dos candidatos reales (un estado nuevo del acta, la reapertura de F9) | `grep -rn "sqlValueList" Sources/Persistence` → **13** usos sobre **10** `CHECK` (los tres de más son las dos gemelas de `kind`/`outcome` y el `revert` de `AddScorersToIngestionRun`); `grep -n "allCases" Tests/PersistenceTests/MigrationIntegrityTests.swift` → **2**, `IngestionKind` e `IngestionOutcome` | **Arreglado** (ronda de A-13, 2026-10-03) — `FrozenEnumCheckTests`, **nivel 1 y sin base**, parametrizado sobre los cinco enumerados que no tenían guarda (los ocho `CHECK`): fija **los valores que los clubes vivos tienen congelados** —medidos contra `club_atleti`— y la migración que los derivó, y exige que `allCases` no se haya movido de ahí. **Valores y no recuento**, porque renombrar un `rawValue` deja el recuento igual y rompe el club vivo igual. La lista tecleada **es** el punto: lo que el *schema* tiene es una lista fija. Verde desde el principio (deuda declarada) y **dos mutaciones, dos cazadas**: `futbol_playa` → `playa` y un `MatchStatus.anulado` nuevo. El mensaje dice qué `CHECK` rehacer y en qué migración se congeló. `kind` y `outcome` siguen con sus tests de club vivo, que miden más |
| **H-83** | **A-13** | **S3** *documental* | **`SQLHelpers.swift` dice que el inventario de H-38 *"ancla los 10 `CHECK`"*; son 19 desde F10-bis.** La cifra es la de A-5, y el test que cita (`revertIsAFaithfulRoundTrip`) ya dice **19** y explica cada salto (15 en F7, 18 en F8, 19 en F10-bis) | `grep -n "los 10" backend/Sources/Persistence/SQLHelpers.swift` → línea 17 · `grep -n "count == 19" backend/Tests/PersistenceTests/MigrationIntegrityTests.swift` | **Corregido** en el acto |
| **H-84** | **A-13** | **S4** — lo que se sostiene | **Con 16 migraciones, el esquema de un club sigue sin depender de cuándo se dio de alta, y queda medido.** **H-30**: cuatro caminos, **un `md5`** —`19aecdd577ef20298328231476a9697b`, **765 líneas** (522 en A-5)—: `club_atleti` (**9 lotes** del 08-26 al 09-23, con `CreateCompetition` antes que `CreateOpponentClub`/`CreateTeam` y los dos `CHECK` rehechos sobre su versión vieja), alta limpia, ida y vuelta y fallo a mitad con reanudación. **H-31**: ningún `prepare` ni `revert` se ha editado tras introducirse, salvo el de `CreateClub` en `8550bcb`, que es el propio H-31. **H-33**: el fallo a mitad sale con código **`1`**, **un** mensaje y el slug; el club queda en **6/16** y la reanudación lo cierra en 2 lotes. **H-35**: los **once** ayudantes de `SQLHelpers` lanzan `schemaHelperNeedsSQL` (eran tres; `grep -c "helper:"` → 11); el único `if let … as? SQLDatabase` que calla, el `DELETE` de `AllowAcceptedIngestionRun.revert`, no es alcanzable sin SQL porque el `dropIndex` de la línea anterior lanza antes. **H-38**: el test deriva de `TenantMigrations.all()`, no de una lista a mano, y el ancla `count == 16` está al día. **Las gemelas**: los 10 `CHECK` de enumerado de `club_atleti` admiten **exactamente** los `allCases` de hoy. **§9.3**: sus dos deberes siguen sin hacer, y `launchd` **no** les cambia el precio (ver la nota de cierre) | `pg_dump --schema-only -n club_<x>` de `atleti`, `a13nuevo`, `a13rt`, `a13fallo`, sin `\restrict` y con el *schema* normalizado → `md5 -q` → un hash. H-31: el cuerpo de cada `struct …: AsyncMigration`, sin comentarios, en su commit de introducción contra `HEAD` → 15 con **0** líneas de diferencia y `CreateClub` con **2**. Gemelas: `sqlValueList` de los siete enumerados (test desechable, no commiteado) contra `pg_get_constraintdef` de `club_atleti` → `diff` vacío, 10/10 | **Nota** |
| **H-85** | **A-15** | **S2** · dueño: **deber de despliegue `launchd`** — **la respuesta al punto 2** | **Si `launchd` ejecuta `.build/debug/Run`, cualquier `swift build` cambia el binario de producción, también las compilaciones de una pasada de mutación.** El binario que `launchd` va a disparar no está decidido. El único que el libro usa contra la base de trabajo es `.build/debug/Run` (A-11, H-59), y es exactamente el que reescriben `swift build`, `swift test` y cada mutación de `Tools/Mutate` (*aplica → compila → prueba*, sobre el mismo `.build`). Un disparo que caiga a mitad de una pasada ejecuta **código roto a propósito contra `club_atleti`**: los tests usan `tfm_test`, pero `ingest` escribe en la base de trabajo, y los catálogos rompen, entre otras, la regla que borra (H-53). Basta con que caiga a mitad de una rama de trabajo para ejecutar código que nadie ha dado por bueno. **Y la pregunta del punto 2 —*¿cambia algo `launchd` para H-07 y H-49?*—, contestada: el *workflow* de CI no cambia de dueño ni de urgencia.** Sigue yendo con Fly.io, porque `launchd` no ejecuta tests y nada de lo que corre en local pide uno. **Lo que cambia es qué tiene que garantizar cada disparo**: no que `main` esté en verde, sino que lo que ejecuta **salió de un commit conocido**. Y una cosa a favor: **el canario programado** que A-7 dejó para el CI cabe en `launchd` desde el primer día, con el mismo `StartCalendarInterval` | `grep -rn "launchd" ../docs/backoffice_initial_draft.md` → no fija binario. H-59: *"`.build/debug/Run ingest; echo $?`"*. `Tools/Mutate/Sources/mutate/main.swift`: `swift build --build-tests` en el paquete que se muta, el mismo `.build` | **Abierto**, con la salida escrita para cuando se monte: `launchd` ejecuta un binario **instalado** (`swift build -c release` desde un commit, copiado fuera de `.build`), nunca `.build/debug/Run` |
| **H-86** | **A-15** | **S3** — a la ronda de arreglos de A-15 | **El canario solo vigila el calendario: los *parsers* de clasificación y goleadores no tienen comprobación contra la RFFM viva.** `RFFMCanaryTests` tiene **un** test y llama a `fetchCalendar`. `fetchStandings` (F7) y `fetchScorers` (F8) se prueban solo con volcados, que contestan *"¿he roto yo el parser?"* y no *"¿han cambiado ellos?"* (README §5.1). Son dos de las tres lecturas que `launchd` hará cada semana, sin nadie mirando (H-59). **H-01, vuelto a medir**: el canario **compila y casa con la RFFM viva** (1,07 s, con red, no omitido), y sus avisos siguen siendo los que el arreglo de H-01 dejó | `FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests` → `exit 0`, *"passed after 1.074 seconds"*. `grep -n "fetch" Tests/FederationTests/RFFMCanaryTests.swift` → solo `fetchCalendar` | **Arreglado** (ronda de arreglos de A-15, 2026-10-03). Dos tests nuevos en `RFFMCanaryTests`, con la coordenada de los volcados (que es **la de `club_atleti`**: cadete, temporada `21`, grupo 24037549) y la jornada 30 por omisión (`FEDERATION_LIVE_ROUND`). Comprueban invariantes que solo rompe la fuente. **Clasificación**: hay filas, posiciones 1…N, G + E + P = J, `codequipo` único, y el código de competición devuelto **es el pedido** (§F.18: no puede ser eco). **Goleadores**: hay filas, llegan goles, los goles no suben al bajar por el ranking, `codigo_jugador` único y el nombre esperado. El `switch` que separa ruido de aviso pasa a un ayudante común (`live`), sin cambiar sus mensajes salvo uno: *"La coordenada no designa nada"* manda **repetirlo antes**, por lo de abajo. **Contra la RFFM viva, los tres en verde.** **Y cada invariante, sostenido por mutación**: `Catalogs/H-86.json` simula en el *parser* nueve formas de *"han cambiado ellos"*, **9/9 cazadas**. Cada una cae por **su** invariante (mirado en los *logs*), y **ninguna** por un `null` pasajero. **Lo que salió al estrenarlo**: la primera pasada dio `null` en clasificación **y** en goleadores con la coordenada viva de `club_atleti`, y las dos siguientes pasaron. Es H-61, que hasta hoy solo se había visto en `/api/scorers`: anotado en su fila para A-9 |
| **H-87** | **A-15** | **S3** — a la ronda de arreglos de A-15 | **La identidad de `D-58`/`D-07` se ejerce por los dos lados en el Dominio y por uno solo en la base: `uq_teams_identity` sin `gender` o sin `modality` pasa la batería entera.** El punto 4, contado y no leído: en las *fixtures*, los valores por omisión de todos los constructores son `masculino`, `futbol11`, `cadete`, `rffm` y `2025/26`. Temporada y letra sí varían (once etiquetas; A, B, C y `nil`), y el género y la modalidad aparecen, pero **ningún test de nivel 3 inserta dos equipos que solo difieran en el género o en la modalidad**. Cada campo de la clave, quitado en cada sitio que la compara (11 mutaciones): el paso 2 de la cadena y `Team.identityMatches` caen **por su test** (*"el mismo equipo en el otro género no es el mismo equipo"*, *"…en otra modalidad…"*). El índice cae **de rebote** para categoría y letra (un 409 de `D-67`, los tests de clasificación) y **no cae** para género y modalidad. Si alguien quitara el género de `uq_teams_identity`, el «Infantil A» femenino de un rival chocaría con el masculino en la ingesta: el ejemplo con el que `D-58` justifica la columna. Hoy el índice está bien; lo que falta es la guarda, la misma forma que H-82 | `Catalogs/A-15-identidad.json` → **11 mutaciones, 9 cazadas, 2 sobreviven** (`ID-uq-gender`, `ID-uq-modality`), batería entera. Valores: `grep -rhoE` por caso sobre `Tests/` y `Sources/TestSupport/` (`masculino` 82/23 ficheros, `femenino` 17/8, `futbol11` 91/23, `futbolSala` 9/7, `futbol7` 3/2) y los `= .masculino`/`= .futbol11` de los constructores | **Arreglado** (ronda de arreglos de A-15, 2026-10-04). `teamsThatDifferInOneKeyColumnFit` en `IngestionPersistenceTests`: nivel 3, parametrizado sobre **un gemelo por cada columna** de la clave que no es el club. Parte del «Infantil A» masculino de fútbol-11 y cambia solo la categoría, solo la letra, solo el género o solo la modalidad; los dos equipos tienen que caber. Van las cuatro y no solo las dos que sobrevivían, porque categoría y letra se cazaban **de rebote**, con tests que no existen para eso. Es la otra mitad de los dos tests de §3.5 que ya había, que prueban que la clave **choca** cuando todo es igual. **Verde desde el principio** (deuda declarada: el índice estaba bien, faltaba la guarda) y sostenido por mutación: las cuatro de `ID-uq-*` en `Catalogs/A-15-identidad.json`, **4/4 cazadas**. Cada una cae por **su** caso del test (*"solo cambia gender"* cae al quitar `gender`, y así las cuatro), batería entera. **588 tests** |
| **H-88** | **A-15** | **S3** *documental* | **`KEEP_TEST_DATA=1` da 42 rojos falsos con la batería entera, y el README no avisa.** Lo que se conserva se conserva también entre los tests de la misma pasada, y las *suites* que reutilizan su club de un test a otro (`TenantTraversal`, `FederationLinkEndpoint`, `IngestionEndpoint`…) chocan con lo que dejó el anterior: `23505 … uq:seasons.label`. El ejemplo del README (`--filter ClubUpdateTests`) funciona porque esa *suite* no repite *slug*. Salió al intentar medir el punto 3 contando en la base | `KEEP_TEST_DATA=1 REQUIRE_DB=1 swift test` → `exit 1`, **42** `✘ Test` con *"fallo montando el entorno de test: … 23505"* | **Corregido** en el acto: README §5, el aviso y para qué sirve |
| **H-89** | **A-15** | **S3** — **del propio instrumento** | **Dos ejecuciones de `mutate` sobre el mismo paquete: la segunda restauraba el fichero que la primera tenía mutado.** Un `--dry-run` lanzado con una pasada en marcha encontró su `.mutate-in-flight.json`, lo tomó por el resto de una ejecución muerta y restauró `BackgroundWork.swift` **a mitad de la mutación `H48-M6`**. La mutación salió *"equivalente"* sin saber contra qué código se había probado. **Es el séptimo fallo del guion, y el primero que el guion versionado podía repetir**: por eso se escribe | Reproducido después del arreglo: pasada `--only H48-M6` en marcha y `--dry-run` en paralelo → *"otra pasada de mutate (pid …) está en curso … no se toca nada"*, `exit 3`, y el fichero **sigue mutado** hasta que la pasada lo restaura | **Corregido** en el acto: **candado por paquete** (`.mutate.lock`, con `O_EXCL` y el pid), que se toma **antes** de mirar el diario, también en `--dry-run`. Un candado de un proceso muerto se recupera (comprobado con un pid inexistente). La regla, pura y con 4 tests (`RunLockTests`). `H48-M6` se repitió sola: **equivalente**, ahora válida |
| **H-90** | **A-15** | **S4** — lo que se sostiene, y la categoría al día | **Puntos 3, 5 y 6: lo que A-15 tenía que volver a medir se sostiene, y la categoría *"fuera del arnés"* tiene dos entradas nuevas que nadie había puesto en ella.** **Punto 3, contaminación entre *suites***: ninguna enumera algo compartido con efectos. La única enumeración de `public.tenants` (`everyTenantIsVisited`) es de **solo lectura** y afirma un subconjunto, y su comentario cuenta que se rehízo así por esa carrera. Las consultas al catálogo de Postgres van todas atadas a un *schema* (`nspname`/`schemaname = \(bind:)`). `ingest` y `migrate-tenants` reciben siempre lista o `-t`. Y ningún *slug* literal se repite entre ficheros. **Punto 6 · H-45**: el par sigue guardado de punta a punta. **Seis de siete** cazadas (la sonda que lanza `databaseUnavailable`, su desaparición, `abortedByInfrastructure`, y las tres ramas de `stopsTraversal`); la séptima, el cable (`if Self.stopsTraversal(result) { break }`), **sobrevive como F6-ter dejó declarado**. **H-48**: el `+6/−1` de `TestEnvironment` es el parámetro `actors:` de F10, con el mismo valor por omisión que `Configure.swift:71`, y los tres tests que lo cambian lo hacen para provocar errores. No mueve los bordes. **Punto 5, la categoría al día**: **(a)** *la frontera del proceso*: los códigos de salida siguen fuera, pero H-80 ya cruza el parser dentro del proceso y `incomplete` es regla pura. **(b)** *el mismo programa*: `M6` vuelve a salir **equivalente**. **Nuevas**: las supervivientes de H-73 (`FOR UPDATE`) y H-76 (leer antes del `lock`) son equivalentes **por configuración**. Lo son mientras valga `D-100` (una conexión por tenant), y dejan de serlo el día que cambie, así que esa decisión es también un borde de la batería. **(c)** *no inyectable*: el cable de F6-ter, re-medido. **Y `launchd` entra por construcción**: el `plist`, `StartCalendarInterval` y el disparo al despertar no los ejerce ningún test, igual que el canario | `Catalogs/A-15.json` → **8 mutaciones, 6 cazadas, 1 sobrevive (`H45-wire`, el borde declarado), 1 equivalente (`H48-M6`)**, batería entera. Punto 3: `grep` de `public.tenants\|pg_namespace\|pg_indexes\|information_schema` y de `tenants(on`/`ingest(`/`migrate-tenants` en `Tests/`. *Slugs*: los literales de cada fichero que provisiona, sin repetidos entre ficheros. **Límite del método**: los *slugs* construidos por variable no salen con `grep`, y contarlos en la base con `KEEP_TEST_DATA` no sirve (H-88). H-48: `git log -p -- Sources/TestSupport/TestEnvironment.swift` | **Nota** |
| **H-91** | **A-9** — **sospecha 6** | **S3** | **El adaptador convierte un `null` en *"no existe"*, y eso es una conclusión que no puede sacar.** Con un cuerpo `null` de cuatro bytes, los dos *parsers* lanzan `coordinateNotFound` con *"ese idGroup no existe"* y *"ese par idGroup+idCompetition no existe"*, y el puerto lo promete igual (`FederationError.coordinateNotFound`: *"La coordenada no designa nada"*). Pero ese `null` tiene **cuatro** causas medidas y una respuesta suelta no las distingue: grupo inexistente, par que no casa, `idCompetition` ausente (§F.18, §F.19) y **`null` pasajero con la coordenada buena** (H-61). Las otras dos piezas ya lo reconocían: el canario (*"desde aquí no se distingue de una coordenada que no existe"*) y `ProblemMiddleware` (502 y no 400, porque *"no se puede afirmar que la coordenada no exista"*). El único que lo afirmaba era el adaptador, y es su texto el que acaba en `ingestion_runs.error`. **No se pierden datos**, porque la pasada falla y no toca la tabla. Lo que falla es el diagnóstico, que **manda a revisar una coordenada que está bien**. **La respuesta a la sospecha 3, de paso**: el puerto **tiene una sola política de errores**. Lo que se pasaba era la **definición** del caso, no faltaba un caso | `RFFMScorersParser.swift:65-68` y `RFFMStandingsParser.swift:55-58` (antes), `FederationError.swift:20`, `FederationClient.swift:111` y `:145`. Contraste: `RFFMCanaryTests.swift:176` y `ProblemMiddleware.swift:413-417`. `grep -rn "no existe" Tests/` → ningún test fija el texto | **Arreglado** (A-9, 2026-10-04), **sin cambiar la forma del puerto**. El `detail` de los dos *parsers* dice ahora las dos lecturas y qué hacer: *"o … no designa nada, o la RFFM devolvió un `null` pasajero (H-61). Repetir antes de revisar la coordenada"*. `coordinateNotFound` pasa a significar *"la fuente no devolvió nada para esa coordenada"*, y su documentación y la de `fetchStandings`/`fetchScorers` dicen que **no promete que la coordenada no exista**. Le vale igual al segundo adaptador. `swift test --filter FederationTests` → 85 en verde. `IngestScorers` + `IngestStandings` → 40 en verde |
| **H-92** | **A-9** — **sospecha 6** | **S3** · dueño: **deber de despliegue `launchd`** (con H-59 y H-85) | **Nadie reintenta un `null` pasajero, y con `launchd` eso es una pasada perdida sin nadie mirando.** Ni el adaptador, ni los casos de uso, ni `ingest` reintentan. Un `null` pasajero (H-61) deja una fila `failed` y la tabla sin refrescar hasta el disparo siguiente. **Reintentar en el adaptador cabe en `D-97`**, porque es conocimiento del universo de la RFFM y el puerto no cambia. **No se hace ahora porque no está medido cuánto dura**: el 2026-09-30, **dos peticiones simultáneas** dieron `null` y a los **2 minutos** contestó bien, así que un reintento inmediato probablemente vuelve a fallar. Uno de minutos ya no es del adaptador: es del calendario de disparos | `grep -rni "retry\|reintent" Sources/` → solo comentarios: reintentos **manuales** o del cron, y respuestas HTTP que invitan o no a reintentar. Ningún código reintenta una lectura de la federación. **Y la documentación lo promete**: `FederationError.swift:10` dice que ante la fuente ajena la ingesta *"degrada y reintenta (§3.7)"*, y hoy no lo hace nadie. Medidas: las de H-61 | **Abierto**. Antes de decidir: medir cuánto dura el `null` (p. ej., el canario en bucle cada 30 s hasta que vuelva al verde). Con ese dato se decide entre reintentar con espera en el adaptador o volver a disparar desde `launchd` |

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

### Nota de cierre de A-11 · ¿la fila que transita cierra siempre, y sigue valiendo lo que A-3 midió?

**No cierra siempre, y lo que A-3 midió vale para el calendario y no para las otras dos pasadas.** No hay S1: nada
de lo encontrado pierde datos. Lo que sí hay son **filas que mienten**, que es el error que la enmienda de `D-85`
llama *"el caro"*, y llegan por dos caminos nuevos:

- **La concurrencia** (H-55). Dos pasadas adoptan la misma fila, y la última en escribir gana aunque sea la que
  falló. La forma de provocarlo es un **doble clic**, no el cron: `accept` deduplica la fila, pero no el trabajo.
- **La copia** (H-56). La clasificación y los goleadores nacieron con la forma de `IngestCalendar` **de antes**
  de H-24.

**La propiedad autocurativa tiene borde, y está medido** (H-57). La fila la cierra la siguiente pasada **de esa
competición**. El antirrebote la aplaza hasta 6 h, y fuera de la temporada vigente el cron **no pasa nunca**. Es
el estado de hoy de `club_atleti`, que no tiene temporada vigente desde el 30 de junio.

**Lo que se sostiene, dicho para no volver a medirlo (S4):**

- **H-25**, con la fila adoptada: sonda de H-60.
- **H-24 en el calendario**: el `record` del éxito sigue fuera del `do` (`IngestCalendar.swift:122`).
- **H-23**: la pregunta a la base sigue detrás de cada fallo (`IngestClubCalendars.swift:165`), y la adopción no
  se interpone. Con la base caída el ámbito 1 no llega a adoptar, y si cae después, la fila adoptada se queda
  `accepted`, que es el mismo caso que H-57.
- **Las dos puertas escriben `kind: .calendar`** (`IngestClubCalendars.swift:248`, `LinkTeamToFederation.swift:284`)
  y la clasificación y los goleadores ni adoptan ni se aceptan, que es correcto (pregunta 3).
- **El *check-then-insert* de `accept`**: dos `POST` en paralelo dejaron **una** fila por competición, así que la
  carrera no se reprodujo y no se apunta.

**Y un borde que no se alcanza hoy:** si el reloj de quien cierra va por detrás del de quien aceptó, el `try
IngestionRun(…)` del `catch` (`IngestCalendar.swift:97`) lanza *"una pasada no puede acabar antes de empezar"*.
Ese error **sustituye** al original y la fila se queda abierta. Hoy los dos procesos corren en el mismo Mac; en
Fly.io, con servidor y cron en máquinas distintas, dejaría de ser teórico. Lo destapó la propia sonda con el reloj
fijo de la suite.

**El mapa fallo-a-garantía de A-3, reescrito para un `record` que actualiza.** «—» significa que no hay test que lo
recorra.

| Clase de fallo | ¿Ámbito 2 se deshace? | ¿Se escribe la constancia? | ¿Con el `id` adoptado? | ¿Motivo correcto? | Test permanente |
|---|---|---|---|---|---|
| **Invariante del Dominio**, fila adoptada | sí | sí | sí | sí | `IngestCalendarTests:1142` (nivel 2) |
| **`23505` real**, fila nueva | sí | sí | n/a | sí | `CalendarIngestionEndToEndTests:384` (H-26) |
| **`23505` real**, fila **adoptada** | sí | sí (sonda) | sí (sonda) | sí (sonda) | **— (H-60)**: el mutante sobrevive 546/546 |
| **La base caída** | n/a | no | la aceptada **queda abierta** | n/a | `IngestClubCalendarsTests:413` (la parada, H-23) |
| **Falla solo el ámbito 3** — calendario | no (correcto) | no: lanza `runNotRecorded` | la aceptada **queda abierta** hasta la pasada siguiente | sí | `IngestCalendarTests:424` (H-24) |
| **Falla solo el ámbito 3** — clasificación y goleadores | no | **`failed` de una pasada buena** | n/a | **no** | **— (H-56)** |
| **Dos pasadas adoptan la misma fila** *(nuevo)* | según cada una | las dos, y **gana la última** | sí, las dos | **el de la última**, aunque la otra escribiera | **— (H-55)** |
| **El proceso muere entre el `202` y la pasada** *(nuevo)* | n/a | nada | abierta hasta la próxima pasada **de esa competición** | n/a | **— (H-57)** |

**`D-89`, convertido en decisión con dueño: la rebanada 1** (H-58). Son cinco preguntas, y ninguna se contesta
sin la pantalla delante:

1. Qué se lee de una `accepted` vieja.
2. De qué clase es *"la última pasada"*.
3. Qué eje de orden usa.
4. Dónde cae la fila adoptada, que conserva su `startedAt`.
5. Con qué umbral una aceptada pasa a ser sospechosa.

El dato para el umbral queda medido: con la fuente sana, la adopción cierra en segundos.

**La pregunta 6 no se mide, se decide, y es del desarrollador** (H-59). Lo que el bloque deja es el inventario de
salidas, la prueba de que **un recorrido vacío sale en verde**, y el aviso de que la base de trabajo, tal como está,
**no acumularía nada**: antes de montar `launchd` hay que dar de alta la temporada 2026/27 y enganchar sus equipos.

**La regla 9, cumplida el 2026-09-30** contra `club_atleti`, con el *schema* respaldado antes (`pg_dump -n
club_atleti`, 543 KB). Se hicieron cuatro disparos (dos dobles clics, cron más `202`, y `kill -9` tras un `202`) y
tres `ingest`. Al terminar: **0 filas abiertas, 426 goleadores y 1.844 goles** —las cifras de A-10—, 480 partidos
y 150 filas de registro (38 nuevas, todas de este bloque). Las sondas corrieron contra `tfm_test` y **no se versionan**.

**Para abrir la puerta de `launchd` (§6-bis):**

- **S1**: cero en A-10 y A-11.
- **`D-89`**: tiene dueño (H-58).
- **Los S2**: todos tienen dueño. **H-55** lo tuvo al día siguiente —la ronda de arreglos de A-11, decidido por
  el desarrollador— y está arreglado (ver su fila).

### Nota de cierre de A-14 · ¿es la frontera HTTP un patrón que se pueda copiar treinta veces?

**Todavía no, pero no por falta de costuras.** No hay S1. Lo que falla es que hay **tres formas** de escribir un
*handler* (H-63), y una de ellas se traga el error del actor (H-64). Las costuras de A-6 siguen donde estaban,
con la misma propiedad que las hacía buenas: `withRepositories(actor:)` **exige** el actor, el tenant se decide en
**un** sitio y el `switch` del middleware no compila sin el código del error nuevo. Lo que ha crecido es todo lo
que **no** vigila el compilador.

**La primera cuenta: añadir un endpoint.** Son **dieciséis sitios**, y el compilador vigila **cuatro**. Es la
lista que la rebanada 1 usa y la rebanada 2 corrige. «C» = el compilador para el *build* si falta; «—» = no lo
para nada.

| # | Sitio | ¿Lo exige? | Qué hay que saber |
|---|---|---|---|
| 1 | El `filter` de `openapi-generator-config.yaml` | — | Sin él, el método del *handler* compila **huérfano** y la ruta da 404 (H-68). Va **primero** (`D-69`). Y la operación del *spec*, con su `default: DefaultProblem` (`D-99`): eso no lo vigila el compilador sino `SpecConventionTests` |
| 2 | El método en `APIHandler` | **C** | Una vez en el `filter` |
| 3 | Devolver un caso del `Output` generado | **C** | Solo los códigos que la ruta declara |
| 4 | El actor: `try actors.currentActor()` | — | `ActorContext` tiene `init` público: un *handler* puede fabricarlo, incluso con `isSystem: true`, y saltarse el resolutor. **No envolverlo en `do/catch`** (H-64) |
| 5 | El caso de uso recibe `actor:` | **C** | Lo fuerza `withRepositories(actor:)` (A-6) |
| 6 | Si el *spec* pide **rol elevado**: el `TODO(§7)` en el caso de uso | — | 4 anclas para 4 operaciones desde la ronda de A-14 (H-66): la que llegue la añade. Las lecturas no llevan ámbito (§7.3) |
| 7 | **La forma del *handler***: se lanza, y solo se atrapa lo que el propio *handler* decodifica | — | La forma **(a)** de H-63. Reconstruir un `Problem` que el middleware ya produce es un segundo sitio decidiendo el mismo código |
| 8 | Mapeo `Entidad → DTO`: campos obligatorios | **C** | El `init` generado no tiene valor por omisión para ellos |
| 9 | Mapeo `Entidad → DTO`: campos **opcionales o anulables** | — | `= nil` por omisión: 35 de los 220 campos de respuesta del *spec* (H-72, M2). Cada uno, con **un test con valor no nulo** |
| 10 | Enumerado espejo nuevo: `toContract()` / `toDomain()` | **C** la línea, — el valor | Y su `@Test` en `ContractEnumTests`, que se escribe a mano |
| 11 | Identificador nuevo | — | Conformar `TypedIdentifier`, interpolarlo (`"\(id)"`) y su renglón en `IdentifierTextTests` |
| 12 | **Caso** nuevo en `DomainError`, `ApplicationError`, `TenancyError` o `FederationError` | **C** | El `switch` exhaustivo de `ProblemMiddleware`. Si el código es **propio de la ruta**, se declara en ella; si puede salir por cualquiera, lo cubre el `default` (H-67, `D-99`) |
| 13 | **Tipo** de error nuevo | — | Cae en el `default` (500) **y** hay que añadirlo a la lista de desenvoltorio de `ServerError`, o la traducción no lo alcanza nunca (M3) |
| 14 | Lo que el generador ignora: `minProperties`, `minItems`, rangos, `default`, `pattern` | — | En el *handler* o en el *Value Object*, según la tabla de §5.5. La plantilla es `limit` en `listIngestionRuns` |
| 15 | Si responde `202`: `runAccepted` e `IngestionsInFlight` | — | Detrás de un `202` el único canal que queda es el log (H-27), y un doble clic son dos trabajos (H-55) |
| 16 | **Los tests** y el **cierre** | — | Un test de nivel 4 **por código** declarado (H-46), con valores **distintos** entre sí si es un mapeo; repetir el cruce de campos y el de códigos (H-72); y los cinco pasos de cierre de `AGENTS.md`: la tabla de operaciones del README, *"las otras N"* |

**La segunda cuenta: encender la auth.** A-6 contó **cinco ficheros, una línea cada uno**. Con el código de hoy
son **once ficheros que ya existen**, más el adaptador nuevo:

| # | Fichero | Qué cambia | Desde |
|---|---|---|---|
| 1 | `App/Configure.swift` | El middleware JWKS **por fuera** de la cadena (H-44) y el adaptador nuevo en `actors:` | A-6 |
| 2 | `HTTPAdapter/ClubHandler.swift` | `AmbientTenantActorResolver` deja de ser el de producción. **Y el valor por omisión de `APIHandler.init` también lo es** (`:65`): es un segundo sitio, que hoy no recorre nadie porque `configure` siempre pasa el suyo | A-6 (antes, `currentActor()`) |
| 3 | `Tenancy/TenantResolutionMiddleware.swift` | **La puerta** (H-42, H-69). Y, por la regla del `@TaskLocal`, quien levanta el *claim* que el middleware de auth dejó en la petición (H-65) | **nuevo** |
| 4 | `Application/ActorContext.swift` | Los campos de §7.4 | A-6 |
| 5 | `Application/ActorResolver.swift` | ~~`async`, si el adaptador carga la plantilla~~ **No se toca** (H-65, `D-98`): el adaptador solo lee el token, y la plantilla se carga en el caso de uso, en las filas 6 a 9. La fila sale de la cuenta, que queda en **nueve** | **nuevo** |
| 6 | `Application/UpdateClub.swift:21` | El `TODO(§7)` pasa a ser la llamada a la política | A-6 |
| 7 | `Application/IngestClubCalendars.swift:42` | Ídem, con la decisión de H-41 | **nuevo** (H-41) |
| 8 | `Application/PreviewFederationLink.swift` | Ídem; ancla puesta en la ronda de A-14 | **nuevo** (H-66) |
| 9 | `Application/LinkTeamToFederation.swift` | Ídem, con la decisión de H-41; ancla puesta en la ronda | **nuevo** (H-66) |
| 10 | `HTTPAdapter/ProblemMiddleware.swift` | El `case` del error de autorización. **Si es un tipo nuevo, también la lista de desenvoltorio**, que no la exige el compilador | A-6 |
| 11 | `HTTPAdapter/IngestionHandler.swift` | ~~Quitar los dos `catch` del actor, o servirán un 401 como 400~~ **Hecho en la ronda (H-64)**: la fila sale de la cuenta, que queda en **diez** | **nuevo** |

**Por qué no es S1, aunque la cuenta haya pasado de cinco a once.** El listón de §5 es *"si encender la auth ya
no es un adaptador"*, y sigue siéndolo. Encenderla sigue siendo un adaptador, un middleware y una llamada a la
política en cada caso de uso: es la arquitectura de §7.4, no una costura que falte. De lo que se añade, la fila 3
estaba prevista desde H-42; las 7 a 9 son H-41, que ya tenía dueño; y la 5 es mecánica y la enumera el
compilador. Lo único que toca la **lógica** de un *handler* es la fila 11, y son dos líneas que hoy no cambian
nada (M4). **Lo que sí es coste creciente** (S2) es que esas formas se copien: por eso H-63, H-64 y H-65 tienen
dueño en la rebanada 1 y no en la auth.

**Las sospechas de partida, contestadas:**

| # | Sospecha | Veredicto |
|---|---|---|
| 1 | Los `TODO(§7)` y H-41 | ❌ **heredado sin decidir y crecido**: 2 anclas para 4 operaciones con rol elevado, y el Plan F10 no lo nombra | **H-66** |
| 2 | `teamNotFound` y el oráculo | ✅ es H-44 con más superficie; el orden forzado sigue en pie | **H-71** |
| 3 | ¿Qué códigos sin testigo hereda una lectura? | ⚠️ **siete** de catorce, y los dos de tenancy los emite toda la API | **H-72** |
| 4 | ¿El mapeo a mano lo puede vigilar el compilador? | ⚠️ sí lo obligatorio, no lo opcional ni lo anulable: 35 de 220 campos van por test | **H-72**, fila 9 de la lista |
| 5 | El cruce de campos | ✅ 0 sin afirmar, en 61 campos | **H-72** |
| 6 | H-40, H-42 y H-43, medidos otra vez | H-43 ✅: las ramas de F10 llevan el motivo al log con `diagnosticText`, y el `default` también. H-40 ⚠️: el sitio único se sostiene en **lo que se lanza**, pero 8 traducciones están duplicadas en los *handlers* (**H-63**), y tres comentarios describen el código de antes (**H-70**). H-42 ❌: hay cinturón y **no hay puerta**, aunque tres sitios digan que sí (**H-69**) | |

**Lo que el bloque no venía a buscar:** H-67 (el middleware traduce sin mirar la ruta) y H-68 (el 404 que no es
RFC 7807). Los dos salieron **con el servidor levantado**, igual que H-40 y H-43 en A-6. Leyendo el código no se
ven, y la batería no los ve porque ningún test pide una ruta que no existe ni compara lo emitido con lo declarado.

**La regla 9, cumplida el 2026-10-01** contra `club_atleti`, solo con lecturas y con peticiones que fallan antes
de escribir: el `/preview` y el enganche con un equipo inexistente, rutas fuera del `filter`, peticiones sin club
y un `PATCH` inválido. Al terminar: **480 partidos, 426 goleadores, 1.844 goles, 0 filas abiertas** y 174 filas
de registro, sin ninguna nueva. La sonda de H-64 corrió contra `tfm_test` y **no se versiona**. Las cinco
mutaciones (M1–M5) se restauraron con `git checkout`. `HTTPAdapter/` mide hoy **1.638 líneas**, no 1.575: en
medio entró `IngestionsInFlight` (A-11).

**Para abrir la puerta de la rebanada 1 (§6-bis):**

- **S1**: cero en A-14.
- **La lista de *"añadir un endpoint"***: escrita, arriba.
- **Los S2**: todos tienen dueño. **H-63, H-64, H-65 y H-67** son de la rebanada 1, y **dos de ellos piden una
  decisión del desarrollador**: H-65 (`async` o carga dentro del caso de uso) y H-67 (cómo se declaran las
  respuestas transversales). **H-66** es de la rebanada 2 y de la auth.

### Nota de cierre de A-12 · ¿aguanta el enganche lo que no es el camino feliz?

**No del todo, y lo que falla tiene la forma de `C-E.10`.** Los errores declarados se sostienen: 409, 501, 504 y
el `rollback` de la cascada. Lo que falla son **decisiones tomadas con una copia de antes de la red**, que es
literalmente lo que este bloque buscaba (*"los hermanos de `C-E.10`"*). Cuatro de los siete hallazgos tienen esa
forma: el equipo (H-73), el código propio contra el calendario que ya está en la mano (H-74), la edad copiada en vez
de comprobada (H-75) y los `id` de los goleadores (H-76).

**La tabla de caminos no felices, con su código medido:**

| # | Camino | Medido | Hallazgo |
|---|---|---|---|
| 1 | Dos enganches a la vez, **mismo grupo** (A y B, doble clic) | **202 + 202**, sin 500: los ámbitos se ponen en fila porque el *pool* es de una conexión | H-77 |
| 1 | Dos enganches a la vez del **mismo equipo a dos grupos** | **202 + 202**: **dos cascadas** | **H-73 (S1)** |
| 2 | Volver a enganchar: mismo código / otro código / otro grupo | 202 idempotente con fila `accepted` nueva / **409** / 202 aditivo | H-79, H-62 |
| 2 | Código que no está en el grupo | **202**, y el propio nace sin partidos | H-74 |
| 3 | Identidad que no cuadra, con temporada nueva | **409**, y la `Season` se deshace | H-79 |
| 3 | Edad de una competición nueva | se copia del equipo: **202** siempre | H-75 |
| 4 | La federación no contesta | **504** a los 20 s (manda el transporte) | H-79 |
| 5, 7 | Club FCF, las cuatro puertas | **501** con `Problem`, 0 filas | H-79 |
| 6 | El trabajo de fondo frente al *commit* | encola después del *commit* | H-79 |
| 8 | Fila `accepted` abierta y segundo 202 | **el `jobId` devuelto se queda `accepted`** | H-62 (S3) |
| 9 | Escrituras del enganche sin `TODO(§7)` | ninguna | H-79 |

**La reutilizabilidad de la guarda de identidad: sí.** `Team.requireIdentityMatches` no depende de la cascada, y
en `PUT /registrations` la competición ya existe, así que la guarda sí muerde.

**Lo que el método de este bloque no habría visto sin la regla 9.** Las dos cascadas de H-73 y el `23505` de
H-76 salieron **contra la RFFM real**, con su latencia; con los dobles de la batería la ventana de H-73 dura
microsegundos. Y H-77 salió **porque la sonda que buscaba la carrera no conseguía provocarla**. Lo que A-12 deja
dicho a quien suba el *pool*: hoy hay tres carreras que esperan su turno, no tres carreras que no existen.

**Para abrir la puerta de la rebanada 2 (§6-bis):**

- **S1**: uno, **H-73**, con dueño y con la forma del arreglo ya en el proyecto (H-55 D). La puerta **no está
  abierta** hasta que se arregle. **Arreglado el 2026-10-03** en la ronda de arreglos, así que por A-12 ya no
  queda ningún S1 abierto.
- **Los S2**: todos tienen dueño. **H-74** y **H-75** son de la rebanada 2, y **H-75 pide una decisión del
  desarrollador**. **H-77** es del despliegue. **H-74 y H-75 se adelantaron a la ronda de arreglos** (2026-10-03) y están arreglados, y **H-77 está decidido y hecho** (`D-100`): de A-12 no queda nada abierto.
- **Los S3**: H-62 y H-76, a la ronda de arreglos de este bloque; H-78, corregido en el acto.
- **A-13** sigue pendiente, y también es condición.

### Nota de cierre de A-13 · con el esquema duplicado, ¿siguen valiendo las garantías de A-5?

**Las garantías sí; los dos sitios que las guardan, a medias.** El esquema no depende de cuándo se dio de alta
un club: cuatro caminos, un `md5`, y uno de ellos es el club vivo con **nueve lotes** y dos `CHECK` rehechos
sobre su versión vieja (H-84). Lo que falla es **lo que se dejó para que nadie tuviera que volver a medirlo**: el
test de convergencia no reproduce el orden que dice reproducir (H-81), y la guarda de H-32 no tiene salida
(H-80). Las dos son la misma forma: **verde por el motivo equivocado**, la que avisa `H-07`. Y las dos salieron
**ejecutando**, no leyendo: H-80, al intentar medir la ida y vuelta por la línea de comandos; H-81, con una
mutación.

**Los `revert` que borran datos.** `migrate-tenants --revert` solo existe en su forma completa (`revertAllBatches`),
así que **todos** borran, y el aviso de H-32 lo dice bien: *"borra las tablas … y sus datos con ellas"*. Por
migración, lo que cada uno se lleva:

| `revert` | Qué borra | ¿Lo dice el aviso? |
|---|---|---|
| Las diez `Create…` | la tabla entera, con sus filas | sí: *"las tablas … y sus datos"* |
| `AddStandingsToIngestionRun` · `AddIngestionRunRound` · `AddScorersToIngestionRun` | columnas con dato: `kind`, `round_id` y los cinco contadores | cubierto: la tabla se va detrás, en el mismo recorrido |
| `AllowAcceptedIngestionRun` | **las filas `accepted`**, con un `DELETE` explícito para poder volver a `NOT NULL` (razonado en su comentario) | cubierto, por lo mismo; **solo** sería un borrado silencioso con un `revert` parcial, que hoy no existe |
| `CreateTeamRegistration` | la tabla, la `UNIQUE` de `competitions` y los dos compuestos de `Match` | sí |
| `DropFinishedAtIngestionRunIndex` | nada: rehace un índice | — |

**Y hoy ninguno es alcanzable por la línea de comandos** (H-80): la lista vale para cuando se arregle.

**Los dos deberes de §9.3, y si `launchd` los encarece: no.** Siguen sin hacer: `TenantPools` registra un *pool*
por *schema* y no lo suelta (`TenantPools.swift:49-61`), y no hay comando que diga en qué versión quedó cada club.
Pero **los dos viven solo en los comandos de migración**: `app.tenantPools` lo usan `migrate-tenants` y
`provision-tenant` y nadie más (`grep -rn tenantPools Sources`), y la ingesta que `launchd` va a disparar va por
el acceso de una conexión de `D-100`. El *pool* que no se suelta vive lo que vive el proceso del comando. **Lo
que sí los encarecería**: mover el alta de club al proceso del servidor, que es donde el backoffice la acabaría
poniendo. Ese día el *pool* por *schema* pasa a ser una conexión directa **permanente** por club, y el deber
deja de ser de operación para ser de esa rebanada.

**Para abrir la puerta de la rebanada 2 (§6-bis):**

- **S1**: cero en A-13. Con A-12 sin nada abierto, **la puerta de la rebanada 2 está abierta**.
- **S2**: ninguno nuevo. El que §5 preveía —*un `CHECK` derivado sin su gemela*— **no existe** (10/10).
- **Los S3**: H-80, H-81 y H-82, a la ronda de arreglos de este bloque; H-83, corregido en el acto.
  **Ronda de arreglos (2026-10-03)**: los tres arreglados, cada uno sostenido por **dos mutaciones cazadas**; H-80
  con rojo de aserción y verificado a mano con el binario, H-81 y H-82 verdes desde el principio porque el código
  era bueno y lo que faltaba era la guarda. **De A-13 no queda nada abierto**: 585 tests.

### Nota de cierre de A-15 · con el doble de tests, ¿qué significa hoy "N/N mutaciones"?

**Hasta este bloque, nada que se pudiera repetir.** El guion no existía fuera de las sesiones que lo usaron
(H-52), los dos cruces del contrato tampoco (H-72), y el proyecto cita cifras de las dos cosas en cada cierre.
Lo que deja A-15 son **dos instrumentos versionados, cada uno con su método escrito y sus reglas como tests**:

| | `Tools/Mutate` | `Tools/Census` |
|---|---|---|
| Contesta | *"¿lo caza algún test si lo rompo?"* | *"¿qué códigos y campos del contrato no nombra ningún test?"* |
| Se afirma con | un catálogo JSON por bloque o ronda (`Catalogs/`) | `known-gaps.json`, cada hueco con su motivo comprobado |
| Sus reglas, como tests | 40, y **15/15** mutaciones contra sí mismo | 17, y **14/14** mutaciones (con el guion de al lado) |
| Lo que se encontró a sí mismo al estrenarse | el atributo `tests` de swift-testing ya excluye los omitidos; dos pasadas a la vez se pisaban (H-89) | el `\b` de Unicode no separa `.competition.ageCategory`; `/tmp` es un enlace, y sin resolverlo no había ningún test de API |

**Y la misma lección cuatro veces en un bloque, que es la del proyecto entero:** el instrumento nuevo se
equivoca al estrenarse, y se equivoca **en la dirección tranquilizadora o en la ruidosa, nunca avisando**. Los
cuatro fallos se vieron porque cada cifra se contrastó con algo que ya se sabía: el recuento de la batería, un
resultado documentado de A-13, una cifra de A-14. **Una cifra nueva sin nada contra qué contrastarla no se cita
hasta tenerlo.**

**Cifras que se pueden citar desde hoy, porque tienen catálogo:** A-13 **6/6**, A-15 (punto 6) **6 cazadas, 1
borde declarado, 1 equivalente**, la identidad de `D-58` **11/11** tras H-87, el canario **9/9**. Las de F1 a A-14
**siguen sin poder repetirse**: se hicieron, pero no se escribió qué se rompió.

**Para las puertas (§6-bis): A-15 no bloqueaba ninguna, y no deja ningún S1.** El único abierto es H-85 (S2),
con dueño: **al montar `launchd`, un binario instalado desde un commit, nunca `.build/debug/Run`**. Va en la
misma lista que H-59.

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
| **A-11** · La fila que transita | ✅ **cerrado** — cero S1; no cierra siempre (H-57, corregido) y lo que A-3 midió vale para el calendario pero no para clasificación y goleadores (H-56). `D-89` con dueño: la rebanada 1 (H-58). H-55 arreglado en su ronda (A + B + D). H-56 arreglado en la misma ronda. **Por A-11, la puerta de `launchd` está abierta**: cero S1, y todo S2 arreglado o con dueño (H-58 → rebanada 1, H-59 → `launchd`). Y H-60 (S3), solo test. **La ronda de arreglos de A-11 queda cerrada** | 2026-09-30 | H-55 … H-62 |
| **A-12** · El enganche fuera del camino feliz | ✅ **cerrado** — **un S1**: dos enganches del mismo equipo a la vez dejan dos cascadas (H-73). El código propio no se comprueba contra el calendario (H-74) y la edad de una competición nueva se copia del equipo (H-75, decisión del desarrollador), los dos de la rebanada 2. H-62 confirmado en el camino canónico, y H-55 D no cubre la primera pasada de goleadores (H-76): los dos a su ronda de arreglos. Las carreras de `INSERT` no dan 500 porque el *pool* de tenant es de una conexión, garantía que nadie escribió (H-77, despliegue). H-78 corregido en el acto. **Ronda de arreglos (2026-10-03)**: H-76, H-62 y H-73 arreglados, cada uno con su test rojo antes del arreglo y verificado contra la base de trabajo. Dos mutaciones sobreviven, las dos por H-77, y queda dicho en el código. **La ronda queda cerrada**: 573 tests. **Por A-12, la puerta de la rebanada 2 está abierta**: cero S1, y todo S2 con dueño **H-74, H-75 y H-77 se adelantaron a la ronda** por decisión del desarrollador: H-74 y H-75 arreglados (H-75 con la salida *inferir del nombre y avisar*) y H-77 decidido y hecho (`D-100`: la conexión única, escrita como regla). **De A-12 no queda nada abierto**: 583 tests. Falta A-13 | 2026-10-02/03 | H-73 … H-79 (y H-62) |
| **A-13** · Las migraciones, con el esquema duplicado | ✅ **cerrado** — **cero S1, cero S2**. Las garantías de A-5 se sostienen con 16 migraciones: cuatro caminos, **un `md5`**, con `club_atleti` en nueve lotes entre ellos; H-31, H-33 y H-35 se sostienen, y los 10 `CHECK` de enumerado admiten exactamente sus `allCases` (H-84). Lo que falla es lo que las guarda: **`--revert --yes` no revierte nunca**, porque ConsoleKit se come el `--yes` (H-80, reabre H-32); el camino B del test de convergencia **aplica el mismo orden** que el A y deja vivir una mutación que depende del orden (H-81); y solo 2 de los 10 `CHECK` de enumerado tienen guarda (H-82). Los tres, a la ronda de arreglos; H-83, corregido en el acto. Los deberes de §9.3 siguen sin hacer y `launchd` no los encarece. **Por A-13, la puerta de la rebanada 2 está abierta**. **Ronda de arreglos (2026-10-03)**: H-80, H-81 y H-82 arreglados, **seis mutaciones, seis cazadas**. **La ronda queda cerrada y de A-13 no queda nada abierto**: 585 tests | 2026-10-03 | H-80 … H-84 |
| **A-14** · La frontera HTTP antes de copiarla | ✅ **cerrado** — cero S1. **No es todavía un patrón copiable**: hay tres formas de *handler* (H-63), y una se traga el error del actor (H-64). Añadir un endpoint toca **16 sitios** y el compilador vigila **4**; la lista está escrita en la nota de cierre. Encender la auth pasa de 5 ficheros a **11** y sigue siendo un adaptador. H-41 se heredó sin decidir (H-66), y la *"puerta"* de H-42 no existe (H-69, corregido). Dos decisiones son del desarrollador: H-65 y H-67. **Por A-14, la puerta de la rebanada 1 está abierta**: cero S1, la lista escrita, y todo S2 con dueño. **Ronda de arreglos (2026-10-01/02)**: H-64, H-63 y H-68 arreglados, H-66 anclado, H-65 decidido (`D-98`) y H-67 decidido y hecho (`D-99`). **La ronda queda cerrada**: 568 tests, y nada de A-14 abierto sin dueño. H-66 sigue con la auth, y H-69/H-70 se corrigieron en el acto | 2026-10-01/02 | H-63 … H-72 |
| **A-15** · El arnés y el instrumento de mutación | ✅ **cerrado** (2026-10-04) — ver su nota de cierre en §6. H-52 confirmado (S2) y **arreglado por adelantado**, por decisión del desarrollador: el guion versionado en `backend/Tools/Mutate/`, con sus cinco fallos como tests y la ronda de A-13 reproducida (6/6). **Puntos 2 a 6 medidos (2026-10-03)**: **cero S1**. `launchd` no cambia el dueño del CI, pero exige ejecutar un binario instalado y no `.build/debug/Run` (H-85, S2, dueño `launchd`). El canario solo vigila el calendario (H-86) y la identidad de `D-58` no tiene guarda en la base para género y modalidad (H-87): los dos a la ronda de arreglos. **Ronda de arreglos**: H-86 arreglado (el canario vigila las tres lecturas, 9/9 mutaciones) y H-87 arreglado (un gemelo por columna de la clave en el índice, 4/4). **La ronda queda cerrada**: 588 tests. H-88 y H-89 (del propio guion), corregidos en el acto. H-45, H-48 y la categoría *"fuera del arnés"*, al día (H-90). **Punto 7**: los cruces de H-72, versionados en `Tools/Census`, con trinquete. **De A-15 queda abierto solo H-85**, con dueño (`launchd`) | 2026-10-03/04 | H-52, H-85 … H-90 |

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
