# Plan de desarrollo R7 · Acta del partido

> Rebanada 7 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Como las
> rebanadas [1](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md) a
> [6](./Plan%20de%20desarrollo%20R6%20Plantilla-001.md), toca la web y el servidor, y lo que se haga en el servidor
> se apunta **solo aquí**.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) (§3.2 y §5.3: `Appearance`, `Card`, `Goal`) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) (`D-41` a `D-47`, `D-52` a `D-54`,
> `D-57`); el acta de la RFFM ([anexo RFFM §F.10](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md)); y la
> rebanada 6, cerrada el 2026-11-22: **1062 tests** en el backend (1059 + 3 omitidos) y, en la web, **622 pruebas de
> piezas y 293 escenarios**. **No hay boceto del acta**: la forma de la pantalla sale de la decisión 5.
>
> **Convención de remisiones**, la de siempre: `LLD-B §x` y `DW-nn` son el LLD de la web y su anexo; `LLD §x` y
> `D-nn`, el LLD del backend y su bitácora.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: las doce decisiones de la §4, revisadas con el desarrollador (2026-11-23); faltan los
> escenarios (`R7.3`) y los pasos del servidor.**
> El servidor empieza en `feature/r7-acta-backend-1`.

---

## 1. Objetivo

**El club apunta lo que pasó en cada partido de sus equipos**: quién fue convocado y cuántos minutos jugó, quién
marcó y cómo, y las tarjetas. El partido (fecha, rival, marcador) es de la federación y no se toca; lo que se apunta
es del club (LLD-B §6, «el partido y su acta son de dueños distintos»).

**Por qué ahora**: las estadísticas (R10) y las amarillas pendientes de sanción se cuentan con lo que se apunta
aquí, y las ausencias (R8) se cruzan con la convocatoria.

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **La pantalla del acta** de un partido: la cabecera del partido, la convocatoria, los goles y las tarjetas | §3 · decisiones 4 y 5 |
| **En Resultados, el enlace de cada partido a su acta** | §3 |
| **En la plantilla, la sección de refuerzos**: los jugadores de otros equipos del club que han jugado con este, con su equipo y su participación, de solo lectura | §4 · decisión 3 |
| **Apuntar, corregir y borrar** una convocatoria, un gol o una tarjeta | §3 · decisiones 5 a 7 |
| **El acta de la federación, cargada sola** con la ingesta: la convocatoria con su dorsal, los goles y las tarjetas; el club completa lo demás | §4 · decisiones 1 y 9 a 12 |
| **El tono de archivo** (`DW-26`) también en la ficha del equipo (Resultados y Plantilla) y en la del jugador, cuando la temporada está archivada; preparado y probado con pruebas de piezas, se verá cuando la web abra las archivadas (rebanada 11) | §4 · decisión 5f (`R7.3`, P12) |
| **El selector de jornada de la competición**, con la fecha, en casa o fuera y el rival en cada opción | §3 |
| En el servidor, **las 16 operaciones del acta** (`getMatch` y el CRUD de convocatorias, goles y tarjetas) y sus tres tablas | §5 |

**Lo que no trae** (llega después): las cifras que se calculan con el acta (R10), las ausencias (R8) y los tramos
de sanción (R9).

---

## 3. La ficha de las pantallas

### El acta (`/temporadas/:temporada/partidos/:id`, decisión 4)

De arriba abajo (decisión 5): **«← Resultados de [equipo]»**, el título con la competición y el enlace a su jornada y
clasificación; **el navegador entre partidos**; **el marcador** (los dos equipos, el resultado y «Finalizado» o «Por
jugar») con la fecha, la hora y el campo; **un aviso** de en qué situación está el acta; y **tres secciones**:
**Convocatoria**, **Goles** y **Tarjetas**. Antes de la hora de comienzo, solo la convocatoria (decisión 11).

| Situación | Aviso | Convocatoria | Goles y tarjetas |
|---|---|---|---|
| Antes del partido | 🗓️ «De momento solo se apunta la convocatoria» | 5a | No se ven |
| Jugado, acta sin cerrar | ⏳ «Se cargará sola en cuanto la Federación la cierre» | 5b | Se añaden, corrigen y borran |
| Acta cargada | ℹ️ De dónde viene y qué queda por completar | 5b y 5c, con el recuadro ámbar | Lo de la federación, fijo; el club completa (5d, 5e) |
| Temporada archivada | 🔒 «Se ve, pero no se cambia» | Solo lectura | Solo lectura (5f) |

### El enlace desde Resultados

*(Decidido el 2026-11-23, en `R7.3`, pregunta P1.)* En la tabla de la pestaña Resultados, **el marcador de cada
partido es el enlace a su acta** (el desarrollador). En los por jugar, lo que ocupa su sitio (la hora o «por
fijar») hace de enlace, porque antes del partido ya se apunta la convocatoria. **En la jornada de descanso, ninguno**:
no hay acta (decisión 8). El icono «Ver la jornada y la clasificación» sigue igual.

| Opción | Elegida |
|---|---|
| Un segundo icono, «Ver el acta», junto al de la jornada | |
| **El marcador** | **Sí** |
| Toda la fila | |

### El selector de jornada, también en la competición

*(Apuntado el 2026-11-23, al ver la maqueta.)* El acta lleva «‹ Anterior», un selector y «Siguiente ›» entre los
partidos del equipo, como la jornada y clasificación de la competición (R4). Cada opción dice **la jornada, la fecha,
🏠 o ✈️ (en casa o fuera) y el rival**: «Jornada 10 · 14 nov · 🏠 C.D. Los Almendros B»; la jornada de descanso, en
gris y sin poder elegirse, y los botones se la saltan. **La misma etiqueta pasa al selector de la competición**, con
el partido del equipo del club en cada jornada (allí la de descanso sí se elige: tiene partidos y clasificación).
Es trabajo de la web (pasos C), no un renglón del plan de la R4, que está cerrado.

### Los casos que el boceto no enseña

*(Se van apuntando al revisar las decisiones y los escenarios.)*

- **La dirección de un partido entre dos rivales, o de uno que no existe**: la página dice «No se ha encontrado el
  partido», como la competición (`R7.3`, P2, 2026-11-23).

---

## 4. Decisiones antes de construir

