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
> 2026-10-16 con 612 tests en el backend y **4** en la web. Antes de esta rebanada se hizo `D-101` (el código de
> la federación pasa a la inscripción): 612 → **632 tests** en el backend.
>
> **Convención de remisiones**, la misma del plan del backoffice: `LLD-B §x` y `DW-nn` son el LLD de la web y su
> anexo; `LLD §x` y `D-nn`, el LLD del backend y su bitácora; `H-nn`, la auditoría 002.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: decisiones revisadas.** Las siete de la §4 se revisaron una a una con el desarrollador
> el 2026-10-18, y las secciones 2 a 5 están escritas con lo acordado. La §6 (escenarios) es una **lista
> provisional**, y la §7 (pasos), revisada el mismo día. Se empieza por `R1.1`.

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
| **La portada**: los equipos del club en una temporada, con su competición, el estado de su ingesta y la fecha de la última sincronización. **Con selector de temporada**: por defecto, la que está en curso | Ficha, §3.2 · decisión 5 |
| **Los mensajes de error en español**, uno para cada código del servidor (`src/api/errors.ts`), y el de «no se ha podido conectar» cuando el servidor está caído detrás del recepcionista | LLD-B §4 · decisiones 3 y 4 |
| **La paleta en un solo fichero** (`src/theme/palette.ts`): cambiar los colores de la web es tocar ese fichero y nada más | LLD-B §9.1, §9.2 · decisión 7 |
| En el servidor, **tres operaciones nuevas** (`listSeasons`, `listCompetitions` y la lectura del equipo en una temporada, `listSeasonRegistrations`) y los cambios del catálogo que piden | §5 |

**Lo que no trae** (llega después): la posición, la racha y los partidos del boceto (rebanada 5); el botón
«Dar de alta un equipo» (rebanada 2); entrar en la ficha de un equipo (rebanada 4); y una paleta propia de cada
club (pendiente, decisión 7).

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
| Nada en 30 s, sin conexión, `DATABASE_UNAVAILABLE`, o **un 502, 503 o 504 sin código** (el servidor está caído detrás del recepcionista, decisión 4) | «No se ha podido conectar con el servidor» | Sí |

### 3.2 La portada (`/` y `/?temporada=2025-26`)

**Qué temporada enseña** (decisión 5):

| Dirección | Se enseña |
|---|---|
| `/` | La temporada en curso (`isCurrent`). Si no hay ninguna, la más reciente, con su rótulo según la fecha: «Temporada 2025/26 · terminada» o «Temporada 2027/28 · todavía no ha empezado» |
| `/?temporada=2025-26` | Esa temporada (LLD-B §6.5: con guion en la dirección, con barra en el rótulo) |
| `/?temporada=2019-20` (no existe) o `/?temporada=abc` | El estado de error de la tabla: «No hay ninguna temporada 2019/20», con un enlace a la temporada en curso. Lo decide la web con la lista de temporadas, sin preguntar al servidor |

**Qué pide al servidor**, en este orden:

1. `listSeasons`, para rellenar el selector y saber cuál es la temporada en curso.
2. A la vez, con el `id` de la temporada elegida:
   - `listSeasonRegistrations` (`GET /seasons/{seasonId}/registrations`): los equipos del club en esa
     temporada, cada uno **con sus competiciones** (decisión 1).
   - `listCompetitions?seasonId=…`: el nombre de cada competición y el estado de su ingesta.

Al abrir, **tres peticiones, tenga el club los equipos que tenga**. Al cambiar de temporada, **dos**: la lista de
temporadas ya está. Nunca una por equipo.

**Qué enseña**: un título «Equipos», el selector de temporada junto a él, y una tabla con cabeceras de verdad
(LLD-B §10.4):

| Columna | De dónde sale | Ejemplo |
|---|---|---|
| **Equipo** | Categoría y letra del equipo, en español | Cadete B |
| **Competición** | `displayName` de la competición | Cadete · PRIMERA CADETE · Grupo 4 |
| **Ingesta** | `ingestionHealth`, en palabras y con un icono, **nunca solo con color** (LLD-B §9.4). Si está «En marcha» y la anterior falló, debajo y más pequeño: «La anterior tuvo fallos» (decisión 2) | Al día |
| **Última sincronización** | `lastSyncedAt`, con fecha y hora | 17/10/2026 23:40 |

- **El selector de temporada**: con su etiqueta «Temporada», no solo el desplegable. Lista las temporadas de la
  más reciente a la más antigua, sin las archivadas. Al cambiarlo **cambia la dirección** (`?temporada=…`), así
  que «Atrás» vuelve a la anterior y el enlace se puede compartir. Con una sola temporada se enseña igual, con
  esa opción. **Solo no se enseña si el club no tiene ninguna** (decisión 6).
