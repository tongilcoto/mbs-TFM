# Plan de desarrollo R3 · Enganche

> Rebanada 3 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Como las
> rebanadas [1](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md) y
> [2](./Plan%20de%20desarrollo%20R2%20Alta%20de%20equipo-001.md), toca la web y el servidor, y lo que se haga en el
> servidor se apunta **solo aquí**.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md); y la rebanada 2, cerrada el
> 2026-10-24 con **743 tests** en el backend y, en la web, **195 pruebas de piezas y 68 escenarios**.
>
> **Convención de remisiones**, la de siempre: `LLD-B §x` y `DW-nn` son el LLD de la web y su anexo; `LLD §x` y
> `D-nn`, el LLD del backend y su bitácora.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: decisiones revisadas.** Las seis decisiones de la §4 se revisaron una a una con el
> desarrollador el 2026-10-25, sobre una maqueta en HTML de las opciones (y, para la 1, de cómo crecen con las
> rebanadas 13 y 14). La revisión cambió la forma de la pantalla (un asistente de dos pasos), añadió un cambio del
> servidor que no estaba previsto (el `/preview` dice qué equipos ya son del club, `D-110`) y el refresco de la
> portada. Los pasos pasan de 13 a 16.
>
> **En la pantalla se dice «Sincronizar», no «Enganchar»** (decidido con la decisión 1). En los documentos sigue
> siendo «el enganche», el nombre de `D-67` y de la operación; lo que lee el usuario es «Sincronizar con la
> Federación».

---

## 1. Objetivo

**El club engancha un equipo con su competición de la federación desde la web**, pegando la dirección del
calendario que ve en la web de la RFFM. Es el segundo paso del alta (Plan R2, §1): en julio se da de alta el
equipo; cuando la federación publica el calendario, se engancha, y desde ese momento la ingesta trae sus
partidos, su clasificación y sus goleadores.

Y estrena **las acciones de cada fila de la portada** (plan del backoffice, §4, «Pendiente de la rebanada 3»):
cómo se ven las cosas que se hacen rápido desde la fila del equipo, sin entrar en su ficha. El enganche es la
primera; relanzar la ingesta (rebanada 14) y lo que la 13 ponga en el menú de la ficha se añadirán al mismo
diseño.

**Por qué ahora**: sin enganche desde la web, un equipo dado de alta en la R2 se queda para siempre en «Sin
competición». Hoy solo se engancha con `curl`.

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **En cada fila de la portada, sus acciones** como iconos, con el primero: sincronizar con la Federación. Y en el equipo sin competición, el enlace «Sincronizar con la Federación» | Ficha, §3.1 · decisión 1 |
| **La pantalla del enganche** (`/equipos/:id/federacion`): pegar la dirección, comprobarla y ver lo que hay en ella | Ficha, §3.2 · decisiones 2 y 3 |
| **Reconocer el equipo propio** entre los del grupo, confirmar el género, y los avisos de lo que no cuadra | Ficha, §3.3 · decisión 4 |
| **Al confirmar**, la vuelta a la portada en la temporada del calendario, con el equipo «En marcha» | Ficha, §3.4 · decisión 5 |
| **Los mensajes de cada error del enganche**, cada uno en su sitio | Decisión 6 |
| En el servidor, **una operación nueva**, `getTeam`, y **el `/preview` dice qué equipos del grupo son ya del club** (`D-110`). Con ello, el servidor sirve **12 de las 85** | §5 · decisión 4 |

**Lo que no trae** (llega después): la ficha del equipo (rebanada 4); relanzar la ingesta desde la fila
(rebanada 14); los escudos de los equipos del grupo (decisión 4); y **deshacer un enganche**, «Dejar de
sincronizar», que **no existe en el catálogo** y se diseña en la rebanada 13 (decisión 1). Mientras tanto, un
enganche equivocado se corrige a mano en la base. Y **el segundo equipo del club en un grupo ya sincronizado**,
que la pantalla avisa pero no puede sincronizar (decisión 4, `D-110`): también a la rebanada 13. *(Este plan decía que lo cubría `releaseTeam`, y no: liberar
deshace una **reclamación**, `claimTeam`, que convierte en propio un equipo que la ingesta creó como rival; no
toca el enganche.)*

---

## 3. La ficha de las pantallas

### 3.1 La portada, con las acciones de cada fila

- **Una columna nueva al final, «Acciones»**, con un **icono por acción** (decisión 1). En esta rebanada, uno
  solo: el de sincronizar, una vez por equipo aunque tenga dos competiciones (como su nombre, `rowspan`).
- **Lo que dice el icono depende del equipo en la temporada elegida**:
  - sin competición: **«Sincronizar con la Federación»**;
  - con alguna: **«Sincronizar otra competición»**. El enganche es aditivo (liga *y* copa, `D-12`), y la otra
    puede ser de la misma temporada o de otra.
- **El texto no se ve** hasta pasar el ratón o llegar con el teclado; el lector de pantalla lo lee siempre, con
  el equipo detrás: «Sincronizar otra competición, Cadete A».
- **El equipo sin competición**, además, cambia su texto: «Pendiente de sincronizar con la Federación» pasa a ser
  el **enlace «Sincronizar con la Federación»**. Es el caso en el que más falta hace, y así no depende de un icono.
- Los dos llevan a `/equipos/:id/federacion`, con la temporada de la portada en el estado de la navegación, para
  que *Cancelar* vuelva a ella (como el alta, Plan R2, decisión 5).

### 3.2 La pantalla del enganche (`/equipos/:id/federacion`)

**Qué pide al servidor al abrir**: `getTeam`, para decir **qué equipo** se engancha. Hace falta aunque se venga
de la portada: al recargar o al abrir la dirección a mano no hay nada más de donde sacarlo.

**Arriba**: el título «Sincronizar con la Federación» y el equipo **siempre con su género y su modalidad**
(«Alevín B · Masculino · Fútbol 7», como en la maqueta D), no el `displayName` del servidor, que no los distingue
(`D-109`). *(Este plan decía «el mismo nombre que en la portada», y la portada solo los añade cuando otro equipo de
la temporada se llama igual (bloque T de la R2): esta pantalla tiene un solo equipo y no puede saberlo. Cambiado en
R3.10.)*

**Dos pasos, en la misma dirección** (decisión 2): «1 La dirección» y «2 Tu equipo», con una línea arriba que
dice en cuál se está.

**Paso 1, la dirección:**

| Campo | Pieza | Obligatorio | Ayuda |
|---|---|---|---|
| **Dirección del calendario** | Texto, ancho | Sí | «Cópiala de la web de la Federación, en la página del calendario del grupo. Por ejemplo: …», con el ejemplo leído del catálogo (`FederationLinkPreviewRequest`, como en la R2) |

- **«Comprobar en la Federación»** envía `previewFederationLink`. Mientras tanto el botón se bloquea y dice
  «Comprobando…»: la federación puede tardar (LLD §5.4). Si va bien, se pasa al paso 2; si no, el error sale en
  el paso 1 (decisión 6).
- **«Cancelar»**, al lado.

**Paso 2, tu equipo** (§3.3): arriba, **la dirección comprobada en una línea**, con dos iconos a la derecha:

- **Editar** (lápiz, «Editar la dirección»): vuelve al paso 1 con la dirección escrita. Lo comprobado se borra:
  lo que se sincroniza es siempre lo que se ha visto.
- **Volver a comprobar** (flecha circular, «Volver a comprobar en la Federación»): repite el `/preview` con la
  misma dirección, sin salir del paso 2, por si la federación ha cambiado algo. Se conserva el equipo elegido
  si sigue en la lista.

Los dos, con las reglas de los iconos de la decisión 1 (texto con ratón y teclado, nombre para el lector).

**Los cuatro estados** (LLD-B §3.1), de lo que se pide al abrir:

| Estado | Cómo se ve |
|---|---|
| **Cargando** | «Cargando equipo…» en el sitio del título |
| **Error** | El mensaje del código, con *Reintentar* si puede ser pasajero (LLD-B §4.4). Si el equipo no existe, «No se ha encontrado el equipo» y un enlace a la portada |
| **Vacío** | No tiene: un equipo existe o no |
| **Con datos** | El paso 1: el campo de la dirección y «Comprobar en la Federación» |

### 3.3 Lo que hay en la dirección, y confirmar

Lo que devuelve el `/preview`, para que una persona reconozca su equipo (`D-16`):

- **La competición**: división, grupo, edad, modalidad y número de jornadas.
- **La temporada**: su etiqueta. Si no existe en el club, «· nueva» y el aviso de que se creará al sincronizar
  (`season.exists`, decisión 3).
- **Si la competición ya la usa otro equipo del club**: «Esta competición ya está en el club; se reutiliza»
  (`alreadyRegistered`). Es informativo, no impide nada.