*Revisadas una a una con el desarrollador (`R7.1`), cada una con lo que hizo falta para verla.* Lo que ya está
decidido en el LLD del backend y se da por bueno salvo que una decisión lo cambie: la convocatoria con cuatro
estados y los minutos solo si jugó, opcionales (`D-41`, `D-42`, `D-14`); una fila de tarjeta es una sanción, y la
doble amarilla, una roja (`D-45`); la tarjeta no exige convocatoria (`D-46`); el gol sin cuadre con el marcador y el
del rival sin goleador (`D-53`, `D-09`); el gol en propia puerta, a nombre del que encaja y sin sumarle (`D-52`); y
la identidad (jugador, partido) que no se cambia (`D-37`).

### Decisión 1 · El acta de la federación se carga sola, con la ingesta (`D-125`, enmienda a `D-57`)

**Lo medido** (2026-11-22): las **91 actas** de los partidos jugados de los equipos del desarrollador, leídas en la
RFFM y contadas sin sacar nombres.

| Qué | Lo que sale |
|---|---|
| Los códigos de gol | `100` normal (503), `101` penalti (16), `102` en propia puerta (5), en la lista del equipo del que lo marca; leído así, el marcador cuadra en 90 de 91 |
| Los códigos de tarjeta | `100` amarilla (199), `101` roja (12); la doble amarilla, dos `100` y la segunda con «segunda amarilla» (5) |
| Casar por el nombre, como la plantilla | 391 de 432 jugadores (90 %) con la plantilla de su equipo (3 equipos con plantilla, 24 actas) |
| Lo que trae | El dorsal de todos (432/432), titular o suplente, los cambios con su minuto (49), el minuto de cada gol |
| Lo que no trae | Asistencia, zona, lado, parte del cuerpo, la falta directa; y los minutos jugados, que habría que calcular |

| Opción | Elegida |
|---|---|
| A · Todo a mano | |
| B · Un botón «Cargar desde la Federación», como la plantilla | |
| **C · Automática, con la ingesta** | **Sí**. Si al diseñarla no se ve clara, para empezar: **al abrir el acta por primera vez** |

**Cómo**: como la plantilla, **solo escribe lo que la web no ha modificado** (*precisado en la decisión 11: una sola
carga, cuando la federación cierra el acta; en la convocatoria manda el acta*). Lo que lee la federación va **en su
adaptador** (pedir el acta y traducirla, como `fetchTeamRoster`), y casar a los jugadores también (decisión 9);
escribir, **en un caso de uso** de la aplicación, como `SyncTeamRoster`.

**Lo que quedaba abierto se decide en la 9 a la 12**: el código del jugador y quién casa (9), el jugador que no casa
(10), cómo se sabe qué ha tocado la web (11) y los minutos (12).

### Decisión 2 · El dorsal del acta, solo en la convocatoria (`D-129`)

El acta trae el dorsal de todos (432 de 432, decisión 1). **Se guarda en la convocatoria**, opcional, junto al
equipo de la decisión 3; la carga lo pone y la web lo puede apuntar o corregir.

| Opción | Elegida |
|---|---|
| **Solo en la convocatoria** | **Sí** (el desarrollador, 2026-11-22). **En la R7, la web solo lo enseña**: el del acta o, sin acta, el de la plantilla; no se apunta ni se corrige a mano (`R7.3`, P10) |
| En la convocatoria y, si el jugador no tiene dorsal en la plantilla, rellenarlo | |

**La plantilla no se toca**: su dorsal es el que pone el club; el del acta puede cambiar de un partido a otro, o ser
el de un refuerzo, y rellenar la plantilla chocaría con el dorsal que no se repite en el equipo (`D-118`).

### Decisión 3 · El jugador de otro equipo del club: cada apunte guarda su equipo, y la plantilla enseña los refuerzos (`D-128`)

**El problema** (lo vio el desarrollador, 2026-11-22): hoy la convocatoria y la tarjeta no guardan el equipo; sale
de la fila del jugador (`D-05`). El partido que un jugador del B juega con el A contaría para el B, y las cifras de
los dos equipos se descuadrarían. Los goles no: el equipo que marca sale del partido (`D-04`).

| Opción | Elegida |
|---|---|
| **A · Cada apunte del acta guarda el equipo con el que jugó**; el jugador sigue con una plantilla por temporada (`D-121`) | **Sí** |
| B · Varias plantillas por jugador, una principal y las demás de refuerzo | |

**Y una sección de refuerzos en la plantilla** (el desarrollador): **al final de la misma página**, los jugadores de
otros equipos del club que han jugado con este, **con su equipo y su participación** en las actas. **Solo lectura**:
se lee de las actas, no se da de alta ni se corrige nada ahí. **Sin refuerzos, la sección no sale** (`R7.3`, P11).

**Lo que cambia en las reglas del LLD**: «el equipo del jugador disputa el partido» pasa a ser **«el equipo del
apunte disputa el partido, y el jugador es del club en esa temporada»**; en el gol, el goleador y el asistente,
del club y en esa temporada, en vez de «del equipo que marca» (`D-52`, con su vuelta en propia puerta).

### Decisión 4 · El camino del acta: con la temporada delante (`DW-22`)

| Opción | Elegida |
|---|---|
| **`/temporadas/:temporada/partidos/:id`** | **Sí** (el desarrollador, 2026-11-22) |
| `/partidos/:id`, como el borrador del LLD-B | |
| `/temporadas/:temporada/equipos/:id/partidos/:partido`, dentro de la ficha del equipo | |

**Por qué**: lo que es de una temporada lleva la temporada en el camino (`DW-22`), como la ficha del equipo, la
competición y el jugador; un partido es de una sola competición. **Si la temporada del camino no es la del partido**,
«no se ha encontrado», como la ficha del jugador. Descartado meterlo en la ficha del equipo: un partido entre dos
equipos del club tendría dos caminos (hoy no hay ninguno, pero puede pasar). Sin entrada nueva en el anexo del
LLD-B: aplica `DW-22`; el camino, en el LLD-B §6.1.

### Decisión 5 · Cómo se ve el acta y cómo se apunta (`D-134`, `D-135`, `D-136`, `DW-26`)

**Revisada del 2026-11-22 al 2026-11-23 sobre una maqueta en HTML** (con datos inventados; no se guarda en el
repositorio, como la de la R6), con cinco situaciones: antes del partido, jugado con el acta aún sin cerrar, con el
acta cargada, de una temporada archivada, y la sección de refuerzos de la plantilla. Arriba de todas, el marcador del
partido (de la federación, no se toca) y el navegador entre partidos (§3).

