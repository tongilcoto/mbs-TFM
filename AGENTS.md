# AGENTS.md

Este fichero es la referencia principal para agentes (Claude Code y similares) que trabajen en este repositorio. `CLAUDE.md` redirige aquí.

## Qué es este proyecto

Proyecto (TFM) para la gestión técnica de pequeños clubs de fútbol españoles: gestión manual de estadísticas de sus distintos equipos, en todas las categorías (desde pre-benjamín a senior), pudiendo existir varios equipos por categoría.

El caso base es **un único club**. Como ampliación de alcance de negocio, el producto puede ofrecerse a **varios clubs** en modo **SaaS multi-tenant**, con dos modelos de propiedad: **gestionado por el proveedor** (instancia compartida con aislamiento por club) o **instancia dedicada del club** (sus propias claves). Esto no invalida el caso de un solo club.

## Documentación clave

**Transversal (todo el proyecto):**

- [docs/Project Seed.md](./docs/Project%20Seed.md) — origen y reglas del proyecto.
- [docs/Project HLD-001.md](./docs/Project%20HLD-001.md) — diseño de alto nivel (artefactos y relaciones).
- [docs/Plan de desarrollo-001.md](./docs/Plan%20de%20desarrollo-001.md) — **cómo se construye**: los dos
  bucles (alcance y TDD) y las fases **F0–F10**: andamiaje primero, después la ingesta.
- [backend/Plan F10-001.md](./backend/Plan%20F10-001.md) — **la última fase, entregada el 2026-09-24,
  troceada en ciclos**: qué quedó decidido, el «Leer antes» de cada bloque y lo que se midió.
  Autocontenido: una sesión nueva arranca de ahí sin releer el LLD entero.
- [backend/Plan de auditoría-002.md](./backend/Plan%20de%20auditor%C3%ADa-002.md) — **la auditoría de lo
  construido tras la 001** (F6-bis → F10-ter) antes de montar `launchd` y abrir el backoffice: bloques
  A-8 a A-15, hallazgos desde H-51, y una puerta por cada cosa que desbloquea.

**Por módulo** (ADR = decisiones; LLD = diseño de bajo nivel; Docs = material de apoyo):

| Módulo | ADR | LLD | Docs |
|--------|-----|-----|------|
| **API backend + Base de datos** | [ADR-API_y_BBDD-001](./docs/ADR-API_y_BBDD-001.md) — tecnología BD/API y despliegue (ver resumen abajo) | [API_y_BBDD LLD-001](./docs/API_y_BBDD%20LLD-001.md) — arquitectura Clean/Hexagonal/DDD, modelo de datos, ORM, contrato API · Anexos: [Decisiones de diseño — bitácora](./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) · [Federación de Madrid (RFFM)](./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md) · [Federación de Cataluña (FCF)](./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md) | [mockups móvil](./docs/design-assets/mobile/) · [OpenAPI](./backend/Sources/APIContract/openapi.yaml) |
| **Web backoffice** | *(pendiente)* | *(pendiente)* | [Borrador inicial](./docs/backoffice_initial_draft.md) — el encuadre acordado antes de abrir el módulo: rebanadas verticales (pantalla + sus endpoints), la ingesta en local con `launchd` como prerrequisito, y la autenticación al final |
| **App iOS** | *(pendiente)* | *(pendiente)* | — |
| **App Android** | *(pendiente)* | *(pendiente)* | — |

## Decisiones de diseño transversales (detalle en el LLD-001)

- **El backend son tres módulos sobre un modelo de datos común** (§2.1): **BFF** (REST para backoffice y
  apps), **ingesta** de la API de la federación, y **gestión de usuarios** (transversal).
- **Cada entidad tiene un solo dueño de escritura** (§5.1), en tres papeles: *entrada de la ingesta*
  (`Season`, `Competition` — las crea el administrador), *salida de la ingesta* (`OpponentClub`, `Match`,
  `Round`… — solo corregibles) y *dominio manual* (`Player`, `Goal`, `Card`…). Regla:
  **el BFF corrige lo que la ingesta trae; no crea ni borra filas *emparejadas* con la federación.**
  Al tocar el spec o el LLD, respetar esta frontera: no añadir `POST`/`DELETE` a entidades de salida.
- **`Team` es la excepción, y es deliberada** (`D-66`): el club forma el equipo, lo inscribe en la
  federación y **solo entonces** la federación publica calendario — es fuente de verdad del *calendario*,
  no del *equipo*. Así que `Team` tiene `POST` (sin ningún dato de federación) y `DELETE` **mientras no
  esté emparejado**; una fila con `federationTeamId` nulo no tiene segundo escritor. La otra mitad de la
  regla, sin la cual esto no se sostiene: **la ingesta no crea equipos propios**, así que todo lo que
  encuentra y no reconoce es de un `OpponentClub`. `gender` y `modality` pasan a ser identidad de alta:
  van en `CreateTeamRequest`, nunca en el `PATCH`.
- **El copia-pega de la URL de la federación vive en el equipo, no en la competición** (`D-67`):
  `POST /v1/teams/{id}/federation-link` (+ su `/preview`) engancha, crea en cascada `Season` y
  `Competition` si hacen falta y **encola** la primera ingesta → **202**, no 201. Su razón escrita —que la
  FCF costaba ~34 peticiones— **caducó** (hoy cuesta una, `D-74`) y **está rehecha en F3**: el `202` se
  mantiene porque lo caro es lo que viene *detrás* del calendario —~240 partidos y **un escudo por club** que
  descargar y subir a Storage (`D-19`)— y porque encolar es lo que permite reintentar sin romper el enganche.
  F10 tiene que medirlo para cerrarlo del todo. `POST /v1/competitions` se conserva solo como vía para
  semillas, *scripts* y tests.
- **La cadena de emparejamiento tiene tres pasos, y los tres se escribieron en F4 con enmienda** (§3.7):
  el paso 2 de equipos compara **la clave única entera** —nombre normalizado, categoría, **letra**, género y
  modalidad—, porque *"nombre más categoría"* fusionaba el "Infantil A" y el "Infantil B" del mismo club
  (`D-77`); el *"si no"* que encadena los pasos significa **"si el anterior no resolvió"**, no *"si el dato no
  viene"*, o `D-76` no llega a ocurrir nunca (`D-78`); y cuando el paso inexacto encuentra dos, **no se
  decide: se reporta** (`D-79`). Al tocarla, dos cosas: la *"marca para revisión manual"* de §3.7 **no es una
  columna** —es el escalón que devuelve la cadena—, y el paso 2 **no puede alcanzar equipos propios sin
  enganchar**, que es el límite que `D-76` le dejó escrito.
- **`modality` y `gender`, cuando el equipo lo crea la ingesta, los hereda de su `Competition`** (§3.2, `D-07`, `D-58`): los dos entran en la
  clave única de `Team` y **ninguno es campo de escritura de `Team`**. La federación no publica género por
  equipo —va en el nombre de la competición—, así que el `/preview` lo propone y el administrador lo confirma
  en el alta. No devolver `gender` a `UpdateTeamRequest`: una inferencia mal puesta ahí no da un dato feo, da
  un 409 de unicidad.
- **La inscripción del equipo lleva la competición, y eso se decidió antes de que la tabla existiera**
  (`D-68` + enmienda): `TeamRegistration` es `(team_id, season_id, competition_id?)`. La razón no es
  rendimiento —derivar la pareja de `Match` cuesta milisegundos, medido en §9.12— sino que **hay un instante
  en que el sistema sabe que un equipo va con una competición y no lo puede leer**: entre el `202` del
  enganche (`D-67`) y la primera pasada no existe ni un `Match`. Es el mismo agujero que creó la entidad en
  el eje de la temporada, tapado ahora en el de la competición. **No es `Participation`** (`D-27`): la
  escribe el club, no la ingesta. Al tocarla: el `UNIQUE` de tres columnas va con **`NULLS NOT DISTINCT`**, y
  la coherencia con la temporada es una **FK compuesta**, no una guarda.
- **Una migración aplicada es inmutable, y el esquema de un club no depende de cuándo se dio de alta**
  (`D-90`, §4.6). Lo segundo está **medido** y es la buena noticia: un alta limpia y un club migrado en tres
  lotes de tres días dan el mismo esquema **byte a byte** —cuatro caminos, un solo `md5`—, y no por
  disciplina: `provision-tenant` no tiene juego propio, llama a la misma función que `migrate-tenants`. Lo
  primero es la única vía que queda para romperlo, y **ya pasó una vez**: `_fluent_migrations` guarda el
  **nombre** de la migración, no su contenido, así que un *schema* que ya la aplicó **no recibe jamás** una
  edición posterior de su `prepare`, sin error y sin aviso. Al añadir una tabla en F7/F8/F10: se añade al
  final de la lista **que le toque por FK**, y lo que haya que corregir de una vieja va en una migración
  **nueva**. Y si el recorrido encuentra un club roto **se para** —correcto por `D-86`: una migración a
  medias *es* estado a medias— diciendo de quién era.
