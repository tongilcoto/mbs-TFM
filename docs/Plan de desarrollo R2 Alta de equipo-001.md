# Plan de desarrollo R2 · Alta de equipo

> Rebanada 2 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Como la
> [rebanada 1](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md), toca la web y el servidor, y lo que se haga
> en el servidor se apunta **solo aquí**, también la mini-fase.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md); y la rebanada 1, cerrada el
> 2026-10-20 con 682 tests en el backend y, en la web, 80 pruebas de piezas y 35 escenarios. Antes de esta
> rebanada se revisó la tabla de equipos (`D-104`, el rival es de una temporada; `D-105`, la jornada de descanso):
> 682 → **697 tests** en el backend. Y se decidió cómo nace una temporada sin código de la federación (`D-106`).
>
> **Convención de remisiones**, la misma de la rebanada 1: `LLD-B §x` y `DW-nn` son el LLD de la web y su anexo;
> `LLD §x` y `D-nn`, el LLD del backend y su bitácora.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: decisiones revisadas.** El flujo (§1 y §3) se colocó con el desarrollador, y la
> decisión 1 es `D-106`, ya grabada. Las decisiones 2 a 6 se revisaron una a una con él el 2026-10-23, y las
> secciones 2, 3, 5, 6 y 7 están escritas con lo acordado. **La revisión cambió una cosa del servidor que no
> estaba prevista**: el alta de un equipo que ya existe en otra temporada lo inscribe, en vez de dar 409
> (decisión 6, y su entrada en la bitácora, `D-107`). **Se diseña como si la rebanada 11 ya estuviera hecha**
> (decidido con el desarrollador): una temporada puede estar archivada, y eso se tiene en cuenta.

---

## 1. Objetivo

**El club puede dar de alta un equipo desde la web**, inscrito en una temporada que ya existe o en una que crea
en ese momento. Es lo que hace el club en julio, cuando forma los equipos de la temporada siguiente y la
federación todavía no ha publicado nada.

El alta tiene **dos pasos**, y esta rebanada hace el primero:

1. **El formulario** da de alta el equipo en una temporada. Sin ningún dato de la federación (`D-66`).
2. **El enganche**: cuando hay calendario, una acción sobre el equipo pide la dirección del calendario de la
   federación. Es la rebanada 3.

**Por qué ahora** (plan del backoffice, §4): es la primera escritura de la web, y sin ella un club nuevo no
puede empezar: la portada vacía dice «Todavía no hay ninguna temporada» y no ofrece salida
([Plan R1, decisión 6](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md)).

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **En la portada, el botón «Dar de alta un equipo»**, junto al selector de temporada, y también en los dos mensajes de la portada vacía | Ficha, §3.1 · decisión 6 |
| **El formulario de alta** (`/equipos/nuevo`): categoría, letra, género, modalidad y temporada, con la comprobación de todos los campos a la vez antes de enviar | Ficha, §3.2 · LLD-B §5 · decisiones 2 y 3 |
| **«Crear nueva temporada»**, un botón al lado del selector del formulario que abre un diálogo: el mismo camino para la primera temporada del club y para las siguientes | Ficha, §3.3 · `D-106` · decisión 4 |
| **El mismo equipo, otra temporada**: dar de alta «Alevín A» en 2027/28 cuando ya existía en 2026/27 lo inscribe en la nueva, sin crear otro | Ficha, §3.4 · decisión 6 · `D-107` |
| **La vuelta a la portada** en la temporada del equipo, con el aviso «Guardado», y sin el formulario en el historial | Ficha, §3.4 · decisión 5 |
| **Los mensajes de los errores nuevos**, y el aviso de «cambios sin guardar» al salir del formulario | LLD-B §4.3, §5.5 · decisión 6 |
| En el servidor, **la temporada sin código** (`D-106`) y **dos operaciones nuevas**: `createSeason` y `createTeam`. Con ellas, el servidor sirve **11 de las 85** | §5 |

**Lo que no trae** (llega después): el enganche desde la web (rebanada 3); corregir o borrar un equipo
(rebanada 13); y la gestión de temporadas: corregir, archivar, recuperar o borrar una creada por error (rebanada
11). Esta rebanada **se diseña como si la 11 ya estuviera hecha**: sus mensajes cuentan con que una temporada
puede estar archivada.

---

## 3. La ficha de las pantallas

### 3.1 La portada, con el botón

- **«Dar de alta un equipo»**, con texto y no solo un «+», junto al selector de temporada (LLD-B §10.1: lo que
  hace un botón se lee). Lleva a `/equipos/nuevo`.
- **En la portada vacía** (Plan R1, decisión 6) el mismo botón, debajo del mensaje:

| Caso | Mensaje | Debajo |
|---|---|---|
| El club no tiene ninguna temporada | «Todavía no hay ninguna temporada.» | «Para empezar, da de alta el primer equipo. La temporada se crea desde el mismo formulario.» y el botón |
| La temporada elegida no tiene equipos | «No hay equipos en la temporada 2025/26.» | El botón |

### 3.2 El formulario de alta (`/equipos/nuevo`)

**Qué pide al servidor al abrir**: `listSeasons`, para el selector. Nada más: categoría, género y modalidad son
listas cerradas del catálogo, y la web ya las tiene (`schema.d.ts`).

**Los campos**, cada uno con la pieza que le corresponde (LLD-B §5.2) y con asterisco si es obligatorio:

| Campo | Pieza | Obligatorio | De dónde sale |
|---|---|---|---|
| **Categoría** | Selector, de menor a mayor edad | Sí | `TeamCategory` |
| **Letra** | Texto corto, con la ayuda «Si el club tiene varios equipos de la misma categoría: A, B…» | No | — |
| **Género** | Selector | Sí | `Gender` |
| **Modalidad** | Selector | Sí | `Modality` |
| **Temporada** | Selector, de la más reciente a la más antigua, sin las archivadas; y **al lado, el botón «Crear nueva temporada»** (§3.3) | Sí | `listSeasons` |

- **Qué temporada viene elegida** (decisión 5), **en este orden**:
  1. **El club no tiene temporadas**: el selector sale vacío, con el botón al lado. No se calcula nada más.
  2. **Viene una temporada de la portada, y sigue en la lista**: esa.
  3. **Si no** (se recargó, se escribió `/equipos/nuevo` a mano, o la de la portada ya no está): la regla de la
     portada, `chooseSeason` — la temporada en curso o, si no hay ninguna, la más reciente. **Sin error**: el
     usuario no ha escrito ninguna temporada.
- **Al pulsar *Guardar***: la web comprueba todos los campos contra `CreateTeamRequest` y marca **todos** los que
  fallan a la vez (LLD-B §5.1). Si todo está bien, envía `createTeam`, y mientras tanto el botón se bloquea
  (LLD-B §3.3).
- **Si el servidor rechaza**: el error junto a su campo si es de un campo, y si no, en un aviso arriba del
  formulario, sin borrar lo escrito (LLD-B §4.3). Los mensajes, en la decisión 6.
- **Salir con cambios sin guardar** pregunta antes (LLD-B §5.5). Es el primer formulario de la web, así que el
  aviso se estrena aquí.
- **«Cancelar»** vuelve a la portada, en la temporada de la que se vino, o a `/` si se llegó sin ninguna. Y
  quita el formulario del historial (decisión 5).

**Los cuatro estados** (LLD-B §3.1):

| Estado | Cómo se ve |
|---|---|
| **Cargando** | «Cargando temporadas…» en el sitio del selector; el resto del formulario ya se puede rellenar |
| **Error** | El mensaje del código en el sitio del selector, con *Reintentar* si el fallo puede ser pasajero (LLD-B §4.4) |
| **Vacío** | El club sin temporadas: el selector vacío, y el botón «Crear nueva temporada» al lado |
| **Con datos** | El formulario entero |

### 3.3 «Crear nueva temporada» (decisión 4)

- **El botón «Crear nueva temporada»**, al lado del selector, **no dentro de él**: una opción de la lista que
  abre un diálogo se dispara sin querer al recorrerla con las flechas, y un lector de pantalla la anuncia como una
  temporada más.
- **Abre un diálogo** encima del formulario, con un solo campo: **Temporada**.
- **Al pulsar *Crear***: la web comprueba el formato con el `pattern` del catálogo (decisión 2) y envía
  `createSeason` solo con la etiqueta, sin código de la federación (`D-106`). Si el formato falla: «El formato no
  es válido. Por ejemplo: 2024/25», con el ejemplo leído del catálogo.
- **Si va bien**, el diálogo se cierra, la temporada nueva entra en el selector y queda elegida. El formulario
  del equipo **no se ha enviado todavía**: lo que el usuario había rellenado sigue ahí.
- **Si falla**: «2026/28» (los años no siguen) sale **junto al campo**, con el motivo del servidor; «ya existe»,
  **en un aviso arriba del diálogo** (decisión 6).
- **«Cancelar»** cierra el diálogo sin crear nada, y el selector vuelve a la temporada que tenía.
- **Con el teclado** (LLD-B §10.1), lo que hace la pieza de diálogo de PrimeVue: al abrirse, el foco va al
  campo; el tabulador no sale del diálogo; *Escape* lo cierra como *Cancelar*; y al cerrarse, el foco vuelve al
  botón, o al selector si se creó la temporada.