- **Los equipos del grupo**, para elegir **cuál es el del club** (decisión 4): botones de opción, uno solo y
  obligatorio, con el nombre tal como lo escribe la federación (`rawName`), **por orden alfabético**. **Ninguno
  viene elegido.** Los que llegan sin código, y los que ya están sincronizados con un equipo del club («Ya está
  sincronizado con Alevín A»), se ven pero no se pueden elegir.
- **El género**, un selector con el que propone el `/preview` ya elegido, que se puede cambiar (`D-58`).
- **Si no cuadra con el equipo** (`identityMatches = false`): un aviso que dice **qué** no cuadra («El equipo es
  Cadete y la competición es Juvenil»), y **«Sincronizar» bloqueado**: el servidor lo rechazaría (409).
- **Si la edad no se ha podido comprobar** (`ageCategoryChecked = false`): un aviso de que el nombre de la
  competición no dice la edad, y de que se usará la del equipo. No bloquea.
- **El botón dice lo que va a sincronizar** (idea del desarrollador): «Sincronizar» sin equipo elegido, y
  **«Sincronizar CELTIC CASTILLA C.F. 'B'»** en cuanto se elige uno. Se lee antes de pulsar, y el lector de
  pantalla lo anuncia igual.
- **Sin equipo elegido, el botón se puede pulsar**: sale arriba «Falta un dato: Elige tu equipo» con el enlace a
  la lista, y la lista marcada, como en el alta (LLD-B §5.1). No se bloquea: un botón bloqueado no dice por qué.
- **Al pulsarlo con equipo**, envía `linkTeamToFederation` con la dirección **comprobada**, el código del equipo
  elegido y el género. **Sin `seasonLabel`**: el servidor usa la de la federación (decisión 3).
- **Solo dos botones**: «Sincronizar…» y «Cancelar». Volver al paso 1 es el icono de editar; no hay «Atrás».
- **«Cancelar»** vuelve a la portada de la que se vino, y quita la pantalla del historial (como el alta).
- **Salir con algo escrito o comprobado** pregunta antes (LLD-B §5.5), con el aviso de la R2 (`LeaveDialog`).

### 3.4 Al enganchar bien

- El servidor contesta **202**: el enganche está escrito y la primera ingesta, en cola.
- Sale el aviso **«Sincronizado. La primera ingesta está en marcha.»**, que pone el marco, como «Guardado».
- La web vuelve a la portada **en la temporada del calendario** (`/?temporada=2026-27`), que puede no ser la de
  partida, y quita la pantalla del historial (decisión 5).
- En la portada, el equipo sale con su competición y la ingesta **«En marcha»**, y la portada **se refresca sola**
  mientras haya algo en marcha: cuando acabe, sale como cualquier otro sin recargar (decisión 5).

---

## 4. Decisiones antes de construir

### Decisión 1 · Cómo se ven las acciones de cada fila

**Decidido el 2026-10-25**, sobre una maqueta en HTML con las opciones y con cómo crece cada una al llegar las
acciones de las rebanadas 13 y 14: **iconos con su texto para el lector de pantalla, visible al pasar el ratón o
al llegar con el teclado; y en la fila sin competición, además, el enlace directo.**

| Opción | A favor | En contra | Veredicto |
|---|---|---|---|
| (a) Botón ⋮ con menú | Caben todas las acciones sin ensanchar la tabla | La acción no se ve hasta abrirlo; relanzar la ingesta, que es **de cada competición**, obliga a un apartado con una opción por competición dentro del menú del equipo | Descartada |
| (b) Un botón con texto por acción | Se ve todo | Con cuatro o cinco acciones aprieta la tabla y repite lo mismo en cada línea | Descartada: no escala |
| **(c) Iconos, con su texto al pasar el ratón o con el teclado** | Ocupan poco, y cada uno puede ir **donde está lo que afecta** | Un icono no se lee solo: el texto tiene que llegar también por teclado y al lector (abajo) | **Elegida** |

**Dónde va cada icono:**

- **Las acciones del equipo**, en una columna «Acciones» al final, una vez por equipo (`rowspan`). En la R3, solo
  sincronizar; la 13 añadirá corregir y, sin sincronizar, borrar.
- **Las de una competición, en su celda**: relanzar la ingesta (rebanada 14) va **en la celda «Ingesta» de cada
  competición**, al lado de su estado. Así un equipo con liga y copa tiene uno por competición, sin preguntar
  cuál.

**El texto de la acción de sincronizar**: «Sincronizar con la Federación» si el equipo no tiene competición en la
temporada elegida; «Sincronizar otra competición» si ya tiene alguna (vale para la copa de la misma temporada y
para otra temporada).

**Lo que los iconos tienen que cumplir** (LLD-B §10):

- **Nombre para el lector, con el equipo**: «Sincronizar otra competición, Cadete A». Diez botones iguales no se
  distinguen en la lista de botones de VoiceOver. Y el texto visible está dentro del nombre (WCAG 2.5.3).
- **El texto sale con el ratón y con el teclado**, y *Escape* lo cierra (WCAG 1.4.13). **El `Tooltip` de PrimeVue
  4.5.5 no hace las dos cosas a la vez**: con el modificador `focus` sale al llegar con el tabulador pero ya no al
  pasar el ratón, y sin él, al revés (`primevue/tooltip`, `bindEvents`). *Escape* sí lo cierra. Se resuelve en
  R3.9, con una pieza propia pequeña o envolviendo la de PrimeVue; lo que vale es que los dos caminos funcionen.
- **40 × 40 px** cada icono, como mínimo 24 (WCAG 2.5.8). Cada acción nueva ensancha la columna unos 40 px.
- **La columna «Acciones» no se ordena**, y su cabecera no se ve pero el lector la lee.
- **Iconos reconocibles**: la web todavía no tiene juego de iconos. Se elige en R3.9 (dibujos SVG propios o
  PrimeIcons, cuya licencia se mira antes).

**Y lo que salió al hacer la maqueta, para la rebanada 13:**

- **«Liberar» no es dejar de sincronizar.** `releaseTeam` deshace una reclamación (`claimTeam`): un equipo que la
  ingesta creó como rival y alguien convirtió en propio vuelve a ser rival. Es una corrección de la puesta en
  marcha, rara, y no va en la fila; si acaso, en la ficha del equipo.
- **Borrar no sirve para un equipo sincronizado**: el catálogo lo rechaza (409), porque la federación lo sigue
  publicando y la ingesta lo volvería a crear como rival (`D-21`).
- **Deshacer un enganche, «Dejar de sincronizar», no existe** en el catálogo, y esta rebanada es la que crea el
  riesgo de equivocarse. Decidido con el desarrollador: **se apunta como 🆕 en la rebanada 13** (qué pasa con los
  partidos y la clasificación ya traídos, y con la competición si la usa otro equipo del club, `D-101`), y la R3
  no ofrece nada.

**Dónde se escribe**: es una regla para todas las tablas con acciones (Rivales, Temporadas, Personal…), así que
va al LLD-B, con su porqué en `DW-19` (R3.2).

### Decisión 2 · La pantalla del enganche: dos pasos, comprobar y después elegir el equipo

**Decidido el 2026-10-25**, sobre la maqueta: **un asistente de dos pasos en la misma dirección**, con lo que
el desarrollador cambió al verlo (abajo).

| Opción | Veredicto |
|---|---|
| (a) Una página: el campo arriba, lo comprobado debajo | Descartada: el desarrollador prefiere separar los dos momentos, pegar y reconocer |
| **(b) Dos pasos: 1, la dirección; 2, tu equipo** | **Elegida.** Cada paso hace una cosa; en el 2 la dirección sigue a la vista en una línea |
| (c) Un diálogo sobre la portada | Descartada: la lista de equipos del grupo (de 12 a 18) necesita su propia barra de desplazamiento justo donde hay que fijarse, y la pantalla ya tiene su camino en el LLD-B §6.1 |

**Lo que cambió en la revisión** (pensando más en una app del móvil que en una web, en palabras del
desarrollador):

- El botón del paso 1 es **«Comprobar en la Federación»**, no «Siguiente»: dice lo que hace.
- El paso 2 tiene **solo «Sincronizar…» y «Cancelar»**. En vez de «Atrás», dos iconos en la línea de la
  dirección: **editar** (vuelve al paso 1) y **volver a comprobar** (repite el `/preview` sin salir).
- **El botón dice el equipo elegido**: «Sincronizar CELTIC CASTILLA C.F. 'B'».
- **Sin equipo elegido, el botón se puede pulsar** y dice qué falta, como el alta de la R2.

**Los dos pasos comparten dirección** (`/equipos/:id/federacion`), sin una entrada propia en el historial para
el paso 2. El «Atrás» del navegador sale de la pantalla, preguntando antes si hay algo escrito (§3.3). Se
descartó darle al paso 2 su propia entrada: al recargar en él habría que volver a llamar a la federación, y es
un caso más que probar.

