# Plan de desarrollo R5 · Portada del boceto

> Rebanada 5 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Como las
> rebanadas [1](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md) a
> [4](./Plan%20de%20desarrollo%20R4%20Resultados-001.md), toca la web y el servidor, y lo que se haga en el servidor
> se apunta **solo aquí**.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md); el boceto 1
> ([`1-Teams_Dashboard.png`](./design-assets/mobile/1-Teams_Dashboard.png)); y la rebanada 4, cerrada el
> 2026-11-13 con **831 tests** en el backend y, en la web, **426 pruebas de piezas y 154 escenarios**.
>
> **Convención de remisiones**, la de siempre: `LLD-B §x` y `DW-nn` son el LLD de la web y su anexo; `LLD §x` y
> `D-nn`, el LLD del backend y su bitácora.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: en curso.** **Las seis decisiones de la §4, revisadas una a una con el desarrollador el
> 2026-11-13**, con medidas de su servidor y sus propios partidos. La revisión cambió cuatro cosas de la propuesta
> inicial: la racha lleva el número de cada jornada y no la letra (`DW-23`); casa o fuera, con un icono; el puesto
> del rival, a la izquierda de su nombre; y solo lleva a algún sitio lo que no está ya enlazado en la fila.

---

## 1. Objetivo

**El club ve de un vistazo, en la portada, cómo le va a cada equipo**: en qué puesto va, cómo le han ido las
últimas jornadas, qué resultado sacó en el último partido y contra quién juega el siguiente. Es lo que enseña cada
equipo en el boceto 1, y lo que la portada de la rebanada 1 dejó para después.

**Por qué ahora**: desde la rebanada 4 todo eso ya está en el servidor (la clasificación con su racha y los
partidos con el puesto de cada lado), pero para verlo hay que entrar en la ficha de cada equipo, uno por uno.

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **En la portada, cada equipo con su posición, su racha, su último resultado y su próximo partido** | Ficha, §3 · decisiones 2 a 5 |
| **La racha, la misma pieza que en la clasificación** de la rebanada 4: el número de cada jornada sobre el color del resultado | §3 · decisiones 3 y 4 |
| **Cada jornada de la racha y el próximo partido llevan a su jornada**, con su clasificación (pantalla de la rebanada 4) | §3 · decisión 6 |
| En el servidor, **lo que la portada necesita en una sola petición**, según la decisión 1 | §5 · decisión 1 |

**Lo que no trae** (llega después): el clic en un partido para ver su acta (rebanada 7); los estados aplazado y
suspendido con datos de verdad, que esperan a que la ingesta lea el acta (`D-57`, sin rebanada); y lo que quedó
abierto en la rebanada 4 (VoiceOver al final del proyecto, el puesto de reserva si un servidor viejo no manda
`previousPosition`), que sigue en la §9 de [su plan](./Plan%20de%20desarrollo%20R4%20Resultados-001.md).

---

## 3. La ficha de la pantalla

**La portada** (`/`, `?temporada=`), tal como la dejó la rebanada 4: los equipos de una temporada en una tabla
ordenable, con su competición, el estado de la ingesta con ↻, la última sincronización y las acciones de cada fila.

**Lo nuevo, en cada equipo** (cómo se coloca, en la decisión 2):

| Dato | De dónde sale | Cómo se ve en el boceto |
|---|---|---|
| **Posición** | La fila del equipo en la última clasificación de su competición, la misma que la caja Posición de la ficha (R4.15) | «1º» en un recuadro junto al nombre |
| **Racha** | `form` de esa fila: los últimos 5 resultados, el más reciente primero, cada uno con su número de jornada (`FormEntry`) | Cinco círculos con el número de jornada, de color según el resultado |
| **Último resultado** | El último partido jugado del equipo en la temporada | «2-1 vs RMA», con el puesto del rival en un óvalo |
| **Próximo partido** | El primer partido sin jugar del equipo | «15/05 @ SEV», con el puesto del rival en un óvalo |

**Cómo quedaría la tabla de la portada**, con lo decidido en la §4 (decisiones 2, 3, 5 y 6). Es una réplica con
datos inventados: los círculos de colores hacen de los cuadros de la racha (🟢 victoria, ⚪ empate, 🔴 derrota),
con el número de su jornada, y el
número entre paréntesis, del óvalo con el puesto (`PositionBadge`, R4), a la izquierda del nombre del rival y
en la columna Posición. Las columnas de hoy, sin cambios; las nuevas, en
**negrita** en la cabecera. Lo que cambie al decidir la §4 se cambia aquí.

