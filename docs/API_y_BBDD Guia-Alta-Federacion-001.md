# Guía de alta de una federación nueva

> **Qué es esto.** Lo que hay que escribir para que el backend sincronice con una federación que hoy no
> soporta: qué funciones implementa el adaptador, con qué datos, qué promete y qué hay que tocar fuera de
> él. Cubre **las tres ingestas** (calendario, clasificación y goleadores) y **el enganche** de un equipo.
>
> **De dónde sale.** De la sospecha 5 del bloque A-9 de la
> [auditoría 002](../backend/Plan%20de%20auditor%C3%ADa-002.md) (2026-10-04), que recorrió campo a campo la
> frontera entre el núcleo y la federación. Es la *"lista de lo que el adaptador catalán tendría que
> resolver sin tocar el puerto"* que A-9 tenía que entregar, **escrita sin abrir la FCF**: son
> obligaciones del puerto, no de una federación concreta.
>
> **La fuente de verdad sigue siendo el código.** El puerto es
> [`FederationClient.swift`](../backend/Sources/Application/FederationClient.swift), y cada campo lleva su
> justificación al lado. Esta guía los reúne; si discrepan, manda el código y hay que corregir la guía.

---

## 0. Antes de escribir una línea: el volcado

**La regla de [D-74]: el volcado antes que la firma.** Se aplicó tres veces (F5, F7 y F8) y las tres cambió
algo que se habría dado por hecho. Antes de tocar código:

1. **Capturar respuestas reales** de cada ruta de la federación, al menos estas:
   - el calendario de un grupo **jugado** y de uno **sin jugar**;
   - la clasificación de **dos jornadas**;
   - los goleadores **del mismo grupo** que el calendario, para poder cruzar los identificadores de equipo;
   - **una coordenada que no exista**, en cada ruta.
2. Guardarlas en `docs/Federation APIs examples/` y copiar las que vayan a usar los tests a
   `backend/Tests/FederationTests/Fixtures/`, siguiendo su [README](../backend/Tests/FederationTests/Fixtures/README.md).
3. **Escribir el anexo de la federación**, como el de la [RFFM](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md)
   y el de la [FCF](./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md): rutas, parámetros, forma de cada
   respuesta y qué devuelve cuando no hay nada. **Cada capacidad y cada decisión del adaptador cita su
   sección**, nunca la memoria (AGENTS.md).

---

## 1. Dónde encaja el adaptador

El núcleo no habla nunca con la federación: pide un adaptador al **proveedor**
(`FederationClientProvider`) según `Club.federation`, y lo usa a través del puerto.

| Quién llama | Cuándo | Métodos del puerto que usa |
|---|---|---|
| `PreviewFederationLink` | `POST /teams/{id}/federation-link/preview`: el administrador pega la URL del calendario | `coordinate(fromCalendarURL:)` → `fetchCalendar` |
| `LinkTeamToFederation` | `POST /teams/{id}/federation-link`: confirma el enganche y crea temporada, competición e inscripción | `coordinate(fromCalendarURL:)` → `fetchCalendar` |
| `IngestClubCalendars` | `POST /v1/ingestion-runs`, el comando `ingest` (lo que dispara `launchd`) y el `202` del enganche | Por competición, **en este orden**: `fetchCalendar` → `fetchStandings` (una vez por jornada que toque pedir) → `fetchScorers` |

El orden de la ingesta importa: la clasificación empareja contra los `Team` que crea el calendario, y por
eso va detrás.

---

## 2. Lista de pasos