- **Un equipo que juega dos competiciones** (liga y copa, `D-12`) sale **en una sola fila**, con las dos
  competiciones una debajo de otra, cada una con su estado. Hoy cada equipo juega una sola por temporada, pero
  la respuesta ya trae una lista (decisión 1) y la pantalla la pinta entera.
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
| **Error** | El mensaje del código, en el hueco de la tabla, con *Reintentar* solo si el fallo puede ser pasajero (LLD-B §4.3, §4.4). También la temporada de la dirección que no existe |
| **Vacío** | Dos casos distintos, en la decisión 6: el club sin temporada y la temporada sin equipos |
| **Con datos** | La tabla. **Una temporada con equipos sin competición no está vacía**: salen sus filas con «Sin competición» |

**Adónde lleva**: a ningún sitio todavía. Es de solo lectura.

### 3.3 «Esta página no existe» (cualquier otro camino)

Título «Esta página no existe» y un enlace «Ir a la portada». Lo decide la web sin preguntar al servidor, con el
marco alrededor (LLD-B §6.7).

---

## 4. Decisiones antes de construir

Las siete se revisaron una a una con el desarrollador el 2026-10-18. Cada una dice qué se decidió, por qué, y
cómo verlo uno mismo.

### Decisión 1 · El equipo y el equipo en una temporada: dos cosas, y cada una con su lectura

**La distinción** (señalada por el desarrollador): el **equipo** dura para siempre —«Cadete B» es el mismo año
tras año (`D-28`)—, y **el equipo en una temporada** es otra cosa, que dura esa temporada y apunta a las
competiciones en las que juega.

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

**Decidido: la pareja tiene su propia lectura**, igual que ya tiene su propia escritura. Dos operaciones nuevas
en el catálogo, sobre el mismo recurso que ya existe:

| Operación | Camino | Qué devuelve | Se activa en |
|---|---|---|---|
| `listSeasonRegistrations` | `GET /seasons/{seasonId}/registrations` | Los equipos del club en esa temporada, un elemento por equipo | **Esta rebanada** |
| `getTeamRegistration` | `GET /teams/{teamId}/registrations/{seasonId}` | Una sola pareja, con la misma forma | La rebanada 4, la ficha del equipo |

**La forma de cada elemento**:

```
{ team, seasonId, competitions: [ { competitionId, federationTeamId } ] }
```

- `team` es igual que la respuesta de un equipo. **La respuesta de un equipo no cambia nunca de forma**, y todo
  lo de la temporada viaja en la pareja.
- **`competitions` es una lista.** Hoy cada equipo juega una sola competición por temporada, pero la lista no
  molesta y deja sitio a la copa (`D-12`). En la fila de junio, sin competición, va vacía.
- **`federationTeamId` es el código del equipo en esa competición**: desde `D-101` vive en la inscripción, y
  `D-101` dice que el del equipo propio, cuando se lea, viene con ella. La portada no lo enseña, pero la ficha
  del equipo (rebanada 4) sí lo necesitará, y así la forma no cambia entre rebanadas.
- **Sigue sin haber un identificador propio de la pareja**: se nombra por (equipo, temporada), como dice `D-68`.
- **Solo equipos propios**: los rivales no se inscriben (`D-68`), y su temporada se sigue leyendo con
  `listTeams?seasonId=`.

**Las competiciones salen solo de la inscripción, sin unión con los partidos.** El borrador las sacaba de la
inscripción **y además** de los partidos de competiciones que nadie inscribió, como pedía `D-68` en «Lo que se
asume». **Desde `D-101` ese caso no puede darse**: la pasada reconoce a un equipo propio solo por el código de
su inscripción en la competición que recorre. En una competición sin inscripción, la ingesta trata al equipo
como un rival (no crea equipos propios, `D-66`), y sus partidos quedan a nombre de ese rival. Buscar en los
partidos no encontraría nunca nada. *(Lo que sí queda abierto, y no es de esta rebanada: enganchar tarde esa
competición daría `FEDERATION_TEAM_ID_TAKEN`, el caso de `C-E.10`, que se resuelve al programar
`PUT /teams/{teamId}/ownership`.)*

**La portada sigue siendo de tres peticiones**: temporadas, parejas de la temporada y competiciones de la
temporada. El nombre y el estado de cada competición se cruzan **por identificador**, no por categoría o
género, así que no es la «adivinanza» que el LLD §9.12 rechaza.

**`listTeams` sale de esta rebanada**: la portada ya no la usa. Pasa a la rebanada 12 (Rivales), que es la
primera que lista equipos sin temporada (`?opponentClubId=`). El catálogo pasa de 83 a **85** operaciones.

**Lo que se escribe**: `D-102` en la bitácora del backend (cambia lo que responde el servidor, y las apps del
móvil lo heredan), con la nota de que la unión de `D-68` («Lo que se asume») dejó de valer con `D-101`; las dos
operaciones en el catálogo; el LLD §9.12, *resuelta* con esta salida y no con la *a*; y el plan del backoffice
(§4: `listTeams` a la rebanada 12, y 85 operaciones). **Es mini-fase**: cambia el catálogo.

**Cómo verlo**:

```sh
# El recurso de la pareja solo tiene escritura (put y delete, ningún get):
sed -n '/^  \/teams\/{teamId}\/registrations\/{seasonId}:/,/^  # ─/p' backend/Sources/APIContract/openapi.yaml | grep -E '^    (get|put|delete):'
# La pasada saca los códigos propios solo de las inscripciones de la competición que recorre:
sed -n 75,78p backend/Sources/Application/CalendarPass.swift
```