**5a · La convocatoria es una lista de la plantilla entera, con acciones en bloque** (el desarrollador). Cada
jugador del equipo, y los refuerzos apuntados, en una fila con su estado. **Sin fila, «No convocado»** (enmienda a
`D-41`, en `D-134`): el club no apunta a quien no va. **Ordenada por dorsal**, y sin dorsal, por nombre; **el orden
no cambia al apuntar**.

| Antes del partido | Qué hay |
|---|---|
| Una casilla en cada «No convocado» y un botón **«Apuntar»** | Los marcados quedan **«Convocado»** |
| Columna **«Apuntar como»**: «Baja médica» y «Sancionado», uno encima de otro | Quien lo tiene elegido queda con ese estado; elegirlo marca la casilla y pulsarlo otra vez lo quita |
| En cada fila apuntada, solo el icono **«Anular»** | Vuelve a «No convocado». Para cambiar un estado, se anula y se vuelve a apuntar |
| «+ De otro equipo del club» | Apuntar a un refuerzo (decisión 3): un buscador de los jugadores del club en la plantilla de otro equipo esa temporada; el elegido queda «Convocado». **El mismo botón en las tres situaciones** que se pueden cambiar (después de la hora, «Convocado sin minutos»), y no hay otro «+ Añadir jugador»: los del equipo ya están en la lista (`R7.3`, P7) |

**5b · Desde la hora de comienzo, una tabla de qué estado pasa a cuál** (el desarrollador): **nada cambia solo**,
porque la web no puede saber quién salió. Antes de la hora, el servidor rechaza un «Jugado», un gol o una tarjeta
(422; `R7.3`, P3). Cada acción, en bloque (casillas y botón) y en cada fila (su icono):

| Estado | Acciones |
|---|---|
| **Convocado sin minutos** | **Ha jugado** (→ Jugado) · **Anular** (→ No convocado) |
| **No convocado** | **Apuntar**, con «Apuntar como» si es baja médica o sanción |
| **Baja médica** · **Sancionado** | **Anular** (→ No convocado) |
| **Jugado** | **Anular** (→ Convocado sin minutos; el servidor borra los minutos, `R7.3`, P4) |

**«Convocado» y «Convocado sin minutos» son el mismo estado guardado** (`convocado_sin_minutos`, `D-132`): antes del
partido se rotula «Convocado» (azul) y desde la hora de comienzo, «Convocado sin minutos» (ámbar). **Los minutos, solo
en «Jugado»**, opcionales: vacío es «jugó, no sé cuánto» (`D-14`); **de 1 a 120** (`R7.3`, P9).

**5c · Con el acta cargada, la convocatoria se puede corregir** (el desarrollador, 2026-11-23): en categorías
inferiores el árbitro no siempre apunta todos los cambios. La misma tabla de la 5b, y dos avisos **que no molestan
en cada cambio** (descartada una ventana que salte a cada uno: el club la vería toda la temporada):

- **Un recuadro ámbar fijo** encima de la tabla: es la convocatoria del acta; se puede corregir, pero lo cambiado
  deja de coincidir con el acta oficial.
- **La marca «Cambiado por el club»** en cada fila cuyo estado no es el que trajo el acta. El servidor lo sabe por la
  copia del acta que guarda el partido (5i).

**5d · El gol** (el desarrollador, `D-135`): el formulario pide todo, opcional (decisión 7), con estos cambios al
modelo del LLD:

| Dato | Cómo queda |
|---|---|
| Equipo que marca | Arriba del todo: el del club o el rival |
| Goleador | **«En propia puerta» a la izquierda del goleador**, porque cambia la lista: en un gol del rival, fijo «Jugador rival»; en propia puerta, el que la mete |
| Tipo de jugada | **De jugada · Falta directa · Tras una falta · Tras un córner · Penalti** (en propia puerta, no se pregunta). «Falta directa» es la que va a gol sin tocar nadie más |
| Asistencia | Sí o no, y de quién (del club solo en los goles del club) |
| Zona | Área chica · Área de penalti · Fuera del área; **en un penalti, sin «Fuera del área»**, y el servidor lo rechaza |
| Lado | **Dos: el del ataque** (por dónde viene la jugada) **y el del remate** (desde dónde se remata); en un penalti, solo el del ataque |
| Parte del cuerpo | **Pie izquierdo · Pie derecho · Cabeza · Otro** |
| **Comentarios** | Texto libre, nuevo: lo que no cabe en lo de arriba. En la tabla de goles, una columna que se corta y se lee entera al pasar el ratón |

**La lista del goleador, del asistente y del jugador de la tarjeta: todos los de la convocatoria de la página** (la
plantilla y los refuerzos apuntados), en su orden, sin separar a los convocados (`R7.3`, P6): es poco importante,
porque luego la federación lo marca bien (el desarrollador).

**Obligatorio, solo el equipo que marca**; en la tarjeta, el jugador y la tarjeta (`R7.3`, P5): **nada obligatorio
que la federación pueda no traer**, porque lo que dice no se rechaza (el desarrollador).

**Con el acta cargada**, lo que trae la federación queda fijo: equipo, goleador, propia puerta, minuto y si fue
penalti; el gol no se añade ni se borra. **El club completa la categorización fina**: el tipo (sin «Penalti» si la
federación dice que no lo fue: «La Federación solo dice que no fue penalti: elige cuál de los otros»), asistencia,
zona, lados, parte del cuerpo y comentarios.

**5e · La tarjeta** (`D-136`): jugador, minuto, **Amarilla · Roja directa · Segunda amarilla** y **comentarios**,
nuevo. «Segunda amarilla» se rotula así y no «roja por doble amarilla», con **dos cartulinas amarillas** de icono: ya
se sabe que es roja, y así no se confunde con amarilla y luego roja directa (`D-45`). **Las del rival no se apuntan.**
Con el acta cargada, jugador, minuto y tarjeta quedan fijos; solo se escribe el comentario, y no se añade ni se borra.

**5f · La temporada archivada, solo lectura y en tono de archivo** (`DW-26`, para toda la web): sin casillas, iconos
ni botones; el fondo de la página y de las tablas, cálido y apagado con rayas suaves, y un sello junto al título.
Hoy la web no abre las temporadas archivadas, ni escribiendo su dirección (`R6.18`, decisión 2): se recuperan desde
Temporadas en la rebanada 11. Así que en esta rebanada el aspecto de archivo y el solo lectura se construyen y se
prueban con pruebas de piezas y en el servidor (`SEASON_ARCHIVED`), como hizo la `R6`, y sus escenarios llegan con la
rebanada 11 (`R7.3`).