### 3.4 Al guardar bien

- **Da igual si el equipo era nuevo o ya existía en otra temporada** (decisión 6): en los dos casos queda inscrito
  en la temporada elegida, y la web hace lo mismo.
- Sale el aviso breve **«Guardado»** (LLD-B §5.4). Lo pone el marco, no el formulario, así que sigue a la vista
  después de cambiar de pantalla.
- La web vuelve a la portada **en la temporada en la que se ha inscrito el equipo** (`/?temporada=2026-27`), no
  en la de la que se vino (decisión 5), y **quita el formulario del historial**: «Atrás» lleva a la portada de
  partida, no a un formulario vacío.
- El equipo sale en la tabla con «Sin competición» y el texto «Se engancha con la federación desde la ficha del
  equipo», como cualquier equipo de junio (Plan R1, §3.2).

---

## 4. Decisiones antes de construir

### Decisión 1 · La temporada sin código de la federación (`D-106`)

**Decidido y grabado** (`a9eea44`, 2026-10-23). En resumen:

- `seasons.federation_season_id` pasa a admitir vacío, y el código sigue sin poder repetirse.
- `createSeason` se programa en esta rebanada, y recibe la etiqueta y, si la hay, el código.
- El enganche y su `/preview` buscan la temporada **primero por el código y después por la etiqueta**; si la
  encuentran sin código, el enganche se lo pone.
- Si la temporada de esa etiqueta ya tiene **otro** código: **409 `SEASON_ALREADY_LINKED`**.
- La etiqueta de la federación la traduce **su conector**, nunca el catálogo. La guarda de fechas de `D-91` sigue
  siendo la red.

Lo que eso pide al servidor está en la §5. El texto entero, en [D-106](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md).

### Decisión 2 · Las reglas del formulario salen del catálogo; el servidor tiene la última palabra

**Decidido.** Lo que dicen el LLD-B §5.1 y `DW-07`: Ajv comprueba lo rellenado contra la descripción del catálogo
(`CreateTeamRequest` en el formulario, `CreateSeasonRequest` en el diálogo) y marca todos los fallos a la vez. La
web escribe a mano solo el texto de cada **tipo** de regla, en una tabla de unas seis entradas.

- **La etiqueta de la temporada** se comprueba con el `pattern` del catálogo (`^\d{4}/\d{2}$`), que es la misma
  regla con la que el servidor la rechaza en su puerta.
- **El mensaje de un `pattern` lleva el ejemplo del catálogo**: «El formato no es válido. Por ejemplo: 2024/25».
  `SeasonLabel` ya trae `examples: ['2024/25']`, y la web lo lee de ahí igual que la regla, así que no hay
  ningún texto por campo escrito a mano. Se descartó dejar el mensaje genérico con una ayuda fija debajo del
  campo: sería una copia a mano que puede quedarse atrás.
- **Que el segundo año sea el siguiente** («2026/28» no vale) solo lo sabe el servidor, en el Dominio: llega como
  `INVALID_VALUE` con `label: debe ser AAAA/AB con AB el año siguiente, como "2025/26"` en el `detail`, y la web
  enseña el motivo junto al campo (LLD-B §4.5 *a*).
- **Que ya esté** el equipo o la temporada, también solo el servidor (decisión 6).

### Decisión 3 · Cómo llega el catálogo a la web

**El problema.** `DW-07` dice que Ajv lee el catálogo, pero no **cómo llega** a la web: se ejecuta en el
navegador y no puede leer `openapi.yaml` del disco, y el servidor no lo publica.

**Decidido: igual que las descripciones de los datos.** `npm run gen:api`, que ya genera `schema.d.ts`, genera
también `src/api/schemas.json`, con **solo** los esquemas (`components/schemas`, con esa misma estructura para
que sus `$ref` sigan valiendo), y sin guardarlo en git. Ajv lo lee de ahí. Los tipos y las reglas salen del
mismo catálogo, a la vez y con el mismo comando: la web nunca comprueba con unas reglas distintas de las de los
tipos con los que compiló.

| Opción | Veredicto |
|---|---|
| **(a) `gen:api` saca también los esquemas, en JSON** | **Elegida** |
| (b) La web importa el `.yaml` del backend al compilar, con un complemento de Vite | Una pieza más, que también tendrían que cargar las pruebas, y el catálogo entero dentro de la web |
| (c) El servidor publica el catálogo y la web lo pide al abrir | La web podría comprobar con un catálogo distinto del de sus tipos |

