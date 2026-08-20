# Anexo de la Federación · Ingeniería inversa de la fuente (FCF, Cataluña)

- **Estado:** vivo — se amplía cada vez que se observa una llamada nueva
- **Fecha:** 2026-08-20
- **Documento principal:** [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · **Decisiones:** [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) · **Federación hermana:** [RFFM (Madrid)](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md)

> **Qué es este anexo.** El material de **observación** sobre la fuente de datos de la FCF: llamadas, muestras
> de respuesta y las deducciones que se extraen de compararlas. Es la evidencia sobre la que se apoyan las
> decisiones de modelo, y la que necesitará quien escriba el adaptador de ingesta de Cataluña.
>
> **Qué NO es.** No es diseño: aquí no se decide nada, se **documenta lo que hay** ([D-26]). Cuando de una
> observación se sigue una decisión, la decisión vive en el [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) y el modelo
> resultante en el LLD.
>
> **Numeración: `§C.x`** (Cataluña), para no colisionar con la `§F.x` de la [RFFM](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md). Un anexo por
> federación: son dos proveedores independientes y mezclarlos haría ilegibles los dos.
>
> **Origen de la evidencia.** Ingeniería inversa de una **app iOS existente** que consume esta fuente en
> producción, y de un volcado real de HTML. Nada de esto es un contrato publicado, y aquí la salvedad pesa
> más que en Madrid: **esto no es una API, es una web** (§C.1).

**Convención de fiabilidad**, usada en todo el anexo:

| Marca | Significado |
|-------|-------------|
| **[C]** | **Comprobado** en el código de la app o en un volcado real |
| **[I]** | **Inferido** — razonable, pero no verificado |
| **[N]** | **No observable** desde esta app; hay que probarlo contra el servidor real |

---

## C.1 No hay API: es HTML y se raspa con expresiones regulares

La diferencia más importante con Madrid, y la que condiciona todo lo demás. **[C]**

| Aspecto | Valor |
|---------|-------|
| Host base | `https://www.fcf.cat` |
| *Assets* (escudos) | `https://files.fcf.cat` |
| Método | **POST** *form-urlencoded* para los dos endpoints AJAX; **GET** para las páginas |
| Autenticación | **Ninguna**: ni cookie, ni token, ni sesión |
| Codificación | **UTF-8** estricto |
| Formato | **HTML** siempre — fragmento en los AJAX, página completa en jornada y clasificación |

No hay ni un solo `JSONSerialization` en la ruta de la FCF: el parser es **100 % expresiones regulares sobre
HTML**.

**Cabeceras que la app replica del navegador** en las peticiones POST. No está comprobado cuáles son
imprescindibles —el autor las copió tal cual— pero conviene enviarlas todas hasta saberlo **[I]**:

```
User-Agent:       Mozilla/5.0 … Chrome/144.0.0.0 Safari/537.36
Accept:           */*
Content-Type:     application/x-www-form-urlencoded; charset=UTF-8
X-Requested-With: XMLHttpRequest
Origin:           https://www.fcf.cat
Referer:          https://www.fcf.cat/competicio
Accept-Language:  es-ES,es;q=0.9,ca;q=0.8
```

> **Aviso para el adaptador.** La app construye el cuerpo POST concatenando `k=v` **sin *percent-encoding***.
> Funciona porque hoy todos los valores son numéricos o *slugs* ASCII, pero es una bomba de relojería:
> **codifica igualmente**.

### Sobre qué se ancla el parseo, que es lo frágil

Ninguna de estas anclas es semántica; todas son de **maquetación**:

| Dato | Ancla | Riesgo |
|------|-------|--------|
| Bloques de partido | *split* por la **cadena literal** `table_resultats` | Cualquier otra aparición de esa cadena —un `<script>`, un comentario— genera bloques espurios |
| Local vs. visitante | **clase de alineación**: `tr` = local, `tl` = visitante | Un cambio de maquetación **invierte local y visitante en silencio** |
| Jugado vs. pendiente | **color de fondo**: `bg-darkgrey` = jugado, `bg-grey` = futuro | El estado del partido depende de una clase de estilo |
| Hora vs. fecha | que `bg-grey` sea la **última clase** del `div` | Añadir una clase detrás rompe la distinción |
| Posición en la clasificación | **el orden de las filas**, no el número | El HTML **sí** trae el número; la app lo ignora |
| GPS | `loc:([\d.]+)\+([\d.-]+)` del enlace a Google Maps | Asume **latitud siempre positiva** y `+` como separador |

---

## C.2 Catálogo de endpoints

### C.2.1 Competiciones — `POST /cargar_competiciones`

| Parámetro | Ejemplo | Qué designa |
|-----------|---------|-------------|
| `temporada` | `21` | Código de temporada — **el mismo que usa la RFFM** (§C.8) |
| `categoria` | `19308233` | **La modalidad.** Ojo al nombre: la FCF llama *categoría* a lo que la RFFM llama *tipo de juego*, y aquí «categoría» **no** es la categoría de edad |

Devuelve un fragmento HTML con una `<p class="competicion" title="CÓDIGO">NOMBRE</p>` por competición. **No
trae número de jornadas, ni de equipos, ni ninguna bandera de capacidad.**

### C.2.2 Grupos — `POST /cargar_grupos`

| Parámetro | Ejemplo | Origen |
|-----------|---------|--------|
| `tipo` | `futbol-11` | *Slug* derivado de `categoria` |
| `categoria` | `19308233` | La modalidad |
| `competicion` | `54322947` | El `title` del `<p class="competicion">` |
| `temporada` | `21` | |

Devuelve `<a class="grupo" href="URL"><p>GRUP N</p></a>`. **La `href` es la clave del sistema**, porque
contiene los cuatro *slugs* que hacen falta para todo lo demás:

```
https://www.fcf.cat/resultats/2526/futbol-11/tercera-catalana/grup-8
```

### C.2.3 Jornada — `GET {URL del grupo}[/jornada-{N}]`

Sin parámetros: **la jornada va en la ruta**. Sin sufijo devuelve la jornada «actual».

> **Una petición por jornada.** Es el mayor cambio operativo respecto a Madrid, donde **una sola** llamada
> trae el calendario entero (§F.1). Aquí hay que descubrir primero el número de jornadas —del máximo
> `/jornada-N` de los enlaces de paginación— y luego pedirlas una a una: **~34 peticiones por grupo y
> sincronización**. **[C]**

### C.2.4 Clasificación — `GET /classificacio/{temporada}/{tipo}/{competición}/{grupo}`

No se construye con parámetros: se obtiene **sustituyendo `/resultats/` por `/classificacio/`** en la URL del
grupo.

> **Solo la clasificación actual. No admite jornada.** Es la diferencia de capacidad con la RFFM, y la que
> hace falta para entender por qué el modelo necesita un *fallback* calculado (§C.5).

### C.2.5 Campo — `GET /camp/{código}`

Definido en la app pero **nunca invocado**, porque el GPS ya viene embebido en el HTML de la jornada. Su
contenido es **[N]**.

### C.2.6 Lo que no existe

- **Búsqueda de campo por nombre**: no hay endpoint. **[C]**
- **Goleadores**: ni endpoint, ni parser, ni bandera. **[N]** — habría que explorar la web directamente.
- **Acta del partido**: la URL existe en el HTML (`/acta/…`) pero la app **nunca la consulta** ni la extrae.

---

## C.3 Identificadores

| Entidad | Identificador | ¿Estable entre sincronizaciones? | ¿Entre temporadas? |
|---------|---------------|:--------------------------------:|:------------------:|
| Temporada | **Dos**: código `21` (POST) y *slug* `2526` (URL) | Sí | Sí |
| Competición | **Dos, no intercambiables**: código `54322947` y *slug* `tercera-catalana` | Sí | **El código, NO** (ver abajo) |
| Grupo | **No tiene id propio** — solo el *slug* `grup-8` dentro de la URL | Sí | Sí **[I]** |
| Equipo | **No hay id numérico** — *slug* `seva-ue-b` | Sí | *Slug* estable, pero la ruta lleva la temporada |
| Club | **No hay id** — inferido del nombre del fichero del escudo | Sí **[I]** | Sí **[I]** |
| **Partido** | **NO HAY** (ver abajo) | — | — |
| Jornada | El entero de la URL | Sí | Sí |
| Campo | Código numérico `/camp/406` | Sí | Sí **[I]** |

### El código de competición no sobrevive a la temporada

En una **misma** llamada (`temporada=21`) conviven estas dos entradas: **[C]**

```
title="54469307"  COPA CATALUNYA MASCULINA 24/25
title="54979299"  COPA CATALUNYA MASCULINA
```

El código numérico identifica una **instancia de competición-temporada**, no la competición conceptual. Para
reconciliar entre años sirve el par *(slug, temporada)*, nunca el numérico.

### No hay identificador de partido

El bloque HTML de un partido **no contiene ningún id**. Lo único que lo identifica es la URL del acta,
compuesta **solo de *slugs***: **[C]**

```
/acta/2526/futbol-11/quarta-catalana/grup-8/4cat/seva-ue-b/4cat/tona-ue-c
```

No lleva la jornada, así que **ni siquiera distingue la ida de la vuelta**. Clave natural practicable:

```
(temporada, competición, grupo, jornada, slug_local, slug_visitante)
```

> **Matiz que sí apareció.** El widget de «racha» de la clasificación **sí** lleva un id numérico de acta
> como atributo `id` de un `<span>`. Es decir: **el id existe internamente en la FCF**, pero solo aflora para
> los últimos ~5 partidos de cada equipo y la app no lo lee. No es una vía fiable de emparejamiento. **[C]**

---

## C.4 Objeto de partido — muestras

**Partido jugado.** Nótese `ACTA TANCADA` donde debería ir la fecha, el `bg-darkgrey`, y la **ausencia total
de identificador**:

```html
<td class="p-5 resultats-w-equip tr">
  <a href="…/calendari-equip/2526/futbol-11/quarta-catalana/grup-8/seva-ue-b">SEVA, U.E. B</a></td>
<td class="p-5 resultats-w-resultat tc">
  <a href="…/acta/2526/futbol-11/quarta-catalana/grup-8/4cat/seva-ue-b/4cat/tona-ue-c">
     <div class="tc fs-9 white bg-darkgrey mb-2 lh-data">ACTA TANCADA</div>
     <div class="tc fs-17 white bg-darkgrey p-r">1 - 2</div></a></td>
<td class="p-5 resultats-w-equip tl">
  <a href="…/grup-8/tona-ue-c">TONA, U.E. C</a></td>
<td class="p-5 resultats-w-text2 tr fs-9 lh-20 d-n_ml">
  <a href="https://www.fcf.cat/camp/406">CAMP DE FUTBOL MPAL. L'ALZINA<img src="…/camp.png"></a>
  <br />GOMEZ SALA, ROBERT<img src="…/xiulet.png"></td>
<td …><a href="http://maps.google.com/maps?z=12&t=m&q=loc:41.835216+2.280804">…Ruta</a></td>
```

**Partido futuro.** El mismo hueco, ahora con fecha y hora, y `bg-grey`:

```html
<td class="p-5 resultats-w-resultat tc">
  <a href="…/acta/2526/futbol-11/tercera-catalana/grup-8/3cat/avia-ue-a/3cat/navas-ce-a">
     <div class="tc fs-9 white bg-grey mb-2 lh-data">
     02-05-2026
     </div>
     <div class="tc fs-17 white bg-grey">
      16:00
     </div></td>
<td class="p-5 resultats-w-equip tl">
  <a href="…/grup-8/navas-ce-a">NAVÀS,C.E. A</a></td>
```

**Dos datos presentes en el HTML que la app descarta** y que sí nos servirían: el **escudo del club**
(`https://files.fcf.cat/escudos/clubes/escudos/00100_0000739648_uetona_200x200.png`) y el **árbitro**.

---

## C.5 Clasificación: existe, pero solo la de hoy

**La FCF sí publica clasificación**, y con **más** detalle que la RFFM: desglose casa/fuera, coeficiente de
puntos y racha de los últimos cinco partidos. Lo que **no** publica es el histórico: **no hay forma de pedir
la clasificación de una jornada pasada**. **[C]**

Fila real, con el orden de columnas verdadero:

```html
<td …><span class="ascens"></span>4<span class="fa fa-caret-up"></span></td>  <!-- posición -->
<td class="tc pr-0"><img src="…/00100_0000852254_artesfc_200x200.png"></td>   <!-- escudo -->
<td class="tl resumida"><a href="…/artes-fc-a">ARTES, F.C. A</a></td>
<td class="tc">37 (1.9)</td>       <!-- puntos (coeficiente) -->
<td class="tc">1.9474</td>         <!-- puntos por partido -->
<td class="tc resumida">19</td>    <!-- PJ -->
<td class="tc resumida">11</td>    <!-- G -->
<td class="tc resumida">4</td>     <!-- E -->
<td class="tc resumida">4</td>     <!-- P -->
<td class="tc detallada" style="display: none;">10</td>   <!-- desglose casa/fuera: 8 celdas ocultas -->
<td class="tc">37</td>             <!-- GF -->
<td class="tc">22</td>             <!-- GC -->
```

| Campo | ¿Publicado? | Observación |
|-------|:-----------:|-------------|
| `position` | **Sí** | Pero la app **no lo lee**: lo deduce del orden de fila |
| `played`, `won`, `drawn`, `lost` | Sí | Celdas `tc resumida` |
| `goals_for`, `goals_against` | Sí | Últimas dos celdas `tc` |
| `points` | Sí | Con coeficiente entre paréntesis: `37 (1.9)` |
| **id de equipo** | **No** | Solo el *slug* de la `href` |
| escudo | Sí | En el HTML; la app no lo extrae |
| `previous_position` | **No** | Hay que calcularlo comparando *snapshots* |

> **Trampa seria para el adaptador.** La app lee puntos, GF y GC **por posición** en la lista de celdas
> `<td class="tc">`. Solo funciona porque la celda del coeficiente (`1.9474`) se cuela fuera del patrón **por
> llevar un punto decimal**. Si la FCF renderizara un coeficiente entero, GF y GC saldrían desplazados y
> **mal, sin error**. **Indexa por la cabecera de la tabla, no por orden de aparición.**

**Las celdas `detallada` están en el DOM aunque no se muestren** (`display: none`) y contienen el desglose
casa/fuera completo. Es riqueza disponible que la app tira.

---

## C.6 Rarezas y trampas

| Observación | Consecuencia para el mapeo |
|-------------|----------------------------|
| **Un partido jugado PIERDE su fecha y su hora.** El HTML las sustituye por `ACTA TANCADA` + marcador **[C]** | **La más grave.** Si un partido no se ingiere **antes** de jugarse, su fecha real se pierde para siempre. El *upsert* **no puede pisar una fecha existente con vacío** — es una excepción a la política de campos volátiles ([D-18]) |
| Fechas en **`dd-MM-yyyy`** (guiones), horas `HH:mm` | No es ISO; parseo explícito. Coincide con la RFFM en formato **[C]** |
| **Sin huso horario** en ningún sitio | La app fija `Europe/Madrid` explícitamente. Vigilar los cambios de hora **[I]** |
| Jugado vs. no jugado se distingue **por clase CSS**, no por contenido | Un `0-0` es `0 - 0` con `bg-darkgrey`; un no jugado **no tiene marcador**. `NULL` ≠ `0`, obligatorio |
| **Aplazamientos: no observable.** El parser solo conoce dos estados y no hay muestra **[N]** | Sin evidencia de cómo se representa un aplazado, un no presentado, o un `3-0` administrativo |
| Nombres en catalán con acentos y apóstrofos: `NAVÀS`, `DIVISIÓ`, `L'ALZINA` | El parser **no descodifica entidades HTML** (a diferencia del de Madrid). Si la fuente emitiera `&agrave;`, pasaría literal |
| Puntuación irregular: `SEVA, U.E. B` vs `NAVÀS,C.E. A` (coma sin espacio) | No normalizar por posición de la coma |
| El *slug* **pierde los acentos**: `NAVÀS` → `navas` | Útil como clave; inútil para reconstruir el nombre |
| El escudo puede faltar: todos los `<img>` llevan `onerror` a `escutbase.png` | Tolerar la ausencia |
| GPS en formato de Google Maps: `loc:41.835216+2.280804` | El `+` es separador, no signo |
| HTML sucio: comentarios `<!-- PROVISIONAL -->` envolviendo celdas, atributos inconsistentes | Parseo tolerante obligatorio |
| **Sin control de tasa observable**, pero la app dispara ~34 peticiones concurrentes sin límite ni reintentos | Para un backend que sincronice varios grupos: **limitar concurrencia y aplicar *backoff***. Riesgo de bloqueo real |

### La letra del equipo va suelta al final, sin comillas

```
SEVA, U.E. B      NAVÀS,C.E. A      ARTES, F.C. A      ARISTOI FOOTBALL ACADEMY A
```

**La app no la separa**: guarda el literal entero y filtra por subcadena. Para nosotros hay que separarla, y
es **más ambiguo que en Madrid**: allí la letra va entre comillas simples (`'A'`) y es inequívoca (§F.5); aquí
hay que quedarse con el último *token* si es una única mayúscula, con el riesgo de falso positivo en un club
cuyo nombre acabe legítimamente en letra suelta. **[C]**

---

## C.7 Modalidades

| Código (`categoria`) | *Slug* (`tipo`) | Modalidad |
|----------------------|-----------------|-----------|
| `19308233` | `futbol-11` | Fútbol 11 |
| `19308235` | `futbol-7` | Fútbol 7 |

**Fútbol sala y fútbol playa: [N].** No hay código, ni *slug*, ni referencia alguna. En Cataluña el fútbol
sala tiene federación propia (FCFS), así que podría no vivir bajo `fcf.cat` en absoluto — **[I]**, no
verificable desde aquí.

> La app convierte código → *slug* con un ternario cuyo **`default` es `futbol-11`**: cualquier código
> desconocido cae ahí en silencio. En el adaptador, **mapa explícito y fallo ruidoso**.

---

## C.8 Diferencias estructurales con la RFFM

La comparación vive aquí, y no en el anexo de Madrid, porque es la FCF la que se aparta del patrón.

| Concepto | RFFM (Madrid) | FCF (Cataluña) |
|----------|---------------|----------------|
| **Formato** | JSON, o JSON incrustado en el HTML de una app Next.js | **HTML puro siempre.** Expresiones regulares |
| **Método** | GET con *query string* | POST *form* para AJAX, GET para páginas |
| **Cabeceras** | Ninguna especial | *User-Agent* de navegador + `X-Requested-With` + `Origin` + `Referer` |
| **Calendario completo** | **1 petición** | **N peticiones**, una por jornada (~34) |
| **Nombre de la modalidad** | `tipojuego` | `categoria` — **mismo concepto, nombre que colisiona** con «categoría de edad» |
| **Id de grupo** | Código numérico | **La URL completa** |
| **Nº de jornadas** | Explícito (`total_jornadas`) | **Hay que inferirlo** del máximo `/jornada-N` |
| **Nº de equipos** | Explícito (`total_equipos`) | No existe |
| **Clasificación por jornada** | **Sí** | **No**: solo la actual |
| **Id de equipo en clasificación** | Sí, y **coincide con el del calendario** | **No existe** |
| **Id de partido** | `codacta`, **siempre presente y único** | **No existe** |
| **Fecha de partido jugado** | Se conserva | **Se pierde** |
| **GPS del campo** | No lo da | **Embebido en el HTML** |
| **Dirección y localidad del campo** | Sí | No |
| **Árbitro** | En el acta | En el HTML de la jornada |
| **Categoría de edad** | **Campo propio** | **Embebida en el nombre**, y desdoblada por año (`S16`/`S15`) |
| **División** | Campo propio | Embebida en el nombre |
| **Letra del equipo** | Entre comillas: `… 'A'` | Suelta al final: `… B` |
| **Códigos de temporada** | `21` = 2025-26 | **Los mismos** — la única coincidencia limpia |

### La categoría por año de nacimiento no tiene equivalente en Madrid

La FCF desdobla cada categoría de edad: `CADET S16` / `CADET S15`, `INFANTIL S14` / `S13`, `ALEVÍ S12` /
`S11`, `BENJAMÍ S10` / `S9`, `PREBENJAMÍ S8` / `S7`. La RFFM **no tiene ese concepto**, y nuestro enumerado
`Team.category` (§3.3) tampoco. **[C]**

### Patrón común en los escudos

Las dos federaciones nombran el fichero del escudo igual: `00100_<10 dígitos>_<texto>`. Sugiere una
**plataforma federativa subyacente común** con dos frontales distintos, y por tanto que podría existir una API
compartida que ninguna de las dos apps explora. **[I]** — merece una comprobación.

---

## C.9 Pendiente de observar

> **Prioridad.** El diseño se está cerrando **primero contra la RFFM**. Lo de aquí queda **aparcado a
> propósito** hasta que Madrid esté terminado; se anota para no perderlo, no para resolverlo ahora.

**Dos que afectan al modelo, no solo al adaptador** — son los que habrá que decidir al abrir la FCF:

- **Qué se guarda en `Competition.federation_group_id`.** §3.5 del LLD justifica la unicidad
  `(season_id, federation_group_id)` diciendo que "el id de grupo ya es único dentro de la temporada". Eso es
  cierto en la RFFM (`grupo=24037549`), pero aquí **el grupo no tiene id**: solo el *slug* `grup-8` (§C.3),
  que **se repite en todas las competiciones**. La unicidad solo se sostiene si el adaptador guarda la
  **ruta completa** del grupo (`/resultats/2526/futbol-11/tercera-catalana/grup-8`) en vez del *slug* suelto.
  Hay que decidirlo y escribirlo; hoy no está dicho en ninguna parte.
- **La categoría por año de nacimiento** (`CADET S16` / `CADET S15`, §C.8) **no tiene contrapartida** en el
  enumerado `Team.category` (§3.3 del LLD) ni en la RFFM. Está observado como **[C]** pero no decidido:
  ¿se colapsan las dos al mismo valor perdiendo la distinción, o el enumerado crece? Es una decisión de
  modelo (`D-nn` futura), no una observación pendiente.

**Y el resto, que es observación:**

- **Goleadores.** No hay ni rastro: ni endpoint, ni parser, ni bandera de capacidad. Hay que explorar la web
  de la FCF directamente. Es lo que decide si `LeagueScorer` existe para este proveedor o queda vacío
  siempre.
- **Cómo se representa un aplazamiento**, un no presentado o un resultado administrativo. El parser solo
  conoce «jugado» y «pendiente».
- **Fútbol sala y fútbol playa**: si viven bajo `fcf.cat` o bajo la federación catalana de sala.
- **El nombre del parámetro de paginación** en la clasificación, si lo hay.
- **La página `/camp/{código}`**: qué contiene, y si trae dirección y localidad como en Madrid.
- **Estabilidad interanual de los *slugs*** de competición y grupo. Se asume, no está verificada.
- **El id numérico de acta del widget de racha**: si es el mismo espacio de identificadores que usa la FCF
  internamente y si hay forma de obtenerlo para todos los partidos, no solo para los cinco últimos.

---

*Referencias `§x.y` → [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · `§F.x` → [Anexo RFFM](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md) · `D-nn` → [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md)*

<!-- Definiciones de enlace -->
[D-01]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-02]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-03]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-04]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-05]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-06]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-07]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-08]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-09]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-10]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-11]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-12]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-13]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-14]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-15]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-16]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-17]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-18]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-19]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-20]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-21]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-22]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-23]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-24]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-25]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-26]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-27]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-28]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-29]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-30]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-31]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-32]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-33]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-34]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-35]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-36]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-37]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-38]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-39]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-40]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-41]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-42]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-43]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-44]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-45]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-46]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-47]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-48]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-49]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-50]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-51]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-52]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-53]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-54]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-55]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-56]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-57]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-58]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[Anexo RFFM]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.1]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.2]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.3]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.4]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.5]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.6]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.7]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.8]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.9]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.10]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.11]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.12]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.13]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo RFFM §F.14]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
