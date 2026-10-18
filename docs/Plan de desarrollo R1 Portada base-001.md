# Plan de desarrollo R1 · Portada base

> Rebanada 1 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Es el
> primer plan de rebanada con fichero propio (decidido con el desarrollador el 2026-10-18): toca la web y el
> servidor, y lo que se haga en el servidor se apunta **solo aquí**, también si es mini-fase.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md); la
> [auditoría 002](../backend/Plan%20de%20auditor%C3%ADa-002.md), que dejó aquí H-58; y la rebanada 0, cerrada el
> 2026-10-16 con **612 tests** en el backend y **4** en la web.
>
> **Convención de remisiones**, la misma del plan del backoffice: `LLD-B §x` y `DW-nn` son el LLD de la web y su
> anexo; `LLD §x` y `D-nn`, el LLD del backend y su bitácora; `H-nn`, la auditoría 002.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: BORRADOR.** Las decisiones de la §4 están **sin revisar** por el desarrollador, y nada
> de este plan se construye hasta que lo estén. Grabado así el 2026-10-18 para poder revisarlo desde otra sesión.
> Antes de él se hizo `D-101` (el código de la federación pasa a la inscripción): 612 → **632 tests** en el
> backend. Secciones 1 a 5 escritas para revisar. Las 6 (escenarios) y 7 (pasos) se escriben
> cuando estén tomadas las decisiones de la §4.

---

## 1. Objetivo

**La web deja de ser una página en blanco**: al abrir `celtic-castilla.localhost:5173` se ve el club, un menú
y la lista de sus equipos con la competición en la que juega cada uno y cómo va su ingesta.

Es la primera pantalla que lee datos de verdad, así que con ella llegan también las piezas que comparten todas
las demás: el marco (cabecera y menú), los mensajes de error y el modo claro u oscuro con su interruptor.

**Por qué es la primera** (el borrador, §2): es de solo lectura, así que no necesita todavía el inicio de
sesión; y enseña de un vistazo si la ingesta está haciendo su trabajo.

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **El marco**: cabecera con el escudo y el nombre corto del club, el interruptor «Cambiar a modo claro / oscuro» y el menú lateral, que de momento solo tiene «Equipos» | LLD-B §6.6, §8.1, §9.3 |
| **La página entera cuando el club no se puede cargar**: no existe, falta en la dirección, no está preparado, o el servidor no responde | LLD-B §8.3 |
| **«Esta página no existe»**, con un enlace a la portada, para cualquier camino que la web no conoce | LLD-B §6.7 |
| **La portada**: los equipos del club en la temporada en curso, con su competición, el estado de su ingesta y la fecha de la última sincronización | Ficha, §3 |
| **Los mensajes de error en español**, uno para cada código del servidor (`src/api/errors.ts`) | LLD-B §4 |
| **Los colores del tema**, medidos del boceto, con nombre y con un valor por modo | LLD-B §9.1, §9.2 |
| En el servidor, **tres operaciones nuevas** (`listSeasons`, `listCompetitions` y la lectura nueva de la pareja equipo–temporada, `listSeasonRegistrations`) y los cambios del catálogo que piden | §5 |

**Lo que no trae** (llega después): la posición, la racha y los partidos del boceto (rebanada 5); el botón
«Dar de alta un equipo» (rebanada 2); y entrar en la ficha de un equipo (rebanada 4).

---

## 3. La ficha de la pantalla

### 3.1 El marco, común a todas las pantallas

- **Al arrancar, la web pide el club** (`getClub`). Hasta que llega, se ve el marco vacío con «Cargando…»; no se
  pinta ninguna pantalla sin saber de qué club es (LLD-B §8.1).
- **La cabecera**: escudo (si el club tiene) y nombre corto. El nombre va también en la pestaña del navegador:
  «Equipos · Celtic Castilla».
- **El interruptor de modo**, en la cabecera. Dice lo que hace («Cambiar a modo oscuro»), no solo un dibujo, y la
  elección se recuerda en el navegador (`tema`, la excepción del LLD-B §2.3).