| # | Dónde | Qué | ¿Lo avisa el compilador? |
|---|---|---|---|
| 1 | `Sources/Domain/FederationCode.swift` | Añadir el caso al `enum` | — |
| 2 | El mismo fichero, `capabilities` | Declarar sus dos capacidades (§6), **citando el anexo** | **Sí**: `switch` exhaustivo |
| 3 | `Sources/APIContract/openapi.yaml`, `FederationCode` | Añadir el valor al `enum` del contrato. El *spec* es la fuente de verdad y no se deriva de Swift ([D-25], [D-65]) | **Sí**: `toContract()` en `ClubHandler.swift` no compila sin él |
| 4 | `Sources/Federation/` | **El adaptador**: un tipo que implemente `FederationClient` (§3), con sus rutas, sus *parsers* y sus conversiones | — |
| 5 | `Sources/App/FederationCatalog.swift` | Devolver el adaptador nuevo en su caso del `switch` | **Sí**: `switch` exhaustivo |
| 6 | `Tests/FederationTests/` | Tests de *parser* contra los volcados, del cliente con un transporte falso y un **canario** contra la fuente viva (§8) | — |
| 7 | `docs/` y `AGENTS.md` | El anexo (paso 0) y su enlace en la tabla de documentación | — |

Lo que **no** hay que tocar, porque ya se deriva solo:

- **El `CHECK` de `clubs.federation`** se genera de `FederationCode.allCases` cada vez que se migra un club,
  así que los clubes nuevos lo reciben con el valor nuevo. Los ya existentes conservan su lista, y da igual:
  la federación de un club no cambia después de aprovisionarlo.
- **`provision-tenant`** acepta la federación nueva en cuanto el catálogo del paso 5 devuelve su adaptador.
  Hasta entonces la rechaza (H-93).
- **Los casos de uso, el Dominio y la persistencia**: si el adaptador cumple el puerto, no cambian.

---

## 3. Los cuatro métodos

El adaptador es **sin estado** (Plan §7.2): todo lo que una llamada necesita le llega por parámetro, y
dos llamadas seguidas no comparten nada. Lo habitual es separar **transporte** (traer el texto) de
***parser*** (interpretarlo, como función pura). `HTTPFederationTransport` se puede reutilizar tal cual:
valida el `2xx`, traduce el `404` y aplica su *timeout*.

### 3.1 `coordinate(fromCalendarURL url: String) throws -> FederationCoordinate`

La **inversa de la coordenada**: qué hay dentro de la URL de calendario que el administrador pegó ([D-97]).

- **No es `async` ni va a la red**: es parseo de una cadena.
- **Rechaza la URL que no es suya**, porque el llamante no sabe de qué federación es: llega por
  club → `Club.federation` → proveedor.
- **Lo que falta se rechaza, no se completa** ([D-22]). Inventar una temporada ausente sirve otro calendario
  en silencio ([D-84]).
- **Error**: `DomainError.unreadableFederationURL(url:reason:)`, que sale como 400. Un error propio del
  adaptador que se escapara saldría como 500.

| Campo de `FederationCoordinate` | Qué es | Se guarda en |
|---|---|---|
| `federationSeasonID` | El código de temporada de la federación | `Season.federationSeasonID` |
| `federationCompetitionID` | El código de competición (categoría de edad + división) | `Competition.federationCompetitionID` |
| `federationGroupID` | El código del grupo, **solo** el grupo | `Competition.federationGroupID` |
| `modality` | La modalidad del Dominio (`futbol11`, `futbol7`, `futbol5`, `futbolSala`, `futbolPlaya`) | `Competition.modality`. El código propio de la federación **no se guarda**: el adaptador lo traduce al llamar |

Los tres códigos son `String` opacos: no se componen ni se interpretan. La coordenada no tiene cuarto eje
(H-14): lo que dependa de la operación, como la jornada, va como parámetro del método.

### 3.2 `fetchCalendar(_ coordinate:) async throws -> FederationCalendar`

El calendario **completo** del grupo, tal como lo publica la fuente. No persiste ni empareja nada.

**El sobre, `FederationCalendar`:**