**5g · El navegador entre partidos**, como el de la jornada y clasificación, con la jornada, la fecha, 🏠 o ✈️ y el
rival en cada opción (§3).

**5h · En el móvil**, cada jugador de la convocatoria es una ficha de dos o tres renglones (casilla, dorsal, nombre e
iconos; el estado y los minutos; «Apuntar como»), y el navegador, un solo renglón con «‹» y «›».

**5i · Cómo sabe el servidor qué ha cambiado el club** en una convocatoria cargada del acta (5c).
`D-133` descartó que cada apunte recordara su origen; la marca lo pide.

| Opción | Qué supone |
|---|---|
| **A · El partido guarda la convocatoria del acta tal como llegó** (una columna en `matches`, la lista de jugador y estado) y la respuesta del acta compara | **Elegida** (el desarrollador, 2026-11-23). Una sola escritura, en la carga; anular a uno del acta borra su fila y se sigue viendo que el acta lo traía. Encaja en una tabla que ya hay |
| B · Cada convocatoria guarda el estado que trajo el acta (una columna en `appearances`) | Anular a uno del acta no puede borrar su fila sin perder la marca: tendría que quedar con un estado `no_convocado`, al revés que en la 5a |
| C · Sin marca: solo el recuadro | Nada nuevo en el servidor; no se ve qué se cambió |

### Decisión 6 · La convocatoria, jugador a jugador, como dice `D-44`

**Es el camino de la web a nuestro servidor**: la federación no tiene entrada; lo que trae, lo escribe la ingesta
por dentro (decisión 1).

| Opción | Elegida |
|---|---|
| **Jugador a jugador** (`D-44`): cada cambio, un envío | **Sí** (el desarrollador, 2026-11-22) |
| La convocatoria entera de un equipo en un partido, de una vez | |

**Por qué**: con la federación trayendo la convocatoria, lo normal en la web es retocar a un jugador (su estado, sus
minutos, su dorsal). Convocar un equipo entero a mano será raro. Si la federación catalana no publica el acta,
se vuelve a mirar. Sin entrada nueva en la bitácora: `D-44` sigue igual.

### Decisión 7 · Qué se pide de cada gol: todo, opcional; y el gol «normal» de la federación, sin tipo (`D-131`)

| Dato | Valores (LLD §3.3) | ¿Lo trae la federación? |
|---|---|---|
| Quién marca | Un jugador del club; en un gol del rival, nadie | Sí, en los del club |
| Minuto | 0 a 120 | Sí, siempre |
| Tipo de jugada | Jugada, penalti, falta, en propia puerta | A medias: penalti (`101`) y propia puerta (`102`); su gol normal (`100`) puede ser de jugada o de falta |
| ¿Con asistencia?, y de quién | Sí o no, y un jugador del club | No |
| Zona · lado · parte del cuerpo | Área chica, de penalti, fuera · derecha, izquierda, centro · pie, cabeza, otro | No |

**7a · La web pide todo, opcional**, en el formulario del gol (el desarrollador, 2026-11-22): es lo que usa la R10, y
el club lo completa partido a partido. También en los goles del rival (`D-09`). Descartado pedir solo quién, minuto
y tipo: los partidos de estos meses se quedarían sin desglose.

**7b · El gol normal de la federación se carga sin tipo** (el desarrollador): **el club lo ve vacío y lo elige**, que
para eso está la pantalla. Descartado ponerle «de jugada»: parecería un dato seguro sin serlo.

### Decisión 8 · Qué partidos tienen acta, y cuándo se lee de la federación: tres situaciones (`D-130`)

**Lo que hay** (2026-11-22), en los partidos de los equipos del desarrollador: en 2025/26, 54 jugados y 2 descansos;
en 2026/27, 37 jugados, 105 por jugar y 4 descansos; ninguno aplazado ni suspendido (la ingesta aún no lo lee).

**Tres situaciones** (el desarrollador, 2026-11-22):

| Partido | Acta | La federación | La web |
|---|---|---|---|
| **Entre dos rivales, o jornada de descanso** | **Sin enlace ni página** | — | — |
| **Con el acta cargada** | Sí | **Ya no se lee** | **El club completa el desglose**: lo que la federación no publica |
| **Todos los demás** | Sí | **Se carga una vez, cuando la federación la cierra** (decisión 11) | **Antes de la hora de comienzo, solo la convocatoria**; después, todo |

*Enmendada por la decisión 11 (2026-11-22): la federación publica el acta de una vez, firmada; no se trae «en cada
pasada, lo que haya». Y antes del partido la web solo apunta la convocatoria, que más adelante podrá enlazarse con
mensajería (WhatsApp, una aplicación para jugadores y padres).*

**Descartada** una regla por estados con goles y tarjetas solo en los jugados: la federación los trae cuando los
tenga, y el club también puede apuntarlos. **La temporada pasada** cae en la segunda situación: el club puede
completarla. **La archivada, solo lectura**, como todo lo archivado (`SEASON_ARCHIVED`, R6). Si el club puede
corregir lo que trajo la federación, y no solo completarlo, es la decisión 11.

### Decisión 9 · El código del jugador en la federación y quién casa: en el perfil, y el conector (`D-126`, enmienda a `D-119` y `D-120`)

**Lo medido** (2026-11-22), comparando la ficha de equipo de la RFFM con las actas, sin nombres:

| Qué | Lo que sale |
|---|---|
| ¿El mismo código en la ficha y en el acta? | Sí: en las 631 coincidencias de código, coincide también el nombre |
| ¿Dura entre temporadas? | Sí: 36 de los 42 jugadores de las actas de 2025/26 siguen hoy en una ficha del club, con el mismo código |
| Casar el acta por el código, esta temporada | 631 de 665 (95 %); los 34 restantes, 7 jugadores de un equipo que no están en ninguna ficha enganchada |
| Casar el acta por el nombre | 391 de 432 (90 %); 7 de los 41 que no casan tienen su código en la ficha: el club corrigió el nombre |

| Opción | Elegida |
|---|---|
| No guardarlo; casar por el nombre | |
| **Guardarlo en el perfil, opcional** | **Sí** |
| Guardarlo en la fila de cada temporada | |