### Decisión 2 · Cómo se lee el estado de la ingesta (H-58)

**El hueco**: la competición trae `ingestionHealth`, que puede ser `ok`, `failing`, `stale` o `never` (`D-89`),
pero ese cálculo no está programado, y la auditoría dejó cinco preguntas sin contestar «hasta tener la pantalla
delante». El Alevín sirve de ejemplo. Esta es su última pasada (17/10, 23:40):

| Clase | Resultado |
|---|---|
| Calendario | bien |
| Clasificación | bien |
| Goleadores | **mal** (el `null` pasajero de la RFFM, H-61) |

**Decidido**, pregunta a pregunta:

| # | Pregunta de H-58 | Decisión |
|---|---|---|
| 2 | Una pasada deja varias filas: calendario, clasificación y goleadores. ¿Cuál es «la última pasada»? | **Cada clase por separado**: se mira la última fila de cada una, y la competición toma **la peor**. El Alevín sale **«Con fallos»**. Si solo contara el calendario, saldría «Al día» con los goleadores rotos. Una federación que no publica goleadores no tiene filas de esa clase, y esa clase no cuenta. Vale también para la clasificación, que deja una fila por jornada: la pasada **se para en la primera jornada que falla** (`IngestStandings.swift:136-137`), así que su última fila es la del fallo |
| 3 | ¿Se ordena por cuándo empezó o por cuándo acabó? | **Por cuándo empezó** (`startedAt`), como ya ordena el registro de pasadas. Por cuándo acabó, Postgres pone primero las que no han acabado, y salen respuestas distintas |
| 4 | La fila de una pasada pedida desde el enganche conserva la hora a la que se pidió, y queda por debajo de las de clasificación y goleadores de esa misma pasada | **Deja de importar** con la respuesta a la 2: esa fila solo se compara con otras de calendario |
| 1 y 5 | Una pasada pedida que no ha acabado (`accepted`) hoy se lee como `ok`. ¿Qué debe decir, y a partir de cuándo es sospechosa? | Un **valor nuevo, `pending`** («En marcha»). Se vuelve sospechosa —y cuenta como **`failing`**— cuando pasan **15 minutos sin que acabe ninguna pasada del club**, contando desde la hora a la que se pidió o desde la última pasada que acabó, la más reciente de las dos. Explicado abajo |

**Por qué el reloj vuelve a cero, y no un umbral fijo.** El borrador ponía 15 minutos desde que se pidió, pensando
en **una** competición (~32 peticiones a la federación, 20 s cada una como mucho: ~11 minutos). Pero el botón de
sincronizar la temporada escribe una fila `accepted` **para cada competición, todas con la misma hora**, y luego
las pasa **una detrás de otra** (`IngestClubCalendars.swift:235-251`). Con 20 competiciones y la federación
lenta, la última seguiría esperando su turno a los 15 minutos sin que nada hubiera fallado, y la portada daría
una falsa alarma.

Lo que hace sospechosa a una fila no es que espere mucho, sino que **la cola esté parada**. Así que el reloj
vuelve a cero cada vez que acaba **cualquier** pasada del club, **bien o mal**: si la competición 5 falla, el
recorrido sigue con la 6 (`D-86`) y la cola avanza. Si el servidor se cae a mitad, ya no acaba ninguna, y a los
15 minutos las que quedaban pasan a «Con fallos».

- **Cuesta una consulta**: cada club tiene su propia tabla `ingestion_runs`, así que basta «¿a qué hora acabó la
  última pasada de este club?» (`max(finished_at)`). Sin columna nueva y sin migración.
- **Cubre también el cron**: sus pasadas escriben su hora de fin en la misma tabla.
- **Descartadas**: subir el umbral hasta cubrir una temporada entera (casi 4 horas con 20 competiciones; una
  huérfana de verdad saldría «En marcha» toda la tarde), y preguntar a la memoria del servidor qué tiene en cola
  (`IngestionsInFlight`), que habría que sacar de la capa HTTP y no ve el cron.
- **Lo que se asume**: mientras otras pasadas del club vayan acabando, una huérfana sigue «En marcha»; se detecta
  15 minutos después de que pare la cola. Es un retraso con límite.

**«En marcha» va por delante del fallo anterior.** Una pasada pedida hace las tres clases de esa competición:
el calendario y los goleadores, enteros; la clasificación, las jornadas que no tienen todavía su foto, que
incluyen la que falló. O sea, vuelve a hacer **todo lo que estaba mal**, y mientras está en marcha lo que pasa
de verdad es que se está reintentando. Para no perder el fallo anterior, la competición trae **un campo nuevo,
`previousIngestionHealth`**: el estado que tendría sin la pasada en marcha. Solo viene cuando el estado es
`pending`.

**El orden de los casos**:

| Orden | Estado | Cuándo |
|---|---|---|
| 1 | `failing` | hay una pasada pedida, y lleva 15 minutos sin acabar ninguna pasada del club |
| 2 | `pending` | hay una pasada pedida, y la cola avanza |
| 3 | `failing` | la última fila de alguna clase falló |
| 4 | `never` | nunca hubo una pasada con éxito |
| 5 | `stale` | el último éxito es de hace más de una semana (§5.6) |
| 6 | `ok` | el resto |

**En la pantalla**: «Al día», «Con fallos», «En marcha», «Sin datos todavía» (`never`) y «Desactualizada»
(`stale`). Con `pending` y la anterior `failing`, debajo y más pequeño: «La anterior tuvo fallos», con su icono.
Por qué falló una pasada no se enseña aquí: es de la pantalla de Ingesta, en la rebanada 14. *(Si en la pasada
nueva falla el calendario, la clasificación y los goleadores no llegan a ejecutarse; al acabar, la competición
sale «Con fallos», que es la verdad.)*

**Lo que se escribe**: una enmienda fechada a `D-89` en la bitácora del backend, con el orden nuevo y el reloj
que vuelve a cero; `pending` y `previousIngestionHealth` en el catálogo, y la descripción de `IngestionHealth`
rehecha; y H-58, decidido en la auditoría con un enlace aquí, que se cierra al programarlo (`R1.8`). **Es
mini-fase**: cambia el catálogo.

**Cómo verlo**:

```sql
-- En TablePlus, sobre club_celtic-castilla: las últimas pasadas, por competición y clase
select c.age_category, r.kind, r.outcome, r.started_at, r.finished_at
from ingestion_runs r join competitions c on c.id = r.competition_id
order by c.age_category, r.started_at desc limit 12;
```

```sh
# Todas las filas aceptadas de una temporada, con la misma hora, y pasadas una detrás de otra:
sed -n 235,251p backend/Sources/Application/IngestClubCalendars.swift
```

### Decisión 3 · La lista cerrada de códigos de error

Es lo que el LLD-B §4.5 dejó para esta rebanada:

- **`code` pasa a tener la lista cerrada** (`enum`) de los **32** códigos que el servidor emite hoy: 31 escritos
  tal cual en `Sources/` y `NOT_FOUND`, que sale de una condición en `ProblemMiddleware.swift:454`. En la web,
  `errors.ts` se declara como «un mensaje para cada código de la lista»: si falta uno, **no compila**. Un código
  que la lista no tenga (un servidor más nuevo que la web, o las apps del móvil) sigue cayendo en el mensaje
  genérico de su familia (LLD-B §4.1).
- **Sí toca Swift, aunque poco.** El LLD-B §4.5 *b* decía «ni una línea de Swift», y **no es así**: la función
  `problem(...)` de `ClubHandler.swift:221-226` construye el error **con el tipo generado del catálogo**, y
  recibe el código como texto. Con la lista cerrada, el tipo generado deja de aceptar un texto y **sus 8
  llamadas** (en `ClubHandler`, `FederationLinkHandler` e `IngestionHandler`) no compilan. Se cambia para que
  reciba el código de la lista: unas 10 líneas, y esos 8 quedan comprobados al compilar. Se corrige la frase del
  LLD-B.
- **El censo vigila la lista.** Los otros 24 códigos los escribe `ProblemMiddleware` como texto libre, y siguen
  así: un código nuevo que se olvide en el catálogo no lo avisaría nada. **El censo** (`backend/Tools/Census`),
  que ya busca los códigos que emite el servidor, **comprueba además que cada uno está en la lista**, y sale con
  `1` si falta alguno. Ya se pasa al añadir cada endpoint.
- **Cada rebanada que traiga códigos nuevos los añade a la lista** al activar sus operaciones.
- **El formato `<campo>: <motivo>` de `detail`** en los errores de valor queda escrito en la descripción del
  esquema `Problem` (LLD-B §4.5 *a*).
- El paso 2 del LLD-B §4.5 *b* (que `ProblemMiddleware` use la lista generada) **sigue fuera**, sin prisa.

**Es mini-fase**: cambia el catálogo.

**Cómo verlo**:

```sh
grep -rhoE 'code: "[A-Z_]+"' backend/Sources | sort -u          # los 31; el 32, en ProblemMiddleware.swift:454
sed -n 221,226p backend/Sources/HTTPAdapter/ClubHandler.swift   # la función que deja de compilar
```

### Decisión 4 · Cómo se prueban «cargando» y «error» sin simulacros (`DW-17`)

El ADR no admite simulacros (decisión 6). Pero el servidor de pruebas contesta en milisegundos, así que
«cargando» dura demasiado poco para verlo, y no falla si nadie lo tumba.

