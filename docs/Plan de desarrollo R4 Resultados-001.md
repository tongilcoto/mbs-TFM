# Plan de desarrollo R4 · Resultados

> Rebanada 4 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Como las
> rebanadas [1](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md),
> [2](./Plan%20de%20desarrollo%20R2%20Alta%20de%20equipo-001.md) y
> [3](./Plan%20de%20desarrollo%20R3%20Enganche-001.md), toca la web y el servidor, y lo que se haga en el servidor
> se apunta **solo aquí**.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md); y la rebanada 3, cerrada el
> 2026-10-27 con **757 tests** en el backend y, en la web, **316 pruebas de piezas y 112 escenarios**.
>
> **Convención de remisiones**, la de siempre: `LLD-B §x` y `DW-nn` son el LLD de la web y su anexo; `LLD §x` y
> `D-nn`, el LLD del backend y su bitácora.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: decisiones revisadas el 2026-10-27 y 28**, con el desarrollador, sobre tres versiones de
> una maqueta en HTML (la cabecera de la ficha, la portada y los partidos). La revisión cambió tres cosas de la propuesta inicial:
> el nombre de los equipos (el nombre del club + letra, no el corto), **las posiciones de cada partido en una sola
> consulta** en vez de una petición por jornada, y relanzar la ingesta, que se adelanta de la rebanada 14 a esta.

---

## 1. Objetivo

**El club ve cómo le va a cada equipo**: todos sus partidos de la temporada, jugados y por jugar, con el puesto en
el que iba en cada momento; y, desde ahí, cualquier jornada de su competición con su clasificación. Es la primera
pantalla de la ficha del equipo (boceto 2) y la de jornada y clasificación (boceto 3).

Y trae **relanzar la ingesta** de una competición con un botón, en la ficha y en la portada: hoy solo se hace con
`curl`, y es lo primero que se quiere hacer al ver «Con fallos».

**Por qué ahora**: desde la rebanada 3 el club sincroniza sus equipos desde la web y la ingesta trae partidos y
clasificaciones, pero **la web no enseña nada de eso todavía**: la portada solo dice si la ingesta está al día.

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **En la portada, el nombre de cada equipo lleva a su ficha**, y la celda de la ingesta de cada competición tiene el botón ↻ para relanzarla | Ficha, §3.1 · decisión 7 |
| **La ficha del equipo** (`/equipos/:id/resultados`): el título, y tres cajas con la temporada, la competición (con el estado de su ingesta y ↻) y la posición | Ficha, §3.2 · decisiones 4 y 7 |
| **La pestaña Resultados**: todos los partidos de la temporada en una tabla, con el puesto de cada equipo y la línea del propio tras cada jornada | Ficha, §3.3 · decisiones 1, 2 y 6 |
| **Jornada y clasificación** (`/temporadas/:temporada/competiciones/:id`): los partidos de una jornada, *Anterior* / *Siguiente*, y la clasificación de esa jornada | Ficha, §3.4 · decisión 3 |
| En el servidor, **cinco operaciones nuevas** (`getTeamRegistration`, `listRounds`, `getRound`, `listMatches` y `getStanding`), y en el catálogo **el nombre del club + letra** (`D-111`) y **el puesto de cada lado de un partido** (`D-112`). Con ello, el servidor sirve **17 de las 85** | §5 · decisiones 1 y 2 |

**Lo que no trae** (llega después): las pestañas Estadísticas (rebanada 10) y Plantilla (rebanada 6), que **no
aparecen** hasta su rebanada (decisión 5); el menú ⋮ del equipo (rebanada 13); el clic en un partido para ver su
acta (rebanada 7); la portada del boceto, con posición, racha, último y próximo partido (rebanada 5); y la pantalla
de Ingesta, con el motivo de cada fallo (rebanada 14, que se queda con eso al perder el botón).

---

## 3. La ficha de las pantallas

### 3.1 La portada: el enlace a la ficha y relanzar la ingesta

- **El nombre del equipo pasa a ser un enlace** a `/equipos/:id/resultados?temporada=<la de la portada>`. Es el
  «clic en un equipo» del mapa (plan del backoffice, §3).