**No guardarlo en git no impide desplegarlo.** Lo que se despliega no es `src/`, es `dist/`, el resultado de
`npm run build`, que ejecuta antes `gen:api`: el fichero nace al compilar y viaja dentro de `dist/`. Es lo que
ya pasa con `schema.d.ts`, y con los tipos del servidor, que el *plugin* de `APIContract` genera en cada
`swift build`. **La web solo hay que recompilarla cuando cambia el catálogo**, no con cada cambio del servidor.

**Dos reglas para el despliegue**, que no son de esta rebanada y se apuntan como pendiente de la 16 en el plan
del backoffice (R2.4):

- La web y el servidor se compilan **desde el mismo commit**, y la web **con el repositorio entero a la vista**:
  `gen:api` lee `../backend/...`, y una compilación que solo vea `backoffice/` falla.
- Si cambió el catálogo, **se despliegan los dos, primero el servidor**. Mientras conviven la web vieja y el
  servidor nuevo, solo valen los cambios que no rompen.

**Lo que entra en el proyecto**, en el commit de su paso y en el README de la web:

- **`ajv` 8, con `Ajv2020`**: el catálogo es OpenAPI 3.1, que es JSON Schema 2020-12. El Ajv que ya hay en
  `node_modules` es el 6, que trae eslint y no lo entiende.
- **`ajv-formats`**, para `format: uuid` (el `seasonId`).
- **`yaml`**, para leer el catálogo en `gen:api`. Ya está en `node_modules` porque lo traen Vite y Cucumber; se
  declara como dependencia propia para no apoyarse en una ajena.

**Ajv en modo estricto, sin apagarlo.** Se queja de las palabras del catálogo que son de OpenAPI y no de JSON
Schema (`discriminator`, por ejemplo): se le declaran. Así una regla mal escrita en el catálogo sigue saltando,
en vez de ignorarse sin avisar.

### Decisión 4 · «Crear nueva temporada» es un botón al lado del selector, y su diálogo guarda por su cuenta

**Decidido.** El botón abre el diálogo de la §3.3, que **crea la temporada al pulsar *Crear***, antes de guardar el
equipo. Dos peticiones, cada una con su botón y sus errores.

| Opción | Qué pasa si algo falla | Veredicto |
|---|---|---|
| **(a) Diálogo que crea la temporada al momento** | Cada error sale en su sitio: el de la etiqueta en el diálogo, el del equipo en el formulario | **Elegida** |
| (b) Un campo de texto en el mismo formulario, y al guardar se envían las dos | Si la temporada se crea y el equipo falla, queda una temporada creada y un formulario con error; al reintentar, «esa temporada ya existe» | Descartada |

**Un botón, no una opción del selector.** El selector es para elegir un valor, y esto es una acción: dentro de la
lista se dispara sin querer al recorrerla con las flechas, y un lector de pantalla la anuncia como una temporada
más. Al lado se ve siempre, se lee como lo que es, y con el club vacío está ahí mismo.

**Lo que se asume a cambio**: si el usuario crea la temporada y luego cancela el alta, la temporada se queda. Es
lo que `D-106` ya acepta, y sale en el selector de la portada con «No hay equipos en la temporada 2027/28.»; se
archiva o se borra desde Temporadas (rebanada 11).

### Decisión 5 · Qué temporada viene elegida, y a cuál se vuelve

**Decidido.**

| Momento | Temporada | Cómo |
|---|---|---|
| **Al abrir el formulario** | La que enseñaba la portada | En el **estado de la navegación** de Vue Router, no en la dirección: `/equipos/nuevo` es siempre el mismo camino |
| **Al guardar bien** | La del **equipo**, aunque no sea la de partida | `/?temporada=2027-28`, con «Guardado» |
| **Al cancelar** | La de partida | `/?temporada=2026-27`, o `/` si se llegó sin ninguna |

- **El estado de la navegación** viaja con esa entrada del historial: «Atrás» y «Adelante» lo conservan; al
  recargar o al escribir `/equipos/nuevo` a mano no hay.
- **El orden para elegir la del selector** es el de la §3.2: **primero, si el club no tiene temporadas**; después,
  la que viene de la portada si sigue en la lista; y si no, `chooseSeason`, sin error. Es el mismo orden que ya
  sigue `chooseSeason` (`seasons.ts:27`: la lista vacía se mira antes de calcular nada).
- **La vuelta es a la temporada del equipo** porque es la que el usuario acaba de elegir, y donde quiere verlo. Si
  es la que creó en el diálogo, la portada la tiene en su selector: vuelve a pedir la lista al entrar (LLD-B
  §2.4).

**«Atrás» después de guardar o cancelar: el formulario sale del historial.**