| Estado | Decisión | Por qué no es un simulacro |
|---|---|---|
| **Cargando** | El escenario **retiene la petición**: Playwright la para antes de que salga, se comprueba «Cargando equipos…» y luego la suelta tal cual | La petición llega al servidor de verdad y la respuesta vuelve sin que nadie la toque. Solo cambia **cuándo** sale. Es el argumento de `DW-14`: todo es de verdad salvo lo que no se puede controlar |
| **Error, página entera** (falla el club) | Se **para el servidor de pruebas (8081)** y se abre la portada. Al acabar se vuelve a arrancar: cuesta **0,25 s** (medido en `R0.9`) | Es el fallo de verdad, como pide el plan del backoffice (§2.4, aviso 2). Nunca se toca el servidor del desarrollador ni su Postgres |
| **Error en la tabla** (el club carga, falla la portada) | Se retiene la petición de temporadas, se para el servidor y se suelta la petición: va a un servidor parado y falla de verdad. Después se arranca otra vez el servidor y se pulsa **Reintentar**: salen los equipos | Lo mismo: el fallo es real, y solo se elige el momento |
| **Error, el club no existe** | Abrir una dirección de un club que no hay | Es la situación real, sin preparar nada |

**Por qué hacen falta los dos errores de servidor**: lo primero que pide la web es el club (§3.1). Con el
servidor parado antes de abrir, falla el club y sale la página entera; el error dentro de la tabla no llega a
verse. Cada uno se prueba por su lado.

**Lo que recibe la web con el servidor parado no es «sin conexión»** (medido el 2026-10-18). La web no habla con
el servidor directamente: pasa por el recepcionista (Vite en desarrollo, Caddy en producción). Si el servidor no
está, **el recepcionista contesta 502 sin cuerpo**:

```
HTTP/1.1 502 Bad Gateway
Content-Type: text/plain
(cuerpo vacío)
```

Por el LLD-B §4.1 saldría el mensaje genérico de «error del servidor», sin Reintentar. **Regla nueva**: un 502,
503 o 504 **sin código** es «No se ha podido conectar con el servidor», con Reintentar. Los 502 y 504 del propio
servidor (la federación, `INGESTION_FAILED`) traen su `code`, así que no se confunden. Con Caddy pasa lo mismo,
así que el escenario prueba lo que pasará en producción.

**Descartado**: añadir un retraso de mentira al servidor (sería código del servidor solo para las pruebas), y
probar el «cargando» solo con Vitest (la pantalla entera quedaría sin probar en ese estado).

**Los escenarios se pueden permitir parar el 8081** porque se ejecutan de uno en uno (`cucumber.mjs` no pide
ejecución en paralelo).

**Lo que se escribe**: `DW-17` (retener la petición y parar el servidor de pruebas) y la regla en el LLD-B §11;
`DW-18` (el 502/503/504 sin código) y la regla en el LLD-B §4.1. Las dos en un commit aparte (LLD-B §E.1),
porque valdrán para todas las pantallas.

**Cómo verlo**:

```sh
cd backoffice && BACKOFFICE_API_URL=http://127.0.0.1:8099 npx vite --port 5199 &
curl -i -H 'Host: celtic-castilla.localhost:5199' http://127.0.0.1:5199/api/v1/club   # 502 sin cuerpo
kill %1
```

### Decisión 5 · Qué temporada enseña la portada, y el selector

**Decidido**: la portada **tiene selector de temporada** desde esta rebanada (señalado por el desarrollador). Sale
casi gratis: la lista de temporadas ya se pide para encontrar la que está en curso, y las dos lecturas de la
portada ya reciben la temporada (`/seasons/{seasonId}/registrations`, `listCompetitions?seasonId=`). Ni
peticiones nuevas ni cambios en el servidor.

- **Sin `?temporada=`, la temporada en curso** (`isCurrent`), como dice el LLD-B §6.5. Cada temporada va **del
  1 de julio al 30 de junio** (`SeasonLabel.swift:90-94`), sin huecos, así que solo puede no haber ninguna en
  curso cuando **la de este año todavía no se ha creado** (de julio a que se engancha el primer equipo). Entonces,
  **la más reciente**, con un rótulo según la fecha: «terminada» si ya acabó, «todavía no ha empezado» si se creó
  por adelantado.
- **Con `?temporada=`, esa**. Si no existe o no se entiende, el error de la §3.2, sin preguntar al servidor.
- **El selector**: lo de la §3.2. Con él desaparece el problema de junio: el club da de alta en junio los equipos
  de la temporada siguiente (`D-68`), y los ve eligiéndola.
- **Las archivadas no cuentan**: `listSeasons` las quita salvo que se pidan, así que no salen en el selector ni
  como «la más reciente».

**Lo que se escribe**: el LLD-B §6.5, que hoy pone de ejemplo `/equipos/:id/plantilla`, gana la portada.

**Cómo verlo**:

```sh
sed -n 89,94p backend/Sources/Domain/SeasonLabel.swift   # 1 de julio a 30 de junio
```

Y en TablePlus, sobre `club_celtic-castilla`: `select label, start_date, end_date, archived_at from seasons;`.

### Decisión 6 · Qué dice la portada vacía

| Caso | Selector | Mensaje |
|---|---|---|
| El club no tiene ninguna temporada | No | «Todavía no hay ninguna temporada.» |
| La temporada elegida no tiene equipos | Sí | «No hay equipos en la temporada 2025/26.» |