| Campo | Tipo | Qué hace el núcleo con él | Si es `nil` |
|---|---|---|---|
| `seasonLabel` | `SeasonLabel?`, en formato del modelo (`"2026/27"`) | El *preview* y el enganche lo usan **solo para crear una temporada que aún no existe** | Si la temporada no existe, el *preview* falla con `seasonLabelUnavailable`. El enganche acepta la etiqueta en la petición, y si no la trae falla igual. Ver §7 |
| `competitionName` | `String?`, literal | Guarda de [D-84] en el calendario y en el enganche; evidencia `federation_name` ([D-72]); de él se propone el `gender` | La guarda calla |
| `groupLabel` | `String?` (`"Grupo 1"`) | Rótulo del grupo al crear la competición. No se deduce del id | Se usa `"Grupo Único"` |
| `currentRound` | `Int?` | **Hoy nadie lo lee.** Lo necesitará el backoffice (la jornada en curso) | Nada |
| `rounds` | `[FederationRound]` | Todo lo demás | — |

**Cada jornada, `FederationRound`:** `number: Int`, el número **real** de la jornada (no el índice del array
ni un rótulo), y `matches`. El rango de fechas de la jornada lo calcula el núcleo a partir de las fechas
de sus partidos ([D-81]).

**Cada partido, `FederationMatch`:**

| Campo | Tipo | Qué hace el núcleo con él | Si es `nil` |
|---|---|---|---|
| `federationMatchID` | `String?` | Paso 1 del emparejamiento de partidos ([D-31]). **Se espera de toda federación** | Empareja el paso 2: jornada + local + visitante |
| `home`, `away` | `FederationTeamRef` | Emparejamiento y alta de equipos (abajo) | — |
| `homeScore`, `awayScore` | `Int?` | `MatchResult`. **Son los dos o ninguno** | `nil` significa *"la fuente no dijo nada"*, **no `0`** ([D-56]). Un solo lado informado se trata como silencio |
| `date` | `Date?`, **fecha de calendario a medianoche UTC** | Alta del partido, rango de la jornada y **guarda de temporada** ([D-91]: la mediana de las fechas tiene que caer en la `Season`) | El partido se descarta (`missingMatchDate`) y se repone en la pasada siguiente |
| `kickoff` | `WallClockTime?`, hora de reloj **sin huso** | `Match.kickoff`. Va separada de la fecha ([D-30]): *"sábado, hora por decidir"* | Hora por decidir |
| `venue` | `String?` | `Match.venue`, texto libre | Nada |
| `venueCode` | `String?` | **Hoy nadie lo lee.** Lo necesitarán los mapas, para las consultas de direcciones | Nada |

**Cada equipo, `FederationTeamRef`** (lo usan el calendario y la clasificación):

| Campo | Tipo | Qué hace el núcleo con él | Si es `nil` |
|---|---|---|---|
| `federationTeamID` | `String?` | Identifica al **equipo**, no al club. Paso 1 del emparejamiento de equipos, y **única** clave del de la clasificación (promesa 3) | El equipo empareja por los pasos siguientes en el calendario; en la clasificación, la fila se descarta |
| `name` | `String`, **sin la letra** | Emparejamiento y alta de `OpponentClub` | Obligatorio (promesa 4) |
| `letter` | `String?`, **ya separada del nombre** | Entra en la clave única de `Team` ([D-77]). El Dominio no parsea nombres | Club sin filial |
| `federationClubID` | `String?` | Identifica al **club**. Emparejamiento de `OpponentClub` (§3.7) | Degrada al nombre. **No lo infieras por parecido de formato** con otra federación |
| `crestURL` | `String?`, **absoluta** | El *preview* la muestra. Descargarla a Storage ([D-19]) está previsto y **aún no existe**: hoy `crestKey` queda a `nil` | Sin escudo |

### 3.3 `fetchStandings(_ coordinate:, round: Int) async throws -> FederationStanding`

La clasificación **tras la jornada pedida**.

- Si la fuente **no sirve jornadas pasadas**, el adaptador devuelve la vigente sin fingir y declara
  `providesRoundStandings: false` (§6). Qué hacer con eso lo decide el núcleo: pide solo la jornada que
  toca y **calcula** las anteriores a partir de `Match` ([D-15], [D-55]).
