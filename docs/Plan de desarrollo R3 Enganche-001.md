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
> **Estado del documento: en revisión.** Las decisiones de la §4 se revisan una a una con el desarrollador antes
> de construir nada (plan del backoffice, §2.2). **La 1, decidida el 2026-10-25**, con una maqueta en HTML de las
> opciones y de cómo crecen con las rebanadas 13 y 14. Las 2 a 6 siguen siendo **propuestas**.
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
| En el servidor, **una operación nueva**: `getTeam`. Con ella, el servidor sirve **12 de las 85** | §5 |

**Lo que no trae** (llega después): la ficha del equipo (rebanada 4); relanzar la ingesta desde la fila
(rebanada 14); los escudos de los equipos del grupo (decisión 4); y **deshacer un enganche**, «Dejar de
sincronizar», que **no existe en el catálogo** y se diseña en la rebanada 13 (decisión 1). Mientras tanto, un
enganche equivocado se corrige a mano en la base. *(Este plan decía que lo cubría `releaseTeam`, y no: liberar
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

**Arriba**: el título «Sincronizar con la Federación» y el equipo, con el mismo nombre que en la portada (el que
distingue género y modalidad, bloque T de la R2), no el `displayName` del servidor, que no lo distingue (`D-109`).

**Primer paso, comprobar** (decisión 2):

| Campo | Pieza | Obligatorio | Ayuda |
|---|---|---|---|
| **Dirección del calendario** | Texto, ancho | Sí | «Cópiala de la web de la Federación, en la página del calendario del grupo. Por ejemplo: …», con el ejemplo leído del catálogo (`FederationLinkPreviewRequest`, como en la R2) |

- **«Comprobar»** envía `previewFederationLink`. Mientras tanto el botón se bloquea y dice «Comprobando…»: la
  federación puede tardar (LLD §5.4).
- **Lo que hay en la dirección sale debajo**, en la misma página (§3.3). **Si se cambia la dirección** después de
  comprobarla, lo de abajo desaparece y hay que comprobar otra vez: lo que se confirma es siempre lo que se ha
  visto.

**Los cuatro estados** (LLD-B §3.1), de lo que se pide al abrir:

| Estado | Cómo se ve |
|---|---|
| **Cargando** | «Cargando equipo…» en el sitio del título |
| **Error** | El mensaje del código, con *Reintentar* si puede ser pasajero (LLD-B §4.4). Si el equipo no existe, «No se ha encontrado el equipo» y un enlace a la portada |
| **Vacío** | No tiene: un equipo existe o no |
| **Con datos** | El campo de la dirección y «Comprobar» |

### 3.3 Lo que hay en la dirección, y confirmar

Lo que devuelve el `/preview`, para que una persona reconozca su equipo (`D-16`):

- **La competición**: división, grupo, edad, modalidad y número de jornadas.
- **La temporada**: su etiqueta. Si no existe en el club: «Se creará la temporada 2026/27» (`season.exists`).
- **Si la competición ya la usa otro equipo del club**: «Esta competición ya está en el club; se reutiliza»
  (`alreadyRegistered`). Es informativo, no impide nada.
- **Los equipos del grupo**, para elegir **cuál es el del club** (decisión 4): uno por línea, con el nombre tal
  como lo escribe la federación (`rawName`). **Ninguno viene elegido.** Los que llegan sin código se ven, pero no
  se pueden elegir, con el motivo.
- **El género**, un selector con el que propone el `/preview` ya elegido, que se puede cambiar (`D-58`).
- **Si no cuadra con el equipo** (`identityMatches = false`): un aviso que dice **qué** no cuadra («El equipo es
  Cadete y la competición es Juvenil»), y **«Sincronizar» bloqueado**: el servidor lo rechazaría (409).
- **Si la edad no se ha podido comprobar** (`ageCategoryChecked = false`): un aviso de que el nombre de la
  competición no dice la edad, y de que se usará la del equipo. No bloquea.
- **«Sincronizar»** envía `linkTeamToFederation` con la dirección **comprobada**, el código del equipo elegido, el
  género y, si la temporada no existe, la etiqueta que propuso el `/preview` (decisión 3).
- **«Cancelar»** vuelve a la portada de la que se vino, y quita la pantalla del historial (como el alta).
- **Salir con algo escrito o comprobado** pregunta antes (LLD-B §5.5), con el aviso de la R2 (`LeaveDialog`).

### 3.4 Al enganchar bien

- El servidor contesta **202**: el enganche está escrito y la primera ingesta, en cola.
- Sale el aviso **«Sincronizado. La primera ingesta está en marcha.»**, que pone el marco, como «Guardado».
- La web vuelve a la portada **en la temporada del calendario** (`/?temporada=2026-27`), que puede no ser la de
  partida, y quita la pantalla del historial (decisión 5).
- En la portada, el equipo sale con su competición y la ingesta **«En marcha»**. Cuando acabe, al volver a pedir
  la portada, sale como cualquier otro.

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
  R3.7, con una pieza propia pequeña o envolviendo la de PrimeVue; lo que vale es que los dos caminos funcionen.
- **40 × 40 px** cada icono, como mínimo 24 (WCAG 2.5.8). Cada acción nueva ensancha la columna unos 40 px.
- **La columna «Acciones» no se ordena**, y su cabecera no se ve pero el lector la lee.
- **Iconos reconocibles**: la web todavía no tiene juego de iconos. Se elige en R3.7 (dibujos SVG propios o
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

### Decisión 2 · La pantalla del enganche: una sola página, comprobar y después confirmar

**Propuesta: una página, con lo que hay en la dirección apareciendo debajo del campo.**

| Opción | Veredicto |
|---|---|
| **(a) Una página: el campo arriba, lo comprobado debajo, «Sincronizar» al final** | **Propuesta.** Se ve a la vez lo que se pegó y lo que hay en ello; no hace falta un «Atrás» propio |
| (b) Dos pasos con un asistente (paso 1: pegar; paso 2: confirmar) | Más piezas, y la dirección deja de verse cuando hay que reconocer el equipo |
| (c) Un diálogo sobre la portada | La lista de equipos del grupo (de 12 a 18) no cabe bien en un diálogo, y la pantalla ya tiene su camino en el LLD-B §6.1 |

- **Lo que se envía al confirmar es la dirección comprobada**, no la del campo: si el campo cambia, lo comprobado
  se borra (§3.2). Así no se engancha nunca algo distinto de lo que se ha visto.
- **El camino** `/equipos/:id/federacion` del LLD-B §6.1 pasa de «Borrador» a confirmado.

### Decisión 3 · La temporada que no existe: se crea con la etiqueta del `/preview`, sin corregirla

**Propuesta: no se deja corregir la etiqueta.** El catálogo permite mandar otra (`seasonLabel`, «salvo
corrección»), pero la etiqueta la traduce el conector de la federación (`D-106`) y la guarda de fechas de `D-91`
es la red. Una corrección a mano solo puede meter una etiqueta que no casa con el calendario. La pantalla dice
«Se creará la temporada 2026/27», y se envía esa.

### Decisión 4 · Cómo se reconoce el equipo propio

**Propuesta:**

- **Una lista de opciones** (un botón de opción por equipo, con su nombre tal como lo escribe la federación),
  agrupadas con su título («¿Cuál es tu equipo?»). **Sin ninguno elegido**: elegirlo por el nombre del club
  sería deducir en silencio lo que `D-16` y `D-67` piden que reconozca una persona.
- **Los equipos sin código** (`federationTeamId = null`) salen **desactivados**, con «La Federación no publica
  el código de este equipo; no se puede enganchar».
- **Sin escudos**. El catálogo los trae para reconocer de un vistazo, pero apuntan a la RFFM de verdad, y que
  los escenarios no se bajen nada de internet es de la rebanada 4 (plan del backoffice, §5, «Lo que no está en
  la rebanada 0»). El nombre de la federación basta para reconocerlo, y es el que el club ve en su web.

*Por revisar con el desarrollador*: si se prefiere adelantar los escudos a esta rebanada, el problema de los
escenarios viene con ellos.

### Decisión 5 · Después de enganchar: vuelta a la portada en la temporada del calendario, sin seguir la ingesta

**Propuesta:**

| Momento | Adónde | Por qué |
|---|---|---|
| **Al enganchar bien** | La portada, en la temporada **del calendario**, con el aviso | Es donde está ahora el equipo con su competición; la etiqueta la tiene la web desde el `/preview` |
| **Al cancelar** | La portada de partida | Como el alta |

**La primera ingesta no se sigue desde la web en esta rebanada.** El 202 trae un `jobId`, y la portada ya enseña
«En marcha» con la pasada `accepted` que el enganche escribe (enmienda de `D-89`, R1). Que la portada se
refresque sola mientras haya algo en marcha es una mejora para todas sus filas, no del enganche: va a la rebanada
14, con la pantalla de la ingesta, si se quiere.

*Por revisar*: si al desarrollador le parece que ver «En marcha» para siempre hasta recargar confunde, la
alternativa barata es que la portada vuelva a pedir sus datos una vez, unos segundos después de llegar con el
aviso.

### Decisión 6 · Los errores del enganche, cada uno en su sitio

`errors.ts` ya tiene un texto por código (lo exige su prueba). Lo que decide esta rebanada es **dónde sale** cada
uno y **si el texto sirve en esta pantalla**, que es la primera que los enseña:

| Código | Cuándo | Dónde |
|---|---|---|
| `UNREADABLE_FEDERATION_URL` (400) | La dirección no es la de un calendario | Junto al campo |
| `FEDERATION_SOURCE_MISMATCH` | La dirección es de otra federación | Junto al campo |
| `FEDERATION_COORDINATE_NOT_FOUND` | La dirección no lleva a ningún calendario | Junto al campo |
| `FEDERATION_UNREACHABLE` (504), `FEDERATION_UNEXPECTED_STATUS`, `FEDERATION_MALFORMED_RESPONSE` (502) | La federación no contesta, o contesta mal | Aviso arriba, con *Reintentar* |
| `FEDERATION_ADAPTER_MISSING` (501) | La federación del club no tiene conector (`D-95`) | Aviso arriba, **sin** *Reintentar*: no es pasajero |
| `SEASON_ALREADY_LINKED` (409) | La temporada de esa etiqueta tiene otro código (`D-106`) | Aviso arriba. El texto ya está escrito desde la R2 |
| `COMPETITION_IDENTITY_MISMATCH`, `OWN_TEAM_NOT_IN_CALENDAR`, `FEDERATION_TEAM_ID_TAKEN`, `ALREADY_LINKED_TO_FEDERATION` (409) | Al confirmar | Aviso arriba, sin borrar lo comprobado |
| `FEDERATION_SEASON_MISMATCH` | La guarda de fechas (`D-91`) | Aviso arriba |
| `TEAM_NOT_FOUND` (404) | El equipo se borró, o la dirección tiene otro código | La página entera: «No se ha encontrado el equipo» |

- **Qué códigos emite de verdad cada operación** se comprueba en el servidor antes de escribir los mensajes (paso
  R3.4), no se copia de la descripción del catálogo: la tabla de arriba es la lista a verificar.
- **«Junto al campo»** solo para los que dicen que la dirección está mal; los demás no son del campo, aunque los
  provoque.

**Y un equipo rival**: `/equipos/<id de un rival>/federacion` no tiene sentido. **Propuesta**: la web lo trata
como «No se ha encontrado el equipo», mirando `isOwn` de `getTeam`, sin pedir nada más al servidor.

---

## 5. Lo que le falta al servidor

Poco: **el enganche y su `/preview` ya están** (F10, y la búsqueda por etiqueta desde R2.8). Falta leer el
equipo.

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **`getTeam`**: un equipo por su código, propio o rival, con los derivados de `TeamResponse` (`isOwn`, `clubName`, `displayName`, `crestUrl`). 404 `TEAM_NOT_FOUND` si no existe en el club | Las cuatro (filtro, Aplicación, Persistencia, HTTP) | **No**, si el catálogo no cambia. Si al programarla hay que tocar su descripción (por ejemplo, el código del 404), sí | 2 |
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
- Cambiar la dirección después de comprobar: lo comprobado desaparece.
- Una competición de otra edad: el aviso dice qué no cuadra, y «Sincronizar» está bloqueado.
- Una temporada que el club no tiene: «Se creará la temporada…».

**Enganchar** (§3.4)

- Enganchar un equipo sin competición: vuelve a la portada con el aviso, y el equipo sale con su competición «En
  marcha».
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
| **R3.2** | Los documentos de lo decidido: el LLD-B (§6.1 con el camino confirmado, y la regla de las acciones de fila si la decisión 1 la hace general, con su `DW-19`); y en el plan del backoffice, lo «pendiente de la rebanada 3» resuelto, y en la fila de la 13 el 🆕 «Dejar de sincronizar» (decisión 1). Si alguna decisión cambia lo que responde el servidor, su `D-110` en la bitácora | El desarrollador lo revisa | Un commit por documento (LLD-B §E.1) |
| **R3.3** | **Los `.feature` de la §6**, con la *skill* de escenarios, revisados con el desarrollador antes de programar; y la federación falsa sirviendo lo que el `/preview` necesita de una competición inventada | Revisión del desarrollador; `npm run e2e` con los nuevos **en rojo porque falta la pantalla**, no porque el arnés no arranque (H-07). Un `curl` al `/preview` del servidor de pruebas sobre una competición inventada devuelve sus equipos | Un commit |

### B · El servidor

Con el método del backend (§5).

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R3.4** | **Los códigos del enganche**: qué emiten de verdad `previewFederationLink` y `linkTeamToFederation`, contrastado con la tabla de la decisión 6 y con el catálogo. Si algo no cuadra, se corrige donde toque (catálogo → mini-fase) | La lista, leída del código y de sus tests, en el renglón del paso | Un commit, si cambia algo |
| **R3.5** | **`getTeam`** | Tests, mutación con su catálogo (`Catalogs/R3-5.json`) y `curl` contra la base de trabajo con un servidor aparte | Un commit |
| **R3.6** | Cierre del servidor: el recuento leído del XML, el censo con `getTeam`, los catálogos de mutación de la rebanada otra vez sobre el código final, y el README del backend | `REQUIRE_DB=1 swift test --xunit-output`, el censo con salida `0` | Un commit |

### C · La web

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R3.7** | **Las acciones de la fila**: el juego de iconos elegido, el icono con su texto por ratón y por teclado (decisión 1), la columna nueva y el enlace del equipo sin competición | Vitest (el nombre según tenga o no competición y con el equipo, una vez por equipo aunque tenga dos competiciones, la columna no ordenable), y la web abierta en Chrome y en Safari | Un commit |
| **R3.8** | **La pantalla del enganche, primer paso**: `getTeam` con sus cuatro estados, el campo, «Comprobar» y los errores del campo | Vitest, y la web abierta contra el servidor del desarrollador con una dirección de la RFFM de verdad | Un commit |
| **R3.9** | **Lo comprobado y confirmar**: la competición, la temporada, la lista de equipos, el género, los avisos de identidad y de edad, «Sincronizar» y sus errores | Vitest, y un enganche de verdad desde la web sobre un equipo del club del desarrollador | Un commit |
| **R3.10** | **La vuelta**: a la portada en la temporada del calendario, con el aviso, sin la pantalla en el historial; y el aviso de salir sin guardar | Vitest, y la web abierta | Un commit |

### D · Los escenarios en verde y el cierre

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R3.11** | Los escenarios de R3.3, en verde | `npm run e2e` en verde, con axe en los dos modos; la duración de la pasada, apuntada (lo abierto de la R2) | Un commit |
| **R3.12** | La revisión a mano del LLD-B §10.7 *b*, con el teclado en Chrome y en Safari, el menú ⋮ incluido; VoiceOver, del desarrollador | La lista en el PR | — |
| **R3.13** | Cierre: los cinco pasos de `AGENTS.md` («Al cerrar una fase»), el mapa del plan del backoffice (§3) con el enganche en verde, el README de la web y lo aprendido | Las cifras buscadas por su número viejo en todo el árbol | Un commit |

---

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| **R3.1** | | |

---

## 9. Lo aprendido

*(Se escribe al cerrar.)*