- **No son errores** (LLD-B §3.1): no van en rojo ni con icono de aviso.
- **El primer mensaje no promete cómo nace una temporada.** El borrador decía «Se crea al dar de alta el primer
  equipo», y no es así: `POST /teams` exige la temporada (`D-68`, punto 2), así que la temporada tiene que
  existir antes. Hoy solo la crea la cascada del enganche (`D-67`), que necesita un equipo; el catálogo tiene
  además `POST /seasons` (`createSeason`), sin activar. Cómo nace la primera temporada lo decide la rebanada 2
  (plan del backoffice, §4), que añadirá a este mensaje el botón y su explicación.
- **El segundo no dice «todavía»**: con el selector se puede elegir una temporada terminada. Es raro que pase,
  porque el enganche crea la temporada y la inscripción a la vez; pasa si se retira la inscripción
  (`DELETE /teams/{teamId}/registrations/{seasonId}`) o si la temporada se creó con `seed-competition`.
- **Sin temporadas no hay selector**: no hay nada que elegir. Es el único caso en que no se enseña.

### Decisión 7 · Los colores: provisionales, y fáciles de cambiar

**Lo que pide el desarrollador**: los colores del boceto son provisionales —salieron de entre las dos o tres
opciones que ofreció Stitch—, irán cambiando, y es probable que cada club quiera su paleta. **Lo que importa es
que cambiarlos sea fácil.**

**Decidido: una paleta en un solo fichero**, `src/theme/palette.ts`, con **pocos colores base** y sus dos modos:

```ts
export const palette = {
  principal: '#…',      // botones, enlaces, lo seleccionado
  oscuro: { fondo: '#…', superficie: '#…', texto: '#…', textoSuave: '#…' },
  claro:  { fondo: '#…', superficie: '#…', texto: '#…', textoSuave: '#…' },
}
```

- **Cambiar los colores de la web es tocar ese fichero y nada más.** Ninguna pantalla escribe un color a mano
  (LLD-B §9.2). Los tonos del principal (más claro al pasar el ratón, más oscuro al pulsar) los calcula PrimeVue
  a partir de uno.
- **Aura pasa a ser la base con la paleta encima** (`src/theme/primevue.ts`, hoy Aura sin tocar).
- **Los colores de los estados** (fallo, aviso, en marcha), que el boceto no tiene, y **el modo claro**, que el
  boceto tampoco tiene, **se toman de Aura** mientras nadie diga otra cosa. Se les da nombre por lo que
  significan (LLD-B §9.2). El fichero se queda con lo que de verdad identifica la web.
- **Valores de partida**: los del boceto 1 (`docs/design-assets/mobile/1-Teams_Dashboard.png`), tomados a ojo.
  No se miden con precisión, porque van a cambiar.
- **axe vigila el contraste en los dos modos** al final de cada escenario: una paleta que no se lee hace fallar
  el escenario y dice qué texto.
- **Los colores de los resultados** (victoria, empate, derrota) no salen en esta portada: se definen con la
  rebanada 5, que es la que los pinta y la que puede comprobar su contraste.

**Para cuando cada club tenga la suya** (no es de esta rebanada): la paleta es un objeto que se aplica al
arrancar, y PrimeVue permite cambiar el tema con la web abierta. Así que bastará con que la web, que ya pide el
club al arrancar, aplique la suya si la tiene; el club tiene un campo `settings` en el catálogo (`D-23`) donde
podría ir. **Una paleta que elige el club puede no llegar al contraste mínimo**, y entonces habrá que comprobarla
al guardarla, no al pintarla. Se apunta como pendiente en el plan del backoffice (§4).

---

## 5. Lo que le falta al servidor

Todo con el método del backend: prueba → esqueleto que devuelve mal a propósito → rojo de aserción →
implementación → mutación con `Tools/Mutate`. Y `REQUIRE_DB=1 swift test`, nunca `swift test` a secas.

**Activar una operación** es añadirla al filtro de `openapi-generator-config.yaml` y programarla en sus cuatro
capas: el catálogo, la Aplicación (el caso de uso), la Persistencia (la consulta) y HTTP (el *handler*). Los
*handlers* se escriben **de la única forma** que dejó H-63: lanzan el error, y lo traduce el middleware.

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **El catálogo**: las dos lecturas de la pareja, con su forma; `pending` y `previousIngestionHealth` en el estado de la ingesta, con la descripción rehecha; la lista cerrada de códigos; y el formato de `detail` | `openapi.yaml` | **Sí**: cambia el catálogo | 1, 2, 3 |
| **La función `problem(...)` de los *handlers***, que pasa a recibir el código de la lista, y sus 8 llamadas | HTTP | Va con la anterior: sin ella no compila | 3 |
| **El censo comprueba la lista**: cada código que emite el servidor está en el `enum` del catálogo | `Tools/Census` | No | 3 |
| **`listSeasons`**: las temporadas del club, de la más reciente a la más antigua, sin las archivadas salvo que se pidan | Las cuatro | No, si el catálogo ya está cambiado | 5 |
| **`listCompetitions`**: las competiciones, con `lastIngestionAt`, `ingestionHealth` y `previousIngestionHealth` calculados al leer (`D-89`, con la enmienda de la decisión 2). Por dentro, la última fila de cada clase por competición y la hora de la última pasada del club que acabó | Las cuatro | No | 2 |
| **`listSeasonRegistrations`**: las parejas de una temporada, con sus competiciones y su código, **solo de la inscripción** | Las cuatro | No | 1 |