| Opción | Después de guardar, «Atrás» lleva a… | Veredicto |
|---|---|---|
| **(a) Guardar y cancelar reemplazan la entrada del formulario** | La portada de partida | **Elegida** |
| (b) El formulario se queda en el historial | Un formulario vacío, que invita a pensar que no se guardó y a darlo de alta otra vez | Descartada |

### Decisión 6 · El mismo equipo en otra temporada, y los errores nuevos

**Lo que salió en la revisión.** El catálogo decía que `createTeam` da 409 si ya hay un equipo del club con esa
categoría, letra, género y modalidad, **sin mirar la temporada**. Pero el equipo propio no lleva temporada
(`D-28`, `D-68`, `D-104`): «Alevín A» es el mismo equipo año tras año, y lo que cambia es su inscripción. Con
aquel 409, dar de alta «Alevín A» en 2027/28 cuando existía en 2026/27 daría «ya existe», justo cuando el usuario
hace lo que esta rebanada quiere.

**Decidido: `createTeam` reutiliza el equipo** (`D-107`, que enmienda la consecuencia 2 de `D-68`).

| Caso | Qué hace `createTeam` |
|---|---|
| No hay ningún equipo igual | Lo crea, inscrito en la temporada: **201** |
| Hay uno igual, **no inscrito** en esa temporada | No crea otro: le añade la inscripción y lo devuelve: **200** |
| Hay uno igual, **ya inscrito** en esa temporada | **409 `TEAM_ALREADY_REGISTERED`** |

El 200 distingue los dos primeros para quien lo necesite; **a la web le da igual**, porque en los dos vuelve a la
portada con «Guardado». Se descartó un 409 con un código propio y un botón «Inscribirlo en 2027/28» en la web: un
paso de más, un aviso que confunde («¿ya existe? ¡si lo estoy creando!») y adelantar `registerTeamInSeason`.

**La lista cerrada de códigos no tiene ninguno para «ya está»**: hasta ahora el servidor no daba de alta nada que
el usuario escribiera. Sin código propio, un duplicado volvería como el `23505` de Postgres dentro de un 500, como
pasó con `FEDERATION_TEAM_ID_TAKEN` en F10. **Tres códigos nuevos**, 32 → **35**, específicos como los que ya
hay:

| Código | Cuándo | Qué dice la web | Dónde |
|---|---|---|---|
| `TEAM_ALREADY_REGISTERED` (409) | `createTeam`: el equipo ya está inscrito en esa temporada | «Ese equipo ya está dado de alta en esta temporada.» | Aviso arriba del formulario |
| `SEASON_ALREADY_EXISTS` (409) | `createSeason`: ya hay una temporada con esa etiqueta, o con ese código (desde la web no se manda) | «Ya existe una temporada con esa etiqueta. Si no la ves en el selector, está archivada: se recupera desde Temporadas.» | Aviso arriba del diálogo |
| `SEASON_ALREADY_LINKED` (409) | El enganche y su `/preview` (`D-106`, punto 4) | «Esa temporada ya está enganchada con otro código de la federación. Revisa que el calendario sea de la temporada correcta.» | Se enseña en la rebanada 3; el texto se escribe ya, porque `errors.ts` exige uno por código |

- **`SEASON_ALREADY_EXISTS` va arriba del diálogo, no junto al campo**: solo va junto al campo el error en el que
  el servidor dice cuál es (`campo: motivo`, LLD-B §4.5 *a*), y eso es `INVALID_VALUE`, no un 409. Y los
  mensajes de `errors.ts` son textos fijos por código: por eso dice «esa etiqueta» y no «la 2026/27».
- **Cuándo pasa de verdad**: si la temporada está a la vista ya sale en el selector, así que queda para dos casos.
  Otra persona la creó a la vez, o **está archivada**: `listSeasons` no enseña las archivadas, pero su etiqueta
  sigue ocupada. Se cuenta con ese segundo caso porque la rebanada se diseña como si la 11 estuviera hecha.

**Y los que ya existen y estas pantallas pueden recibir:**

| Código | Cuándo | Qué dice | Dónde |
|---|---|---|---|
| `INVALID_VALUE` (422) | «2026/28» | El motivo del servidor | Junto al campo Temporada (decisión 2) |
| `SEASON_NOT_FOUND` (404) | La temporada elegida se borró entre abrir el formulario y guardar | «No se ha encontrado la temporada», como hoy | Aviso arriba del formulario |
| Los de conexión | Servidor o base caídos | Los de siempre, con *Reintentar* (LLD-B §4.4) | Aviso arriba |