- **En la celda «Ingesta» de cada competición, el icono ↻** junto a su estado (decisión 7), con las reglas de los
  iconos de la R3 (`IconAction`, `DW-19`): su texto, «Volver a traer los datos de la Federación», con el ratón y
  con el teclado, y para el lector con la competición detrás. Al pulsarlo, la competición pasa a «En marcha», el
  botón se bloquea, y al acabar la portada pide otra vez las competiciones (como el refresco de la R3, sin
  «Cargando…»). Si falla, el aviso arriba, con el texto del código.
- **Sin competición, no hay botón**: no hay nada que traer.

### 3.2 La ficha del equipo: título y cabecera

**Qué pide al servidor al abrir**: `getTeam` (el equipo), `listSeasons` (el selector), y
`getTeamRegistration` del equipo en la temporada de la dirección (sus competiciones). Con la competición,
`listCompetitions` para su estado de la ingesta, y `listRounds` y `getStanding` para la posición.

**Arriba**: «← Equipos» (a la portada, en la misma temporada), y el título con **el equipo con su género y su
modalidad**, como en la pantalla de sincronizar (R3.10): «Infantil A», y debajo «Masculino · Fútbol 11». Sin el
nombre del club, que ya está en la cabecera de la web.

**Tres cajas** (decisión 4):

| Caja | Qué dice | Qué se puede hacer |
|---|---|---|
| **Temporada** | La de la dirección (`?temporada=2025-26`); sin ella, la en curso, y si no hay, la más reciente (LLD-B §6.5) | Un selector con **todas las temporadas del club**. Cambiarla cambia la dirección |
| **Competición** | Su nombre, su estado de la ingesta (✓ Al día, ✕ Con fallos, ↻ En marcha…, los nombres de `IngestionHealth`) y el botón ↻ | El nombre lleva a la jornada y clasificación (§3.4). El ↻, como en la portada. **Si el equipo tiene más de una** (liga y copa, `D-12`), el nombre pasa a ser un selector y la tabla enseña solo los de la elegida |
| **Posición** | «2º», y «de 16 · tras la jornada 22» | — |

**La posición** es la de la clasificación de la jornada en curso (`isCurrent`); si esa todavía no tiene tabla, la
anterior, y así hasta encontrarla (es lo que pide el catálogo, `getStanding`). Si ninguna la tiene, «—» y «aún no se
ha jugado».

**Los estados de la cabecera:**

| Caso | Cómo se ve |
|---|---|
| **Cargando** | «Cargando equipo…» bajo el título |
| **Error** | El mensaje del código, con *Reintentar* si puede ser pasajero (LLD-B §4.4). El equipo que no existe, un rival o un código que no es un UUID: «No se ha encontrado el equipo» y el enlace a la portada, como en la R3 |
| **No juega en esa temporada** (404 de `getTeamRegistration`) | La caja de la temporada, sola, y el aviso «CD Ejemplo Infantil A no jugó la temporada 2024/25». Se cambia con el selector |
| **Inscrito sin sincronizar** | En la caja de la competición, el enlace «Sincronizar con la Federación» (a la pantalla de la R3), sin estado ni ↻; posición «—» |
| **Sincronizado, sin jornadas jugadas** | La competición con su estado; posición «—», «aún no se ha jugado» |
| **Con datos** | Las tres cajas |

**Mientras la ingesta de la competición está «En marcha»** (la lanzada con ↻ o la de `launchd`), la ficha se
refresca sola con `refreshWhile`, como la portada (R3.13).

### 3.3 La pestaña Resultados

**Una sola pestaña, «Resultados»**, con su barra (decisión 5): las otras llegan con sus rebanadas.

**Qué pide**: `listMatches` con `teamId` y `seasonId` (todas las páginas; una temporada son unos 30 partidos, y la
página llega a 100). Con `D-112`, cada lado del partido trae su puesto tras esa jornada. **La posición de hoy de los
equipos de los partidos por jugar** sale de la clasificación que ya pidió la cabecera: ninguna petición más.

**Una tabla, una fila por partido** (decisión 6), **en orden de jornada**, y **sin título de grupo** sobre las
columnas de la derecha:

| J | Fecha | Local | Resultado | Visitante | | Pos. | Pts | G | E | P | DG | |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Jornada | «Sáb 1 mar» | Equipo y su puesto | «3 - 1» | Equipo y su puesto | V / E / D | Del propio tras la jornada | | | | | | ☰ |

- **El nombre de los equipos, el del club + letra** (decisión 1): «Celtic Castilla A», «A.D. ALHONDIGA C». El
  propio, resaltado.
- **El puesto junto a cada nombre**: el de tras esa jornada si se jugó; el de hoy si no.
- **V / E / D**, la letra en un cuadro de color: verde, gris y rojo, con la letra siempre (el color no es lo único
  que lo dice, LLD-B §10).
- **Las columnas de la derecha** solo en los partidos jugados.
- **☰** lleva a esa jornada en la pantalla de jornada y clasificación (§3.4), con su texto «Ver la jornada 20 y la
  clasificación».
- La etiqueta **«Federación»** junto al título (LLD-B §7.5): ni crear, ni editar, ni borrar.

**Cada partido según su estado** (decisión 6):

| Estado | En «Resultado» | Color de la letra |
|---|---|---|
| Jugado | El marcador | V, E o D |
| Por jugar, con hora | La hora («12:00») | — |
| Por jugar, sin hora | «por fijar» | — |
| Aplazado | «Aplazado», en ámbar. **Se queda en la fila de su jornada** | — |
| Suspendido | El marcador al suspender, apagado, y «Suspendido» | — |

La fecha, **sin marca de provisional**.

**La tabla abre arriba**, en la jornada 1: en la pantalla de un ordenador caben las ~30 filas sin desplazarse.

**Los estados de la tabla:**

| Estado | Cómo se ve |
|---|---|
| **Cargando** | «Cargando partidos…» |
| **Error** | El mensaje, con *Reintentar* si es pasajero; la cabecera se queda |
| **Vacío, sin sincronizar** | «Este equipo aún no tiene partidos.» y el enlace «Sincronizar con la Federación» |
| **Vacío, sincronizado** | «Trayendo el calendario de la Federación…» mientras la ingesta está «En marcha»; si no, «La Federación aún no ha publicado partidos de este equipo.» |
| **Con datos** | La tabla |

**«Clasificación calculada»**: si la federación del club no da la tabla de jornadas pasadas
(`federationProvidesRoundStandings = false`, LLD-B §8.4), los puestos de antes del alta llevan esa marca. Con la
RFFM no aparece.

### 3.4 Jornada y clasificación (`/temporadas/:temporada/competiciones/:id`)

**Por revisar al escribir sus escenarios**: la decisión 3 fija el camino; lo de abajo es la propuesta, sobre el
boceto 3, que no tiene maqueta.

- **Arriba**: la competición y el grupo, la temporada, y «Jornada 22 · 14 – 16 feb».
- **La jornada que se enseña** es la en curso (`isCurrent`), o la última si la competición terminó. **Si se llega
  desde ☰**, la de ese partido. La jornada no va en el camino (decisión 3): va detrás de `?`, como la temporada
  (`?jornada=22`), para que recargar deje en la misma.
- **Los partidos de la jornada** (`listMatches` con `roundId`), en una tabla como la de Resultados pero sin las
  columnas del propio: local, resultado, visitante. Los equipos del club, resaltados.
- **«‹ Anterior» · «Jornada 22» · «Siguiente ›»**, bloqueados en la primera y en la última.
- **La clasificación** de esa jornada (`getStanding`): Pos., Equipo, J, G, E, P, GF, GC, Pts, Ant. (la anterior) y
  la racha de los últimos cinco (V/E/D, con la letra). La fila del club, resaltada. Sin tabla todavía: «Esta jornada
  aún no tiene clasificación.»
- **«←»** vuelve a donde se estaba (la ficha del equipo, si se vino de ella).
- **Los cuatro estados**, como las demás: cargando, error (con «No se ha encontrado la competición»), vacío (sin
  jornadas: «La Federación aún no ha publicado el calendario.») y con datos.

---

## 4. Decisiones antes de construir