- **El menú lateral**, con «Equipos» como única entrada (LLD-B §6.6).
- **Un enlace «Saltar al contenido»** al principio de la página (LLD-B §10.1).
- **Si el club falla**, en vez del marco sale la página entera del LLD-B §8.3, sin menú:

| El servidor responde | Se enseña | ¿Reintentar? |
|---|---|---|
| `UNKNOWN_TENANT` | «Este club no existe. Revisa la dirección» | No |
| `TENANT_NOT_RESOLVED` | «Falta el club en la dirección», con el ejemplo `celtic-castilla.localhost:5173` | No |
| `TENANT_NOT_PROVISIONED` | «Este club aún no está preparado. Avisa a quien lo administra» | No |
| Nada en 30 s, sin conexión, o `DATABASE_UNAVAILABLE` | «No se ha podido conectar con el servidor» | Sí |

### 3.2 La portada (`/`)

**Qué pide al servidor**, en este orden:

1. `listSeasons`, para saber cuál es la temporada en curso (`isCurrent`). Qué hacer si no hay ninguna en curso,
   en la decisión 5 (§4).
2. A la vez, con el `id` de esa temporada:
   - `listSeasonRegistrations` (`GET /seasons/{seasonId}/registrations`): los equipos del club en esa
     temporada, cada uno **con sus competiciones** (decisión 1).
   - `listCompetitions?seasonId=…`: el nombre de cada competición y el estado de su ingesta.

Son **tres peticiones, tenga el club los equipos que tenga**. Nunca una por equipo.

**Qué enseña**: un título «Equipos», la temporada debajo («Temporada 2026/27») y una tabla con cabeceras de
verdad (LLD-B §10.4):

| Columna | De dónde sale | Ejemplo |
|---|---|---|
| **Equipo** | Categoría y letra del equipo, en español | Cadete B |
| **Competición** | `displayName` de la competición | Cadete · PRIMERA CADETE · Grupo 4 |
| **Ingesta** | `ingestionHealth`, en palabras y con un icono, **nunca solo con color** (LLD-B §9.4) | Al día |
| **Última sincronización** | `lastSyncedAt`, con fecha y hora | 17/10/2026 23:40 |

- **Un equipo que juega dos competiciones** (liga y copa, `D-12`) sale **en una sola fila**, con las dos
  competiciones una debajo de otra, cada una con su estado. Es lo que `D-68` pide: que la portada no enseñe dos
  veces el mismo equipo.
- **Un equipo inscrito sin competición todavía** (el estado de junio, `D-68`) sale con «Sin competición» y el
  texto «Se engancha con la federación desde la ficha del equipo». El enganche llega con la rebanada 3.
- **Hacer clic en un equipo no hace nada todavía**: la ficha del equipo llega con la rebanada 4.
- **La fecha y hora se escriben desde `src/theme/format.ts`** (LLD-B §9.6), así que ese fichero **se adelanta**
  a esta rebanada, solo con la fecha y la hora de un instante. La fecha sin hora de los partidos y su prueba en
  otra zona horaria siguen en la rebanada 4, como dice el plan del backoffice.

**Los cuatro estados** (LLD-B §3.1):

| Estado | Cómo se ve |
|---|---|
| **Cargando** | «Cargando equipos…», leído en voz alta sin mover el foco (LLD-B §10.3) |
| **Error** | El mensaje del código, en el hueco de la tabla, con *Reintentar* solo si el fallo puede ser pasajero (LLD-B §4.3, §4.4) |
| **Vacío** | Dos casos distintos, en la decisión 6 (§4): el club sin temporada y la temporada sin equipos |
| **Con datos** | La tabla |

**Adónde lleva**: a ningún sitio todavía. Es de solo lectura.

### 3.3 «Esta página no existe» (cualquier otro camino)

Título «Esta página no existe» y un enlace «Ir a la portada». Lo decide la web sin preguntar al servidor, con el
marco alrededor (LLD-B §6.7).

---