- **La federación es un catálogo en código, no una tabla** (§3.6): soportar una nueva exige un adaptador.
  **Y ese adaptador es dueño del universo de datos de su federación de punta a punta** (`D-97`): su URL, su
  JSON, dónde pega la letra del equipo, cómo codifica la modalidad. Nada de eso es conocimiento del *core*,
  y la consecuencia es la que hay que proteger: **cada federación nueva se escribe sin tocar la anterior**.
  Por eso `coordinate(fromCalendarURL:)` va en `FederationClient` y no en un puerto aparte — el criterio para
  admitir un método nuevo ahí es *"¿es conocimiento del universo de esa federación?"*, no *"lo necesita un
  caso de uso"*. **Escrito en F10 (Bloque B), y con tres cosas que no se ven en la firma:** va **sin
  implementación por defecto** —así el adaptador que venga no puede nacer sin leer su propia URL, y el
  compilador lo dice en vez de la ejecución—; **no es `async`**, porque es la única operación del puerto que
  no habla con la fuente; y **rechazar la URL que no es suya es también del adaptador**, que es quien conoce
  su *host* — el llamante llega por club → `Club.federation` → `FederationClientProvider` y **no sabe de qué
  federación es lo que le han pegado**. Lo que sale del adaptador es un `DomainError`, no su error interno:
  ver el criterio del 400 abajo.
  Lo que sí es dato es cuál es la del club (`Club.federation`), una por tenant. El catálogo describe también
  **qué sabe hacer** cada proveedor, no solo sus coordenadas (`D-17`, `D-55`).
- **Los dos proveedores se parecen mucho más de lo que dicen los documentos antiguos, y eso es reciente.**
  El 2026-08-28 se descubrió que **la FCF ha rehecho su web y ahora publica una API JSON** ([D-74],
  [Anexo FCF §C.10]): coordenada de tres códigos numéricos como la de Madrid, calendario entero en **una**
  petición, identificador de partido (`CODACTA`) e identificador de club como campo propio. **§C.1–§C.9 del
  anexo FCF están obsoletas** — describen el sitio de raspado anterior. De las diferencias que ese anexo daba
  por medidas, **solo sobrevive una**: la FCF publica **únicamente la clasificación vigente** (`D-55`,
  reverificado), así que las jornadas anteriores al alta se calculan (`D-15`).
- **Y aun pareciéndose tanto, la FCF está hoy FUERA DEL ALCANCE, decidido y medido** (`D-95`,
  [Anexo FCF §C.12]). No por trabajo: porque **su clasificación está rota en origen** —`played`, `won`,
  `drawn` y `lost` llegan concatenando casa y fuera sin separador, y su propia web los pinta en crudo—,
  porque **dice que no con el contenedor vacío** en vez de con `null`, lo que ante la retirada de `D-94`
  vaciaría un ranking entero sin dejar fallo, y porque **cambió de forma en 23 días y hacia atrás**. Al
  tocar cualquier cosa que mencione la FCF: el catálogo del Dominio **sigue declarando sus capacidades** —es
  lo que `D-17` pide— y la raíz de composición **devuelve `nil` a propósito**; las dos cosas a la vez son el
  diseño, no una incoherencia. **No quitar `.fcf` del enumerado** (`D-90`) y **no escribir su adaptador**
  hasta que se cumpla la condición de reapertura, que está escrita y se comprueba en una llamada.
- **Esas dos razones caducadas se rehicieron en F3, y ninguna regla cambió: cambiaron de argumento.**
  `D-56` (*ausente o vacío nunca sobrescribe*) ya no se apoya en que la FCF borre nada —no lo hace: 240 de
  240— sino en que **los dos errores no cuestan lo mismo** (`D-75`): ignorar un vacío real se corrige solo en
  la pasada siguiente; escribir un silencio pierde el dato y `Match` no tiene `PATCH`. La cadencia semanal de
  §5.6 sigue siendo **requisito**, pero por `D-55` —la clasificación de la FCF no se puede pedir hacia
  atrás—, no por la fecha. Y el `202` de `D-67`, arriba. **La lección se repite: una regla puede sobrevivir a
  su ejemplo, pero hay que ir a comprobarlo.**
- **Una coordenada equivocada no falla: devuelve el calendario de otra competición** (`D-84`, **con enmienda
  del 2026-09-02**). Lo que la entrada decía —que la RFFM reutiliza los códigos entre temporadas— **es falso**:
  cada temporada recibe un bloque nuevo (PREFERENTE AFICIONADO G1 es `24037456` en 25-26 y `26737701` en
  26-27). Lo cierto, medido: **`competicion`+`grupo` lo determinan todo y `temporada` se ignora**. La
  conclusión no cambia —la guarda sigue haciendo falta— pero **el riesgo principal sí**. Y ojo con cómo se
  cuenta, que es fácil contarlo mal: **los códigos no caducan solos con el tiempo.** Siguen apuntando
  exactamente a lo mismo —*"Primera Cadete Grupo 4 **de 25-26**"*—, y servir eso es correcto. Lo que pasa es
  que **la coordenada lleva la temporada dentro y nada en la respuesta lo dice**, así que el fallo lo comete
  un humano en el alta: al llegar la temporada nueva se copian los códigos del año pasado y la ingesta
  sincroniza 2025 en una competición marcada como 2026, sin un solo error. Y **no da 404 nunca** en esa ruta:
  con `competicion`/`grupo` inexistentes responde `200` con `calendar: null`, y con otra `temporada`
  responde `200` con el calendario **de los mismos códigos** e **ignora el parámetro**. Consecuencias:
  confirma con dato la regla de §3.5 (`Competition` se identifica por `season_id` **+**
  `federation_group_id`); obliga a la ingesta a **comparar el nombre contra `Competition.federation_name`
  antes de escribir**; y le da al canario de Plan §4.4 **cuatro** señales en vez de dos. Al tocar cualquier
  adaptador de federación: **una premisa sobre un sistema de terceros no se hereda, se mide** — ésta llevaba
  escrita desde F2 y era falsa.
- **Y el nombre no distingue temporadas, así que hacen falta dos guardas y no una** (`D-91`,
  [Anexo RFFM §F.17], medido el 2026-09-13 sobre PRIMERA CADETE G4). Los rótulos `competicion` y `grupo` son
  **idénticos** en 25-26 y 26-27, de modo que la guarda del nombre caza *"me equivoqué de competición"* y es
  **ciega** al error que ocurre cada verano, *"me traje los códigos del año pasado"*. La señal que no puede
  ser eco son **las fechas**, que se van un año entero: la pasada exige que **la mediana** de las fechas del
  calendario caiga en la ventana de la `Season`. **Mediana** y no *"todas dentro"* —un aplazado a julio
  tumbaría la competición para siempre— ni *"que solapen"* —un solo aplazado la haría pasar—. Las dos guardas
  son complementarias, y **la de las fechas vale también para la FCF**, que no publica nombre pero sí fecha.
  Y una lección de método que ya va por la tercera vez: **el dato estaba medido desde el 2026-09-02 y la
  conclusión que se sacó de él era incompleta** — la tabla de §F.16 ya mostraba el mismo nombre en las cuatro
  filas. *Hay que volver a leer una medición cuando se construya algo encima.*
- **Y medir no basta cuando la fuente te devuelve tu propio parámetro** (`D-84` enmendada,
  [Anexo RFFM §F.16]). El `calendar.temporada` de la RFFM **es el eco de lo que le pediste**, no un dato suyo:
  con los códigos de 2025-26 y `temporada=22` responde *"2026-2027"* y sirve los partidos de 2025-26. Así se
  escribió mal `D-84` en F5, **midiendo**. La regla que se añade: **desconfiar de todo campo que se parezca a
  lo que enviaste**, y buscar una señal que no pueda ser eco — aquí, las fechas de los partidos.
- **El recorrido de la ingesta no se detiene en el primer fallo, y eso solo es seguro por dos cosas que ya
  estaban puestas** (`D-86`): la pasada es **atómica** (`D-83`) y **deja constancia** de su fallo (`D-85`). La
  unidad de aislamiento es la **competición**: abortar haría que una sola coordenada equivocada —de las que
  `D-84` demuestra que existen y que no dan error— dejara sin sincronizar a todo lo que va detrás. Las dos
  mitades son inseparables: **se continúa y se apunta**, y el comando sale con código distinto de cero.
  **Y eso vale para el fallo de datos, no para el de la base** (`D-86` enmendada el 2026-09-12, H-23): el
  ámbito que escribe la constancia usa **el mismo recurso que acaba de fallar**, así que con la base caída el
  recorrido continuaba sin apuntar nada — exactamente lo que `D-86` declara inseguro. Ahora se **para**, y para
  distinguir un caso del otro **se le pregunta a la base si sigue ahí** en vez de clasificar el error: los
  códigos de un `PSQLError`, un *pool* agotado y un relevo del *pooler* son una premisa sobre un sistema ajeno
  (`D-84`). Se para también el recorrido de los clubes que faltan, porque el *pool* y el Postgres son **uno
  solo** (§6.4) y la caída no está aislada por club. Lo que **no** se aplaza al parar: las competiciones sin
  intentar no han movido su `last_synced_at` y entran enteras en el disparo siguiente. Ojo al
  copiar esto a las migraciones por tenant (§9.3): **no es la misma pregunta** — una migración a medias deja
  *schemas* a distinta versión y nada que lo diga.