**El servidor comprueba antes de escribir**, como en F10: busca si ya está y, si está, devuelve su 409. **Lo que
se acepta**: si dos personas guardan lo mismo a la vez y las dos pasan la comprobación, la base rechaza la
segunda por su restricción de únicos y ese caso vuelve como 500. Es el límite de dos personas editando a la vez
que ya acepta el LLD-B §5.6.

---

## 5. Lo que le falta al servidor

Todo con el método del backend: prueba → esqueleto que devuelve mal a propósito → rojo de aserción →
implementación → mutación con `Tools/Mutate`. Y `REQUIRE_DB=1 swift test`, nunca `swift test` a secas. Las
migraciones, siempre nuevas, nunca editando una que ya existe (`D-90`).

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **El catálogo**: `CreateSeasonRequest.federationSeasonId` opcional; `SeasonResponse.federationSeasonId` puede ser `null`; las descripciones de `createSeason`, de su 409 y de `PreviewSeason.exists` (que también vale `true` cuando la temporada se encuentra por etiqueta); el 409 del enganche y de su `/preview`; `createTeam` con su 200 (el equipo ya existía y se inscribe), su 409 rehecho («ya inscrito en esa temporada») y su descripción (`D-107`); y los tres códigos nuevos | `openapi.yaml` | **Sí**: cambia el catálogo | 1, 6 |
| **La temporada sin código**: una migración nueva que quita el «obligatorio» de `federation_season_id` (el `UNIQUE` se queda); `Season.federationSeasonID` pasa a opcional en el Dominio; y la ingesta, si encuentra una competición cuya temporada no tiene código, falla esa pasada con un error claro en vez de llamar a la federación sin él (`D-106`, punto 7) | Dominio, Persistencia, Aplicación | Va con el catálogo: la respuesta cambia de forma | 1 |
| **`createSeason`**: etiqueta y, si la hay, código; fechas derivadas de la etiqueta; 409 `SEASON_ALREADY_EXISTS` si la etiqueta o el código ya existen, **comprobado antes de escribir**, no esperando al `23505` | Las cuatro | No, con el catálogo ya cambiado | 1, 6 |
| **El enganche y su `/preview` buscan la temporada en dos pasos**: por código y, si no, por etiqueta. El repositorio de temporadas gana la lectura por etiqueta. El enganche pone el código a la temporada que no lo tiene; el `/preview` no escribe. 409 `SEASON_ALREADY_LINKED` si la de esa etiqueta tiene otro | Aplicación, Persistencia, HTTP | No | 1 |
| **`createTeam`** (`D-107`): si no hay un equipo propio igual, lo crea sin código e inscrito en la temporada (201); si lo hay y no está inscrito en ella, le añade la inscripción (200); si ya lo está, 409 `TEAM_ALREADY_REGISTERED`. 404 si la temporada no existe. Todo comprobado antes de escribir | Las cuatro | No | 6 |

**Lo que ya está y se reutiliza**: el repositorio de temporadas (`SeasonRepository`), que ya guarda; el de
equipos y el de inscripciones, que ya guardan desde el enganche; y la regla de la etiqueta (`SeasonLabel`, con
las fechas del 1 de julio al 30 de junio). **`createTeam` y `createSeason` están en el catálogo y sin
programar**: se activan añadiéndolos al filtro de `openapi-generator-config.yaml`.

**Los permisos**: el catálogo dice que `createTeam` requiere rol elevado (§7.3). Como el resto de operaciones
hasta la rebanada 16, no se comprueba todavía: no hay inicio de sesión.

**Al pasar el censo** con las dos operaciones activadas, los campos y los códigos nuevos sin nombrar en ningún
test se escriben o se apuntan en `known-gaps.json` con su motivo.

**Al terminar**, el servidor sirve **11 de las 85** operaciones.

---

## 6. Los escenarios

**Lista provisional.** Los `.feature` se escriben al final (R2.16), con la *skill* de escenarios del
desarrollador, y **los que valen son ellos**. Al final de cada escenario, axe en los dos modos.

**El botón** (§3.1)

- La portada con equipos tiene el botón, y lleva al formulario.
- El club sin temporadas: el mensaje, su explicación y el botón.
- La temporada sin equipos: el mensaje y el botón.

**El alta** (§3.2, §3.4)

- Dar de alta un equipo en una temporada que ya existe: vuelve a la portada en esa temporada, con «Guardado»,
  y el equipo sale con «Sin competición».
- El formulario abre con la temporada que enseñaba la portada.
- Dar de alta un equipo en una temporada que no es la de partida: la portada vuelve en la del equipo.
- Enviar sin categoría ni temporada: los dos campos marcados a la vez, y el foco en la lista de errores (LLD-B
  §10.7).