- **Lo que se envía al sincronizar es la dirección comprobada**: al editarla, lo comprobado se borra. Así no se
  engancha nunca algo distinto de lo que se ha visto.
- **El camino** `/equipos/:id/federacion` del LLD-B §6.1 pasa de «Borrador» a confirmado.

### Decisión 3 · La temporada que no existe: se crea con la etiqueta de la Federación, sin corregirla

**Decidido el 2026-10-25**, sobre la maqueta (pantalla H).

**Cuándo pasa.** El enganche busca la temporada primero por el código de la federación y después por la etiqueta
(`D-106`), así que la temporada en curso casi siempre está: la creó el alta (R2). No está cuando se pega el
calendario de una temporada que el club no ha creado, como el de 2027/28 para un equipo dado de alta en 2026/27.
Entonces el enganche **la crea**, e inscribe en ella al equipo.

**Lo que se ve**: en el resumen del paso 2, «Temporada: 2027/28 · nueva», y debajo el aviso «La temporada 2027/28
no existe todavía en el club: se creará al sincronizar, con el nombre que le da la Federación.» Informa; no
bloquea.

**La etiqueta no se corrige.** El catálogo permite mandar otra (`seasonLabel`, «salvo corrección»), pero la
traduce el conector de la federación de su propia página (`D-106`), y la guarda de fechas de `D-91` rechaza un
calendario de otra temporada. Una corrección a mano solo puede meter una etiqueta que no casa con el calendario.

**Y la web no manda `seasonLabel`.** Visto en el servidor (`LinkTeamToFederation`, el paso 1 de la cascada): sin
ella, busca y crea con la de la federación, `calendar.seasonLabel`, que es la misma que enseñó el `/preview`. Sin
mandarla, lo que se ve y lo que se guarda no pueden diferir.

**El caso raro**: si la página de la federación no trae la etiqueta y la temporada no existe, el `/preview` falla
con `SEASON_LABEL_UNAVAILABLE`. Va en la decisión 6.

### Decisión 4 · Cómo se reconoce el equipo propio

**Decidido el 2026-10-25**, sobre la maqueta (pantallas E e I). De la decisión 2 venía ya la forma: botones de
opción, uno solo y obligatorio, **ninguno elegido** (elegirlo por el nombre del club sería deducir en silencio lo
que `D-16` y `D-67` piden que reconozca una persona), y los equipos **sin código** (`federationTeamId = null`)
desactivados, con «La Federación no publica su código: no se puede elegir». Y se decidieron tres cosas más:

- **Por orden alfabético** del nombre de la federación, con las reglas del español. La federación los da en el
  orden de su calendario, que no ayuda a encontrar el club entre 14 o 18; así, «CELTIC CASTILLA C.F. 'A'» y
  «'B'» salen juntos.
- **El equipo que el club ya tiene sale desactivado, diciendo cuál**. Es el caso de dos equipos del club en el
  mismo grupo, y elegirlo daría 409 (`FEDERATION_TEAM_ID_TAKEN`). **Lo dice el servidor en el `/preview`**: cada
  equipo de `teams[]` lleva `takenBy`, el equipo del club que ya tiene ese código, o nulo ([D-110], escrito en
  R3.2). Le sirve igual a la app del móvil. **Cambia el catálogo: mini-fase** (§5). Tres textos:
  - otro equipo propio, sincronizado en esa competición: «Ya está sincronizado con Celtic Alevín A»;
  - el mismo equipo que se sincroniza: «Ya está sincronizado con este equipo»;
  - **un rival** (`isOwn = false`): «Ya está en el club como rival: la Federación lo trajo antes de
    sincronizarlo». **Este caso no tiene salida todavía** (abajo).
- **Sin escudos.** El catálogo los trae, pero apuntan a la RFFM de verdad, y que los escenarios no se bajen nada
  de internet es de la rebanada 4. El nombre de la federación basta para reconocerlo, y es el que el club ve en
  su web.

| Opción para el equipo ya sincronizado | Veredicto |
|---|---|
| (a) Nada en la lista: el 409 al pulsar, con su mensaje | Descartada: explica el error, pero no lo evita |
| (b) La web lo deduce, con `listSeasons` y `listSeasonRegistrations` y comparando códigos | Descartada: deduce en la web lo que sabe el servidor, y el `/preview` no da los identificadores de la temporada ni de la competición con los que comparar |
| **(c) Lo dice el servidor en el `/preview`** | **Elegida** |

**La forma**, en `D-110`: `takenBy` es un `TeamRef` (`D-32`), y su `isOwn` distingue el equipo propio del rival.

**Lo que salió al escribir `D-110` (2026-10-25): el segundo equipo del club en un grupo ya sincronizado no se puede
sincronizar.** La primera ingesta del Alevín A escribe los equipos del grupo, y como no crea equipos propios
(`D-66`), el «CELTIC CASTILLA C.F. 'B'» queda **como rival**. Sincronizar después el Alevín B con ese código da 409,
y reclamarlo (`claimTeam`) crearía un segundo equipo propio en vez de unirlo al Alevín B: es la fusión que el LLD
deja sin diseñar (§9.5). Viene de F10; la rebanada 3 lo pone a la vista. **Decidido con el desarrollador: la R3 lo
avisa y no lo resuelve**; la salida (la fusión, o una ingesta que no escriba como rivales los del club) va a la
**rebanada 13**, junto a «Dejar de sincronizar».

### Decisión 5 · Después de enganchar: vuelta a la portada en la temporada del calendario, que se refresca sola mientras haya algo en marcha

**Decidido el 2026-10-25**, sobre la maqueta (pantallas J, K y L).

| Momento | Adónde | Por qué |
|---|---|---|
| **Al enganchar bien** | La portada, en la temporada **del calendario**, con el aviso | Es donde está ahora el equipo con su competición; la etiqueta la tiene la web desde el `/preview` |
| **Al cancelar** | La portada de partida | Como el alta |

**La portada se refresca sola mientras alguna competición esté «En marcha».** El 202 trae un `jobId`, pero no
hace falta seguirlo: la portada ya enseña «En marcha» con la pasada `accepted` que escribe el enganche (enmienda
de `D-89`, R1). Lo que faltaba es ver cómo acaba sin recargar, y hasta la rebanada 14 no hay otro sitio donde
verlo.

| Opción | Veredicto |
|---|---|
| (a) Nada: «En marcha» hasta recargar | Descartada: en la maqueta parece colgada |
| (b) Volver a pedir los datos una vez, a los pocos segundos | Descartada: acierta solo si la ingesta ya acabó |
| **(c) Refrescarse sola mientras haya algo en marcha** | **Elegida** |

**Cómo**:

- **Cada 10 s**, vuelve a pedir lo de la portada (`listCompetitions`; LLD-B §2.4), **solo** mientras alguna
  competición de la temporada elegida esté `pending`, **solo con la pestaña a la vista** (`visibilitychange`), y
  **como mucho 5 minutos** seguidos, por si una pasada no acaba nunca.
- **Vale para todas las filas**, no solo para la recién sincronizada: también para las pasadas de `launchd`.
- **Sin «Cargando…»**: lo que hay se queda a la vista hasta que llega lo nuevo, con el orden elegido, sin mover el
  foco. Si una de esas peticiones falla, se deja como estaba y se reintenta en la siguiente; no se pinta un error
  por un refresco.
- **No se anuncia al lector de pantalla** cada cambio de estado, para no interrumpir; el aviso de arriba ya dice
  que la ingesta está en marcha.
- **Se prueba sin simulacros** (`DW-17`): la federación falsa retiene el calendario de una competición inventada
  (LLD-B §11.3), el escenario ve «En marcha», la suelta, y ve «Al día» sin recargar. En Vitest, con un reloj de
  mentira, como la espera de 30 s de `R0.4`.

### Decisión 6 · Los errores del enganche, cada uno en su sitio y con texto nuevo

**Decidido el 2026-10-25**, sobre la maqueta (pantallas M, N y O).

**Dónde sale cada uno**, con una regla por sitio:

- **Junto al campo, en el paso 1** (M): los que dicen que la dirección está mal. El campo se marca y el motivo va
  debajo.
- **Aviso arriba, en el paso 1** (N): la federación no responde o responde mal, con *Reintentar*; y lo que no es
  pasajero, sin él. Lo escrito sigue en el campo.
- **Aviso arriba, en el paso 2** (O): lo que falla al pulsar «Sincronizar…». Lo comprobado y el equipo elegido se
  conservan. **El enganche vuelve a leer la federación** (R3.4), así que aquí también pueden salir los del paso 1:
  todos van arriba, con su mismo texto y **sin *Reintentar***, porque «Sincronizar…» sigue a mano y es lo que se
  reintenta.
- **La página entera**: el equipo no existe.

**Y los textos de `errors.ts`, reescritos** con el vocabulario de la pantalla («sincronizar») y diciendo qué
hacer. Los de hoy se escribieron en F10 y en la R2, pensando en el servidor:

| Código | Cuándo | Dónde | Texto |
|---|---|---|---|
| `UNREADABLE_FEDERATION_URL` (400) | La dirección no es la de un calendario | Campo | Esa dirección no es la de un calendario de la Federación. Cópiala de la página del calendario del grupo. |
| `FEDERATION_COORDINATE_NOT_FOUND` (502) | La dirección no lleva a ningún calendario: el grupo o la competición no existen, o la temporada no existe y la RFFM devuelve otra con la etiqueta vacía. **No es pasajero**, aunque sea un 502 | Campo | La Federación no tiene ningún calendario en esa dirección. Revisa que esté completa. |
| `FEDERATION_UNREACHABLE` (504) | La federación no contesta | Aviso, *Reintentar* | La Federación no responde. Prueba otra vez en un rato. |
| `FEDERATION_UNEXPECTED_STATUS`, `FEDERATION_MALFORMED_RESPONSE` (502) | La federación contesta mal | Aviso, *Reintentar* | La Federación ha respondido con un error. Prueba otra vez en un rato. |
| `FEDERATION_ADAPTER_MISSING` (501) | La federación del club no tiene conector (`D-95`) | Aviso, **sin** *Reintentar* | Todavía no se puede sincronizar con la federación de este club. |
| `SEASON_LABEL_UNAVAILABLE` (400) | La página no trae la etiqueta y la temporada no existe (decisión 3) | Aviso, **sin** *Reintentar* | La Federación no dice de qué temporada es ese calendario. |
| `FEDERATION_SEASON_MISMATCH` (502) | Al sincronizar: la guarda de fechas (`D-91`). El `/preview` no la pasa | Aviso, paso 2 | Las fechas de ese calendario son de otra temporada. Revisa que la dirección sea la de esta temporada. |
| `FEDERATION_SOURCE_MISMATCH` (502) | Al sincronizar: la dirección de una competición que ya existe devuelve otra (`D-84`). El `/preview` no la pasa | Aviso, paso 2 | En esa dirección la Federación tiene ahora otra competición. |
| `SEASON_ALREADY_LINKED` (409) | La temporada de esa etiqueta tiene otro código (`D-106`) | Aviso, paso 1 | Esa temporada ya está sincronizada con otro código de la Federación. Revisa que el calendario sea de la temporada correcta. |
| `COMPETITION_IDENTITY_MISMATCH` (409) | Al sincronizar | Aviso, paso 2 | El equipo y la competición no cuadran: no son de la misma edad, género o modalidad. |
| `OWN_TEAM_NOT_IN_CALENDAR` (409) | Al sincronizar: el calendario cambió desde la comprobación | Aviso, paso 2 | Ese equipo ya no está en el calendario de la Federación. Vuelve a comprobar con el botón ↻ de la dirección. |
| `FEDERATION_TEAM_ID_TAKEN` (409) | Al sincronizar | Aviso, paso 2 | Ese equipo de la Federación ya es de otro equipo del club. |
| `ALREADY_LINKED_TO_FEDERATION` (409) | Al sincronizar | Aviso, paso 2 | Este equipo ya está sincronizado con otro equipo de la Federación en esa competición. |
| `TEAM_NOT_FOUND` (404) | El equipo se borró, o la dirección tiene otro código | Página entera | No se ha encontrado el equipo (como hoy), con un enlace a la portada |

**Tres cosas que salieron al repasarlos:**

1. **El texto de `COMPETITION_IDENTITY_MISMATCH` estaba mal**: decía «categoría o temporada», y lo que se compara
   es edad, género y modalidad (`identityMatches`). Es un fallo de hoy, no de estilo.
2. **Esta tabla decía mal qué es `FEDERATION_SOURCE_MISMATCH`** («la dirección es de otra federación»): en el
   servidor (`ProblemMiddleware`) es que la dirección guardada de una competición devuelve ahora otra. Una
   dirección de otra web cae en `UNREADABLE_FEDERATION_URL`, porque se mira el *host* (confirmado en R3.4).
3. **Los dos 502 pasan a ser pasajeros** (`transientCodes` de `errors.ts`, con *Reintentar*): la RFFM contesta a
   veces `null` unos minutos (H-61), y eso llega como respuesta que no se entiende. Vale para toda la web.

- **Qué códigos emite de verdad cada operación** se comprueba en el servidor antes de escribir los mensajes (paso
  R3.4), no se copia de la descripción del catálogo: la tabla es la lista a verificar.
- **Los textos son de `errors.ts`, para toda la web**, aunque hoy solo los enseña esta pantalla.

**Y un equipo rival**: `/equipos/<id de un rival>/federacion` no tiene sentido. La web lo trata como «No se ha
encontrado el equipo», mirando `isOwn` de `getTeam`, sin pedir nada más al servidor.

---

## 5. Lo que le falta al servidor

Poco: **el enganche y su `/preview` ya están** (F10, y la búsqueda por etiqueta desde R2.8). Falta leer el
equipo, y que el `/preview` diga qué equipos del grupo son ya del club (decisión 4).

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **`getTeam`**: un equipo por su código, propio o rival, con los derivados de `TeamResponse` (`isOwn`, `clubName`, `displayName`, `crestUrl`). 404 `TEAM_NOT_FOUND` si no existe en el club | Las cuatro (filtro, Aplicación, Persistencia, HTTP) | **No**, si el catálogo no cambia. Si al programarla hay que tocar su descripción (por ejemplo, el código del 404), sí | 2 |
| **El `/preview` dice qué equipos del grupo ya tiene el club** (`D-110`): cada equipo de `teams[]` lleva `takenBy`, un `TeamRef` del equipo propio sincronizado en esa competición o del rival de esta temporada que ya tiene ese código, o nulo. Con **las mismas dos comprobaciones** que el 409 del enganche (su paso 3), sacadas a una función que usan los dos | Catálogo, Aplicación, HTTP | **Sí**: cambia el catálogo | 4 |
| **Los códigos que emiten el enganche y su `/preview`**, contrastados con lo que dice el catálogo | Ninguna, si cuadran | Solo si no cuadran | 6 |
| **El `/preview` contra la federación falsa**: que una competición inventada por un escenario se pueda comprobar y enganchar, y que la página que sirve lleve lo que el `/preview` lee (la temporada, el grupo, los equipos) | Ninguna del servidor; la federación falsa de `backoffice/e2e/support/` | No | — |

**Lo que ya está y se reutiliza**: el repositorio de equipos, que ya lee para el enganche; los nombres del
catálogo en el servidor (`D-109`) para el `displayName`. **`getTeam` está en el catálogo y sin programar**: se
activa añadiéndolo al filtro de `openapi-generator-config.yaml`.

**Los permisos**: el enganche requiere rol elevado (§7.3). Como todo hasta la rebanada 16, sin comprobar.

**Al pasar el censo** con `getTeam` activada, los campos de `TeamResponse` sin nombrar en ningún test se
escriben o se apuntan en `known-gaps.json` con su motivo.

**Al terminar**, el servidor sirve **12 de las 85** operaciones.

---

## 6. Los escenarios

**Lista provisional.** Lo aprendido en la R2 (§9): **los `.feature` se escriben y se revisan con el desarrollador
antes de programar la web**, con la *skill* de escenarios, y quedan en rojo porque falta la pantalla (plan del
backoffice, §2.3, punto 1). Con las etiquetas `@e2e` y `@ui` de la R2, y axe en los dos modos al final de cada
uno.

**Las acciones de la fila** (§3.1)

- El equipo sin competición tiene el enlace «Sincronizar con la Federación», y lleva a la pantalla de ese equipo.
- El icono de un equipo sin competición se llama «Sincronizar con la Federación»; el de uno con competición,
  «Sincronizar otra competición». Los dos, con el nombre del equipo para el lector.
- Al llegar al icono con el tabulador sale su texto, y *Escape* lo cierra.

**Comprobar** (§3.2, §3.3)

- Pegar la dirección de una competición del grupo y comprobarla: salen la competición, la temporada y los
  equipos, ninguno elegido.
- Una dirección que no es de un calendario: el error junto al campo.
- Una dirección que no lleva a nada: el error junto al campo.
- La federación no contesta: el aviso con *Reintentar*.
- Editar la dirección desde el paso 2: vuelve al paso 1 con la dirección escrita, y hay que comprobar otra vez.
- Volver a comprobar desde el paso 2: se queda en el paso 2, con el equipo elegido.
- Pulsar «Sincronizar» sin elegir equipo: «Falta un dato: Elige tu equipo», y la lista marcada.
- Al elegir un equipo, el botón dice su nombre.
- La lista, por orden alfabético.
- Un segundo equipo del club en el mismo grupo: el del primero sale desactivado, «Ya está sincronizado con…»; y
  el suyo, que la primera ingesta dejó como rival, también: «Ya está en el club como rival…».