- **La cadencia de la ingesta vive fuera del proceso; lo que el código trae es un antirrebote** (`D-87`). No
  hay temporizador dentro del servidor: lo dispara un cron (§5.6 pide **lunes** + fin de semana). El
  `--min-interval-hours` (6 por defecto) es un **mínimo** que hace inofensivo un disparo de más — **no es el
  tope semanal**, que es un máximo y lo hace cumplir el calendario de disparos. Y **la competición que nunca
  se sincronizó entra siempre**: sin esa excepción, la recién dada de alta por el enganche de `D-67` esperaría
  para siempre. Lo encontró la comprobación de mutación, no un rojo.
- **`LeagueScorer` no tenía clave de negocio, y era la única de la salida de la ingesta sin ella** (`D-93`).
  §3.5 enumera las unicidades del modelo y esa entidad **no aparecía**; mientras el ranking no se ingería no se
  notaba. La alternativa aparente —`(competición, nombre, equipo)`— **la desmiente el propio *spec***, que dice
  en la descripción del `id` que *"`fullName` no es identificador: dos jugadores pueden llamarse igual"*. La
  clave es **`federation_player_id`**, que las dos federaciones publican (`codigo_jugador` / `codjugador`) y
  que está medido: 426/426 filas únicas y no vacías. Es obligatorio —al revés que sus tres hermanas, que son
  anulables porque sus entidades tienen un estado intermedio— y **no viaja en el DTO**, igual que `synced_at`.
- **Y es la única salida de la ingesta que *borra*** (`D-94`). `D-75` dice que lo que la fuente deja de
  publicar no se destruye, y por eso ningún otro repositorio tiene `delete`. La condición que autoriza la
  excepción es **"la tabla es estado vigente y no histórico"**, y solo la cumple ésta: una fila de
  clasificación es la foto de una jornada que ya pasó y sigue siendo verdad; un goleador que el proveedor dejó
  de publicar es una fila **indistinguible de las buenas** dentro de una tabla que afirma ser la de hoy. La
  retirada va por la marca `synced_at` y **dentro del mismo ámbito que la escritura**, para que una caída a
  mitad no pueda dejar la tabla vacía. Al añadir la séptima salida de la ingesta: **si tiene jornada, es
  histórico y no se borra**.
- **El módulo de ingesta asoma exactamente dos endpoints, y el `POST` no crea filas de resultado**
  (`D-88`, **enmendada por `D-96`**: sí crea una fila `accepted` —sin un solo campo de la pasada— para
  que el backoffice pueda enterarse leyendo; quien escribe **el dato** sigue siendo el job).
  `GET /v1/ingestion-runs` lee el registro; `POST /v1/ingestion-runs` **pide que el job pase** —el cuerpo no
  lleva ni un campo de la pasada, lleva qué sincronizar, igual que `Competition` como entrada (`D-16`)—, y
  responde **200** con una competición (cabe en la respuesta) o **202** con una temporada (decenas de
  competiciones y ~240 partidos cada una: es `D-67` un nivel más abajo). El `202` **planifica antes de
  responder**, para que una `seasonId` inexistente dé 404 y no un 202 con un fallo invisible detrás. **Y ese
  recurso es el *detalle*, no la lista** (`D-89`): el resumen —*"¿está al día?"*— viaja con la competición
  (`ingestionHealth`, `lastIngestionAt`) como derivado de lectura. Ojo con la trampa: `last_synced_at` **no**
  sirve para saber si algo va mal, porque una pasada fallida hace `rollback` sin tocarla (`D-83`). El cuerpo
  lleva **lista** de competiciones porque la pantalla que lo usa son equipos con una casilla al lado: marcar
  tres es **una** acción del usuario. Y diseñarlo destapó §9.12 — **ninguna lectura sirve la terna *(equipo,
  temporada, competición)***, que es lo que el backoffice llama *"un equipo"*; hoy costaría N+1 peticiones.
  No es fallo del modelo (la participación se deriva por diseño, `D-27`/`D-28`): es una vista derivada que
  falta.
- **La cascada del enganche presta la categoría del EQUIPO a la competición que crea, y eso no es una
  elección entre varias** (F10, Bloque C). La federación **no publica la categoría de edad** —va en el
  nombre, como el género— y `FederationLinkRequest` no la lleva: el contrato pide `gender` y no la edad. Así
  que cuando la cascada de `D-67` crea la `Competition`, `ageCategory` sale del equipo que se está
  enganchando, `modality` de la coordenada (`tipojuego`) y `gender` del cuerpo. La consecuencia hay que
  leerla entera para no confundirla con un descuido: **en el alta de una competición nueva la edad cuadra
  por construcción**, y de las tres que `identityMatches` compara (`D-58`, §3.2) las que de verdad muerden
  son las otras dos. La tercera se cobra cuando **la competición ya existe** —la que dio de alta otro equipo
  o `seed-competition`—, que es exactamente el caso de `D-58`: el Cadete A enganchado a la juvenil. Por eso
  el `/preview` enseña **la identidad de la fila** cuando la hay y **los rótulos de la fuente** siempre: los
  rótulos están para *reconocer* el grupo (`D-16`), la identidad para *decidir* si esto va a dar un 409. Y
  por eso la negativa vive en el Dominio (`Team.requireIdentityMatches`) y no en el caso de uso: la otra
  puerta que afirma esta correspondencia a mano —`POST /teams` + `PUT /registrations`, del backoffice—
  **sigue sin fase**, y tendría que acordarse de escribirla otra vez.
- **Y la abre el `202`, la cierra la pasada, y el mecanismo es el mismo por las dos puertas** (F10-bis).
  `IngestionOutcome.accepted` no es un estado que alguien ponga y otro mire: es **una fila que transita**. La
  escribe quien acepta —el enganche de `D-67` y el `POST /v1/ingestion-runs`, los dos `202`— y la **cierra la
  propia pasada**, que **adopta** su `id` y su `startedAt` en vez de escribir una fila nueva. Adoptar y no
  *"escribo la mía y cierro la otra"* tiene un motivo exacto: `closed(as:at:)` arrastra los contadores **del
  informe sobre el que se llama**, y los de una fila aceptada son ceros — cerrando la otra, el resultado
  quedaría en una fila y los contadores en ninguna. Consecuencias al tocar esto: `record` es ***upsert* por
  `id`** y ya no *"solo inserta"* (la excepción está razonada en el puerto), `findAccepted` **filtra por
  `outcome` y por `kind`** —sin lo primero, la pasada del cron adoptaría la fila cerrada de la semana pasada
  y la ingesta se caería en la segunda pasada de cada competición, medido con mutación—, y **aceptar dos
  veces no deja dos filas**, porque la pasada cierra una. De regalo, una propiedad que nadie pidió: si el
  proceso muere entre el `202` y la pasada, **la siguiente del cron cierra lo que quedó abierto**.
- **La fila `accepted` de `D-96` va DENTRO del ámbito de su cascada, al revés que la constancia de `D-85`.**
  No es una incoherencia: son dos cosas distintas con el mismo nombre de tabla. El registro de `D-85` vive
  en su **propio** ámbito precisamente para que el `rollback` de la pasada fallida no se lleve la constancia
  **del fallo**; la fila `accepted` es la constancia de que **esto se ha aceptado**, y sin la cascada no hay
  nada que aceptar — una fila prometiendo una pasada sobre una competición que el `rollback` se llevó es
  peor que no tener fila. Al tocar cualquiera de las dos: la pregunta no es *"¿dentro o fuera?"* sino
  *"¿qué deja de ser verdad si la transacción se deshace?"*.
- **Ojo con el atajo "RFFM = JSON, FCF = *scraping*": ya no vale por partida doble.** La FCF es JSON puro; y
  en la RFFM el **calendario sigue siendo HTML** con el JSON dentro de un `__NEXT_DATA__` embebido
  ([Anexo RFFM §F.7, §F.15]) — solo sus rutas `/api/…` son JSON directo. Evidencia campo a campo en los
  anexos y en `docs/Federation APIs examples/`; **no deducir nada de memoria, y revalidar el anexo antes de
  escribir su adaptador** — es la lección de `D-74`.

## Dónde va cada cosa al documentar

El LLD de API/BD se dividió en tres ficheros **por naturaleza del contenido**, no por tema (decisión `D-26`).
Al escribir documentación nueva, aplicar este criterio:

| Si el contenido… | Va a |
|------------------|------|
| lo necesita alguien **para escribir el código** | el **LLD** (normativo) |
| es la razón por la que se **descartó otra opción** | el **Anexo de Decisiones** (bitácora, entradas `D-nn`) |
| es una **observación sobre un sistema de terceros** (muestras, deducciones) | el **Anexo de la Federación** |