- **Una clasificación es un bloque**: si falta un contador en una fila, se lanza `malformedResponse`
  diciendo cuál faltaba. No se devuelve una fila a medias.

**El sobre, `FederationStanding`:**

| Campo | Tipo | Qué hace el núcleo con él | Si es `nil` |
|---|---|---|---|
| `federationCompetitionID` | `String?` | Guarda de [D-84] **por identificador** (`requireSameCompetitionCode`), la más fuerte que hay. **Solo si no es eco** (promesa 2) | La guarda calla |
| `competitionName` | `String?` | Guarda de [D-84] por nombre | La guarda calla |
| `rows` | `[FederationStandingRow]`, **en el orden de la fuente** | Se escriben como el *snapshot* de la jornada | — |

**Cada fila, `FederationStandingRow`:** `team: FederationTeamRef`, más **ocho contadores obligatorios**:
`position` (≥ 1), `played`, `won`, `drawn`, `lost`, `goalsFor`, `goalsAgainst` y `points`. Los puntos son
**los que dice la fuente**: no se recalculan, porque una sanción hace que no cumplan `3·G + E`.

### 3.4 `fetchScorers(_ coordinate:) async throws -> FederationScorerTable`

El **ranking de goleadores** de la competición entera. Sin jornada: es estado vigente único.

**Cuidado: ésta es la única ingesta que borra.** Lo que no llega en una pasada con éxito **se retira**
([D-94]). La protege la guarda de H-53, que no deja bajar el total de goles, y esa guarda da por hecho la
promesa 6.

**El sobre, `FederationScorerTable`:**

| Campo | Tipo | Qué hace el núcleo con él | Si es `nil` |
|---|---|---|---|
| `competitionName` | `String?` | Guarda de [D-84] por nombre. **No hay guarda por código**: aquí el código se envía, así que sería eco | La guarda calla |
| `rows` | `[FederationScorerRow]`, **en el orden de la fuente** | El orden es el ranking. **No se numera** | — |

`rows: []` es una respuesta **legítima**: un grupo sin goles todavía. No es lo mismo que "no hay nada"
(promesa 1).

**Cada fila, `FederationScorerRow`:**

| Campo | Tipo | Qué hace el núcleo con él | Si es `nil` |
|---|---|---|---|
| `federationPlayerID` | `String?` | **La clave del *upsert*** ([D-93]) | La fila se descarta (`unidentifiedScorer`) |
| `fullName` | `String` | Se guarda tal cual. No se normaliza ni se empareja ([D-09]) | Obligatorio (promesa 4) |
| `teamLabel` | `String`, **entero y sin partir** | Se guarda como texto ([D-32]). No es un `FederationTeamRef` porque no se empareja | Obligatorio (promesa 4) |
| `goals` | `Int?` | `LeagueScorer.goals` | La fila se descarta: `nil` no es `0` |
| `rank` | `Int?` | `LeagueScorer.rank`, **solo si la fuente publica puesto**. No se sintetiza a partir del orden | Hoy `nil` en las dos federaciones medidas |

Las filas son **independientes**: una fila rara se descarta y se apunta, sin tirar la pasada ([D-75]).
Justo al revés que en la clasificación.

---

## 4. Qué error lanzar en cada caso

Todos son `FederationError` salvo el de la URL. El núcleo y la frontera HTTP ya los distinguen: no hace
falta ninguno nuevo.

| Situación | Error | Cómo sale por HTTP |
|---|---|---|
| No se pudo hablar con la fuente (DNS, conexión, *timeout*) | `transportFailure(url:reason:)` | 504 |
| Respondió fuera de `2xx` | `unexpectedStatus(status:url:)` | 502 |
| Respondió algo que no tiene la forma documentada en el anexo | `malformedResponse(field:reason:)`, con `field` como coordenada **dentro del cuerpo ajeno** | 502 |
| La coordenada no devolvió nada | `coordinateNotFound(detail:)` (promesa 1) | 502 |
| La URL pegada no es de esta federación o le falta algo | `DomainError.unreadableFederationURL(url:reason:)` | 400 |