**Quién casa: el conector de cada federación** (lo propuso el desarrollador), que sabe qué es lo mejor que publica:
la RFFM, primero por su código y, si no hay, por el nombre exacto con las reglas de la plantilla; una federación sin
código, solo por el nombre. **Sin leer la base**: la aplicación le pasa nuestra lista (identificador, nombre y
código si lo hay) y el conector devuelve las parejas y los que no casan. **Todo se escribe con nuestro
identificador**; al casar por el nombre a uno sin código, se le guarda el suyo. **La sincronización de la plantilla
usa el mismo casado.** Lo que se asume: el conector ya no solo traduce, también decide quién es quién.

### Decisión 10 · El jugador del acta que no casa, y el acta que llega antes que la plantilla

**Lo medido** (2026-11-22), en las **37 actas de esta temporada** de los equipos del desarrollador, casando por el
código (decisión 9): en **27** están todos en la ficha de su equipo; en **10** hay alguno que no, **7 jugadores** en
total, sin goles y con 4 tarjetas. De los 9 equipos del club, solo 3 tienen plantilla en el sistema.

**10a · El acta que llega antes que la plantilla: la ingesta sincroniza la plantilla** (el desarrollador,
2026-11-22). El club tiene hasta el primer partido de liga para sincronizarla con el botón; si no lo ha hecho, **con
la primera acta la sincroniza la ingesta**, la misma sincronización, que solo añade (`D-120`). Descartado que el
acta espere a que el club pulse el botón: en 6 de los 9 equipos no cargaría.

**10b · El jugador del acta que no está en la plantilla: se da de alta** (el desarrollador, 2026-11-22). Los 7 son
un fallo de la propia federación, que pone en el acta a jugadores que su ficha de equipo no lista; **si juega, tiene
los papeles en regla**. Tres casos:

| El jugador del acta… | Qué se hace |
|---|---|
| No está en ninguna plantilla del club esa temporada | **Alta en la plantilla del equipo del acta**, como la sincronización: con su perfil si casa (decisión 9) o uno nuevo, sin año |
| Está en la plantilla de otro equipo del club | **No se da de alta**: sus apuntes guardan el equipo con el que jugó y sale en los refuerzos de la plantilla (decisión 3) |
| El club lo dio de baja en ese equipo | **Se da de alta otra vez**: si ha jugado, no está de baja. Al revés que la sincronización, que respeta la baja (`D-120`, punto 3) |

Descartados: saltarse lo suyo (no llegaría nunca) y dejarlo pendiente hasta que el club lo dé de alta (la
federación ya dice que puede jugar).

### Decisión 11 · El acta se carga una vez, cuando la federación la cierra; en la convocatoria manda el acta (`D-133`)

**Lo que sabe el desarrollador**: el acta es un único acto en el tiempo; la federación no la publica por partes, y
las revisiones son muy escasas. La ingesta del sábado por la noche ya debería cargar los partidos del sábado.

**Lo medido** (2026-11-22): la página del acta existe también antes del partido. En los 6 próximos partidos del club,
el de la semana que viene trae **`acta_cerrada = 0`**, sin hora, sin marcador y sin jugadores; los 5 del fin de semana,
**`acta_cerrada = 1`**, con marcador y de 13 a 18 jugadores por equipo. Las 91 actas de la decisión 1, todas a `1`.

**Cuándo se carga** (el desarrollador, 2026-11-22):

1. En cada pasada, la ingesta pregunta por **los partidos del club cuya fecha y hora de comienzo han pasado** y que no
   tienen el acta cargada; sin hora, cuenta el final del día.
2. **Solo carga si `acta_cerrada = 1`** (el acta firmada). Con `0`, aunque la página exista o el partido esté en juego,
   nada; se vuelve a preguntar en la pasada siguiente. **Si la federación falla o tarda, igual**: nada, ni a medias
   (`R7.3`, P8).
3. **Una vez cargada, el partido queda marcado** («acta cargada», con la fecha) y no se vuelve a leer. Una revisión
   de la federación la corrige el club a mano.

**Qué apunta la web**: antes de la hora de comienzo, **solo la convocatoria**, con su estado previsto («Convocado
sin minutos», no convocado, baja médica, sancionado; «jugado», todavía no); después, todo.

**En la carga, lo que ya hay**:

| Lo que trae el acta | Lo que tiene el club | Qué hace la carga |
|---|---|---|
| Un jugador | Su convocatoria, en cualquier estado | **Manda el acta**: el estado (jugado, o «Convocado sin minutos» si es suplente sin cambio) y el dorsal; los minutos del club no se tocan |
| Un jugador | Nada | La crea |
| — | Un jugador que el acta no trae | Lo deja |
| Una tarjeta o un gol | El mismo apunte (en el gol: equipo, goleador y minuto) | Lo deja |
| Una tarjeta o un gol | Nada | Lo crea |

**Descartado** que cada apunte recuerde si vino de la federación y si el club lo cambió: con una sola carga basta la
marca del partido. **Lo que se asume**: un gol repetido si el club y la federación ponen minutos distintos; lo borra
el club.

### Decisión 12 · Los minutos no se calculan; el suplente sin cambio, «Convocado sin minutos» (`D-132`)

**Lo medido** (2026-11-22) en las 91 actas: **81 sin ningún cambio** apuntado (49 cambios en total); 11 titulares
en 67 actas y de 12 a 14 en las otras 24; y la «participación» marcada sin regla (594 titulares con «sí» y 463 con
«no»; 39 actas con todos a «sí», 37 con todos a «no» y 15 mezcladas).

**12a · Los minutos no se calculan** (el desarrollador, 2026-11-22): con cambios en 1 de cada 9 actas, saldrían
números falsos. Son del club, opcionales; vacío es «jugó, no sé cuánto» (`D-14`).

**12b · Quién jugó**:

| Opción | Elegida |
|---|---|
| Todos los del acta, «jugado» | |
| **«Jugado» los titulares y los que entran en un cambio; los demás suplentes, un estado nuevo** | **Sí** |
| Los demás suplentes, sin convocatoria | |

**El estado nuevo se rotula «Convocado sin minutos»** (el desarrollador): estuvo en el acta, y no consta que jugara.
El club lo cambia a «jugado» si salió. Es un quinto estado de la convocatoria (enmienda a `D-41`).

---

## 5. Lo que le falta al servidor