Tres señales de que algo **no** es LLD aunque lo parezca: una **tabla de opciones con veredicto**, una
narrativa **"antes pensábamos X, ahora Y"**, o un **volcado JSON**. El LLD enuncia el *qué* en una línea y
enlaza con `[D-nn]`. Detalle campo a campo de los DTOs: **solo** en el spec OpenAPI, nunca duplicado en el
LLD (`D-25`).

### Al cerrar una fase (o una mini-fase): los sitios que el cierre no toca solo

Cada cierre escribe su detalle en su plan y su lección al final de este fichero, y **eso no basta**: la auditoría
002 (`A-8`·H-51) encontró *"F10 en curso"* cuatro secciones por encima de *"F10 entregada"*, y el README parado
en F8 con seis cifras viejas. La deriva cae siempre en lo que el cierre no tiene delante, así que el cierre no se
da por hecho sin estos cinco pasos:

1. **El recuento, medido y no copiado**: `REQUIRE_DB=1 swift test --xunit-output /tmp/x.xml`, y el total
   **leído del XML** (`grep -c '<testcase ' /tmp/x-swift-testing.xml`), no de la línea de resumen (H-07).
2. **La cabecera del [README](./backend/README.md)**: §0 (fases entregadas, recuento, tabla de operaciones y
   *"las otras N"*), el recuento y la duración de §5, la tabla de filtros de §5 con los de la fase, y las tablas
   de §3 si la fase añadió una.
3. **«Estado actual» de este fichero**, y el rótulo de su plan en «Documentación clave».
4. **Los rótulos de su plan de fase**: cada `### Bloque` con su ✅, y la cabecera con la fecha de cierre.
5. **Las cifras que la fase movió**, buscadas por el número viejo en todo el árbol y no solo en los ficheros
   que se tocaron: `grep -rn "<cifra vieja>" AGENTS.md backend/*.md docs/ backend/Sources backend/Tests`. Sirve para
   tests, migraciones, operaciones del `filter`, motivos de `IngestionSkip.Reason`, códigos `Problem` afirmados…
   Una cifra que va acompañada de *"los N que faltan"* se mueve **con** ella.

Las cifras de un registro fechado (*"Hecho el …: 537 → 539 tests"*) **no se tocan**: son historia y son
correctas. Lo que se actualiza es lo que dice *"hoy"*.

## Decisiones técnicas (resumen — detalle y razones en el ADR-API_y_BBDD-001)

- **Base de datos:** PostgreSQL gestionado en **Supabase** (BD + Auth + Storage), **región UE** (RGPD; datos de menores).
- **API backend:** **Swift — Vapor + Fluent** (ORM oficial), estilo **REST** con **OpenAPI**. API *tenant-aware*.
- **Contrato de la API: *design-first*** (`D-65`). El *spec* es la **fuente de verdad** y de él se generan los tipos
  y el `APIProtocol` con `swift-openapi-generator` + `vapor/swift-openapi-vapor`. **Al tocar el *spec*, tenerlo
  presente: el generador emite tipos, no validación** — ignora `readOnly`, `pattern`, longitudes, rangos,
  `minProperties`, `default`, `tags` y `security`. Esas reglas las hace cumplir el **Dominio** (Value Objects) o el
  *handler*, según la tabla de reparto del LLD §5.5. No dar por hecho que declararlo en el YAML lo hace cumplir.
- **Autenticación:** **Supabase Auth** (`auth.users`), *pool* compartido; *claims* de tenant (`club_id`, `role`) hechos cumplir por la API/RLS.
- **Multi-tenancy:** **una sola base de código**; aislamiento por **_schema_ por club** (tier gestionado) o **proyecto por club** (tier dedicado). Modelo *pooled* (`club_id` en tablas compartidas) descartado.
- **Despliegue:** **PaaS con Docker**, **Fly.io** preferente para Vapor (compilación de Swift en *builder* remoto/CI, no en el host); Railway/Render como alternativas. Tope de coste **20 $/mes** en el tier gestionado.

## Licencia

Repositorio **propietario** — ver [LICENSE](./LICENSE) (`LicenseRef-Proprietary`, declarada también en
`info.license` del *spec*). No es código abierto: no publicar fragmentos fuera del repositorio ni añadir
cabeceras de licencias permisivas a ficheros nuevos.

## Idioma

El desarrollador es hispanohablante y toda la documentación del proyecto se escribe en español (es-ES). Responde y documenta en español salvo que se indique lo contrario.

## Artefactos previstos

El proyecto se compone de los siguientes artefactos, aún por construir:

- Base de datos
- API backend
- Web backoffice
- App iOS de consulta
- App Android de consulta

Los tres primeros artefactos (base de datos, API backend y web backoffice) se alojarán mediante servicios cloud contratados para tal fin.

## Estado actual

Las **decisiones tecnológicas de BD/API y despliegue están tomadas** (ver ADR y resumen arriba) y el
**backend camina**: del [Plan de desarrollo](./docs/Plan%20de%20desarrollo-001.md) están entregadas **F0**
—`GET /v1/club` responde de HTTP a Postgres contra tenants aislados—, **F1**, que añade `Season` y
`Competition` en dominio y persistencia, **F2**, el puerto `FederationClient` con el adaptador del
calendario de la RFFM contra volcados reales (Plan §4.3), **F3**, la **política de *upsert*** de §3.7
—`UpsertPolicy`, `Kickoff` y `MatchResult` en el Dominio, sin una sola bandera nueva en el esquema (Plan
§4.5)—, **F4**, la **cadena de emparejamiento** —`MatchingChain`, `MatchOutcome` y `NormalizedName`, también
sin columnas nuevas (Plan §4.6)—, **F5**, la **ingesta del calendario de punta a punta** —las cuatro
entidades de salida contra Postgres real, el transporte HTTP y el canario (Plan §4.7)—, y **F6**, el **job**:
el `AsyncCommand`, el recorrido por tenant, la cadencia y **los dos primeros endpoints desde F0** (Plan §4.8).
Y las dos que la auditoría añadió: **F6-bis** —el sobre del puerto de federación y la resiliencia del
recorrido— y **F6-ter**, el segundo freno de `D-86` bajo el arnés. Y **F7**, la **clasificación**: la entidad
9 de §3.2 con sus **dos fuentes** —ingerida de la federación o calculada desde `Match` (`D-15`)—, su
puerto, su adaptador contra volcado real, su tabla y su pasada (Plan §4.9). Y **F8**, los **goleadores**: la
entidad 15 de §3.2, con la clave de *upsert* que esa sección no tenía (`D-93`), la **única retirada de filas de toda la
salida de la ingesta** (`D-94`) y un hallazgo que nadie buscaba — **un `CHECK` derivado de un enumerado no se
mantiene solo** (Plan §4.10).
Y **F9**, que **no escribió código y eso es su resultado**: el adaptador de la **FCF** se aplazó al
revalidar la fuente antes de escribirlo (`D-95`, Plan §4.11). Y **F9-bis**, la mini-fase que **le pone voz al
equipo que la fuente publica sin código**: el motivo número diez de `IngestionSkip`, y con él el ensanche
—decidido, no heredado— de lo que esa lista significa.
Y **F10**, **entregada el 2026-09-24**: el enganche del equipo con su federación (`D-67`), troceado en
[su propio plan](./backend/Plan%20F10-001.md) —siete bloques, 47 ciclos—, con las dos puertas
`POST /teams/{id}/federation-link` y `/preview` asomadas a HTTP. Antes de cerrarla, **F10-bis**: el ciclo de
vida de la pasada aceptada (`D-96`). Y después, **F10-ter**: el identificador que sabe escribirse, en
minúscula y en un solo sitio (`TypedIdentifier`).
**546 tests.** Lo siguiente es la [auditoría 002](./backend/Plan%20de%20auditor%C3%ADa-002.md), antes de
montar `launchd` y abrir el backoffice. **Web backoffice, app iOS y app Android siguen sin empezar.**

**F5 es la fase que junta lo que F3 y F4 entregaron sueltos**: la cadena decide qué fila es, `UpsertPolicy`
decide qué se le escribe. El volcado real de una temporada jugada entra entero —30 jornadas, 240 partidos, 16
equipos— y la segunda pasada no duplica nada contra los `UNIQUE` de verdad. Trae además **la entidad 21 del
modelo**, `IngestionRun` (`D-85`): el registro de cada pasada, escrito **fuera** de su transacción para que
sobreviva al `rollback` de la que falla — que es la única que nadie ve, porque la ingesta no tiene usuario
delante.