- Una competición de otra edad: el aviso dice qué no cuadra, y «Sincronizar» está bloqueado.
- Una temporada que el club no tiene: «Se creará la temporada…».

**Enganchar** (§3.4)

- Enganchar un equipo sin competición: vuelve a la portada con el aviso, y el equipo sale con su competición «En
  marcha»; cuando acaba la ingesta, «Al día», sin recargar.
- Enganchar con un calendario de otra temporada: la portada vuelve en la del calendario.
- Enganchar el segundo equipo del club en la misma competición: «ya está en el club; se reutiliza», y engancha.
- Una temporada enganchada con otro código: su aviso.
- Enganchar solo con el teclado (LLD-B §10.7).
- Después de enganchar, «Atrás» lleva a la portada de partida, no a la pantalla.
- Salir con la dirección escrita pregunta antes; *Cancelar* sin nada escrito vuelve sin preguntar.
- La dirección de un equipo que no existe: «No se ha encontrado el equipo».

**Los datos**: las competiciones que inventa la federación falsa (LLD-B §11.3), con la edad, el género y la
modalidad que le toquen al escenario; y la dirección que se pega es la de la RFFM de verdad, aunque la ingesta
pida a la falsa (`RFFM_BASE_URL`). **«La federación no contesta»** se consigue con una competición inventada que
tarda más que el *timeout* del `/preview`; si eso alarga demasiado la pasada, se decide con la cifra delante.

---

## 7. Los pasos

Cada paso dice qué se hace, cómo se comprueba y qué se graba. **Al acabar cada uno se para** y se espera el visto
bueno del desarrollador antes del siguiente, y su renglón va en la §8. Cada paso deja el árbol en verde por sí
solo, y lo que no venga en el plan va en su propio commit.

### A · Las decisiones y los escenarios

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R3.1** | Este plan, con las decisiones 1 a 6 revisadas una a una | El desarrollador lo revisa | Un commit, y otro por cada corrección |
| **R3.2** | Los documentos de lo decidido: el LLD-B (§6.1 con el camino confirmado, y la regla de las acciones de fila si la decisión 1 la hace general, con su `DW-19`); y en el plan del backoffice, lo «pendiente de la rebanada 3» resuelto, y en la fila de la 13 el 🆕 «Dejar de sincronizar» (decisión 1). Y `D-110` en la bitácora del backend: el `/preview` dice qué equipos del grupo ya son del club (decisión 4) | El desarrollador lo revisa | Un commit por documento (LLD-B §E.1) |
| **R3.3** | **Los `.feature` de la §6**, con la *skill* de escenarios, revisados con el desarrollador antes de programar; y la federación falsa sirviendo lo que el `/preview` necesita de una competición inventada | Revisión del desarrollador; `npm run e2e` con los nuevos **en rojo porque falta la pantalla**, no porque el arnés no arranque (H-07). Un `curl` al `/preview` del servidor de pruebas sobre una competición inventada devuelve sus equipos | Un commit |

### B · El servidor

Con el método del backend (§5).

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R3.4** | **Los códigos del enganche**: qué emiten de verdad `previewFederationLink` y `linkTeamToFederation`, contrastado con la tabla de la decisión 6 y con el catálogo. Si algo no cuadra, se corrige donde toque (catálogo → mini-fase) | La lista, leída del código y de sus tests, en el renglón del paso | Un commit, si cambia algo |
| **R3.5** | **El catálogo (la mini-fase)**: el dato nuevo de `PreviewTeam` (decisión 4), con la forma de `D-110`; y en las dos operaciones del enganche, el 400 y el 502 con los códigos que agrupan (R3.4): en el enganche, el 502 incluye las guardas de fechas y de competición | `npx @redocly/cli lint`, `swift build`, `REQUIRE_DB=1 swift test` sin cambios en el recuento, los tipos de la web regenerados y `npm run build` en verde | Un commit |
| **R3.6** | **El `/preview` dice qué equipos ya son del club** | Tests de los cuatro casos (temporada o competición nuevas: nulos; otro equipo propio sincronizado; el mismo equipo que se sincroniza; un rival de esta temporada con ese código), y que el `/preview` y el enganche usan la misma comprobación; mutación con su catálogo (`Catalogs/R3-6.json`) y `curl` | Un commit |
| **R3.7** | **`getTeam`** | Tests, mutación con su catálogo (`Catalogs/R3-7.json`) y `curl` contra la base de trabajo con un servidor aparte | Un commit |
| **R3.8** | Cierre del servidor: el recuento leído del XML, el censo con `getTeam` y el dato nuevo del `/preview`, los catálogos de mutación de la rebanada otra vez sobre el código final, y el README del backend | `REQUIRE_DB=1 swift test --xunit-output`, el censo con salida `0` | Un commit |

### C · La web

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R3.9** | **Las acciones de la fila**: el juego de iconos elegido, el icono con su texto por ratón y por teclado (decisión 1), la columna nueva y el enlace del equipo sin competición | Vitest (el nombre según tenga o no competición y con el equipo, una vez por equipo aunque tenga dos competiciones, la columna no ordenable), y la web abierta en Chrome y en Safari | Un commit |
| **R3.10** | **La pantalla del enganche, paso 1**: `getTeam` con sus cuatro estados, la línea de los pasos, el campo, «Comprobar en la Federación» y los errores del paso 1; y los textos nuevos de `errors.ts`, con los dos 502 pasajeros (decisión 6) | Vitest, y la web abierta contra el servidor del desarrollador con una dirección de la RFFM de verdad | Un commit |
| **R3.11** | **El paso 2**: la línea de la dirección con editar y volver a comprobar, la competición, la temporada, la lista de equipos, el género, los avisos de identidad y de edad, el botón con el nombre del equipo elegido, «Falta un dato» y los errores al sincronizar | Vitest, y un enganche de verdad desde la web sobre un equipo del club del desarrollador | Un commit |
| **R3.12** | **La vuelta**: a la portada en la temporada del calendario, con el aviso, sin la pantalla en el historial; y el aviso de salir sin guardar | Vitest, y la web abierta | Un commit |
| **R3.13** | **La portada se refresca sola** mientras haya algo en marcha (decisión 5): cada 10 s, con la pestaña a la vista, hasta 5 minutos, sin «Cargando…» y sin perder el orden ni el foco | Vitest con reloj de mentira (empieza, para al acabar, para con la pestaña oculta y a los 5 minutos, un fallo no pinta error), y la web abierta durante una ingesta de verdad | Un commit |

### D · Los escenarios en verde y el cierre

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R3.14** | Los escenarios de R3.3, en verde | `npm run e2e` en verde, con axe en los dos modos; la duración de la pasada, apuntada (lo abierto de la R2) | Un commit |
| **R3.15** | La revisión a mano del LLD-B §10.7 *b*, con el teclado en Chrome y en Safari, los iconos y su texto incluidos; VoiceOver, del desarrollador | La lista en el PR | — |
| **R3.16** | Cierre: los cinco pasos de `AGENTS.md` («Al cerrar una fase»), el mapa del plan del backoffice (§3) con el enganche en verde, el README de la web y lo aprendido | Las cifras buscadas por su número viejo en todo el árbol | Un commit |