## 4. Decisiones antes de construir

Cada una dice qué propongo, por qué, y cómo verlo uno mismo. **Ningún paso de la §7 empieza sin que estén
tomadas.**

### Decisión 1 · El equipo y el equipo en una temporada: dos cosas, y cada una con su lectura

**La distinción** (señalada por el desarrollador el 2026-10-18): el **equipo** dura para siempre —«Cadete B» es
el mismo año tras año (`D-28`)—, y **el equipo en una temporada** es otra cosa, que dura esa temporada y apunta a
las competiciones en las que juega, con sus códigos de competición y de grupo.

**Cómo está hoy en cada capa:**

| Capa | El equipo (para siempre) | El equipo en una temporada |
|---|---|---|
| **Base de datos** | `teams`: categoría, letra, género y modalidad | `team_registrations`: (equipo, temporada, competición) y el código de equipo de la federación en esa competición (`D-68` con su enmienda, `D-101`). Los códigos de competición y grupo están en `competitions`, que es de una sola temporada |
| **Catálogo, escribir** | `POST /teams`, `PATCH /teams/{teamId}` | `PUT` y `DELETE /teams/{teamId}/registrations/{seasonId}`: la pareja **ya es un recurso** |
| **Catálogo, leer** | `GET /teams/{teamId}`, `GET /teams` | **Ninguna.** El filtro `?seasonId=` de `listTeams` dice qué equipos hay, pero no con qué competición (LLD §9.12) |
| **Web** | `/equipos/:id`: el camino nombra el equipo | `?temporada=2026-27` (LLD-B §6.5): elige la pareja |

**El hueco está solo en la lectura**: la pareja se puede escribir y no se puede leer. La salida *a* del LLD §9.12
lo tapaba metiendo las competiciones **dentro del equipo** cuando se pide con `?seasonId=`. **Se descarta**: el
mismo recurso cambiaría de forma según cómo se le pregunte, y lo de la temporada se mezclaría con lo permanente.

**Propuesta: la pareja tiene su propia lectura**, igual que ya tiene su propia escritura. Dos operaciones
nuevas en el catálogo (🆕), sobre el mismo recurso que ya existe:

| Operación | Camino | Qué devuelve | Se activa en |
|---|---|---|---|
| `listSeasonRegistrations` | `GET /seasons/{seasonId}/registrations` | Los equipos del club en esa temporada. Cada elemento es una pareja: `{ team, seasonId, competitionIds }`, con `team` igual que la respuesta de un equipo | **Esta rebanada** |
| `getTeamRegistration` | `GET /teams/{teamId}/registrations/{seasonId}` | Una sola pareja, la misma forma | La rebanada 4, la ficha del equipo |

- **La respuesta de un equipo no cambia nunca de forma**, y todo lo de la temporada viaja en la pareja. Si
  mañana aparece otro dato del equipo en una temporada, ya tiene sitio.
- **Sigue sin haber un identificador propio de la pareja**: se nombra por (equipo, temporada), como dice `D-68`.
- **Las competiciones de la pareja** salen de la inscripción y, además, de los partidos que la ingesta haya
  traído de una competición que nadie inscribió. Es la unión que `D-68` deja escrita en «Lo que se asume».
- **Solo equipos propios**: los rivales no se inscriben (`D-68`), y su temporada se sigue leyendo con
  `listTeams?seasonId=`.
- **La portada sigue siendo de tres peticiones**: temporadas, parejas de la temporada y competiciones de la
  temporada. El nombre y el estado de cada competición se cruzan **por identificador**, no por categoría o
  género, así que no es la «adivinanza» que el LLD §9.12 rechaza.
- **`listTeams` sale de esta rebanada**: la portada ya no la usa. Propuesta: pasa a la rebanada 12 (Rivales),
  que es la primera que lista equipos sin temporada (`?opponentClubId=`). El catálogo pasa de 83 a **85**
  operaciones, y el plan del backoffice (§4) se pone al día.