**De F0 a F5 no se añadió un solo endpoint, y no fue un descuido: era el plan.** F1 entrega entidades,
*Value Objects*, puertos, `Record`s y migraciones **sin ningún caso de uso**; F3 y F4, dos reglas puras sin
llamante; y F5, la pasada entera, cuyo adaptador primario es un `AsyncCommand` y **no un Controller**
(§2.3-b). **F6 es la primera que mueve el `filter`**, con las dos operaciones que el módulo de ingesta sí
necesita asomar (`D-88`): `GET /v1/ingestion-runs` —el registro de `D-85`, que si no no lo lee nadie— y
`POST /v1/ingestion-runs`, el disparador manual del job. Las siguientes llegaron en **F10**
(`POST /teams/{id}/federation-link` + `/preview`). El `filter` de `openapi-generator-config.yaml` **es**
literalmente el alcance entregado (`D-69`): al añadir un endpoint, se añade ahí primero — y el compilador
para el *build* hasta que el *handler* exista.

Sí existe ya un **artefacto ejecutable**: el *spec* OpenAPI en [`backend/Sources/APIContract/openapi.yaml`](./backend/Sources/APIContract/openapi.yaml), que se construye **entidad a entidad** en paralelo al §5 del LLD (hoy: `Club`, `Season`, `Competition`, `OpponentClub`, `Team`, `Round`, `Match`, `StandingRow`, `LeagueScorer` — con la que queda **cerrada toda la superficie de salida de la ingesta**— y, del **dominio manual**, `Player`, `Absence`, `Appearance`, `Card` y `Goal` con CRUD completo, más `CompetitionSanctionBracket`, que es **configuración** y se escribe como conjunto con un `PUT` (`D-50`). más las cuatro de **roles y permisos** (`StaffMember`, `StaffPosition`, `PositionPermission`,
`StaffAssignment`), más `TeamRegistration`, la inscripción del equipo en la temporada (`D-68`). **El contrato queda completo: las 20 entidades que §3.2 tenía cuando se cerró tienen sus endpoints**).
**La 21ª, `IngestionRun`, ya también**: la añadió F5 al modelo y F6 le dio su recurso, con el job delante
(`D-85`, `D-88`). Validación:

```sh
npx @redocly/cli lint backend/Sources/APIContract/openapi.yaml
```

### El backend: cómo está montado y cómo se trabaja

> **Para levantarlo, hablarle con `curl`, mirar la BD con TablePlus o ver los cuerpos que cruzan la frontera
> en los tests: [`backend/README.md`](./backend/README.md)** — el manual de a bordo, verificado comando a
> comando. Lo de aquí abajo es el mapa; ése es el manual.

Paquete SwiftPM en `backend/`, **Swift 6** en todos los *targets* (modo de lenguaje `.v6` + *upcoming
features*; **sin** `defaultIsolation: MainActor`, que es recomendación de apps, no de un backend).

**Un *target* por capa, y el grafo de `Package.swift` ES la Regla de dependencia de §2.2** — no una
convención de carpetas. Comprobado: `import Vapor` desde `Domain` o `Application` **no compila**.

```
Run ─► App ─┬─► HTTPAdapter ─┬─► APIContract   (tipos generados del spec)
            │                └─► Application
            ├─► Persistence ────► Application
            ├─► Federation ─────► Application   (adaptadores RFFM / FCF)
            ├─► Tenancy
            └─► Application ────► Domain        (Domain no depende de nada)
```

**`Federation` cuelga de `App` desde F6**, y hasta entonces no colgaba: de F2 a F5 lo mantuvo en el grafo de
*build* su *target* de tests, porque el adaptador no tenía llamante. Ese llamante es el job de ingesta
(§2.3-b), y la raíz de composición es el único sitio donde el puerto y su implementación se conocen.

| Target | Capa (§2.2) | Qué contiene |
|---|---|---|
| `Domain` | Dominio | Entidades, *Value Objects*, catálogo de federaciones y **las dos mitades de §3.7**: la política de *upsert* (F3) y la **cadena de emparejamiento** (F4). F5 añade las cuatro entidades de la **salida** de la ingesta —`Round`, `OpponentClub`, `Team`, `Match`— y `IngestionRun`. F7, `StandingRow` y `StandingTable`, el *fallback* calculado de `D-15`. F8, `LeagueScorer` — con eso la salida de la ingesta está **completa**. **Sin** `import Vapor/Fluent` |
| `Application` | Aplicación | Casos de uso y **puertos** (`ClubRepository`, `TenantUnitOfWork`, `FederationClientProvider`). F6 añade `IngestClubCalendars`: **el recorrido de un club**, con sus reglas de alcance y de fallo. F7 añade `StandingsSyncPlan` —qué jornadas entran y de dónde sale cada una— y `IngestStandings`, cuya **unidad es la jornada** y no la competición. F8 añade `IngestScorers`, cuya unidad **vuelve a ser la competición** (§3.2) y que es la única pasada con una operación de **retirada** (`D-94`). F10 añade al puerto de federación **la inversa de la coordenada** —leer la URL que el administrador pega—, que es su **única operación que no habla con la fuente** (`D-97`)— y los **dos casos de uso del enganche** (`PreviewFederationLink`, `LinkTeamToFederation`), con `TeamRegistrationRepository` y `TeamRepository.find(_:)` como puertos nuevos |
| `APIContract` | — | Generado del *spec* por el plugin. **No se edita a mano** |
| `HTTPAdapter` | Adaptador primario | Conforma el `APIProtocol` generado; mapea DTO ↔ dominio |
| `Persistence` | Adaptador secundario | `…Record` de Fluent, repositorios, migraciones |
| `Federation` | Adaptador secundario | Adaptadores de las APIs de federación. **Sin Vapor ni Fluent**: lo que hace es parsear texto ajeno |
| `Tenancy` | Infraestructura | Plano de control, `SET LOCAL search_path`, middleware |
| `App` | — | **Raíz de composición**: el único sitio que cablea las capas. Y los `AsyncCommand`: `migrate-tenants`, `provision-tenant`, `ingest` (F6) y las dos herramientas de operación, `seed-competition` y `seed-team` (F10, `C-F.1`) |

```sh
cd backend
docker compose up -d                      # Postgres 16 efímero en :5434
swift build
swift test                                # 4 niveles (§8.1); los 2 primeros sin I/O
swift test --filter FederationTests       # los adaptadores de federación: sin red y sin Docker
                                          # (sus volcados: Tests/FederationTests/Fixtures/README.md —
                                          #  son copias de docs/, y en Xcode no se leen: una sola línea)
swift run Run migrate --yes               # plano de control (public.tenants)
swift run Run provision-tenant atleti     # alta de club: schema + registro + migraciones
swift run Run migrate-tenants             # recorre todos los clubes (§4.7)
                                          # hoy son DIECISÉIS migraciones por tenant:
                                          #   clubs -> seasons -> opponent_clubs ->
                                          #   teams -> competitions -> rounds ->
                                          #   matches -> standing_rows ->
                                          #   league_scorers ->
                                          #   ingestion_runs -> (+kind, +contadores)
                                          #   -> (+round_id) -> (+contadores de
                                          #   goleadores Y EL CHECK DE kind REHECHO)
                                          #   -> (F10-bis: finished_at ANULABLE, el
                                          #   CHECK de outcome REHECHO y el índice
                                          #   por started_at) -> (F10: la tabla
                                          #   team_registrations, con el UNIQUE
                                          #   NULLS NOT DISTINCT de tres columnas,
                                          #   la FK COMPUESTA a la temporada de la
                                          #   competición y, de paso, los dos
                                          #   índices compuestos de matches que
                                          #   §4.6 mandaba y no existían —H-36—)
                                          #   -> (F10: se RETIRA el índice de
                                          #   ingestion_runs por finished_at, que
                                          #   desde que la consulta ordena por
                                          #   started_at no tiene ningún lector)
                                          #   Las que ALTERAN ingestion_runs son
                                          #   varias y no una porque cada una ya
                                          #   estaba aplicada cuando llegó la
                                          #   siguiente (`D-90`). Y la de F8 rehace
                                          #   el CHECK de `kind` porque un enumerado
                                          #   derivado NO se mantiene solo: se
                                          #   deriva al migrar y ahí se congela.
                                          #   Las dos últimas van SEPARADAS aunque
                                          #   sean de la misma fase: no son la misma
                                          #   razón, y una migración que hace dos
                                          #   cosas no se revierte a medias
                                          #   El orden es el de FK, y cada fase
                                          #   añade la suya AL FINAL DE LA LISTA
                                          #   QUE LE TOQUE, no al final a secas
                                          #   (`D-90`). Una ya aplicada NO se
                                          #   edita: `_fluent_migrations` guarda
                                          #   el nombre, no el contenido
                                          #   --revert exige --yes: borra las tablas de
                                          #   TODOS (o del que diga -t). Si uno falla, el
                                          #   recorrido SE PARA y el error dice de qué
                                          #   club fue (`D-86`, §9.3)
swift run Run seed-competition -t atleti -u "<URL del calendario>" \
                               -c cadete -g masculino
                                          # HERRAMIENTA, no contrato: da de alta la
                                          # *entrada* de la ingesta desde la URL pegada
                                          # (`D-22`), con los rótulos que dice la
                                          # federación y pasando por el Dominio. Valida
                                          # antes de escribir. Hasta que llegue F10 (`D-67`)
swift run Run seed-team -t atleti -c cadete -g masculino -m futbol_11 -l A
                                          # LA OTRA MITAD (F10, `C-F.1`): el EQUIPO
                                          # PROPIO. Nace propio y SIN enganchar —las
                                          # dos claves nulas—, que es el único estado
                                          # desde el que `D-67` engancha y el único en
                                          # que la fila no tiene segundo escritor
                                          # (`D-66`). `POST /v1/teams` es del
                                          # backoffice y NO existe: sin esto la base de
                                          # trabajo no puede tener un equipo propio.
                                          # Categoría, género y modalidad son IDENTIDAD
                                          # y no tienen defecto honesto: equivocarlas da
                                          # un 409, no un rótulo feo. La letra nula ES
                                          # un valor —«el único equipo»—, no un comodín.
                                          # NO escribe TeamRegistration, y desde el
                                          # bloque D de F10 ya no es porque la tabla
                                          # falte: quien la escribe es LA CASCADA DEL
                                          # ENGANCHE (`D-68`, `C-C.10`), que es la que
                                          # sabe en qué competición queda inscrito.
                                          # Manual: README §6.2
swift run Run ingest                      # LA PASADA DE INGESTA (§2.3-b, F6)
                                          #   -t <slug[,slug]>  solo esos clubes
                                          #   -c <uuid>         solo esa competición
                                          #   --season <uuid>   esa temporada, aunque no sea la vigente
                                          #   --force           ignora el antirrebote de 6 h
                                          # Sale con código 1 si algo falló: es la
                                          # única señal que ve el cron (`D-86`).
                                          # Antes salía 133 —el SIGTRAP de un
                                          # `throw` en el nivel superior—, que no
                                          # se distingue de un crash (`A-5`/H-39)
swift run Run serve
curl http://atleti.localhost:8080/v1/club   # el club va en el subdominio (§6.1)
curl "http://atleti.localhost:8080/v1/ingestion-runs?competitionId=<uuid>"   # el registro (D-85)
HTTP_TRACE=1 swift test --filter APITests --no-parallel   # ver los cuerpos HTTP
FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests     # el CANARIO: pasa el parser por
                                          # encima de la respuesta VIVA (Plan §4.4). Fuera de
                                          # `swift test`, y con red. Coordenada configurable por
                                          # FEDERATION_LIVE_SEASON/_COMPETITION/_GROUP/_NAME
docker compose down -v
```