Las siete, **decididas el 2026-10-27 y 28** con el desarrollador, sobre tres versiones de una maqueta en HTML (la cabecera
y los partidos). La maqueta no se guarda en el repositorio, como en la R3.

### Decisión 1 · Cómo se llama un equipo en un partido: el nombre del club + letra

Era lo pendiente de la rebanada 4 en el plan del backoffice (§4). **«Celtic Castilla A», «A.D. ALHONDIGA C»**: el
**nombre** del club (no el corto) y la letra del equipo. Dentro de una competición todos los equipos son de la misma
categoría, así que no hace falta repetirla. Sin letra (la federación no la publica cuando el club tiene un solo
equipo en esa categoría), solo el nombre.

**Lo que hay hoy**: el servidor monta todos sus rótulos con el **nombre corto** (`short_name`), del club propio y
del rival. `TeamRef` trae `displayName` (corto + categoría + letra) y `shortDisplayName` (corto + letra: «Celtic
A»); y en `TeamResponse`, `clubName` es también el corto, aunque el catálogo lo describa como «Nombre del club»
(`TeamRegistrationHandler.swift`). En la base del desarrollador, el club propio es «Celtic Castilla» / «Celtic», y
en los rivales los dos son iguales, el que da la federación.

**Decidido**: **`TeamRef` suma un rótulo con el nombre + letra, junto a `shortDisplayName`**, que se queda. **La web
usa el nuevo**; el corto se verá si lo usan la web del móvil o las apps. **Cambia el catálogo**: va en la bitácora
como **`D-111`**, y el nombre del campo se fija en R4.4. Y en el mismo paso, **la descripción de
`TeamResponse.clubName`** se corrige para decir que es el corto, o el campo pasa a dar el nombre: se decide en R4.4
con lo que lo use.

Lo que dejaba pendiente `D-109` (el nombre no distingue masculino de femenino ni fútbol 7 de 11) no afecta aquí:
dentro de una competición todos son iguales. **En el título de la ficha** sí, y por eso va con su género y su
modalidad (§3.2).

### Decisión 2 · Las posiciones de cada partido, en la misma consulta que los partidos

La propuesta era pedir la clasificación de cada jornada por separado: **hasta 34 peticiones** para pintar una ficha
(las competiciones de la base del desarrollador tienen entre 26 y 34 jornadas). **Descartada**: la ingesta ya
guarda la tabla de cada jornada (`standing_rows`), y si los partidos de la temporada salen de una consulta, sus
posiciones también.

**Decidido**: **cada lado de un partido trae su puesto tras esa jornada** en la respuesta de `listMatches`, y con él
la línea que pinta la tabla (Pts, G, E, P, GF, GC). Nulo si esa jornada no tiene tabla. Un solo dato para los dos
lados, aunque la web solo pinte la línea del propio: así no depende de quién es el propio. **Cambia el catálogo**:
va en la bitácora como **`D-112`**, y su forma exacta se fija en R4.4.

**Los partidos por jugar** llevan el puesto de hoy, que sale de la clasificación que pide la cabecera.

### Decisión 3 · El camino de jornada y clasificación: la competición dentro de su temporada

**`/temporadas/:temporada/competiciones/:id`**, con la temporada como en el resto (`2025-26`, LLD-B §6.5) y la
competición por su código interno (§6.3). **El número de jornada no va en el camino**: la pantalla es de la
competición, y la jornada es lo que se está mirando de ella; va detrás de `?` (§3.4). Era el «camino por decidir»
del mapa (plan del backoffice, §3).

### Decisión 4 · La cabecera de la ficha: tres cajas

| Opción | Veredicto |
|---|---|
| **(a) Tres cajas, como el boceto** | **Elegida** |
| (b) Una línea bajo el título | Descartada |

- **El selector enseña todas las temporadas del club**, no solo aquellas en las que juega el equipo: saberlo
  costaría una petición por temporada. Elegir una en la que no juega es un estado de la ficha (§3.2).
- **El selector de competición, solo con más de una.**
- **Y en la caja de la competición, el estado de su ingesta y el botón ↻** (decisión 7), propuesto por el
  desarrollador al ver la maqueta.