**Hoy no hay nada del acta**: ni las tablas ni el código. Las 16 operaciones están en el catálogo desde F1, y
`R7.4` las pone al día y añade la 89, la de los refuerzos (`D-128`). Lo que se programa en la fase B:

| Qué | Operaciones | Paso |
|---|---|---|
| **El partido**: la cabecera del acta, con la fecha de la carga y los que el club ha quitado del acta | `getMatch` | `R7.6` |
| **La convocatoria**, con el equipo, el dorsal del acta, los estados por la hora de comienzo y la marca de lo cambiado | `listAppearances`, `getAppearance`, `createAppearance`, `updateAppearance`, `deleteAppearance` | `R7.6` |
| **Los goles**, con los dos lados, los seis tipos, el comentario y lo bloqueado del acta | `listGoals`, `getGoal`, `createGoal`, `updateGoal`, `deleteGoal` | `R7.7` |
| **Las tarjetas**, con el equipo, el comentario y lo bloqueado del acta | `listCards`, `getCard`, `createCard`, `updateCard`, `deleteCard` | `R7.8` |
| **Los refuerzos** de la plantilla, ya contados | `listTeamReinforcements` (la 89) | `R7.9` |
| **Las tres tablas y lo nuevo del partido y del perfil** (la copia del acta, su fecha, el código de la federación) | — | `R7.5` |
| **La carga del acta** con la ingesta, el adaptador y la federación falsa | — | `R7.11` a `R7.13` |

**Los códigos de error nuevos**, descritos en el catálogo y añadidos a `ProblemCode` cuando el servidor los emita
(como en la `R6`): `MATCH_NOT_FOUND`, `MATCH_NOT_STARTED`, `MATCH_REPORT_LOADED`, `LOCKED_BY_MATCH_REPORT`,
`TEAM_NOT_IN_MATCH`, `PLAYER_NOT_IN_SEASON`, `STATUS_CHANGE_NOT_ALLOWED` y `LOOSE_YELLOW_EXISTS`.

---

## 6. Los escenarios

*(Escritos en `R7.3`, con la* skill *de escenarios, sobre la lista de casos que aprobó el desarrollador. Sus pasos
se definen con la web y se ponen en verde en la fase D.)*

| Fichero | Escenarios | Qué cubre |
|---|---|---|
| `acta.feature` | 19 | Entrar desde Resultados, la cabecera, las tres situaciones, «No se ha encontrado el partido» y el navegador de partidos |
| `acta-convocatoria.feature` | 43 | Los estados de cada jugador, los minutos, los refuerzos, el contador y lo que cambia con el acta cargada |
| `acta-goles.feature` | 32 | Apuntar, corregir y borrar un gol; lo obligatorio, el desglose, la propia puerta y el penalti; los de la Federación |
| `acta-tarjetas.feature` | 18 | Apuntar, corregir y borrar una tarjeta; la segunda amarilla; las de la Federación |
| `acta-federacion.feature` | 30 | La carga del acta con la ingesta: cuándo se pide, cada jugador, los goles y las tarjetas |
| Añadidos a `resultados`, `jornada` y `plantilla` | 4 + 2 + 6 | El enlace al acta desde el marcador; la etiqueta del selector de jornada; los refuerzos |

**Lo que no tiene escenario en esta rebanada:** la temporada archivada (decisión 5f), porque la web aún no la abre;
lo cubren las pruebas de piezas y del servidor, y sus escenarios llegan con la rebanada 11.

---

## 7. Los pasos

### A · Las decisiones y los escenarios

| Paso | Qué |
|---|---|
| `R7.1` | La revisión de las decisiones con el desarrollador, una a una |
| `R7.2` | Los documentos de lo decidido: la bitácora del backend (`D-nn`), el LLD-B y su anexo si hace falta (`DW-nn`), y esta ficha al día |
| `R7.3` | Los escenarios escritos y revisados, sin definir |

### B · El servidor

*(Apuntados el 2026-11-24, al cerrar `R7.3`. Cada operación, a la tabla del README del backend en su paso.)*

**B1 · Lo que apunta el club** (`feature/r7-acta-backend-1`)

| Paso | Qué |
|---|---|
| `R7.4` | **La mini-fase del catálogo**, solo documentos: lo que cambia en `openapi.yaml` en las 16 operaciones del acta y sus respuestas: el estado «convocado sin minutos» (`D-134`), el equipo del apunte (`D-128`), el dorsal de solo lectura (`D-129`), los campos del gol (`D-135`) y de la tarjeta (`D-136`), y en `getMatch` el acta cargada con su fecha y su copia de la convocatoria (`D-133`); los errores nuevos (antes de la hora, minutos fuera de 1 a 120, un cambio de estado no permitido, un penalti fuera del área, la segunda amarilla con una amarilla suelta); cómo se piden los refuerzos; el código de la federación en el perfil (`D-126`); y la enmienda al LLD del backend |
| `R7.5` | **Las tablas y sus reglas**, en ciclos TDD: la migración (convocatoria, goles y tarjetas; en el partido, la copia del acta y su fecha; en el perfil, el código); en el dominio, los cambios de estado, los minutos, el penalti, la segunda amarilla y lo que no se apunta antes de la hora |
| `R7.6` | **`getMatch` y la convocatoria**, en ciclos TDD: sus cinco operaciones, con los minutos borrados al anular un «Jugado» (`R7.3`, P4) |
| `R7.7` | **Los goles**, en ciclos TDD: sus cinco operaciones |
| `R7.8` | **Las tarjetas**, en ciclos TDD: sus cinco operaciones |
| `R7.9` | **Los refuerzos de la plantilla**, en ciclos TDD: los de otros equipos del club que han jugado con este, con su equipo y su participación (decisión 3) |
| `R7.10` | **El cierre de B1**: tests, mutación, censo |