**Cinco cosas que hay que saber antes de tocar este código:**

- **El *spec* se genera *filtrado*** (`D-69`). `APIProtocol` obliga a implementar **todas** las operaciones
  generadas, así que el `filter` de `openapi-generator-config.yaml` lista solo las implementadas — esa lista
  **es** el alcance entregado. Al añadir un endpoint, **se añade ahí primero**. El *spec* no se toca: sigue
  completo.
- **Todo acceso a datos de tenant entra por `TenantUnitOfWork`** (§6.2). No se pasan `Database` por ahí: el
  aislamiento depende de que haya **un** punto de paso.
- **El contexto de actor (`ActorContext`) ya cruza la frontera de los casos de uso** (§7.4), aunque hoy solo
  lleve el club. Un caso de uso nuevo lo recibe **desde el principio**, no cuando llegue §7.
- **El ámbito de tenant *es* una transacción, y eso condiciona cómo se escribe un test** (§6.2). Lo que se
  escriba dentro de un `withRepositories` **no lo ve otra conexión** hasta que cierra, así que un `SELECT` en
  crudo para comprobar una columna no encuentra nada; y una violación de restricción **aborta la transacción
  entera** (`25P02`), de modo que dos intentos que deban fallar en el mismo ámbito hacen que el segundo pase
  por el motivo equivocado. `TenantFixture` (nivel 3) obliga a declarar cada ámbito justo por eso.
- **El `CHECK` de un enumerado se deriva, nunca se teclea** (§4.6, `D-02`): `sqlValueList` es genérico sobre
  `CaseIterable where RawValue == String`, así que un enumerado nuevo lo hereda solo. Y el `switch` sobre
  `DomainError` en `ProblemMiddleware` es **exhaustivo** a propósito — un caso de error nuevo no compila hasta
  que alguien decida su código HTTP. **Y ese código no se elige a ojo**: el 422 es para el cuerpo que se
  decodificó y dice algo que la regla no admite; el **400**, *"para lo que ni siquiera se pudo decodificar"*.
  Por eso la URL de calendario ilegible de F10 (`unreadableFederationURL`) es un **400** y no un 422 — no es
  un campo del modelo, es **el sobre** del que salen los cuatro parámetros de la coordenada (`D-22`)—, y por
  eso hay que mirar **qué códigos declara el *spec* en esa ruta** antes de decidir: un 422 que el contrato no
  declara no lo sabe leer un cliente generado.
- **`IngestionRun.skipped` ya no es *"lo que la pasada no escribió"*: es *"lo que dejó señalado"*** (F9-bis).
  Nueve de sus **diez** motivos son filas ausentes; el décimo —`unidentifiedTeam`, el equipo que la fuente
  publica sin código— es una fila que **sí** se escribió, pero coja. La consecuencia para quien la lee: **se
  lee por el motivo de cada línea y no se cuenta**, porque su longitud ya no es *"cuántas filas faltan"*. Al
  añadir el motivo número once: `IngestionSkip.Reason` **cruza la frontera HTTP** —enumerado espejo en el
  *spec* y traducción a mano en `IngestionHandler.toContract()`—, así que toca **cuatro** *targets* y el
  `switch` exhaustivo obliga a escribir la línea pero **no** a escribirla bien. *(El recuento decía **once**
  aquí, en el plan de F10 y en la descripción del propio* spec*; son diez, contados en los dos lados el
  2026-09-24. Lo vigila ahora `ContractEnumTests`.)*
- **Un identificador sabe escribirse, y no se escribe a mano** (`F10-ter`). Los **once** —`TeamID`,
  `SeasonID`, `IngestionRunID`…— conforman `TypedIdentifier`, que decide la forma canónica **una vez**: RFC
  4122 §3, minúscula. Se interpola el identificador, `"\(teamID)"`, **nunca** `raw.uuidString.lowercased()`
  ni, mucho menos, `"\(teamID.raw)"` — que era el defecto: 14 puntos de salida se acordaban de bajar la caja
  y 14 no, y el `detail` de un problema no casaba con el id que el cliente había enviado. `raw` sigue siendo
  el `UUID` para quien lo necesite de verdad (repositorios, columnas). Al añadir el identificador número doce:
  conformarlo y ponerle su renglón en `IdentifierTextTests`, que los enumera a mano porque Swift no deja
  recorrer los tipos que cumplen un protocolo.
- **Lo que se queda sin arnés no es lo complicado: es lo que ningún montaje llega a ejercer** (medido el
  2026-09-25, [Plan de desarrollo §4.1](./docs/Plan%20de%20desarrollo-001.md), detalle bajo `F10-ter`). Los
  cuatro campos que cruzaban la frontera sin una sola aserción eran **un anulable que todas las *fixtures*
  dejaban en nulo** —el escudo del `/preview`, el del club— y **un camino que la batería no provoca** —el
  `roundId`, que solo existe en la pasada de clasificación, y ésa no ocurre con un calendario vacío—. Ninguno
  se habría encontrado leyendo el código. **El método que los encontró cuesta dos minutos y conviene repetirlo
  cuando el *spec* crezca**: cruzar los campos que el contrato declara contra el árbol de tests y mirar los
  que tienen cero aciertos. Hoy: **52 campos, 0 sin afirmar**, y **17 de 30** códigos `Problem` afirmados
  **por código** y no solo por *status* (`A-7`·H-46 lo dejó en 3 de 14; los trece que faltan son los quince
  que su fila del plan de auditoría lista por nombre, menos los dos de federación que cerró `6a837ab`).
- **Y los valores de un test tienen que ser distintos entre sí cuando lo que se prueba es un mapeo.** Los
  trece contadores de `IngestionRunResponse` se afirman con 1..13 **a propósito**: con ceros, o con el mismo
  número repetido, una permutación es **invisible** y el test pasa igual con los campos cruzados. Lo mismo
  vale para los enumerados espejo (`C-E.9`) y para el UUID del identificador, que lleva letras adrede porque
  uno de solo dígitos se escribe igual en las dos cajas.
- **Los tests citan el diseño.** Cada `@Test` lleva su `§x` o su `D-nn`: es lo que permite revisar una fase
  leyendo los tests en vez del código (Plan §9). `swift-testing`, no XCTest (`D-70`).
- **Y se escriben con esqueleto: el rojo tiene que ser de aserción, no de compilación** (Plan §5.1). Escribir
  el test primero compra la presión de diseño, pero un `cannot find 'X' in scope` **no** demuestra que la
  aserción cace nada, porque no llegó a ejecutarse. Antes de implementar, la función existe con su firma
  definitiva y **devuelve mal a propósito** — un valor válido pero equivocado, nunca `fatalError()`, que
  trapea y se lleva la ejecución entera. Y una regla por ciclo: con un *suite* entero el esqueleto no dice
  nada. Es lo que F2 se saltó (Plan §4.3).