`HTTPFederationTransport` ya lanza los tres primeros y el `404`. **Un "no hay nada" con `200`**, que es lo
que hace la RFFM en sus tres rutas, lo tiene que detectar el *parser*. **La forma cambia de una ruta a
otra** dentro de la misma federación: la RFFM manda la página entera con un campo a `null` en el
calendario, y el documento entero a `null` en clasificación y goleadores. Si se decodifica a ciegas, eso
sale como `malformedResponse`, y el canario gritaría *"¡han cambiado la forma!"* cada vez que alguien se
equivoque de número.

---

## 5. Lo que cada adaptador promete

Son las obligaciones que el tipo no puede imponer y que el núcleo da por cumplidas. Las cinco primeras
están en la cabecera de `FederationClient.swift`.

| # | Promesa | Si no se cumple |
|---|---|---|
| 1 | **"No hay nada" se dice con `coordinateNotFound`, sin afirmar que la coordenada no exista.** La misma respuesta puede ser pasajera (H-61) | El motivo guardado en `ingestion_runs` manda a revisar una coordenada que está bien (H-91) |
| 2 | **El código de competición del sobre solo se trae si no es eco.** Si la ruta lo recibió como parámetro, va `nil` | La guarda compara el dato consigo mismo y siempre pasa (la trampa de [D-91]) |
| 3 | **Un mismo equipo lleva el mismo `federationTeamID` en todos los métodos.** Si la fuente usa espacios distintos, traducir es del adaptador | Ninguna fila de la clasificación casa, todas se descartan y no falla nada (H-98) |
| 4 | **Un `String` obligatorio que falte se entrega como `""`, no inventado** | `"Desconocido"` pasaría el Dominio como si fuera un dato (H-99) |
| 5 | **La URL que no es suya se rechaza** | El enganche lee una coordenada de otra federación |
| 6 | **El ranking de goleadores es completo**: todo el que ha marcado, sin *top-N*. Si la fuente pagina, el adaptador junta las páginas | La guarda de H-53 da por hecho que el total no baja nunca. Con un *top-N*, quien sale del corte **se retira** de la tabla o la pasada falla cada semana. **La FCF incumple esta premisa** (su lista es un *top*-50), y la propia guarda lo avisa: hay que revisarla antes de reutilizarla |

---

## 6. Las capacidades

Se declaran en `FederationCode.capabilities`, **con la sección del anexo que las prueba**.

| Capacidad | `true` significa | Con `false`, el núcleo… |
|---|---|---|
| `providesRoundStandings` | La fuente sirve la clasificación **de cualquier jornada pasada** | …pide solo la jornada que toca y calcula las anteriores a partir de `Match` ([D-15], [D-55]). Sigue habiendo dato oficial en régimen estacionario |
| `providesScorers` | La fuente publica el ranking de goleadores | …no llama a `fetchScorers`, no hay *fallback* posible ([D-09]), y la app oculta la pantalla de goleadores |

La segunda llega a las apps por `ClubResponse.federationProvidesScorers`, y **deciden con ella qué
pantalla enseñar**. Por eso `provision-tenant` no da de alta un club de una federación sin adaptador (H-93).

---

## 7. Trampas ya medidas