**Decisiones de `R7.4`** (2026-11-24), una a una con el desarrollador, al cruzar el contrato con `D-125` a `D-136`:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Qué gol y qué tarjeta trajo el acta** (el servidor no lo sabía, y el gol repetido de `D-133` no se podía borrar con el acta cargada) | Que cada uno lo recuerde, o todo bloqueado con el acta cargada | **Que cada uno lo recuerde** (`D-137`): en los del acta, lo de la federación no se cambia y no se borran; los del club se corrigen y se borran igual. En los escenarios, «ningún gol tiene Borrar» pasa a «ningún gol de la federación», y entra el caso más cercano: el del club sí lo tiene (dos escenarios más, 154 en la rebanada) |
| **2 · El equipo de cada convocatoria y cada tarjeta** (`D-128`) | Obligatorio en la petición, o deducido de la plantilla si no se manda | **Obligatorio** (nota en `D-128`): en un partido entre dos equipos del club es la única forma de saber cuál es; el servidor comprueba que juegue el partido |
| **3 · Quién compara la convocatoria con el acta**, para «Cambiado por el club» (`D-134`, punto 4) | El servidor, o `getMatch` devuelve la copia y compara la web | **El servidor** (nota en `D-134`): cada fila dice si ha cambiado, y `getMatch` trae la fecha de la carga y los que el acta traía y ya no tienen fila |
| **4 · Cómo se piden los refuerzos** de la plantilla (decisión 3) | Una operación nueva que los trae contados, o abrir `listAppearances` a equipo y temporada y que cuente la web | **Una operación nueva**, la 89 (nota en `D-128`): de cada refuerzo, su equipo, sus actas, las jugadas, las de sin minutos y el último partido; cuenta el servidor, como las demás agregaciones |

**B2 · La carga del acta de la federación** (en su propia rama, como la sincronización de la `R6`)

| Paso | Qué |
|---|---|
| `R7.11` | **El adaptador de la RFFM lee el acta**, en ciclos TDD, con una grabación de verdad con los nombres y los códigos cambiados (como en `R6.14`, decisión 2); la traducción de los códigos de gol y de tarjeta (`D-131`) |
| `R7.12` | **La ingesta**, en ciclos TDD: qué partidos pregunta y cuándo carga (`D-133`); el casado por código o por nombre (`D-126`); el alta del que no está en ninguna plantilla, el refuerzo del de otro equipo, y la plantilla sincronizada si no lo estaba (decisión 10); sin repetir lo que el club ya apuntó |
| `R7.13` | **La federación falsa** de los escenarios publica el acta de cada uno, con su fallo y su espera; y **el cierre de B2**: tests, mutación, censo |

**Decisiones de `R7.12`** (2026-11-25), una a una con el desarrollador, al diseñar la carga (`D-138`):

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Dónde va la carga en la pasada, y qué pasa si falla un acta** | Una cuarta pasada con su fila, o sumada a la del calendario; que un acta fallida hunda la competición o no | **Una cuarta pasada, «las actas», con su fila** en `ingestion_runs` (tipo nuevo, con migración). Cada acta en su transacción: la que falla no se carga, se cuenta y se reintenta en la pasada siguiente; **no hace fallida la competición** |
| **2 · Qué temporadas** | Solo la en curso; la en curso y la pasada si se pide; siempre las dos | **La en curso siempre; la pasada, solo si se pide su temporada** (`POST /ingestion-runs` con `seasonId`), como el resto de la pasada. La archivada, nunca. Sin plantillas en la pasada: sus jugadores entran por el alta del acta (`D-127`), casados por el código si lo tienen |
| **3 · Qué apunta la pasada** | Contadores y motivos como las otras pasadas, o solo los motivos | **Como las otras**: cuatro contadores (actas cargadas, sin cerrar, fallidas; jugadores dados de alta por el acta) y tres motivos de omitido (código desconocido, nombre que no se lee, acta que no se pudo leer), con el código del acta. **Cambia el contrato**: el tipo `kind` nuevo, los contadores y los motivos; primero el catálogo, como en `R7.4` |
| **4 · El jugador con un nombre que no se lee** | Casar por el código o dejarlo fuera; o no cargar el acta | **Por el código, si casa**; si no, sin alta ni convocatoria, sin su tarjeta, y su gol sin goleador; apuntado como omitido. Medido: ninguno en 1631 apariciones del club en 95 actas |
| **5 · Lo del rival** | — (confirmar lo decidido) | **Sus jugadores y sus tarjetas, nada** (`D-136`); **sus goles, sin goleador** (`D-09`); en propia puerta, el de un rival es gol del club sin goleador, y el de uno del club, gol del rival a su nombre (`D-52`). Los goles de cada lado cuadran con el marcador |
| **6 · El partido entre dos equipos del club** (2 de 95) | — | **Los dos lados, como del club**: cada convocatoria y tarjeta con su equipo (`D-128`); **el gol en propia puerta, a nombre del que lo mete**, del equipo que encaja, sin contarle como goleador (`D-52`); y si falta, la sincronización de los dos |
| **7 · Que el acta sea de ese partido** | — | **Sus dos códigos de equipo, los de nuestro local y visitante**; si no, no se carga, cuenta como fallida y se reintenta, como el calendario con el nombre de la competición |

### C · La web (otra rama)

### D · Los escenarios en verde y el cierre