- **El mismo equipo en otra temporada**: «Alevín A» existe en 2026/27 y se da de alta en 2027/28; vuelve a la
  portada en 2027/28 con «Guardado», y en 2026/27 sigue estando.
- Un equipo que ya está en esa temporada: el aviso arriba del formulario, y lo escrito sigue ahí.
- Dar de alta un equipo solo con el teclado (LLD-B §10.7).
- Después de guardar, «Atrás» lleva a la portada de partida, no al formulario.
- Recargar el formulario: el selector pasa a la temporada en curso.
- Salir con cambios sin guardar pregunta antes; «Cancelar» sin cambios vuelve sin preguntar.

**La temporada nueva** (§3.3)

- Club vacío: crear la primera temporada desde el diálogo, dar de alta el equipo, y la portada ya tiene selector.
- Club con temporadas: crear la siguiente, que queda elegida en el selector.
- Etiqueta con mal formato («2026-27»): el error del catálogo junto al campo, sin llegar al servidor.
- Etiqueta con años que no siguen («2026/28»): el error del servidor junto al campo.
- Una etiqueta que ya existe, archivada: su mensaje arriba del diálogo.
- Cancelar el diálogo, o *Escape*, deja el selector como estaba, y el foco vuelve al botón.

**El enganche de una temporada sin código** (decisión 1). En la rebanada 3 tendrá su pantalla; aquí se prueba en
el servidor, con los tests de la §5. Los escenarios de la web llegan con la pantalla del enganche.

---

## 7. Los pasos

Cada paso dice qué se hace, cómo se comprueba y qué se graba. **Al acabar cada uno se para** y se espera el visto
bueno del desarrollador antes del siguiente, y su renglón va en la §8. Cada paso deja el árbol en verde por sí
solo, y lo que no venga en el plan va en su propio commit.

### A · Los documentos de las decisiones

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.1** | `D-106` en la bitácora, con sus notas «Enmendado por» en `D-67` y `D-68` | El desarrollador lo revisa | Un commit |
| **R2.2** | Este plan, y las decisiones 2 a 6 revisadas una a una | El desarrollador lo revisa | Un commit, y otro por cada corrección |
| **R2.3** | `D-107` en la bitácora (decisión 6), con su nota «Enmendado por» en `D-68` | El desarrollador lo revisa | Un commit |
| **R2.4** | El LLD del backend (§3.2, §3.5 y §3.7: el código de la temporada puede faltar; §5.1: `createSeason`, el alta que reutiliza el equipo y la búsqueda por etiqueta del enganche). El LLD-B: §6.1 con `/equipos/nuevo` confirmado, y `DW-07` con la decisión 3. Y el plan del backoffice: `createSeason` se adelanta de la rebanada 11 a la 2, con lo «pendiente de confirmar» resuelto, y las dos reglas del despliegue (decisión 3) como pendiente de la 16 | El desarrollador lo revisa | Un commit para el backend y otro para la web (LLD-B §E.1) |

### B · El catálogo (la mini-fase)

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.5** | `openapi.yaml`: lo de la primera fila de la §5. Y en el mismo paso, los tres mensajes nuevos de `errors.ts`, porque sin ellos la web no compila | `npx @redocly/cli lint`, `swift build`, `REQUIRE_DB=1 swift test` sin cambios en el recuento, los tipos de la web regenerados y `npm run build` en verde. El censo, con los tres códigos que todavía nadie emite | Un commit |

### C · El servidor

Con el método del backend (§5).

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.6** | **La temporada sin código**: la migración, el Dominio, la Persistencia, la respuesta de `listSeasons` con `null`, y el error claro de la ingesta | Tests de los niveles que toque, el test de migraciones con la nueva, mutación con su catálogo; y la migración pasada a la base de trabajo **por el desarrollador** | Un commit |
| **R2.7** | `createSeason` | Tests, mutación y `curl` contra la base de trabajo, con un servidor aparte en el 8799 | Un commit |
| **R2.8** | **El enganche busca la temporada por etiqueta**, en el enganche y en su `/preview`, con `SEASON_ALREADY_LINKED` | Tests de los dos caminos y de los tres casos (por código, por etiqueta sin código, por etiqueta con otro código), mutación; y un enganche de verdad contra la RFFM sobre una temporada creada con `curl` | Un commit |
| **R2.9** | `createTeam` | Tests, mutación y `curl` | Un commit |
| **R2.10** | Cierre del servidor: el recuento leído del XML, el censo con las dos operaciones, los catálogos de mutación de la rebanada pasados otra vez sobre el código final, y el README del backend | `REQUIRE_DB=1 swift test --xunit-output`, el censo con salida `0` | Un commit |