| Trampa | Dónde se vio | Qué hacer |
|---|---|---|
| **Eco**: la respuesta repite un parámetro que enviaste | RFFM: la etiqueta de temporada (§F.16), el código de competición en goleadores | No usarlo como evidencia (promesa 2) |
| **El nombre de la competición es idéntico entre temporadas** | RFFM §F.17 | La guarda de nombre no detecta *"me traje los códigos del año pasado"*. Lo detectan las **fechas** ([D-91]) |
| **La fuente no publica la etiqueta de temporada** | FCF §C.10.4 | `seasonLabel: nil`, sin inventarla. El *preview* de la primera competición de cada temporada fallará hasta que la temporada exista. Con una temporada ya creada, se reutiliza por `federationSeasonID` y la etiqueta no hace falta. **Es un hueco del flujo, no del adaptador** |
| **Fechas sin ISO, y con formatos distintos en la misma fuente** | RFFM §F.5 y §F.11 | Parsear **por campo**, nunca con un formateador que acepte varios |
| **Fecha a medianoche local** | — | Construirla **en UTC**: con huso local, la medianoche cae en el día anterior |
| **Sin huso horario en ningún dato** | RFFM §F.11 | `kickoff` es hora de reloj; no convertir a instante en la ingesta |
| **"No jugado" escrito de varias formas**: `""`, campo ausente, o `"0"` | RFFM; FCF | Traducir a `nil` en el adaptador. Un `0` aquí afirma un resultado |
| **La letra del equipo, embebida en el nombre**, y de forma distinta en cada ruta | RFFM: entre comillas simples en el calendario (§F.5) y pegada en goleadores (§F.13) | Separarla en `letter` en calendario y clasificación; en goleadores, `teamLabel` entero |
| **El número de jornada no es el índice** ni el rótulo | RFFM §F.15 (`codjornada`) | Usar el campo del número |
| **El identificador de club no es el mismo número en dos federaciones** aunque el formato coincida | El escudo `00100_<10 dígitos>_…` existe en las dos, y en la FCF no es el club | Usar el campo propio de cada fuente, o `nil` |
| **Un campo que se llama como la pregunta no es la respuesta** | FCF: `total` en goleadores son partidos jugados, no goles (0/50 cuadran) | Comprobarlo contra el volcado |
| **Una clasificación con contadores concatenados** | FCF §C.12.1: `played: "1515"` | Es la razón de que la FCF esté aplazada ([D-95]) |
| **`null` pasajero** con la coordenada buena | RFFM, H-61 | Es la promesa 1. Hoy nadie reintenta (H-92) |

---

## 8. Cómo probarlo

El patrón a copiar es el de la RFFM, en `Tests/FederationTests/`:

| Test | Qué comprueba | Necesita |
|---|---|---|
| ***Parsers*** (`RFFM…ParserTests`) | Cada volcado da lo que el anexo dice, campo a campo, incluido el "no hay nada" de cada ruta | Los volcados copiados en `Fixtures/` |
| **Cliente** (`RFFMFederationClientTests`) | Qué URL pide para cada coordenada, y que dos llamadas no se contaminan | Un `FederationTransport` falso |
| **URL** (`RFFMCalendarURLTests`) | La inversa de la coordenada, y el rechazo de URLs ajenas o incompletas | Nada |
| **Canario** (`RFFMCanaryTests`) | **Contra la fuente viva**, invariantes que solo rompe la fuente: posiciones 1…N, `G + E + P = J`, ids únicos, goles que no suben al bajar por el ranking | `FEDERATION_LIVE=1` y una coordenada viva (`FEDERATION_LIVE_SEASON`, `_COMPETITION`, `_GROUP`, `_MODALITY`, `_NAME`, `_ROUND`) |

Los tests de los casos de uso (`Tests/ApplicationTests/Ingest*Tests`) **no cambian**: usan dobles del puerto,
no el adaptador.

---

## 9. Lo que el adaptador NO hace

- **Persistir o emparejar.** Eso es del núcleo (§3.7, `MatchingChain`).
- **Decidir si una llamada sirve.** Eso lo decide el núcleo con las capacidades del Dominio.
- **Reordenar, numerar o recalcular.** Ni el ranking, ni los puntos, ni el orden de la clasificación.
- **Inventar** un valor que la fuente no dio: ni un nombre, ni un `0`, ni una temporada, ni un rótulo.
- **Guardar estado** entre llamadas.
- **Transportar un campo que nadie lee.** La regla de F6-bis tiene dos excepciones declaradas,
  `currentRound` y `venueCode`, que tienen lector previsto (H-95).