**El código de equipo de la federación es de la pareja, no del equipo** (`D-101`, hecho antes de esta
rebanada). El número de la federación no cambia de una temporada a otra
([Anexo RFFM §F.3.1](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md)), pero designa la **plaza** del club en
la división, no su «Juvenil A»: en Granollers, el A de una temporada es el B de la siguiente
([Anexo FCF §C.13](./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md)). Por eso el código ya va en la
inscripción de cada competición, y la pareja tiene un dato más propio.

**Lo que se escribe**: una decisión nueva en la bitácora del backend (`D-102`), porque cambia lo que responde el
servidor y las apps del móvil la heredan; las dos operaciones en el catálogo; el LLD §9.12, *resuelta* con esta
salida y no con la *a*; y el plan del backoffice (§4). **Es mini-fase**: cambia el catálogo.

**Cómo verlo**:

```sh
# El recurso de la pareja solo tiene escritura (put y delete, ningún get):
sed -n '/^  \/teams\/{teamId}\/registrations\/{seasonId}:/,/^  # ─/p' backend/Sources/APIContract/openapi.yaml | grep -E '^    (get|put|delete):'
# La base sí guarda la competición en la inscripción (en TablePlus, sobre club_celtic-castilla):
#   select t.category, t.letter, r.competition_id from teams t join team_registrations r on r.team_id = t.id;
```

### Decisión 2 · Cómo se lee el estado de la ingesta (H-58)

**El hueco**: la competición trae `ingestionHealth`, que puede ser `ok`, `failing`, `stale` o `never` (`D-89`),
pero ese cálculo no está programado, y la auditoría dejó cinco preguntas sin contestar «hasta tener la pantalla
delante». Ya la tenemos delante, y tu Alevín sirve de ejemplo. Esta es su última pasada (17/10, 23:40):

| Clase | Resultado |
|---|---|
| Calendario | bien |
| Clasificación | bien |
| Goleadores | **mal** (el `null` pasajero de la RFFM, H-61) |

**Propuesta**, pregunta a pregunta:

| # | Pregunta de H-58 | Propuesta |
|---|---|---|
| 2 | Una pasada deja varias filas: calendario, clasificación y goleadores. ¿Cuál es «la última pasada»? | **Cada clase por separado**: se mira la última fila de cada una, y la competición toma **la peor**. El Alevín sale **«Con fallos»**. Si solo contara el calendario, saldría «Al día» con los goleadores rotos. Una federación que no publica goleadores no tiene filas de esa clase, y esa clase no cuenta |
| 3 | ¿Se ordena por cuándo empezó o por cuándo acabó? | **Por cuándo empezó** (`startedAt`), como ya ordena el registro de pasadas. Por cuándo acabó, Postgres pone primero las que no han acabado, y salen respuestas distintas |
| 4 | La fila de una pasada pedida desde el enganche conserva la hora a la que se pidió, y queda por debajo de las de clasificación y goleadores de esa misma pasada | **Deja de importar** con la respuesta a la 2: esa fila solo se compara con otras de calendario |
| 1 y 5 | Una pasada pedida que no ha acabado (`accepted`) hoy se lee como `ok`. ¿Qué debe decir, y a partir de cuándo es sospechosa? | Un **valor nuevo, `pending`** («En marcha»), mientras lleve **menos de 15 minutos** pedida. Pasado ese tiempo, cuenta como **`failing`**: algo la dejó a medias. **Los 15 minutos**: medido, una pasada se cierra entre 1 y 5 s; en el peor caso, cada una de sus ~32 peticiones a la federación agota los 20 s de espera, y son ~11 minutos |

**El orden de los casos** pasa a ser: `failing` (incluida la pedida de hace más de 15 minutos) → `pending` →
`never` → `stale` → `ok`. Así, un fallo nunca queda tapado por una pasada en marcha.

**En la pantalla**: «Al día», «Con fallos», «En marcha», «Sin datos todavía» (`never`) y «Desactualizada»
(`stale`). Por qué falló una pasada no se enseña aquí. Eso es de la pantalla de Ingesta, en la rebanada 14.