### Decisión 5 · Sin las pestañas que aún no existen

Estadísticas y Plantilla **no aparecen** hasta sus rebanadas (LLD-B §7.4: lo que no se puede hacer, no aparece).
Tampoco el menú ⋮.

### Decisión 6 · Los partidos, en tabla

| Opción | Veredicto |
|---|---|
| (a) Tarjetas, como el boceto | Descartada: el boceto es de móvil; en el ordenador, la temporada entera no cabe sin desplazarse |
| **(b) Una tabla, una fila por partido** | **Elegida**, con G, E y P además de Pos. y Pts, estrechando las columnas, y sin título sobre ellas: es un formato conocido |

- **Por jugar**: la hora si la hay, «por fijar» si no; la fecha sin marca de provisional.
- **Un partido aplazado se queda en la fila de su jornada**, aunque la federación le ponga otra fecha. «Menos lío»;
  que eso mueve las clasificaciones de las otras jornadas ya lo sabe quien sigue la competición.
- **La tabla abre arriba**: en un ordenador cabe sin desplazarse.

Por eso **la tabla se ordena por jornada**, no por fecha: `listMatches` ordena por fecha (el aplazado se iría a su
fecha nueva), así que la web reordena por `roundNumber`.

### Decisión 7 · Relanzar la ingesta, adelantado de la rebanada 14

En la R3 (decisión 1) quedó **dónde** va el botón (en la celda de la ingesta de cada competición) y **cuándo**, la
rebanada 14. **Se adelanta a esta**: hace falta en la portada y en la ficha, y el servidor ya lo tiene
(`triggerIngestion`, activa desde F6). **Con una sola competición responde cuando la pasada ha terminado** (200), así
que la web no tiene que esperar a nada: «En marcha» mientras tanto, y al acabar vuelve a pedir lo que enseña. La
rebanada 14 se queda con la pantalla de Ingesta.

---

## 5. Lo que le falta al servidor

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **El catálogo**: el rótulo nombre del club + letra en `TeamRef`, junto a `shortDisplayName` (`D-111`), y la descripción de `TeamResponse.clubName`, que dice «nombre» y da el corto; el puesto de cada lado del partido en `MatchTeam` (`D-112`); y los códigos de error de las cinco operaciones, contrastados con lo que emitirán (como R3.4) | Catálogo | **Sí** | 1, 2 |
| **`getTeamRegistration`**: el equipo en una temporada, con la misma forma que cada elemento de `listSeasonRegistrations` (que ya existe, R1). 404 si el equipo, la temporada o la inscripción no existen | Las cuatro | Con la de arriba | 4 |
| **`listRounds`** (`?competitionId=`, obligatorio) y **`getRound`**: las jornadas, con `isCurrent` derivado al leer | Las cuatro | Con la de arriba | 3, 4 |
| **`listMatches`**: los tres ámbitos (`roundId`, `competitionId`, `teamId` con `seasonId`), paginada, orden de calendario con las horas sin fijar al final del día, `status` y `order`; y **el puesto de cada lado** (`D-112`), en la misma consulta | Las cuatro | Con la de arriba | 2, 6 |
| **`getStanding`** (`?roundId=`, obligatorio): la tabla de la jornada, con `previousPosition` y **la racha (`form`), que no se guarda**: se calcula de los partidos al leer (LLD §4.5) | Las cuatro | Con la de arriba | 3 |
| **El rótulo nombre del club + letra** en `TeamRef`, en todos los sitios donde sale (`listMatches`, `getStanding` y el `/preview` del enganche), con el `name` del club propio o del rival | HTTP | Con la de arriba | 1 |
| **La federación falsa**, con competiciones **jugadas** (§6) | Ninguna del servidor | No | — |

**Lo que ya está y se reutiliza**: las tablas de jornadas, partidos y clasificación, que escribe la ingesta desde
F5–F7; `listSeasonRegistrations`, cuya forma repite `getTeamRegistration`; `triggerIngestion`; y los nombres del
catálogo en el servidor (`D-109`).