---

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| **R3.1** | ✅ 2026-10-25 | El plan escrito (`c5ab725`) y sus seis decisiones revisadas una a una con el desarrollador sobre una maqueta en HTML, cada una en su commit. Lo que cambió en la revisión: los iconos de la fila, con relanzar la ingesta en su celda, y «Sincronizar» en vez de «Enganchar» (1); el asistente de dos pasos, con editar y volver a comprobar y el botón con el nombre del equipo (2); la temporada nueva sin `seasonLabel` (3); el orden alfabético y el equipo ya sincronizado, que pide `D-110` y dos pasos del servidor (4); el refresco de la portada, un paso más (5); y los textos de los errores (6). Y dos hallazgos: «Dejar de sincronizar» no existe (a la rebanada 13) y el texto de `COMPETITION_IDENTITY_MISMATCH` estaba mal |
| **R3.2** | ✅ 2026-10-25 | Tres commits. **El backend** (`ccabb69`): `D-110` en la bitácora y su línea en §5.1 del LLD. Al escribirla salió el caso del rival: el segundo equipo del club en un grupo ya sincronizado no se puede sincronizar; decidido con el desarrollador avisarlo y llevar la salida a la rebanada 13. **El LLD-B** (`cfbc8c4`): las acciones de fila como iconos (§3.7, `DW-19`), el refresco de lo que está en marcha (§2.4, `DW-20`, enmienda a `DW-03`), el camino del enganche decidido (§6.1) y «sincronizar» en la pantalla (§9.8); y un ejemplo que estaba mal en §7.4 y en `DW-10` («libéralo»). **El plan del backoffice**: lo pendiente de la R3, resuelto; los dos 🆕 de la R13; relanzar la ingesta en la fila, en la 14; la R3 en curso en el mapa y en el estado |
| **R3.3** | ✅ 2026-10-25 | **Los escenarios de la rebanada**, con la *skill* del desarrollador y revisados con él antes de programarlos: **44 nuevos** —`sincronizar.feature` (34), `acciones-fila.feature` (8) y `refresco.feature` (2)—; y fuera de `portada.feature` el «Pendiente de sincronizar con la Federación», que ya no se pinta (decisión 1). Lo que cambió en la revisión: **el título se entiende leído suelto**, diciendo de qué pantalla habla; **un paso que necesita un dato concreto nombra el objeto por lo que lo distingue** («el equipo de mi club inscrito sin competición»), sin posesivos que apunten fuera del paso; **un vocabulario fijo**, declarado en la cabecera de `sincronizar.feature`; **los textos largos, en una tabla**, una fila por frase; abrir la pantalla **escribiendo su dirección**, con un equipo que no existe (un UUID al azar) y con un código que no es un UUID, que la web da por no encontrado sin preguntar (LLD-B §6.7, `a8d89d1`). `npm run e2e`: **112 escenarios, los 68 de antes en verde y los 44 nuevos sin definir**; el arnés arranca. El `/preview` del servidor de pruebas sobre una competición inventada devuelve la temporada 2026/27, la competición y sus cuatro equipos; y el enganche del segundo equipo con un código que la ingesta escribió como rival da `409 FEDERATION_TEAM_ID_TAKEN` (el caso de `D-110`, a la 13). **Los pasos y lo que le falta a la federación falsa** (respuestas de error, un calendario sin temporada, un equipo sin código, otra edad, retener el enganche sin retener la ingesta) se programan en R3.14, con la pantalla hecha, como en la R2 |
| **R3.4** | ✅ 2026-10-25 | **Los códigos del enganche, leídos del código y de sus tests**, sin cambios en el servidor. El `/preview` emite `INVALID_UUID`, `UNREADABLE_FEDERATION_URL` y `SEASON_LABEL_UNAVAILABLE` (400), `TEAM_NOT_FOUND` (404), `SEASON_ALREADY_LINKED` (409), `FEDERATION_ADAPTER_MISSING` (501), `FEDERATION_UNEXPECTED_STATUS`, `FEDERATION_MALFORMED_RESPONSE` y `FEDERATION_COORDINATE_NOT_FOUND` (502) y `FEDERATION_UNREACHABLE` (504). El enganche, los mismos, porque **vuelve a leer la federación**, y además los cuatro 409 de la inscripción y **las dos guardas 502, `FEDERATION_SEASON_MISMATCH` y `FEDERATION_SOURCE_MISMATCH`, que el `/preview` no pasa**. Todos están en `ProblemCode`. Lo que cambió en la decisión 6, revisado con el desarrollador: las dos guardas, **arriba en el paso 2**; los del paso 1 que se repiten al sincronizar, también arriba en el paso 2 y **sin *Reintentar***, porque el botón sigue a mano; `FEDERATION_COORDINATE_NOT_FOUND` es 502 pero **no pasajero**, junto al campo; y confirmado que una dirección de otra web es `UNREADABLE_FEDERATION_URL`. **El catálogo**: el 400 y el 502 de las dos operaciones no nombran sus códigos; va en la mini-fase de R3.5. **Lo que la web no provoca, apuntado**: sincronizar un **rival** da **422 `INVALID_VALUE`**, que la ruta no declara (sale por `default`; leído del código, sin test), a la rebanada 13; y `INVALID_UUID` no tiene test en estas dos rutas. Por puerta, sin test: los fallos de la federación solo se prueban en el `/preview`, y el enganche pasa por el mismo código |
| **R3.5** | ✅ 2026-10-25 | **El catálogo**: `PreviewTeam.takenBy`, obligatorio y anulable, con la forma de `D-110`; y el 400 y el 502 de `previewFederationLink` y `linkTeamToFederation` con los códigos que agrupan (R3.4). Los 400 siguen siendo el `$ref` de `BadRequest`, con su `description` al lado (OpenAPI 3.1): escritos dentro de la operación, el generador les daba un tipo propio y el *handler* dejaba de compilar. **La forma de «un `TeamRef` o nulo», probada con los dos generadores**: `oneOf`/`anyOf` con `type: 'null'` hace que Swift **se salte el campo entero** (avisa «Schema "null" is not supported»); `type: [object, 'null']` con `allOf` lo genera en Swift, pero en TypeScript sale `(TeamRef \| null) & TeamRef`, que **pierde el nulo**; **`type: [object, 'null']` con `anyOf: [TeamRef]`** sale bien en los dos (`takenByPayload?` en Swift, `TeamRef \| null` en TypeScript). El *handler* manda `takenBy: nil` hasta R3.6. `redocly lint`, `swift build`, `REQUIRE_DB=1 swift test` con **743** leídos del XML, como al cerrar la R2; en la web, `gen:api`, `typecheck`, `lint`, **195** pruebas y `build` en verde. **Encontrado al mirar el JSON del `/preview`**: un campo nulo **no viaja como `null`, falta** (el `Codable` generado usa `encodeIfPresent`); pasa ya con `crestUrl`, y pasará con `takenBy` aunque el catálogo lo diga obligatorio |
| **R3.6** | ✅ 2026-10-25 | **El `/preview` dice quién del club tiene cada código** (`D-110`). Las dos comprobaciones del 409 `FEDERATION_TEAM_ID_TAKEN` del enganche salen a una pieza nueva de Aplicación, `FederationCodeHolders`, que **usan el enganche y el `/preview`**, en el mismo orden: un rival de esta temporada con ese código, y un equipo propio sincronizado con él en esta competición. El enganche excluye al equipo que se sincroniza (volver a sincronizarlo con su código es idempotente); el `/preview` no, y así enseña que ya lo está. Se carga una vez y se pregunta por cada equipo del grupo; los clubes rivales solo se piden si hay algún rival que rotular. En HTTP, un `TeamRef` con los rótulos de su club, compuestos como en `TeamResponse`. **Corregido al programarlo**: `D-110` y la descripción del catálogo decían «si la temporada o la competición no existen, nadie tiene el código», y con la temporada ya creada **un rival de esa temporada sí puede tenerlo**, porque su código no es de una competición; el enganche lo rechaza igual. Tests: 4 del `/preview` (la temporada o la competición nuevas, con un propio sincronizado en otro grupo; otro propio en esta competición; el mismo equipo; un rival de esta temporada y el de la pasada), con **rojo de aserción visto** en tres sobre un esqueleto que daba siempre nulo (el de los nulos pasaba con él, y lo vigila la mutación); y 1 de extremo a extremo contra Postgres. **743 → 748**, leído del XML. Mutación (`Catalogs/R3-6.json`): **12/12**. Censo en `0`, con `PreviewTeam.takenBy` y los campos de `TeamRef` nombrados. **Contra el servidor de pruebas** (federación falsa): con un equipo del club sincronizado y su ingesta hecha, el `/preview` del segundo equipo sobre el mismo grupo da el primero con `isOwn: true` y **los otros tres como rivales de esta temporada**: en un grupo ya sincronizado, ningún otro equipo se puede elegir, que es el hueco ya apuntado para la 13. README del backend (§4.1 y el recuento) y `AGENTS.md` |
| **R3.7** | ✅ 2026-10-27 | **`getTeam`**: un equipo del club, propio o rival, con `clubName` y `displayName` de su club (el propio, o el rival). Activada en el `filter` (**12 de las 85**). Caso de uso nuevo, `GetTeam`, que devuelve el equipo con su club; el club rival se busca **en la lista** de clubes rivales, como las temporadas en R2.8, sin añadir una lectura por id al puerto; si la FK fallara, es un 500, no un 404. En HTTP, el mapeo del rival junto al del propio (`toResponse(opponentClub:)`), con su club, su temporada (`D-104`) y su código (`D-101`). **Mini-fase del catálogo, prevista en la §5**: la operación no declaraba **400**, así que no podía responder `INVALID_UUID`; ahora declara el 400 y el 404 con sus códigos (`$ref` con `description`, como en R3.5) y una descripción. Tests: 3 del caso de uso (propio, rival con su club entre dos, no está), con **rojo visto** sobre un esqueleto que daba siempre «no encontrado»; y 4 por HTTP contra Postgres (propio y rival campo a campo, 404 y 400). **748 → 755**, leído del XML. Mutación (`Catalogs/R3-7.json`): **8/8**. Censo en `0`, con 12 operaciones. En la web, los tipos regenerados, `typecheck`, `lint`, 195 pruebas y `build` en verde. **`curl` contra la base de trabajo** con un servidor aparte en el 8766, solo lecturas: el Alevín A propio («Celtic Alevín A»), un rival («U.D. ARROYOFRESNO Cadete A», con su código, su club y su temporada), un UUID que no está (404 `TEAM_NOT_FOUND`) y `abc` (400 `INVALID_UUID`); y los nulos, sin clave (`DW-21`). README del backend (§0 y §4.6), `AGENTS.md` y el plan del backoffice (12 de 85) |
| **R3.8** | ✅ 2026-10-27 | **Cierre del servidor**, tras actualizar el desarrollador macOS a 27.2 (Swift 6.4): Docker volvió sin contenedores, y `docker compose up -d` levantó `backend-db-1` con sus datos. El recuento, leído del XML de `REQUIRE_DB=1 swift test --xunit-output`: **755** (752 + 3 omitidos); **743 → 755** en la parte del servidor de la rebanada (5 de R3.6 y 7 de R3.7). El censo, salida `0`: **12 operaciones**; 34 códigos emitidos, 27 nombrados en un test; 102 de 112 campos, los huecos los sabidos; y de la lista de 35, solo `NOT_FOUND` sin un test que lo nombre, como en la R2. Los dos catálogos de la rebanada, pasados otra vez sobre el código final: R3-6 **12/12**, R3-7 **8/8** (20/20). README del backend: §0 y §4.6 ya se escribieron en cada paso; ahora, los filtros de la R3 en la tabla de §5. `AGENTS.md`, con el servidor de la rebanada 3 cerrado y lo siguiente, `R3.9` |
| **R3.9** | ✅ 2026-10-27 | **El juego de iconos, elegido sobre la maqueta** (una tabla por candidato, en los dos modos): **Lucide, copiado** en una pieza propia, `AppIcon`, con el texto de su licencia al lado (`AppIcon.LICENSE.txt`: ISC, y MIT los dibujos que vienen de Feather, como el de enlace). Al mirar las licencias salió que **PrimeIcons 8 ya no es MIT** (licencia comercial de PrimeUI, con clave); la última libre es la 7.0.0, en fuente tipográfica y sin futuro. Y `@primevue/icons`, que trae PrimeVue (MIT), no tiene enlace y es un juego interno suyo. **El icono con su texto**, `RowAction`: un enlace de 40 × 40 con el nombre y el equipo («Sincronizar otra competición, Cadete A»); el texto sale con el puntero (en toda la acción, así que pasar al texto no lo esconde) y con el foco, y *Escape* lo esconde desde cualquier sitio sin mover el foco, hasta volver a llegar. El texto va `aria-hidden`: el nombre ya lo dice. Con `pointerenter`, no `mouseenter`, porque el revisor de accesibilidad pide junto a los del ratón los del teclado, que aquí están en el enlace. **La tabla**: la columna «Acciones», sin ordenar y con la cabecera solo para el lector; el icono una vez por equipo (`rowspan`); el enlace «Sincronizar con la Federación» bajo «Sin competición»; los dos, a `/equipos/:id/federacion` con la temporada en el estado de la navegación (la pantalla, en R3.10). **Encontrado al abrirla**: la web no tenía color para los enlaces sueltos y salía el azul del navegador; el nuevo va con el del tema y 24 px de alto, como en `FormErrorList`. Vitest: **195 → 211** (8 de la acción, 6 de la tabla y 2 de la portada, adónde lleva y con qué temporada), con **rojo visto** quitando *Escape* (2) y el equipo del nombre (13). `typecheck`, `lint` y `build` en verde. **En Chromium** (Playwright, contra el servidor del desarrollador): las cuatro acciones con su nombre y su dirección, el texto con el ratón y con el tabulador, *Escape* lo esconde con el foco en el icono, 40 × 40, y **axe sin fallos** en los dos modos. **Safari y Chrome**, vistos por el desarrollador con la web abierta: bien. Sus pestañas, abiertas desde antes, no recibieron los cambios solas y hubo que recargar; una pestaña nueva sí los recibe (Vite, `hot updated`), así que era la conexión de esas pestañas, no Vite |
| **R3.10** | ✅ 2026-10-27 | **La pantalla del enganche, paso 1**, en `/equipos/:id/federacion` (`SyncTeamScreen`, con su lógica sin pintar en `link.ts`). **Al abrir**, `getTeam` con sus estados: «Cargando equipo…» bajo el título; el equipo con su género y su modalidad (la §3.2, corregida: la portada no siempre los dice y esta pantalla no puede saber cuándo); y «No se ha encontrado el equipo» con el enlace a la portada para un 404, para un código que no es un UUID **sin preguntar al servidor** (LLD-B §6.7) y para un rival (`isOwn`); otro fallo, con *Reintentar* si es pasajero. **La línea de los pasos**, pieza propia (`StepLine`, con `aria-current="step"`). **El campo**, obligatorio, con la ayuda y el ejemplo del catálogo; vacío o con espacios es «obligatorio», no «formato no válido»; lo que no es una dirección lo para el catálogo sin llegar al servidor. **«Comprobar en la Federación»** dice «Comprobando…» y se bloquea; bien, pasa al paso 2 (lo que enseña, en R3.11). **Los errores, cada uno en su sitio** (decisión 6): junto al campo y en la lista, los dos de la dirección; la página entera, `TEAM_NOT_FOUND`; arriba, el resto, con *Reintentar* que vuelve a comprobar la misma dirección. **«Cancelar»**, a la portada de la que se vino, sustituyendo a la pantalla en el historial. **`errors.ts`**: los catorce textos del enganche, con los de la decisión 6, y los dos 502 de la Federación que contesta mal, pasajeros. Los textos nuevos acaban en punto, como los revisados en los escenarios; los de antes no lo llevan. Vitest: **211 → 251** (22 de la pantalla, 15 de `link.ts` y 3 de `errors.ts`), con **rojo visto** en cuatro roturas: todos los errores arriba (3), el rival como propio (1), un 502 que deja de ser pasajero (1) y vacío como formato (1). `typecheck` y `lint` en verde. **Contra el servidor del desarrollador** (Chromium, Playwright), sobre el Alevín A · Fútbol 7, desde su enlace de la portada: otro dominio y una dirección sin grupo, junto al campo (unos 500 ms); un grupo que no existe, «no tiene ningún calendario» (680 ms); una dirección de la RFFM de 2026/27, al paso 2 (850 ms); «Cancelar», a `/?temporada=2026-27`; `/equipos/abc/federacion`, no encontrado; axe sin fallos con y sin error. **Encontrado**: la página de la **clasificación** con los mismos cuatro parámetros también vale, porque el servidor mira el dominio y los parámetros, no la ruta; da el mismo calendario, así que no se toca, pero «una dirección que no es la de un calendario» del escenario tiene que ser de otro dominio o sin un parámetro. **Encontrado por el desarrollador al probarla**: una competición que no existe en la dirección, con el grupo bueno, no da error. La RFFM saca el calendario **solo del grupo**, y la competición solo pone el nombre (vacío si no existe, y el de otra si es de otra); `tipojuego` tampoco cuenta. Anotado en el anexo de la RFFM (§F.20), **sin tocar el servidor**: equivocarse así es muy difícil, porque el cursor se queda en el grupo, y la competición se cambia a propósito. Lo que haría falta, en el plan del backoffice como pendiente. Y dos fallos de la R2 en `FormErrorList`, que no se veían con mensajes cortos, en su propio commit: con un mensaje de dos líneas, la viñeta bajaba a la segunda; y el enlace salía en el azul del navegador. **El color de los enlaces va ahora en `index.html`, para toda la web**, y el de R3.9 en la portada sale de ahí; axe sin fallos en los dos modos |
| **R3.11** | ✅ 2026-10-27 | **El paso 2 de la pantalla del enganche**. **La línea de la dirección** comprobada (`CheckedAddress`), sin el `https://` y cortada con «…», con **editar** (al paso 1 con la dirección en el campo y el foco en él; lo comprobado y el equipo elegido se borran) y **volver a comprobar** (el mismo `/preview` sin salir; el equipo elegido se queda si se puede seguir eligiendo; un fallo, arriba). Sus dos iconos salen de `IconAction`, que es `RowAction` renombrada: un enlace si lleva a otra pantalla, un botón si no, y el equipo en el nombre solo en las filas; `AppIcon` suma `pencil` y `rotate-cw`. **El resumen**: competición, edad, modalidad, temporada («· nueva» si el club no la tiene) y jornadas; el foco va a su título al llegar al paso 2. **Los avisos** (`NoticeBox`): la temporada que se creará, la competición que ya está en el club, la edad que no se ha podido comprobar, y **qué no cuadra**, pieza a pieza («Edad: el equipo es Alevín y la competición, Cadete»), con «Sincronizar» bloqueado. **Lo que no cuadra lo calcula la web, y con el género elegido**: el servidor, al sincronizar, crea la competición nueva con el género enviado, así que corregir el género la desbloquea; la que ya está en el club tiene el suyo y el enviado no lo cambia, así que **su género se enseña en el resumen y no se elige** (la §3.3 no lo decía). **La lista de equipos** (`TeamChoiceList`), por orden alfabético en español, ninguno elegido; los que no se pueden elegir, desactivados y con el motivo como descripción, fuera de la etiqueta para que no se lea dos veces (`takenBy` ausente o nulo, lo mismo: LLD-B §3.8). **El botón** dice el equipo elegido; sin elegir, «Elige tu equipo» en la lista de errores, con el foco, y su enlace lleva al primero que se puede elegir. **Al sincronizar**, la dirección comprobada, el código y el género, sin `seasonLabel`; los errores arriba, **sin *Reintentar*** aunque sean pasajeros, y lo elegido sigue; el equipo que ya no está, la página entera. **Bien, de momento vuelve como «Cancelar»**: la vuelta de verdad, con su aviso, es de R3.12. Vitest: **251 → 292** (24 de la pantalla, 14 de `link.ts` y 3 de `IconAction`), con **rojo visto** en cuatro roturas: sin el bloqueo (2), sin el orden (3), sin *retry* quitado (1), y soltar siempre el elegido al volver a comprobar, que **no la cazaba**: la prueba miraba antes de que llegara la segunda respuesta; ahora la segunda trae otra cifra de jornadas y se espera a verla (1). `typecheck`, `lint` y `build` en verde. **Contra el servidor del desarrollador** (Chromium), el Alevín A · Fútbol 7 con la dirección del grupo del Cadete B: el resumen, los dos «no cuadra» y el botón bloqueado; axe sin fallos en los dos modos. **Encontrado al abrirla**: (1) en el móvil la página se salía por la derecha (816 px en 390): la dirección, larga y sin espacios, hacía que la página entera reservara su ancho aunque se cortara; arreglado en `CheckedAddress`. (2) **Los dieciséis equipos del grupo salen como rivales**, también «CELTIC CASTILLA C.F. 'B'»: la base del desarrollador tiene el Cadete B propio inscrito con el código `820` **y además un rival** «CELTIC CASTILLA C.F.» cadete B con el mismo `820` (y lo mismo con el Alevín A y el `824`). El `/preview` mira primero los rivales, como el 409 del enganche (R3.6), y dice «rival». Es lo que el servidor sabe; de dónde salieron esos rivales, por mirar. **El enganche de verdad, desde la web, lo hizo el desarrollador** con el Cadete A: en la base, su inscripción con el código `821` en PREFERENTE CADETE · Grupo 2 (`26737742`/`26737744`), y su primera ingesta bien, con 15 rivales creados en un grupo de 16, **sin el propio**: el fallo del rival duplicado no se repite con el código de hoy. **Lo que pasó con los rivales duplicados**, investigado con el desarrollador y arreglado antes de R3.12, en su propio commit: el 2026-10-18 a las 23:30 la ingesta programada corrió con el binario instalado el 12 (`f982c9d`), **anterior a `D-101`** (`b55a10b`, de ese mismo día), sobre la base ya migrada por el servidor de desarrollo; buscó a los propios por `teams.federation_team_id`, que la migración había vaciado, y creó a los dos como rivales de un club «CELTIC CASTILLA C.F.». El binario nuevo no se instaló hasta el 23. **Y el daño seguía**: la clasificación juntaba rivales e inscripciones con `uniquingKeysWith: first`, ganaba el rival, y la jornada del 26 se escribió en él; la cadena del calendario cogía el primero con el código, y los partidos se quedaron en el propio por el orden de la lista. **Datos**: copia del esquema con `pg_dump`, y en una transacción, las jornadas repetidas con las cifras del rival (las más nuevas) y el puesto anterior del propio, las del rival solo al propio, y fuera los dos rivales y su club, comprobando antes de confirmar una fila por equipo y sin puestos repetidos. **Código**: con el mismo código en un propio y en un rival, **gana el propio**, en la cadena y en la clasificación; 2 tests con **rojo visto**, **755 → 757**, y su catálogo de mutación (`rival-duplicado.json`) **3/3** |
| **R3.12** | ✅ 2026-10-27 | **La vuelta**: al sincronizar bien, a la portada **en la temporada del calendario** (la etiqueta del `/preview`, que puede no ser la de partida), sustituyendo a la pantalla en el historial, con el aviso **«Sincronizado. La primera ingesta está en marcha.»** del marco, como «Guardado». **Salir con algo escrito o comprobado pregunta antes**, con el `LeaveDialog` de la R2: «Cancelar» en los dos pasos, «Atrás» del navegador, y el navegador al cerrar o recargar; sincronizar bien y el enlace del equipo no encontrado salen sin preguntar. **Hay algo que perder si el campo tiene una dirección**: el paso 2 la conserva, así que «o comprobado» no hace falta mirarlo aparte (salió en la mutación, abajo). Vitest: **292 → 300** (8 de la pantalla, y la provisional de R3.11, que volvía como «Cancelar», cambiada por dos: la temporada del calendario con el aviso, y la temporada nueva). **Rojo visto** en tres roturas: volver a la de partida (2), sin el aviso (1), preguntar al sincronizar (2). **Dos no se cazaron, y las dos enseñaron algo**: no mirar lo comprobado no cambiaba nada, porque el campo lo lleva (quitado del código); y contar los espacios del campo tampoco, porque **un campo `type="url"` ya quita los espacios de los lados**, en el navegador y en jsdom: el `trim` de la web no tenía nada que hacer (se queda, por si el campo cambia, y lo dice el código). `typecheck` y `lint` en verde. **En Chromium, contra el servidor del desarrollador**, con el enganche contestado por el navegador (202) para no escribir en la base, y el `/preview` de verdad con el Cadete A elegible: «Cancelar» con la dirección escrita pregunta, con el foco en «Seguir editando» y *Escape* que la cierra sin salir; «Atrás» pregunta, y **mientras pregunta la barra ya dice la portada** (el navegador cambia la dirección antes de que la web decida), pero al seguir editando vuelve sola a la de la pantalla, con lo escrito; sincronizar lleva a `/?temporada=2026-27` con el aviso y sin preguntar. axe sin fallos con la pregunta abierta |
| **R3.13** | ✅ 2026-10-27 | **La portada se refresca sola** mientras alguna competición de la temporada esté «En marcha» (decisión 5, LLD-B §2.4). Una pieza para cualquier pantalla, **`refreshWhile`** (`src/refresh.ts`): cada 10 s mientras se cumpla la condición, nada con la pestaña escondida, como mucho 5 minutos seguidos, un refresco lento no se pisa con el siguiente (se cuenta desde que acaba), y se para al salir. **Al volver a la pestaña, lo último ya y otros 5 minutos**: la §2.4 no decía qué pasaba al volver, y sin esto una pestaña escondida más de 5 minutos se quedaba «En marcha» hasta recargar. En la portada, **solo vuelve a pedir las competiciones** (las inscripciones no cambian con una ingesta) y rehace las filas con las mismas `id`, así que Vue las reaprovecha: el foco se queda y el orden es el de la dirección; sin «Cargando…», y si falla se deja lo que había. Vitest: **300 → 315** (10 de `refreshWhile` y 5 de la portada, con reloj de mentira). **Rojo visto** en diez roturas: no pintar lo nuevo (4), mirar otro estado (4), enseñar «Cargando…» (4), pintar el error (1), pedirlo todo (3), sin los 5 minutos (1), al volver sin otros 5 (1), al volver sin nada en marcha (1), al salir no para (1), y **con la pestaña escondida, que no se cazaba**: esa condición solo cuenta si se esconde con un refresco a medias, y ahora tiene su prueba (1). `typecheck` y `lint` en verde. **En Chromium, contra el servidor del desarrollador**, con las dos primeras respuestas de competiciones cambiadas a «En marcha» para el Cadete A: a los 10 s pide otra vez sin «Cargando…», a los 20 s la fila dice «Al día» y el refresco para (3 peticiones en 40 s); el foco sigue en el icono del Cadete B. Con `?orden=ingesta`, **la fila cambia de sitio** al pasar a «Al día»: se respeta la columna elegida, no la posición. **Con una ingesta de verdad, el flujo entero, hecho por el desarrollador**: alta de un equipo nuevo (Sénior A, R2), su enganche desde la web con PREFERENTE AFICIONADO · Grupo 1 (`3349086`), la vuelta a la portada «En marcha» y, al refrescarse, «Al día». En la base, la primera ingesta tardó unos 6,6 s (calendario: 10 clubes, 17 rivales en un grupo de 18, sin el propio, 34 jornadas y 306 partidos; siete pasadas de clasificación y una de goleadores), y ningún rival con el código de un propio. **Por qué así y no con la ingesta programada**: su antirrebote de 6 horas se saltaría las competiciones de esta tarde, y aun con `--force` una ingesta dura segundos: la portada solo se refresca si al abrirla ya ve algo «En marcha», que es justo lo que pasa al volver de sincronizar |

---

## 9. Lo aprendido

*(Se escribe al cerrar.)*

[D-110]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