**Lo que se escribe**: una enmienda fechada a `D-89` en la bitácora del backend; `pending` en el catálogo; y
H-58, cerrado en la auditoría con un enlace aquí. **Es mini-fase**: cambia el catálogo.

**Cómo verlo** (en TablePlus, sobre `club_celtic-castilla`):

```sql
select c.age_category, r.kind, r.outcome, r.started_at
from ingestion_runs r join competitions c on c.id = r.competition_id
order by c.age_category, r.started_at desc limit 12;
```

### Decisión 3 · La lista cerrada de códigos de error

Es lo que el LLD-B §4.5 dejó para esta rebanada, y solo toca el catálogo, ni una línea de Swift:

- **`code` pasa a tener la lista cerrada** (`enum`) de los **32** códigos que el servidor emite hoy. En la web,
  `errors.ts` se declara como «un mensaje para cada código de la lista»: si falta uno, **no compila**.
- **Cada rebanada que traiga códigos nuevos los añade a la lista** al activar sus operaciones.
- **El formato `<campo>: <motivo>` de `detail`** en los errores de valor queda escrito en la descripción del
  esquema `Problem` (LLD-B §4.5 *a*).
- El paso 2 del LLD-B §4.5 *b* (que el servidor use la lista generada) **sigue fuera**, sin prisa.

**Es mini-fase**: cambia el catálogo.

**Cómo verlo**:

```sh
# Los códigos que aparecen en el servidor (salen también los nombres de variables de entorno, DB_*, API_PORT…,
# que no son códigos):
grep -rhoE '"[A-Z][A-Z_]{3,}"' backend/Sources/HTTPAdapter backend/Sources/Tenancy | sort -u
```

### Decisión 4 · Cómo se prueban «cargando» y «error» sin simulacros (`DW-17`)

El ADR no admite simulacros (decisión 6). Pero el servidor de pruebas contesta en milisegundos, así que
«cargando» dura demasiado poco para verlo, y no falla si nadie lo tumba.

| Estado | Propuesta | Por qué no es un simulacro |
|---|---|---|
| **Cargando** | El escenario **retiene la respuesta de verdad**: Playwright deja pasar la petición al servidor de pruebas, guarda la respuesta y no la entrega hasta que el escenario lo dice. Mientras, se comprueba «Cargando equipos…» | La respuesta es la que dio el servidor, sin tocar. Solo cambia **cuándo** llega. Es el argumento de `DW-14`: todo es de verdad salvo lo que no se puede controlar |
| **Error, servidor caído** | El escenario **para el servidor de pruebas (8081)**, abre la portada y lo vuelve a arrancar al acabar. Arrancarlo cuesta **0,25 s** (medido en `R0.9`) | Es el fallo de verdad, como pide el plan del backoffice (§2.4, aviso 2). Nunca se toca el servidor del desarrollador ni su Postgres |
| **Error, el club no existe** | Abrir una dirección de un club que no hay | Es la situación real, sin preparar nada |

**Descartado**: añadir un retraso de mentira al servidor (sería código del servidor solo para las pruebas), y
probar el «cargando» solo con Vitest (la pantalla entera quedaría sin probar en ese estado).

**Lo que se escribe**: `DW-17` en el anexo del backoffice, y la regla en el LLD-B §11 en un commit aparte (LLD-B
§E.1), porque valdrá para todas las pantallas.

### Decisión 5 · Qué temporada enseña la portada

**Propuesta**: la **temporada en curso** (`isCurrent`), como dice el LLD-B §6.5. **Si no hay ninguna en curso**
(entre el 30 de junio y el día en que se crea la nueva), **la más reciente**, rotulada «Temporada 2025/26 ·
terminada». Si no, la portada se quedaría vacía todo el verano con los equipos ahí.

**Sin selector de temporada en esta rebanada**: no hay todavía nada que comparar. Llega con la ficha del equipo
(`?temporada=`, LLD-B §6.5).