**El censo y la mutación**, como siempre (plan del backoffice, §2.5): un catálogo de mutación por paso, y el censo
en `0` con las cinco operaciones.

**Al terminar**, el servidor sirve **17 de las 85** operaciones.

---

## 6. Los escenarios

**Lista provisional.** Se escriben y se revisan con el desarrollador antes de programar la web, con la *skill* de
escenarios, con las etiquetas `@e2e` y `@ui` y axe en los dos modos.

**La portada** (§3.1)

- El nombre de un equipo lleva a su ficha, en la misma temporada.
- ↻ en una competición: pasa a «En marcha» y vuelve a «Al día» sin recargar.
- ↻ en una competición cuya federación falla: «Con fallos».
- Un equipo sin competición no tiene ↻.

**La cabecera** (§3.2)

- La ficha de un equipo jugado: su título con género y modalidad, la temporada, la competición «Al día» y la
  posición «tras la jornada…».
- Cambiar la temporada en el selector cambia la dirección y lo que se ve.
- Una temporada en la que el equipo no juega: el aviso.
- Un equipo inscrito sin sincronizar: «Sincronizar con la Federación», y lleva a su pantalla.
- Un equipo sincronizado sin jornadas jugadas: posición «—».
- Un equipo que no existe, un rival o un código que no es un UUID: «No se ha encontrado el equipo».
- ↻ desde la ficha.
- La competición lleva a su jornada y clasificación.

**Resultados** (§3.3)

- Todos los partidos, en orden de jornada, con el marcador, la letra y la línea del propio.
- El puesto junto a cada equipo: tras la jornada en los jugados, el de hoy en los que no.
- Un partido por jugar con hora, y uno sin ella («por fijar»).
- Un partido aplazado, en su jornada; uno suspendido.
- ☰ lleva a esa jornada.
- Vacío sin sincronizar, y mientras llega el calendario.

**Jornada y clasificación** (§3.4)

- Abre en la jornada en curso, con sus partidos y su clasificación; el club resaltado.
- *Anterior* y *Siguiente*, y bloqueados en los extremos.
- Recargar deja en la misma jornada.
- Una jornada sin clasificación todavía.
- La racha y la posición anterior.
- Una competición que no existe.

**Los datos**: **una competición jugada inventada** por la federación falsa (LLD-B §11.3), con lo que hoy no sabe
servir: marcadores y horas en el calendario, **la clasificación de cada jornada** y **el acta de los partidos del
club** (la ingesta la pide para saber si un partido se aplazó o se suspendió, `D-57`). Se programa en R4.3, porque los
escenarios no se pueden ver en rojo de verdad sin datos. La única grabación que tiene hoy
(`RFFM-standings-temp21-group-24037549-round01-28.txt`) es de un grupo real; si sirve de modelo de formato, se
inventa sobre ella.

---

## 7. Los pasos

Cada paso dice qué se hace, cómo se comprueba y qué se graba. **Al acabar cada uno se para** y se espera el visto
bueno del desarrollador antes del siguiente, y su renglón va en la §8. Cada paso deja el árbol en verde por sí
solo, y lo que no venga en el plan va en su propio commit.

### A · Las decisiones y los escenarios

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R4.1** | Este plan, con las decisiones 1 a 7 | El desarrollador lo revisa | Un commit, y otro por cada corrección |
| **R4.2** | Los documentos de lo decidido: en la bitácora del backend, **`D-111`** (club + letra) y **`D-112`** (el puesto en el partido), con su línea en el LLD; en el LLD-B, los caminos de la ficha y de jornada y clasificación confirmados (§6.1); y en el plan del backoffice, lo «pendiente de la rebanada 4» resuelto, relanzar la ingesta pasado de la fila 14 a la 4, el camino de jornada en el mapa y la R4 en curso | El desarrollador lo revisa | Un commit por documento (LLD-B §E.1) |
| **R4.3** | **Los `.feature` de la §6**, revisados con el desarrollador antes de programar; y **la federación falsa con una competición jugada**: marcadores, horas, la clasificación de cada jornada y las actas, con un aplazado y un suspendido | Revisión del desarrollador; `npm run e2e` con los nuevos **en rojo porque falta la pantalla**. La ingesta del servidor de pruebas sobre la competición jugada deja en `tfm_test` sus partidos con marcador, una tabla por jornada y los estados del acta | Un commit |