**Si abres el proyecto en Xcode y ves `Cannot find type 'Components' in scope`, no está roto.** `Components`
y el resto del contrato **no existen en disco hasta que el plugin corre** (`D-69`), así que el índice de Xcode
no los conoce **antes de la primera compilación exitosa**. Además, Xcode pide **confiar y habilitar** los
plugins de *build* de paquetes externos: si ese aviso no se acepta, el plugin no corre nunca y el error no se
va. Orden: aceptar el aviso → ⌘B → si persiste, *File ▸ Packages ▸ Reset Package Caches* y volver a compilar.
**La CLI es la fuente de verdad**, no el índice de Xcode: si `swift build` pasa, el código está bien.
*(Comprobado con Swift 6.3.2 y con la 6.4 de Xcode 27 Beta: el paquete compila con las dos.)*

**El club viaja en el subdominio, nunca en una cabecera que ponga el cliente.** `*.localhost` resuelve a
127.0.0.1 sin configurar nada, así que **desarrollo usa la misma vía que producción**:
`http://atleti.localhost:8080/v1/club`. La cabecera `X-Club` existe solo como andamiaje y está **restringida
por lista blanca a `.development` y `.testing`** — aceptarla en producción sería dejar abierto un conmutador
de tenant, porque es un dato que controla el cliente por completo.

**Deuda declarada de F0**, para que nadie la confunda con diseño: el tenant se resuelve por `Host`, **no** por
*claim* firmado. §6.1 dice que el *claim* es autoritativo, el subdominio solo enrutado, y que una discrepancia
**se rechaza**; `TenantResolutionMiddleware` es el sitio donde eso se corregirá.

Próximos pasos: **el orden y el método los fija ahora el [Plan de desarrollo-001](./docs/Plan%20de%20desarrollo-001.md)**
(**F0** = esqueleto que camina con `GET /v1/club`; **F1** = `Season` y `Competition`, la *entrada* de la
ingesta; **F2–F10** = la ingesta propiamente dicha).
Con F0–F6, **F6-bis**, **F6-ter**, **F7**, **F8**, **F9-bis**, **F10-bis**, **F10** y **F10-ter**
entregadas y **F9
aplazada sin escribir código** ([D-95], Plan §4.11), **la ingesta está completa de punta a punta**: el
enganche de [D-67] es por donde entra el usuario y era lo último que faltaba
([`backend/Plan F10-001.md`](./backend/Plan%20F10-001.md), 47 ciclos en siete bloques, **541 tests**).

**Lo que F10 deja puesto y conviene saber antes de tocar la frontera HTTP:**

- **Las dos puertas de [D-67] existen**: `POST /v1/teams/{id}/federation-link/preview` → **200** sin
  persistir nada, y `POST /v1/teams/{id}/federation-link` → **202** con la cascada escrita y la primera
  ingesta encolada. El manual con los `curl` y los ocho códigos de error está en
  [`backend/README.md` §4.2](./backend/README.md).
- **La traducción error → HTTP tiene UN sitio y es `ProblemMiddleware`.** F10 midió que los códigos que el
  contrato declara ya salían correctos por ahí cuando el error se escapa de un *handler*, así que **no se
  duplicó** en los *handlers*: un segundo sitio decidiendo el mismo código HTTP es lo que acaba divergiendo.
  Lo que un *handler* sí atrapa es lo que quiera servir como respuesta **tipada** del contrato.
- **`FederationError` ya se distingue en producción** (`A-6`/H-15): `transportFailure` → **504**, las otras
  tres → **502**. Ojo a la mitad que no se ve en el `case`: lo que sale de un *handler* llega **envuelto** en
  un `ServerError`, así que un tipo de error nuevo hay que añadirlo **también** a la lista de desenvoltorio o
  la traducción no lo alcanza nunca.
- **El actor sale de un puerto, `ActorResolver`** (`C-E.2`): la guarda de §6.1 dejó de comparar un valor
  consigo mismo. El adaptador de producción sigue leyéndolo del `Host` —la deuda declarada de F0—, así que
  **montar la auth es cambiar ese adaptador**, no el middleware ni los *handlers*.
- **El 409 del enganche tiene TRES causas y la tercera se escribió midiendo contra la base de trabajo**
  (`C-E.10`): *"ese `federationTeamId` ya pertenece a otro equipo"*. Es el desenlace **normal de enganchar
  tarde** —la ingesta no crea equipos propios ([D-66]), así que el equipo que nadie enganchó ya existe como
  rival con su código— y daba un **500 con el SQL en crudo**. Ningún test de la batería podía verlo: en todos
  los montajes el código estaba libre.

**F9 era el adaptador de la FCF y no se escribió, y conviene saber por qué antes de reabrirlo.** La fase
abrió, hizo lo primero que [D-74] manda —**revalidar el anexo antes de escribir el adaptador**— y la
revalidación la paró ([Anexo FCF §C.12], medido el 2026-09-20): la clasificación de la FCF publica `played`,
`won`, `drawn` y `lost` como **la cifra de casa y la de fuera concatenadas sin separador** —`played: "1515"`,
`won: "107"`, 16/16 filas contra el calendario del mismo grupo—, y **no es que no sepamos descodificarlo**:
su propio frontal las pinta en crudo, así que su web enseña `1515` en la columna de partidos jugados. Además
dice que no con **el contenedor vacío** —`{}`, `[]`, `{"data":[]}`, los tres con `200`—, indistinguible de
*"todavía no hay datos"*, que con la retirada de [D-94] vaciaría el ranking entero ante un `grupId` mal
tecleado. Y **cambió de forma en 23 días, hacia atrás**: de 21 a 23 claves por partido y la letra pegada al
nombre del equipo **también en una liga terminada en mayo**.

**Aplazarla no costó tocar nada, y eso es lo que hay que no romper:** `CatalogFederationClientProvider`
devuelve `nil` para `.fcf`, las dos puertas de `POST /v1/ingestion-runs` dan **501** con cuerpo RFC 7807
(`H-28`) y el recorrido salta el club **sin dejarle pasadas fallidas** ([D-85]) — no hay fallo que registrar,
hay federación sin adaptador. **`FederationCode.fcf` se queda en el enumerado**: quitarla no destensaría el
`CHECK` de un *schema* que ya existe ([D-90]) y tiraría lo medido. La condición de reapertura está escrita y
se comprueba en una llamada ([D-95]). **La consecuencia de negocio, sin adornos: un club catalán no se puede
dar de alta con ingesta**, y eso lo hereda F10, que es la fase del enganche.

**Lo que de la FCF sigue siendo bueno y está medido** ([Anexo FCF §C.12.5]), para el día que se retome: el
host del escudo (`files.fcf.cat`, que **no viaja en la respuesta** al revés que en la RFFM), la letra suelta
al final del nombre, `CODACTA` único en 240/240, la clave de jornada que **sí** coincide con su campo, el
formato de `COMIENZO1`, el par `CERRADA`/`ESTADO` como única señal de "jugado" —el marcador no sirve: los
pendientes traen `"0"`— y que **no hacen falta cabeceras de navegador**, al revés de lo que decía un
comentario nuestro heredado del §C.1 obsoleto. Su ranking de goleadores publica `goles`, `penalti` y `total`
como **números JSON y no como cadenas**, lo que rompe la regla de §F.11 que vale en Madrid; y **`total` no es
el total de goles, son partidos jugados** — 0/50 filas cuadran con `goles + penalti`, medido en F8. El
`goals` del modelo sale de **`goles`**.

**Y lo que F8 dejó desmentido, que hay que leer antes de añadir el cuarto caso a `IngestionKind`** (el acta
de `D-57`): *"el `CHECK` de un enumerado se deriva solo"* es **falso** para un *schema* que ya existe. `D-02`
y `sqlValueList` derivan la expresión, sí — **una sola vez, cuando la migración corre**. Lo que queda en la
base es el texto de aquel día, y `D-90` explica por qué no se actualiza: `_fluent_migrations` guarda el
nombre, no el contenido. Se midió en `club_atleti` antes de arreglarlo. **Un caso nuevo en un enumerado con
`CHECK` obliga a una migración que lo *rehaga*** (`replaceCheckConstraint`), o un alta limpia lo acepta y un
club vivo lo rechaza con un `23514` que nadie relaciona con Swift. Lo vigila `MigrationIntegrityTests`, y hizo
falta **tumbar dos versiones del test con mutación** para escribirlo bien: un *schema* migrado antes de que el
caso existiera **no se puede fabricar ejecutando el código de ahora**, porque el código de entonces ya no está.