**Los filtros**: `listCompetitions` acepta cuatro en el catálogo, y `listSeasons` uno. **Se programan todos.** Un
filtro que el catálogo acepta y el servidor ignora devolvería datos que no se han pedido, sin avisar. Son
condiciones sencillas sobre columnas que ya existen.

**Lo que ya está y se reutiliza**: los repositorios de temporadas y de competiciones (`SeasonRepository`,
`CompetitionRepository`), que hoy usa la ingesta, y las tablas de inscripciones y de pasadas. **El de
inscripciones también existe** (`TeamRegistrationRepository`, `IngestionRepositories.swift:83`): lee por
(equipo, temporada) y por competición, y **solo le falta leer por temporada**. Se le añade esa lectura.

**Al pasar el censo** con las tres operaciones activadas, saldrán campos nuevos sin nombrar en ningún test: se
escriben sus tests o se apuntan en `known-gaps.json` con su motivo, como dice su README.

**Al terminar**, el servidor sirve **9 de las 85** operaciones.

---

## 6. Los escenarios

**Lista provisional.** Lo que hay que probar de punta a punta, sacado de la ficha (§3) y de las decisiones (§4).
Los `.feature` **se escriben al final**, con la *skill* de escenarios del desarrollador, porque la lista irá
cambiando mientras se construye. Al final de cada escenario, axe en los dos modos, como ya hace el arnés.

**El marco** (§3.1)

- Se ve el nombre del club en la cabecera y en la pestaña del navegador.
- El interruptor cambia de modo, y la elección se recuerda al volver a abrir la web.
- «Saltar al contenido» lleva el foco a la tabla.
- Un camino que la web no conoce enseña «Esta página no existe», con un enlace a la portada (§3.3).

**El club que falla: la página entera** (§3.1)

- El club no existe.
- Falta el club en la dirección.
- El club no está preparado.
- El servidor está parado: «No se ha podido conectar con el servidor», con Reintentar (decisión 4).

**La portada** (§3.2)

- Con datos: un equipo con su competición, su estado de ingesta y su fecha de sincronización.
- Un equipo inscrito sin competición sale con «Sin competición».
- Un escenario por estado de la ingesta: «Al día», «Con fallos», «En marcha», «En marcha» con «La anterior tuvo
  fallos», «Sin datos todavía» y «Desactualizada» (decisión 2).
- Cargando: se retiene la petición y se ve «Cargando equipos…» (decisión 4).
- Error en la tabla: falla la portada con el club ya cargado, y Reintentar con el servidor de vuelta enseña los
  equipos (decisión 4).

**La temporada** (decisión 5)

- Sin `?temporada=`, la portada enseña la temporada en curso.
- Sin ninguna en curso, enseña la más reciente con su rótulo.
- Cambiar el selector cambia la dirección, y «Atrás» vuelve a la temporada anterior.
- Una temporada de la dirección que no existe enseña su error, con el enlace a la temporada en curso.

**Vacío** (decisión 6)

- El club sin temporadas: su mensaje, y sin selector.
- La temporada sin equipos: su mensaje.

## 7. Los pasos

Cada paso dice qué se hace, cómo se comprueba y qué se graba. **Al acabar cada uno se para** y se espera el visto
bueno del desarrollador antes del siguiente, y su renglón va en la §8. Cada paso deja el árbol en verde por sí
solo, y lo que no venga en el plan va en su propio commit.

### A · Los documentos de las decisiones

Antes del código, para que el código se escriba contra algo ya escrito.

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R1.1** | Backend: `D-102` (decisión 1), la enmienda de `D-89` (decisión 2), H-58 decidido en la auditoría con un enlace aquí, y el LLD (§3.4, las tablas de rutas de `Season` y `Team`, la nota de `/ingestion-runs` y §9.12 *resuelta*) | El desarrollador lo revisa | Un commit |
| **R1.2** | Web: `DW-17` y `DW-18` (decisión 4), y el LLD-B §4.1 (el 502 sin código), §4.5 *b* (sí toca Swift), §6.5 (la portada) y §11 (retener la petición y parar el servidor de pruebas) | El desarrollador lo revisa | Un commit aparte (LLD-B §E.1) |
| **R1.3** | El plan del backoffice (§4): `listTeams` a la rebanada 12, **85** operaciones, y la paleta por club como pendiente | El desarrollador lo revisa | Un commit |