### B · El servidor

Con el método del backend (§5).

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R4.4** | **El catálogo (la mini-fase)**: `D-111` y `D-112` con su forma, y las cinco operaciones con los códigos que emitirán | `npx @redocly/cli lint`, `swift build`, `REQUIRE_DB=1 swift test` sin cambios en el recuento, los tipos de la web regenerados y `npm run build` en verde | Un commit |
| **R4.5** | **`getTeamRegistration`**, y el rótulo club + letra en `TeamRef` (`D-111`) | Tests, mutación (`Catalogs/R4-5.json`) y `curl` contra la base de trabajo con un servidor aparte | Un commit |
| **R4.6** | **`listRounds` y `getRound`** | Ídem (`R4-6.json`) | Un commit |
| **R4.7** | **`getStanding`**, con la racha calculada | Ídem (`R4-7.json`) | Un commit |
| **R4.8** | **`listMatches`**, con los tres ámbitos y el puesto de cada lado (`D-112`) | Ídem (`R4-8.json`); y en el `curl`, la temporada de un equipo de verdad en una sola petición | Un commit |
| **R4.9** | Cierre del servidor: el recuento leído del XML, el censo con las cinco operaciones, los catálogos de la rebanada otra vez sobre el código final, y el README del backend | `REQUIRE_DB=1 swift test --xunit-output`, el censo con salida `0` | Un commit |

### C · La web

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R4.10** | **La portada**: el nombre del equipo como enlace a su ficha, y ↻ en la celda de la ingesta, con sus textos de error | Vitest, y la web abierta contra el servidor del desarrollador | Un commit |
| **R4.11** | **La ficha: título y cabecera**, con sus estados, el selector de temporada, la competición con su estado y ↻, la posición, y el refresco mientras está «En marcha» | Vitest, y la web abierta con los equipos del desarrollador | Un commit |
| **R4.12** | **La pestaña Resultados**: la tabla, cada estado de partido, el orden por jornada y sus estados | Vitest, y la web abierta | Un commit |
| **R4.13** | **Jornada y clasificación**: los partidos de la jornada, *Anterior* / *Siguiente*, `?jornada=` y la clasificación con su racha | Vitest, y la web abierta | Un commit |

### D · Los escenarios en verde y el cierre

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R4.14** | Los escenarios de R4.3, en verde | `npm run e2e` en verde, con axe en los dos modos; la duración de la pasada, apuntada | Un commit |
| **R4.15** | La revisión a mano del LLD-B §10.7 *b*, con el teclado en Chrome y en Safari; VoiceOver, del desarrollador | La lista en el PR | — |
| **R4.16** | Cierre: los cinco pasos de `AGENTS.md` («Al cerrar una fase»), el mapa del plan del backoffice (§3) con Resultados y jornada en verde, el README de la web y lo aprendido | Las cifras buscadas por su número viejo en todo el árbol | Un commit |

---

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| **R4.1** | ✅ 2026-10-28 | El plan escrito y sus siete decisiones revisadas con el desarrollador sobre tres versiones de una maqueta en HTML (cabecera, portada y partidos). Lo que cambió en la revisión: **el nombre de los equipos**, el nombre del club + letra y no el corto (1); al mirarlo salió que el servidor monta todos sus rótulos con el corto, y que `TeamResponse.clubName` lo da aunque el catálogo diga «nombre» (a R4.4). **Las posiciones de cada partido, en la misma consulta que los partidos**, en vez de una petición por jornada (2). **El camino de jornada y clasificación** sin el número de jornada (3). **Las cajas de la cabecera**, con el estado de la ingesta y ↻ en la de la competición (4), y relanzar la ingesta adelantado de la rebanada 14 (7). **Los partidos en tabla**, con G, E y P, el aplazado en su jornada y abriendo arriba (6). La pantalla de jornada y clasificación (§3.4) queda sin maqueta, por revisar en un paso posterior |

---

## 9. Lo aprendido

*(Al cerrar la rebanada.)*