| Equipo | Competición | **Posición** | **Racha** | **Último** | **Próximo** | Ingesta | Última sincronización | Acciones |
|---|---|---|---|---|---|---|---|---|
| Cadete A | Primera Cadete, Grupo 1 | (1º) | 🟢29 🟢28 ⚪27 🟢26 🔴25 | (V) 🏠 2 - 1 (3º) Rayo Sur B | sáb 16/05 18:00 ✈️ (18º) Atlético Norte A | Al día ↻ | 12/05 06:00 | (las de hoy) |
| Infantil B | Segunda Infantil, Grupo 4 | (8º) | 🔴29 ⚪28 🟢27 🔴26 ⚪25 | (D) ✈️ 3 - 1 (2º) Unión Oeste A | dom 17/05 10:30 🏠 (9º) Deportivo Este C | Con fallos ↻ | 12/05 06:00 | (las de hoy) |
| Alevín A | Primera Alevín, Grupo 2 | — | — | — | dom 20/09 09:00 🏠 Racing Centro A | Al día ↻ | 12/05 06:00 | (las de hoy) |
| Benjamín A | Sin competición · [Sincronizar con la Federación](#) | | | | | | | 🔗 |

- **Cadete A**: un equipo con jornadas jugadas; los cuatro datos.
- **Infantil B**: la ingesta con fallos; se enseña lo que hay, y la celda de la ingesta lo avisa.
- **Alevín A**: el calendario publicado y nada jugado todavía; solo el próximo partido, con el rival sin puesto.
- **Benjamín A**: sin competición, como hoy; la fila no gana nada.

**Los casos que el boceto no enseña**, y que la pantalla tiene que decir con palabras:

- **Un equipo sin competición** (inscrito, sin sincronizar): sigue como hoy, con el enlace «Sincronizar con la
  Federación»; los cuatro datos, vacíos.
- **Una competición sin jornadas jugadas** (el calendario ya publicado, nada jugado): sin posición ni racha ni
  último resultado; sí el próximo partido.
- **Una temporada acabada**: el último resultado, pero sin próximo partido.
- **Una jornada de descanso**: en la racha, un cuadro vacío con su número (`D-114`, decisión 3); no es «último
  partido», y si es la siguiente, el próximo dice «Descansa · jornada N» (decisión 5).
- **Un equipo con dos competiciones** (liga y copa, `D-12`): hoy ninguno tiene más de una, pero la lista lo
  permite. Con la tabla (decisión 2) no hay nada que decidir: desde la R1 cada competición es su propia fila, con
  el nombre del equipo una sola vez, así que cada una lleva su resumen.
- **La ingesta nunca pasó, o falló**: los datos que haya, sin inventar ninguno; el estado de la ingesta ya lo dice
  su celda.

---

## 4. Decisiones antes de construir

**Se revisan una a una con el desarrollador** (`R5.1`), cada una con lo que haga falta para verla: medidas de su
servidor, o una maqueta en HTML si la decisión es de cómo se ve. Revisadas las seis el 2026-11-13, sin maqueta: bastaron las medidas y los partidos de su club.

### Decisión 1 · Cómo se piden los datos: en lo que la portada ya pide

**El problema.** Con lo que hay, cada fila necesita tres peticiones: las jornadas de su competición
(`listRounds`), la clasificación de la última jugada (`getStanding`) y los partidos del equipo (`listMatches`).
Con seis equipos, dieciocho peticiones más cada vez que se abre la portada, y otra vez cada pocos segundos mientras
una ingesta está en marcha (`refreshWhile`, R3).

**Las opciones:**

| Opción | A favor | En contra |
|---|---|---|
| **A. Equipo por equipo**, con lo que hay | Nada nuevo en el servidor | Muchas peticiones; la portada se pinta a trozos; tres sitios donde fallar por fila |
| **B. Un resumen en cada competición de `listSeasonRegistrations`**, que la portada ya pide | Una sola petición; no crece el número de operaciones; «lo de la temporada viaja en la inscripción» ya es la regla (`D-102`) | Cambia una respuesta que ya existe (sin romperla: solo suma campos) |
| **C. 🆕 Una operación nueva** que lo junte | No toca lo que hay | Una operación más (86), y la portada pasa a pedir dos cosas sobre los mismos equipos |

**Decidido (2026-11-13): B** → [`D-113`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md). Cada
`TeamRegistrationCompetition` suma un resumen: la posición y la racha de la última clasificación, y el último y el
próximo partido, cada uno con su rival y el puesto de este. «La última clasificación» la decide el servidor (la de la
jornada más alta con tabla), y el resumen viaja también en `getTeamRegistration`, que tiene la misma forma.

**Lo que se midió para decidirlo**, en la base del desarrollador (servidor de depuración, por Vite, media de 5):

| Petición | Tiempo | Tamaño |
|---|---|---|
| La lista de equipos de la temporada (la que ya pide la portada) | 28 ms | 3,4 KB |
| Las jornadas de una competición | 21 ms | 9 KB |
| La clasificación de una jornada | 64 ms | 18 KB |
| Los partidos de un equipo | 51 ms | 29 KB |

Con A, sus 5 equipos con competición suman 15 peticiones y unos 280 KB, cada 10 s mientras hay una ingesta en
marcha; con B, unos 5 KB más en la misma petición. Lo que tarde B se estimó en menos de 100 ms y **se mide en
`R5.5`**. La lista solo la usa la portada; su hermana, `getTeamRegistration`, la ficha del equipo (R4).

### Decisión 2 · La forma de la portada: la tabla, con cuatro columnas más

La portada es hoy una tabla ordenable (R1), y el boceto son tarjetas de móvil.

| Opción | Veredicto |
|---|---|
| (a) Tarjetas, como el boceto | Descartada: el boceto es de móvil; se pierde ordenar por columnas y habría que rehacer la portada de R1 a R4 con sus escenarios |
| **(b) La tabla de hoy, con cuatro columnas más** | **Elegida (2026-11-13)**, como en la pestaña Resultados (Plan R4, decisión 6) |

- **Las columnas nuevas, detrás de la competición**, que es de la que son: Posición, Racha, Último y Próximo (la
  réplica, en la §3). La tabla pasa de 5 a 9.
- **Ordenable al menos por posición.**
- **Si no cabe en un portátil**, se desplaza dentro de su caja (`ScrollBox`, R4.15), como con el zoom al 200 %. Se
  mira en la revisión a mano (`R5.10`).
- Las tarjetas se quedan para la pantalla del móvil.

### Decisión 3 · La racha: el número de cada jornada sobre el color, como en la clasificación

El servidor da hasta 5 resultados, con su jornada. El boceto pinta el número de jornada y distingue el resultado
solo por el color; la rebanada 4 ya lo hace así en la racha de la clasificación, y con la letra en los partidos de
la pestaña Resultados.

| Opción | Veredicto |
|---|---|
| (a) La letra V, E o D, y la jornada al pasar el ratón | Descartada: en una fila de letras no se sabe hacia qué lado va el tiempo |
| **(b) El número de la jornada sobre el color, la misma racha que la clasificación** | **Elegida (2026-11-13)** → [`DW-23`](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md) |
| (c) El número y la letra a la vez | Descartada: no caben en un cuadro pequeño |

- **El orden se lee solo**: el desarrollador, en otras webs, nunca sabe si la racha va hacia un lado o hacia el otro.
- **La misma pieza que la clasificación** (`StandingTable`, R4.13), sacada a `components/` para usarla en las dos:
  el texto «Victoria en la jornada 7» al pasar el ratón o al llegar con el teclado, y el mismo para el lector.
- **La pestaña Resultados sigue con V, E o D**: es un solo partido, y su orden lo da la fila.
- El más reciente, a la izquierda; con menos de 5, los que haya, sin huecos.
- **La jornada de descanso, un cuadro vacío**: solo el borde y su número, «Descansó en la jornada 28». Lo propuso el
  desarrollador al revisar los escenarios (R5.3), para que los números de la racha vayan seguidos. El servidor
  manda el descanso como una jornada más de la racha, y cuenta entre las cinco → [`D-114`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md).
  Sale igual en la clasificación de la R4, que usa la misma racha.

### Decisión 4 · Los colores de victoria, empate y derrota: los de la rebanada 4

La rebanada 1 los dejó para esta (su plan, decisión 7), pero **la 4 ya los puso**: la racha de la clasificación y
la letra de la pestaña Resultados usan `--p-estado-bien` (verde), `--p-estado-sin-datos` (gris) y
`--p-estado-fallo` (rojo), con el texto del color del fondo, y axe los dio por buenos en los dos modos (R4.14).
**Decidido (2026-11-13): los mismos, sin cambios**; la nota de la rebanada 1 se da por cumplida. Sin entrada en
ninguna bitácora: no hay nada nuevo que decidir.

### Decisión 5 · El último y el próximo partido: casa o fuera con un icono

**El problema del boceto**: «2-1 vs RMA» no dice si el 2 es del club o del local. Con los partidos del Cadete A del
desarrollador, la jornada 6 (COBEÑA A 4 - 2 Celtic Castilla A, fuera) se leería «4-2 fuera», como una victoria.

**Decidido (2026-11-13)**, sobre una propuesta del desarrollador:

| Último | Próximo |
|---|---|
| (V) 🏠 5 - 0 (16º) FUNDACION ADF B | sáb 14/11 16:45 ✈️ (5º) JUVENTUD SANSE B |
| (D) ✈️ 4 - 2 (9º) ESCUELA MUNICIPAL DE COBEÑA A | sáb 21/11, hora por fijar 🏠 (12º) S.A.D. FUNDACIÓN C.D. RECUERDO A |

*(Los puestos del próximo partido, inventados: hoy el servidor no los manda.)*

- **El resultado, con su letra V, E o D** sobre su color, como en la pestaña Resultados: es un solo partido (`DW-23`).
- **Casa o fuera, con un icono**: una casa (🏠) o un avión (✈️), los de Lucide (`house` y `plane`), copiados en
  `AppIcon` como los demás. Con su texto, «En casa» o «Fuera», al pasar el ratón y para el lector de pantalla,
  como los iconos de las acciones (`DW-19`).
- **El marcador, en orden local - visitante**, como en la pestaña Resultados y en cualquier crónica: la letra dice
  quién ganó, y el icono, de qué lado estaba el club.
- **El rival**, con el nombre del club + letra (`D-111`), no la abreviatura de tres letras del boceto, que la
  federación no da. Los nombres largos parten en dos líneas.
- **El puesto del rival, el que tiene al llegar al partido**, en el óvalo de la rebanada 4 (`PositionBadge`) y **a la
  izquierda de su nombre**, como en la pestaña Resultados (lo señaló el desarrollador): en el
  último, el de antes de jugarlo (`previousPosition`, como en Resultados); en el próximo, el de hoy, que es con el que
  llegará. Hoy los partidos sin jugar no lo traen (`standing` nulo): lo da el resumen (`D-113`, punto 5).
- **La fecha del próximo**: día de la semana, día/mes y hora, o «hora por fijar» si no está confirmada (R4).
- **La jornada de descanso** (`D-105`) no es «último partido». Si la siguiente es de descanso, el próximo dice
  «Descansa · jornada N».

### Decisión 6 · Adónde lleva cada cosa: cada jornada de la racha, y el próximo partido

**Decidido (2026-11-13)**, sobre lo que propuso el desarrollador: solo lleva a algún sitio lo que no está ya
enlazado en la misma fila.

| Dato | Lleva a |
|---|---|
| El nombre del equipo | Su ficha, como desde la R4 |
| **Cada cuadro de la racha** | Su jornada en la pantalla de la competición (`/temporadas/:temporada/competiciones/:id?jornada=N`): sus partidos y la clasificación que dejó |
| La posición | **Nada**: el cuadro más reciente de la racha ya lleva a esa clasificación |
| El último partido | **Nada**: su jornada es la del cuadro más reciente de la racha |
| **El próximo partido** | Su jornada, en la misma pantalla: no está en la racha |

- **Los cuadros son enlaces solo en la portada.** La racha de la clasificación (R4.13) es la misma pieza, sin
  enlaces: ahí ya se está en la competición, y el selector de jornada hace ese papel.
- **Cada enlace dice lo que es**, «Victoria en la jornada 7», al pasar el ratón y para el lector de pantalla.
- **Con el teclado, cada fila suma hasta 6 paradas** (5 de la racha y el próximo). Se mira en la revisión a mano
  (`R5.10`) que recorrer la portada no se haga pesado.
- El acta de cada partido, en la rebanada 7.

---

## 5. Lo que le falta al servidor

Con la decisión 1 (B, `D-113`):

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **El catálogo**: el resumen en `TeamRegistrationCompetition` (posición, racha, último y próximo partido con su rival y el puesto de este), con lo que vale cuando falta cada dato | Catálogo | **Sí** | 1, 5 |
| **`listSeasonRegistrations` y `getTeamRegistration`** devuelven el resumen, calculado al leer: la posición y la racha de la última clasificación (como `getStanding`), y los partidos (como `listMatches`) | Aplicación, Persistencia y HTTP | Con la de arriba | 1 |
| **La racha cuenta jornadas** (`D-114`): `MatchOutcome` suma `descanso`, y el cálculo de la racha (`Form`) reconoce el partido de descanso, en un solo sitio. Cambia también la racha de `getStanding` | Catálogo, Dominio y lo que haga falta para reconocer el descanso | Con la de arriba | 3 |
| **La federación falsa**, con lo que necesiten los casos de la §3 que aún no tenga | Ninguna del servidor | No | — |

**Lo que ya está y se reutiliza**: la racha calculada de los partidos (`getStanding`, R4.7), el puesto de cada
lado de un partido (`D-112`, R4.8) y el rótulo nombre del club + letra (`D-111`).

**El censo y la mutación**, como siempre (plan del backoffice, §2.5).

**Al terminar**, el servidor sigue sirviendo **17 de las 85** operaciones (con B no hay ninguna nueva).

---

## 6. Los escenarios

**Escritos y revisados con el desarrollador el 2026-11-13** (`R5.3`), con la *skill* de escenarios: **16**, sin definir
todavía, con las etiquetas `@e2e` y `@ui` y axe en los dos modos. Quince en
[`portada-resumen.feature`](../backoffice/e2e/features/portada-resumen.feature) y uno en `jornada.feature`, porque
el descanso de la racha (`D-114`) también se ve en la clasificación. La revisión cambió el del descanso: de «no
está en la racha» a «es un cuadro vacío», y con él la decisión 3 (`D-114`).

| Grupo | Escenarios | Etiqueta |
|---|---|---|
| La posición | El puesto tras la última jornada jugada | `@ui` |
| La racha | Las últimas jornadas, hasta cinco, la más reciente primero, con su número y lo que dice al lector · el descanso, un cuadro vacío | `@ui` |
| El último partido | La letra, casa o fuera, el marcador con el local primero, el rival y su puesto con el que llegó · si descansó en la última jugada, el de antes | `@ui` |
| El próximo partido | El día, la fecha y la hora, casa o fuera, el rival y su puesto de hoy · «hora por fijar» · «descansa, y en qué jornada» | `@ui` |
| Los que no tienen todo | Sin competición, nada · sin jornadas jugadas, solo el próximo · todas jugadas, sin próximo | `@ui` |
| Adónde lleva | Un cuadro de la racha abre su jornada · el próximo partido abre la suya | `@e2e` |
| Ordenar | Por posición, el mejor primero y al final los que no tienen puesto | `@ui` |
| Ponerse al día | Al acabar la ingesta, el resumen sin recargar | `@e2e` |
| La clasificación (`jornada.feature`) | En la racha, el descanso es un cuadro vacío | `@ui` |

**Sin escenario, a propósito** (lo dice la cabecera del fichero): un equipo con dos competiciones, que el enganche
no da; la ingesta con fallos con datos ya traídos, que se ve igual que «Al día»; y los colores, que son los de la R4.

**La federación falsa**, con lo que pedían (`invented.ts`, `playedCompetition` con opciones): un grupo impar de
cinco equipos, con el descanso del club en una jornada jugada, en la última jugada o en la jornada en curso, como la
RFFM (el ficticio «Equipo Casa/Fuera (No asignado)», código `-1`, sin fecha); todas las jornadas jugadas; y la
jornada en curso sin hora. Sin opciones, la competición sale igual que en la R4. **Los tres equipos en puestos
distintos** para ordenar los coloca el paso, no la federación: con marcadores al azar pueden empatar.

---

## 7. Los pasos

### A · Las decisiones y los escenarios

| Paso | Qué |
|---|---|
| `R5.1` | La revisión de las seis decisiones con el desarrollador, una a una, con una maqueta en HTML donde haga falta |
| `R5.2` | Los documentos de lo decidido: `D-113` en la bitácora, el LLD-B y su anexo si hace falta (`DW-23`), y esta ficha al día |
| `R5.3` | Los escenarios escritos y revisados, sin definir, y la federación falsa con lo que necesiten |

### B · El servidor

| Paso | Qué |
|---|---|
| `R5.4` | La mini-fase del catálogo |
| `R5.5` | El resumen en `listSeasonRegistrations` y `getTeamRegistration`, en ciclos TDD |
| `R5.6` | El cierre del servidor: tests, mutación, censo; y su renglón en el README del backend |

### C · La web

| Paso | Qué |
|---|---|
| `R5.7` | La racha de la clasificación, sacada a una pieza común para la portada, con el cuadro vacío del descanso (`D-114`) también en la pantalla de jornada y clasificación |
| `R5.8` | Las columnas nuevas de la portada, con su orden y sus enlaces |

### D · Los escenarios en verde y el cierre

| Paso | Qué |
|---|---|
| `R5.9` | Los escenarios de la rebanada en verde, con axe en los dos modos |
| `R5.10` | La revisión a mano: el teclado y el zoom al 200 % |
| `R5.11` | El cierre: cifras, `AGENTS.md`, el plan del backoffice (§4 y §6) y lo aprendido |

Los pasos pueden cambiar tras `R5.1`.

---

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| `R5.1` | 2026-11-13 | Las seis decisiones, una a una. La 1 con lo medido en el servidor del desarrollador (§4, decisión 1); la 3 y la 5, con los partidos de su Cadete A; la 4, ya resuelta en la R4 (sus colores pasaron axe en los dos modos en R4.14) |
| `R5.2` | 2026-11-13 | Escritas con cada decisión: `D-113` en la bitácora del backend (con los puntos 5 y 6 de la decisión 5), `DW-23` en el anexo de la web y su excepción en el LLD-B §9.4; el plan del backoffice (§4 y §6) y `AGENTS.md`, al día. La enmienda a §5.1 y §5.2 del LLD del backend va con el catálogo (`R5.4`), como con `D-112` |
| `R5.3` | 2026-11-13 | **16 escenarios** revisados con el desarrollador, sin definir: la pasada en seco da 170, los 16 nuevos sin definir (46 pasos) y los 154 de antes intactos. La revisión reabrió la decisión 3 (`D-114`, en su commit). La federación falsa, con descansos, todas jugadas y la jornada en curso sin hora: **comprobado con la ingesta de verdad** (un guion de usar y tirar contra el servidor de pruebas, 5 competiciones por pasada, 5 pasadas): el descanso llega como partido contra «Equipo Fuera (No asignado)», con la fecha de su jornada y sin marcador; la clasificación de cada jornada jugada, sin el ficticio y con el puesto que calcula la federación falsa; la jornada en curso, la siguiente a la última jugada; con todas jugadas, sin jornada en curso; y el próximo sin hora, sin confirmar. **La primera pasada falló una vez** (el quinto equipo, sin partidos tras su ingesta) y no se repitió en las cuatro siguientes: a vigilar en `R5.9`. Hoy la racha del servidor todavía salta el descanso (lo cambia `R5.5`). Y los 154 escenarios de la R4, en verde con la federación falsa nueva (5 min 36 s) |
| `R5.4` | 2026-11-13 | **El catálogo (la mini-fase).** `TeamRegistrationCompetition.summary`, obligatorio: un `TeamCompetitionSummary` nuevo con `position`, `form` (la racha, `FormEntry`), `lastMatch` y `nextMatch` (anulables, con la forma de `MatchResponse`, la misma que da `/matches`: así la web reutiliza lo de la pestaña Resultados) y `nextOpponentPosition` (`D-113`, campos apuntados en su entrada). El próximo partido puede ser el descanso, el partido contra el ficticio. `MatchOutcome` suma **`descanso`** (`D-114`), y las descripciones de `FormEntry` y `StandingResponse.form` dicen «jornadas». Sin códigos de error nuevos: no hay operación nueva. El servidor rellena el resumen **provisional vacío** hasta `R5.5`, y el censo apunta los cuatro campos en `known-gaps.json` con ese motivo. LLD del backend, §4.5, §5.1 y §5.2; `backend/README.md` §4.5. Redocly sin errores (2 avisos más, los de `lastMatch` y `nextMatch`, la forma «objeto o nulo» de siempre); `swift build`; `REQUIRE_DB=1 swift test` con **831** leídos del XML (828 + 3 omitidos), como al cerrar la R4; censo con salida `0`. En la web, los tipos regenerados; dos pruebas de la portada montaban inscripciones sin `summary` y se les da uno vacío; `typecheck`, `lint`, **426** pruebas y `build` en verde. **Hay que relanzar el servidor** (`swift run Run serve`): sin él, la web nueva no se entera, pero la de hoy no lo nota |
| `R5.5` | 2026-11-13 | **El resumen calculado y el descanso en la racha.** Antes de programar, decidido con el desarrollador **cómo reconoce el servidor el descanso** (`D-114`, punto 3): **una marca en el partido**, `matches.is_rest_day`, que escribe la ingesta con lo que dice el adaptador (migración `AddRestDayToMatches`, la 20ª; sin relleno: la pasada siguiente marca los descansos que ya había, porque la marca es volátil), y **condición para integrar un conector nuevo** (guía de alta, §3.2 y promesa 8). Descartadas la marca en el ficticio y reconocerlo por el nombre. **Ciclos TDD**, cada uno con su rojo: la ingesta marca el descanso al crear y al fusionar; la marca va y vuelve de la base; la racha lo cuenta como `descanso` entre las cinco, solo el del equipo y solo hasta la jornada pedida; `getStanding` lo manda; la regla del resumen en el dominio (`TeamSummary`: la última tabla, el último jugado sin el descanso, el próximo que puede ser el descanso, el puesto del rival); el caso de uso lo monta en la lista y en la ficha (`CompetitionSummaries`); y el adaptador lo traduce con el mapeo de `/matches`. Los cuatro huecos del censo de `R5.4`, fuera. **Medido con una copia del club del desarrollador** en `tfm_test` (borrada después; su base, sin tocar): la lista con el resumen tardaba **327 ms** en el servidor de depuración, por encima de los 100 estimados (`D-113`); Postgres respondía en menos de 1 ms, y el tiempo era convertir cientos de filas. Con **solo los partidos del equipo y solo la última tabla** (una lectura nueva, `StandingRowRepository.latest`), **97 ms** y la misma respuesta. **Mutación 28/28** (`Tools/Mutate/Catalogs/R5-5.json`), tras dos rondas: la primera dejó vivas tres (faltaban dos pruebas, y la comprobación de que el próximo no es un descanso antes de buscar el puesto del rival sobraba: el ficticio no tiene fila), y al cambiar las lecturas se quitó otro filtro que sobraba. **831 → 850 tests** leídos del XML (847 + 3 omitidos); censo con salida `0`. La racha de la clasificación de la R4 también manda el descanso. **Hay que pasar `swift run Run migrate-tenants` y relanzar el servidor** (`swift run Run serve`): sin la migración, el servidor nuevo falla al leer los partidos; y los descansos que ya hay se marcan en la siguiente ingesta (o con ↻) |
| `R5.6` | 2026-11-13 | **Cierre del servidor.** El recuento, leído del XML de `REQUIRE_DB=1 swift test --xunit-output`: **850** (847 + 3 omitidos), sin fallos; **831 → 850** en la rebanada, todos de `R5.5` (`R5.4` no añadió ninguno). El censo, salida `0`, con los cuatro campos del resumen fuera de `known-gaps.json`. La mutación, **28/28** (`Catalogs/R5-5.json`), sobre el código final: después solo cambió la cabecera de `FederationClient.swift` (la promesa 8, un comentario). En `backend/README.md`, el resumen en §4.5 y la rebanada en la tabla de §0. Y, aparte (`cdd6ab7`), la regla de despliegue del README, que decía que `serve` migra al arrancar: no lo hace, migra `migrate-tenants`. **Para instalar**: fusionar la rama, `swift run Run migrate-tenants` (en la base del desarrollador ya está pasada) e `install.sh`, porque el binario de `launchd` (`0871fa2`) no marca los descansos |

---

## 9. Lo aprendido

*(Se escribe al cerrar la rebanada.)*