### D · La web

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.11** | **Las reglas del catálogo en la web**: `gen:api` saca los esquemas (decisión 3), Ajv los lee, y la tabla de mensajes por tipo de regla. Y la lectura del `detail` con formato `<campo>: <motivo>` (LLD-B §4.5 *a*) | Vitest: cada tipo de regla con su mensaje, `CreateTeamRequest` vacío nombra sus campos obligatorios, y un `detail` sin formato va al aviso de arriba | Un commit |
| **R2.12** | **El formulario** (`/equipos/nuevo`): los campos, el selector de temporada, sus cuatro estados, los errores en su sitio y el aviso de cambios sin guardar | Vitest, y la web abierta contra el servidor del desarrollador | Un commit |
| **R2.13** | **«Crear nueva temporada»**: el diálogo, su comprobación, sus errores y la temporada nueva elegida en el selector | Vitest, y la web abierta | Un commit |
| **R2.14** | **La portada**: el botón, el botón en los dos vacíos, y la vuelta a la temporada del equipo creado con «Guardado» | Vitest, y la web abierta con el club del desarrollador | Un commit |

### E · Los escenarios y el cierre

| Paso | Qué | Cómo se comprueba | Se graba |
|---|---|---|---|
| **R2.15** | Los datos de los escenarios: el club vacío y el club con temporadas, por la aplicación (LLD-B §11.3) | Un escenario que los use | Un commit |
| **R2.16** | Los `.feature` de la §6, con la *skill* de escenarios del desarrollador | `npm run e2e` en verde, con axe en los dos modos; y la revisión a mano del LLD-B §10.7 *b* | Un commit |
| **R2.17** | Cierre: los cinco pasos de `AGENTS.md` («Al cerrar una fase»), el README de la web y lo aprendido | Las cifras buscadas por su número viejo en todo el árbol | Un commit |

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| **R2.1** | ✅ 2026-10-23 (`a9eea44`) | `D-106` en la bitácora, con su fila en el índice, su enlace y las notas «Enmendado por [D-106]» en el paso 1 de la cascada de `D-67` y en la consecuencia 2 de `D-68`. Revisado por el desarrollador |
| **R2.2** | ✅ 2026-10-23 | El plan escrito (`9ce3c33`) y sus decisiones 2 a 6 revisadas una a una con el desarrollador. Lo que cambió en la revisión: el ejemplo del catálogo en el mensaje del formato (2); cómo llega el catálogo a la web y qué supone para el despliegue (3); el botón al lado del selector, no dentro (4); el orden para elegir la temporada, con el vacío primero, y el formulario fuera del historial (5); y **el alta de un equipo que ya existe en otra temporada lo inscribe** (6), que pide `D-107` y un paso nuevo, R2.3: los pasos pasan de 16 a 17. Se diseña como si la rebanada 11 estuviera hecha |
| **R2.3** | ✅ 2026-10-23 (`8ecdac4`) | `D-107` en la bitácora, con su fila en el índice, su enlace y la nota «Enmendado por [D-107]» en la consecuencia 2 de `D-68`. Deja escrita una tercera opción descartada que no salió en la revisión: meter la temporada en la clave del equipo propio. Revisado por el desarrollador |
| **R2.4** | ✅ 2026-10-23 | Dos commits, como manda el LLD-B §E.1. **Backend** (`docs(D-106, D-107)`): el LLD con el código de temporada anulable (§3.2, §3.5, §3.7), `POST /v1/seasons` con el código opcional, su 422 y `SEASON_ALREADY_EXISTS`; `POST /v1/teams` con su 200 y `TEAM_ALREADY_REGISTERED`; y el enganche y su `/preview` con `SEASON_ALREADY_LINKED` y la búsqueda en dos pasos (§5.1). **Web**: `DW-07` con cómo llega el catálogo a la web, el LLD-B §5.1 y §6.1, el plan del backoffice (`createSeason` adelantada a la 2, lo pendiente resuelto, las reglas del despliegue como pendiente de la 16 y la rebanada 2 en curso) y `AGENTS.md`. **Además de lo previsto**, en su propio commit: el mapa del plan del backoffice, que la R1 dejó en ámbar al cerrar. Revisado por el desarrollador |
| **R2.5** | | |
| **R2.6** | | |
| **R2.7** | | |
| **R2.8** | | |
| **R2.9** | | |
| **R2.10** | | |
| **R2.11** | | |
| **R2.12** | | |
| **R2.13** | | |
| **R2.14** | | |
| **R2.15** | | |
| **R2.16** | | |
| **R2.17** | | |

## 9. Lo aprendido

Se escribe al cerrar la rebanada (R2.17).