**Cómo verlo**: tu club tiene una sola temporada, la 2026/27, y hoy es la que está en curso (TablePlus:
`select label, start_date, end_date from seasons;` sobre `club_celtic-castilla`).

### Decisión 6 · Qué dice la portada vacía

| Caso | Mensaje |
|---|---|
| El club no tiene ninguna temporada | «Todavía no hay ninguna temporada. Se crea al dar de alta el primer equipo.» |
| La temporada no tiene equipos inscritos | «Todavía no hay equipos en la temporada 2026/27.» |

Los dos **no son errores** (LLD-B §3.1): no van en rojo ni con icono de aviso. **El botón para dar de alta un
equipo no está todavía**: llega con la rebanada 2, que añade su enlace a estos dos mensajes.

**Ojo con el primero**: la rebanada 2 todavía tiene que decidir cómo nace la primera temporada de un club (plan
del backoffice, §4). Si allí se decide otra cosa, este mensaje se cambia en esa rebanada.

### Decisión 7 · Los colores del tema

**Propuesta**: medir los colores del boceto 1 con un cuentagotas (fondo, superficie de las tarjetas, verde
principal, texto y texto suave, y los tres de los resultados) y darles nombre en `src/theme/`, con su valor para
el modo oscuro (el del boceto) y otro para el claro. **axe comprueba el contraste en los dos modos** al final de
cada escenario. Si un color del boceto no llega al mínimo, se ajusta y se apunta en el registro.

No hay nada que decidir aquí salvo el visto bueno. Los valores se enseñan en su paso, con la web delante.

---

## 5. Lo que le falta al servidor

Todo con el método del backend: prueba → esqueleto que devuelve mal a propósito → rojo de aserción →
implementación → mutación con `Tools/Mutate`. Y `REQUIRE_DB=1 swift test`, nunca `swift test` a secas.

**Activar una operación** es añadirla al filtro de `openapi-generator-config.yaml` y programarla en sus cuatro
capas: el catálogo, la Aplicación (el caso de uso), la Persistencia (la consulta) y HTTP (el *handler*). Los
*handlers* se escriben **de la única forma** que dejó H-63: lanzan el error, y lo traduce el middleware.

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **El catálogo**: las dos lecturas de la pareja, `pending` en el estado de la ingesta, la lista de códigos y el formato de `detail` | `openapi.yaml` | **Sí**: cambia el catálogo | 1, 2, 3 |
| **`listSeasons`**: las temporadas del club, de la más reciente a la más antigua, sin las archivadas salvo que se pidan | Las cuatro | No, si el catálogo ya está cambiado | — |
| **`listCompetitions`**: las competiciones, con `lastIngestionAt` y `ingestionHealth` calculados al leer (`D-89`, con la enmienda de la decisión 2) | Las cuatro | No | 2 |
| **`listSeasonRegistrations`**: las parejas de una temporada, con sus competiciones (la unión de la decisión 1) | Las cuatro | No | 1 |

**Los filtros**: `listCompetitions` acepta cuatro en el catálogo, y `listSeasons` uno.
**Propuesta: se programan todos.** Un filtro que el catálogo acepta y el servidor ignora devolvería datos que no
se han pedido, sin avisar. Son condiciones sencillas sobre columnas que ya existen.

**Lo que ya está y se reutiliza**: los repositorios de temporadas y de competiciones (`SeasonRepository`,
`CompetitionRepository`), que hoy usa la ingesta, y las tablas de inscripciones y de pasadas. **De inscripciones no
hay todavía un repositorio de lectura**: se crea.

**Al terminar**, el servidor sirve **9 de las 85** operaciones.

---

## 6. Los escenarios

*Pendiente: se escriben cuando estén tomadas las decisiones de la §4.*

## 7. Los pasos

*Pendiente: se escriben cuando estén tomadas las decisiones de la §4.*

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| — | — | — |

**Punto de partida: 612 tests en el backend, 4 en la web.**

**Hallazgos de la rebanada 1** (no venían en el plan; cada uno en su commit): ninguno todavía.