---

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| **R7.1** | ✅ 2026-11-23 | Las doce decisiones, una a una: lo medido en 91 actas y en las fichas de la RFFM (sin sacar nombres), y la decisión 5 sobre una maqueta en HTML en cinco situaciones, en oscuro, en claro y a 375 px |
| **R7.2** | ✅ 2026-11-23 | En la bitácora del backend, `D-125` a `D-136`, con las notas de enmienda en `D-41`, `D-119`, `D-120`, `D-125`, `D-130` y `D-133`; en el anexo de la web, `DW-26`, y en el LLD-B, §6.1 (el camino) y §9.9 (la temporada archivada); en el plan del backoffice, el mapa (Acta y Plantilla en ámbar) y la fila 7. Revisado con `git diff --numstat`: ninguna tabla ensanchada |
| **R7.3** | ✅ 2026-11-24 | La lista de casos, aprobada con sus doce dudas resueltas (P1 a P12, apuntadas en el plan y la bitácora); 152 escenarios nuevos (§6). La pasada en seco de Cucumber los lee todos (445: 152 sin definir y los 293 de antes intactos). Los de la temporada archivada, fuera hasta la rebanada 11 (decisión 5f) |
| **R7.4** | ✅ 2026-11-24 | **El catálogo, con cuatro decisiones** revisadas una a una (`D-137` y notas en `D-128` y `D-134`). En `openapi.yaml`, las 16 operaciones del acta al día y la 89, la de los refuerzos (8.462 líneas, 89 operaciones en 50 rutas); el LLD del backend, §3.2, §3.3 y §5.1. El servidor compila, sus 1062 tests en verde (3 omitidos) y el censo, con dos huecos nuevos apuntados (`reportLoadedAt` y `federationPlayerId`, que llegan en `R7.5` y `R7.12`). El linter del catálogo (Redocly 1), válido, pasado por el desarrollador |
| **R7.5** | ✅ 2026-11-24 | **Las reglas del acta en el dominio** (`MatchReport.swift`, 34 tests): la hora de comienzo (sin hora, el final del día de Madrid), los minutos (1 a 120), el minuto (0 a 120), el comentario (recortado, hasta 500), el equipo y el jugador del apunte, los cambios de estado, la forma del gol y de la tarjeta, y lo que el acta deja fijo; siete códigos de error nuevos, traducidos a 422 y apuntados en el censo hasta sus operaciones. **Las migraciones 25ª y 26ª**: las tres tablas, con 20 `CHECK` y sus índices, y en el partido y el perfil la copia del acta, su fecha y el código de la federación (21 `CHECK` más en total, 47), probadas contra Postgres (17 tests). **1113 tests** (1110 + 3 omitidos) y el censo, en verde |
| **R7.6** | ✅ 2026-11-24 | **`getMatch` y las cinco operaciones de la convocatoria**, servidas (**33 de las 89**). `getMatch` lee el partido como la lista (`D-112`), con la fecha de la carga y los que el club ha quitado del acta; uno entre dos rivales es 404 `MATCH_NOT_FOUND` (`D-130`). La convocatoria: el equipo del apunte (`D-128`), el estado según la hora (`D-133`), solo «Convocado sin minutos» ↔ «Jugado» (`D-134`), los minutos que se borran al dejar «Jugado» (P4) y `changedFromReport`, que compara el servidor. Tres códigos nuevos: `MATCH_NOT_FOUND`, `APPEARANCE_NOT_FOUND` y `PLAYER_ALREADY_CONVOKED` (409, mirado antes de escribir). **Decidido al construir**: en este `PATCH` un `null` es como no mandar el campo, porque el generador no los distingue (`D-65`); escrito en el contrato y en el LLD §5.1. La copia del acta se lee aparte del partido, para que guardar el partido (la ingesta del calendario) no la pise. **1156 tests** (1153 + 3 omitidos), censo en verde |
| **R7.7** | ✅ 2026-11-24 | **Las cinco operaciones de los goles**, servidas (**38 de las 89**). El que encaja lo pone el servidor (`D-54`); el goleador y el asistente, del club en la temporada y del lado propio (`D-52`, `D-128`): uno del club en el lado del rival es 422 `INVALID_VALUE`; desde la hora y sin el acta cargada (`D-133`, `D-137`); el penalti sin fuera del área ni lado del remate (`D-135`); y en uno del acta, el goleador, el minuto y el penalti o la propia puerta, fijos, y no se borra. La lista, paginada, por minuto con el partido y por fecha sin él, con la temporada por la competición (`D-28`). Un código nuevo: `GOAL_NOT_FOUND`. Como en la convocatoria, en el `PATCH` un `null` no borra. **1182 tests** (1179 + 3 omitidos), censo en verde |
| **R7.8** | ✅ 2026-11-24 | **Las cinco operaciones de las tarjetas**, servidas (**43 de las 89**): con el equipo del partido (`D-128`), desde la hora y sin el acta cargada (`D-133`, `D-137`), una de cada tipo (409 `CARD_ALREADY_RECORDED`), la segunda amarilla, una roja y sin una amarilla suelta (`D-45`, 422 `LOOSE_YELLOW_EXISTS`), y en una del acta, solo el comentario, sin borrarla (`D-136`, `D-137`). La lista, por minuto con el partido y por fecha con el jugador. Dos códigos nuevos: `CARD_NOT_FOUND` y `CARD_ALREADY_RECORDED`. Con esto, todos los códigos del acta se prueban por HTTP y salen de la lista de huecos del censo. **1199 tests** (1196 + 3 omitidos), censo en verde |
| **R7.9** | ✅ 2026-11-24 | **Los refuerzos de la plantilla**, la operación 89, servida (**44 de las 89**): refuerzo es quien tiene una convocatoria de este equipo en la temporada sin estar en su plantilla (`D-128`); de cada uno, su equipo, sus actas, las jugadas, las de sin minutos y el último partido, contados en el servidor (§3.4); por el último partido y el nombre; sin refuerzos, lista vacía (P11). **1204 tests** (1201 + 3 omitidos), censo en verde |
| **R7.10** | ✅ 2026-11-25 | **El cierre de B1.** Mutación **37/37** sobre el código final (`Tools/Mutate/Catalogs/R7-10.json`): la hora de comienzo, los valores, el equipo y el jugador del apunte, los estados y los minutos, lo que el acta deja fijo, el penalti, la propia puerta, la segunda amarilla, lo que ha cambiado el club, los refuerzos, el orden de las lecturas, la copia del acta y tres restricciones de la base. **1204 tests** (1201 + 3 omitidos) y el censo en verde: todos los códigos del acta se prueban por HTTP. El servidor sirve **44 de las 89** operaciones. Lo siguiente, B2 (la carga del acta), en su propia rama |
| **R7.11** | ✅ 2026-11-25 | **El adaptador de la RFFM lee el acta** (`feature/r7-acta-backend-2`). Medido en las 96 actas cerradas del club, una sin cerrar y un código que no existe (anexo RFFM, final de §F.10): la página `acta-partido/<codacta>` responde con el código solo; el gol en propia puerta viene en la lista del que lo marca y suma al otro (cuadra en las 3 que hay); a un código que no existe, un acta vacía sin equipos. **Cuatro grabaciones** (`Tests/FederationTests/Fixtures/RFFM-acta-*.html`): penalti, roja y segunda amarilla con 7 cambios; propia puerta; sin cerrar; inexistente; las dos primeras con nombres y códigos cambiados por `Tools/Fixtures/anonymize-rffm-match-report.swift`, comprobado aparte que no queda ningún nombre completo ni código de verdad. En el puerto, `fetchMatchReport(federationMatchID:)`, que devuelve el acta ya traducida (`D-131`): el gol normal sin tipo, el penalti, la propia puerta del lado al que suma, la doble amarilla en una roja sin su primera amarilla, y lo que no entiende en `skipped`; sin casar ni escribir nada. **1222 tests** (1219 + 3 omitidos), censo en verde y sin cambios. **Apuntado para `R7.12`**: la capacidad «publica actas» del catálogo, que la pide quien carga; y el 0-3 sin goles (1 de 96), con todos de titulares |

---

## 9. Lo aprendido