### B · El catálogo (la mini-fase)

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R1.4** | `openapi.yaml`: las dos lecturas de la pareja, `pending` y `previousIngestionHealth` con la descripción rehecha, la lista cerrada de códigos y el formato de `detail`. Y en el mismo paso, la función `problem(...)` y sus 8 llamadas, porque sin ellas no compila | `npx @redocly/cli lint`, `swift build`, `REQUIRE_DB=1 swift test` sin cambios en el recuento, y los tipos de la web regenerados (`schema.d.ts`) con `npm run build` en verde. Y las cifras de **83 operaciones** que describen el catálogo de hoy pasan a 85 (`AGENTS.md`, el README del backend, `SpecConventionTests` y el comentario de `openapi-generator-config.yaml`), buscadas por el número | Un commit |
| **R1.5** | El censo comprueba que cada código que emite el servidor está en la lista | Sus tests (`swift test --package-path Tools/Census`), y un código quitado a propósito de la lista lo hace salir con `1` | Un commit |

### C · El servidor

Con el método del backend (§5): prueba → esqueleto → rojo de aserción → implementación → mutación.

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R1.6** | `listSeasons`, con su filtro | Tests de los niveles que toque, mutación con su catálogo, y `curl` contra la base de trabajo | Un commit |
| **R1.7** | `listCompetitions`, con sus cuatro filtros, **sin** el estado de la ingesta | Lo mismo | Un commit |
| **R1.8** | **El estado de la ingesta**: la regla de la decisión 2 entera (cada clase, el reloj que vuelve a cero, `pending`, `previousIngestionHealth`, el orden). Va en un paso propio porque es la parte más delicada. Al acabar, H-58 se cierra en la auditoría | Un test por caso del orden, con valores distintos entre sí; mutación con su catálogo; y la base de trabajo mirada en TablePlus contra lo que dice `curl` (el Alevín) | Un commit |
| **R1.9** | `listSeasonRegistrations`, con la lectura por temporada del repositorio de inscripciones | Tests, mutación y `curl` | Un commit |
| **R1.10** | Cierre del servidor: el recuento leído del XML, el censo con las tres operaciones (huecos nuevos con su test o en `known-gaps.json`), y el README del backend | `REQUIRE_DB=1 swift test --xunit-output`, el censo con salida `0` | Un commit |

### D · La web

De las piezas comunes a la pantalla.

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R1.11** | `src/api/errors.ts`: un mensaje para cada código de la lista, el genérico por familia y la regla del 502/503/504 sin código | Vitest; y un código quitado de la tabla hace fallar `npm run build` | Un commit |
| **R1.12** | La paleta (`src/theme/palette.ts`), Aura con la paleta encima y el interruptor de modo | Vitest, y la web abierta en los dos modos | Un commit |
| **R1.13** | El marco: el club al arrancar, la cabecera, el menú, la página entera de error, «Esta página no existe» y «Saltar al contenido» | Vitest, y la web abierta contra el servidor del desarrollador | Un commit |
| **R1.14** | `src/theme/format.ts`: la fecha y la hora de un instante | Vitest | Un commit |
| **R1.15** | La portada: la tabla, los cuatro estados y el selector de temporada | Vitest, y la web abierta con el club del desarrollador | Un commit |
| **R1.16** | El arnés: retener una petición, y parar y arrancar el servidor de pruebas (8081) | Un escenario de prueba que lo use, y el servidor del desarrollador (8765) sin tocar | Un commit |

### E · Los escenarios y el cierre

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R1.17** | Los `.feature` de la §6, con la *skill* de escenarios del desarrollador | `npm run e2e` en verde, con axe en los dos modos | Un commit |
| **R1.18** | Cierre: los cinco pasos de `AGENTS.md` («Al cerrar una fase»), el README de la web y lo aprendido | Las cifras buscadas por su número viejo en todo el árbol | Un commit |

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| **R1.1** | ✅ 2026-10-18 (`771b490`) | `D-102` y la enmienda de `D-89` en la bitácora, con sus notas «Enmendado por» en `D-68` y `D-89`; el LLD con las dos lecturas en las tablas de `Season` y `Team`, el estado por clase en §3.4 y §9.12 resuelta; H-58 decidido. Revisado por el desarrollador. Al leer salió que `POST /seasons` ya está en el catálogo: corregida la decisión 6 aparte (`51e7017`) |
| **R1.2** | ✅ 2026-10-18 (`856408d`) | `DW-17` y `DW-18` en el anexo; el LLD-B §4.1 y §4.4 (el 502, 503 o 504 sin código), §4.5 *b* (sí toca Swift, y el censo), §6.5 (la portada y la temporada más reciente), §11.5 nuevo y §E.2. Revisado por el desarrollador |
| **R1.3** | ✅ 2026-10-18 | El plan del backoffice: la fila de la rebanada 1 con `listSeasonRegistrations` 🆕 y `listCompetitions` ⚠️; `getTeamRegistration` 🆕 en la 4; `listTeams` a la 12; **85** operaciones (83 repartidas), también en `AGENTS.md`; la paleta por club como pendiente; la portada en ámbar en el mapa, y la rebanada 1 en §6 con su enlace. Revisado por el desarrollador |

**Punto de partida: 632 tests en el backend, 4 en la web.**

**Hallazgos de la rebanada 1** (no venían en el plan; cada uno en su commit): ninguno todavía.