Las otras dos reglas que F8 sí heredó de F7 y cumplió: su pasada cae del lado **nulo** de `round_id`
—`LeagueScorer` es estado vigente único, no *snapshot* por jornada (§3.2), y el `CHECK` ya lo admitía sin
tocarlo porque se escribió enunciando la regla y no enumerando los casos—; y **no copiar la forma del sobre**,
que es lo que F6-bis avisó. En `/api/scorers` esa advertencia valía doble: su equivalente catalán es **un
array pelado, sin sobre ninguno**, así que `FederationScorerTable` lleva **un** campo y deja fuera hasta el
`codigo_competicion` que su vecina celebra —aquí ese código **se envía**, luego solo podría ser eco—. **La auditoría está cerrada**: ocho bloques, **cero S1**, 50 hallazgos, y su
último bloque dejó una fase más — la misma válvula que parió F6-bis. **F6-ter fue una función y su test**:
`IngestCommand.stopsTraversal(_:)`, la pregunta *"¿este resultado detiene el recorrido?"* sacada del bucle,
porque `D-86` enmendada tiene **dos** frenos y el del recorrido de **clubes** emparejaba un caso de error entre
dos *targets* sin que nada lo comprobara (`A-7`/H-45). Ahora los dos entran por la misma puerta —son la misma
razón contada desde dos sitios— y el desenlace del club viaja **entero** hasta la decisión, porque
`diagnosticText` pierde el caso del error. **Lo que sigue fuera del arnés, y está declarado**: el *cable* —la
línea que llama a la regla—, que solo se cierra haciendo inyectable la unidad de trabajo de `ingest`; la
**regla** sí está afirmada por su nombre. Iba antes de F7 por el mismo argumento que F6-bis: F7 y F8 **no
estrenan recorrido, le cuelgan trabajo**. F6-bis era *"arréglalo antes de que F7 y F8 lo copien"* en dos mitades: **la resiliencia del
recorrido** (`4d66aa0`) y **el sobre del puerto**, que dejó `FederationRound.label` fuera —no lo leía nadie— y
`seasonLabel` **opcional** —la FCF no la publica y en la RFFM es el eco de nuestro propio parámetro—, más la
guarda de temporada de `D-91`. Al añadirle `fetchStandings` y `fetchScorers`: **no copiar la forma del
sobre**. `/api/standings` y `/api/scorers` de la RFFM traen `competicion` y `grupo` y sus equivalentes de la
FCF no, así que un DTO modelado por analogía reproduce H-08 y H-09 **dos veces más** antes de que exista el
adaptador catalán.

**F7: `StandingRow`, con la clasificación histórica de la RFFM y el
*fallback* calculado desde `Match`** (`D-15`, `D-55`). **Los tres deberes que F6 arrastraba están hechos**: el
recorrido continúa tras un fallo y la unidad de aislamiento es la competición (`D-86`), la cadencia vive fuera
del proceso y el código trae un antirrebote que no es el tope semanal (`D-87`), y el registro tiene su `GET`
—más un `POST` que dispara la pasada, que no estaba previsto y lo pidió el desarrollador para controlarlo
desde la web (`D-88`)—.

**Quedan dos deberes que no son de código, van juntos y conviene no perderlos**: **montar el cron** y **montar
el CI**. F6 entrega el comando, pero quién lo llama los lunes y los fines de semana es una decisión de
despliegue; hasta que exista, el tope semanal de §5.6 **no lo garantiza nada**. Y **no hay CI de ningún tipo**,
con el agravante de que el código sí está preparado: la guarda de `DatabaseAvailability` falla con `CI` o
`REQUIRE_DB` definidas y **nadie las define**, así que hoy un verde puede significar *"no se probó nada que
toque la base"* — el texto de la salida es **idéntico** corriendo y omitiendo, y lo único que cambia es la
duración: 5,70 s contra 0,002 s (`A-7`/H-07, medido). Al correr la batería a mano: **`REQUIRE_DB=1 swift test`,
nunca `swift test` a secas**. Y si hace falta una señal legible por máquina, `--xunit-output` trae los
recuentos por *target* y el motivo de cada omitido. Los dos deberes son la misma decisión de despliegue,
porque el canario necesita exactamente lo mismo que el cron.

**La vara de medir sigue siendo la misma, y va subiendo**: F3 hizo el bucle de Plan §5.1 entero (doce ciclos,
11/11 mutaciones), F4 lo repitió con **16/16**, F5 con **35 mutaciones, 34 cazadas y 1 equivalente** sobre
**35 ciclos**, y F6 con **23/23**, F6-bis con **8/8**, F6-ter con **4/5 — y la que sobrevive es el borde
declarado de la fase, no un descuido**: lo que queda sin testigo es la línea que *llama* a la regla, porque la
unidad de trabajo de `ingest` no es inyectable; la regla en sí tiene sus cuatro. Y **F7 con 57/57**, de las
que **cinco sobrevivieron a la primera pasada**: una era un defecto real —el orden de la tabla dependía del
recorrido de un `Dictionary`, que depende del proceso— y cuatro eran *"falta un test"* —tres de ellas son las tres alternativas que `D-91` descartó, así que los tests dicen también por qué la regla es la mediana— — pero **cinco sobrevivieron a la primera pasada y las cinco eran "falta un
test"**, una de ellas seria: *"la competición que nunca se sincronizó no entra"* pasaba toda la batería, y
significaba que una competición recién dada de alta se quedaría esperando para siempre. Ningún rojo la habría
encontrado, porque ningún test tenía motivo para existir hasta que la mutación preguntó. F5 aportó una lectura que no se había dado: una mutación superviviente son *"falta un test"* o
*"sobra el código"* — **y a veces ninguna de las dos**, porque el programa mutado es el mismo programa
(cruzar los dos marcadores que `Match` le pasa a `Kickoff` no es observable: `Kickoff` solo pregunta *"¿hay
marcador?"*, y esa pregunta es simétrica).

**Y una lección de F7 sobre el propio instrumento de medir, que conviene tener delante antes de creerse una
mutación superviviente.** En esa fase el guion de mutación falló **tres veces, por tres motivos distintos**, y
las tres veces el fallo se leyó como un resultado: un `$0` sin escapar en el reemplazo de `perl` hizo que una
mutación **no compilara** y el detector lo contó como *"sobrevive"*; el detector comprobaba `error:` **antes**
que `✘`, y como un fallo de Postgres trae esa palabra dentro, leyó dos mutaciones **cazadas** como fallos de
compilación; y un patrón que no casaba producía un *"sobrevive"* sin haber mutado nada. Es el mismo error que
`H-07`: confundir *"no se ejecutó"* con un resultado. **Una mutación que no compila, o que no llegó a
aplicarse, no es una mutación que sobrevive** — el guion tiene que comprobar que el fichero cambió, que
compila, y mirar el `✘` antes que el `error:`.

**Y dos defectos que F6 solo encontró ejecutando el sistema contra la base de trabajo**, no con la batería:
el motivo de una pasada fallida era ilegible —`PSQLError` esconde su descripción; se arregla con
`String(reflecting:)`— y **la pasada con éxito no medía su duración**, porque el informe se construye al
empezar. Los dos en `IngestionRun`, y los dos invisibles por la misma razón de método: **los niveles 2 y 3
corren con un reloj fijo y con dobles sin restricciones**, que es lo que los hace baratos y lo que oculta esta
clase de fallo. Al añadir algo a `IngestionRun`, ejecutarlo y mirar la tabla.

**Y una lección de arnés nueva, de F6: un test de nivel 3 puede romper los de otras suites.** El primer test
del recorrido enumeraba **todos** los tenants de `public.tenants`, y las suites corren en paralelo — así que
se puso a ingerir los clubes de las demás y a escribirles filas en sus *schemas*. **Probar una regla global
con efectos globales, en una batería paralela, no es un test: es una carrera.** Se parte en dos: la regla
*"sin filtro son todos"* se afirma sobre una consulta **sin efectos**, y el recorrido de verdad se lanza sobre
una lista explícita de clubes. Al escribir un test que enumere algo compartido, mirar esto primero.

**Los dos deberes que F5 arrastraba están hechos** (Plan §4.3 y §4.4). El **volcado de temporada en curso**
existe —de hecho es de una temporada **jugada**, la 2025-26 entera: 240 partidos con marcador y con hora, así
que la rama de "partido jugado" ya la ejercita dato real—. Y el ***canario*** está escrito y verificado en
vivo: `FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests`. **No compara bytes** —el calendario cambia cada
semana por diseño—: pasa el parser por encima de la respuesta viva y exige que no falle. Al tocarlo, saber que
tiene **cuatro** señales y no dos, porque `D-84` obligó: sin red · coordenada mala · código HTTP raro ·
formato cambiado. Solo la última es para lo que existe.

Sigue pendiente de diseño: forma del *tier* dedicado (§9.2), fallo parcial y paralelismo de las migraciones por
tenant (§9.3), política de retención RGPD (§9.4) y estimación de costes cloud por *tier*.

## Equipo

El desarrollo cuenta con un único desarrollador humano, con la ayuda de Claude Code.

[Anexo FCF §C.10]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.12]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.12.5]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[D-85]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-90]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-94]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-95]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-96]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-97]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-74]: ./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[Anexo RFFM §F.7, §F.15]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.16]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.17]: ./docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
