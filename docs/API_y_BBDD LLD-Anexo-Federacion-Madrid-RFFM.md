# Anexo de la Federación · Ingeniería inversa de la API (RFFM, Madrid)

- **Estado:** vivo — se amplía cada vez que se observa una llamada nueva
- **Fecha:** 2026-08-11
- **Documento principal:** [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · **Decisiones:** [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md)

> **Qué es este anexo.** El material de **observación** sobre la API de la Federación: llamadas, muestras de
> respuesta, y las deducciones que se extraen de compararlas. Es la fuente sobre la que se apoyan las
> decisiones de modelo (§3.2, §3.5, §3.7 del LLD) y la que necesitará quien escriba el adaptador de ingesta.
>
> **Qué NO es.** No es diseño: aquí no se decide nada, se **documenta lo que hay**. Cuando de una observación
> se sigue una decisión, la decisión vive en el [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) y el modelo
> resultante en el LLD; aquí queda la evidencia que la sostiene.
>
> **Alcance: solo RFFM.** La **FCF (Cataluña)** tiene su [anexo propio](./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md) — un anexo
> por federación, porque son dos proveedores independientes y mezclarlos haría ilegibles los dos. Las
> **diferencias de capacidad** entre ambos se comparan allí, que es donde tienen consecuencia ([D-17]).
>
> **Salvedad general.** Nada de esto es un contrato publicado. Es **ingeniería inversa** de la app iOS
> existente y de la web pública. Todo lo que sigue puede cambiar sin aviso, y por eso el modelo trata estos
> identificadores como **datos de integración**, nunca como claves de unión (§3.7 del LLD).

**Convención de fiabilidad**, usada de §F.7 en adelante:

| Marca | Significado |
|-------|-------------|
| **[C]** | **Comprobado** en el código de la app o en un volcado real |
| **[I]** | **Inferido** — razonable, pero no verificado |
| **[N]** | **No observable** desde esta app; hay que probarlo contra el servidor real |

> **Nota de numeración.** §F.7 en adelante se **añadieron después** de que el LLD y el *spec* ya
> referenciasen §F.1–§F.6. Se han anexado en vez de intercalarse para no romper esas referencias, así que
> §F.6 (*pendiente de observar*) queda **en medio** y no al final. Es deliberado.

---

## F.1 Anatomía de la llamada al calendario

La consulta del calendario de un grupo —el punto de entrada de toda la ingesta— es exactamente esta:

```
https://www.rffm.es/competicion/calendario?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549
```

Cuatro parámetros, **jerárquicos y descompuestos** (no un identificador opaco único):

| Parámetro | Qué designa | Observaciones |
|-----------|-------------|---------------|
| `temporada=21` | la temporada | **Secuencial**, sin relación con la etiqueta "2024/25". Propio de cada federación. **Cambia cada temporada** |
| `tipojuego=1` | la modalidad | Valores conocidos: fútbol-11, fútbol-7, fútbol-5, fútbol-sala, fútbol-playa. *(Correspondencia código↔modalidad pendiente de confirmar para los cuatro últimos)* |
| `competicion=24037548` | **categoría de edad + división** | Los dos juntos, en un solo id |
| `grupo=24037549` | **solo** el grupo | Nótese que va inmediatamente después del anterior en la numeración |

**Los identificadores de la web y los de la API son los mismos.** Verificado sobre una aplicación existente
que ya opera contra esta API. Es lo que hace viable el flujo de alta del LLD (§5.1): lo que el administrador
copia de la barra de direcciones del navegador es literalmente lo que la ingesta necesita para llamar.

**No existe una API de descubrimiento.** La navegación temporada → categoría+división → grupo → calendario
es la **web**, pensada para un navegador y un ratón; no hay endpoints que la recorran. De ahí que las
coordenadas sean configuración tecleada y no un dato ingerido ([D-17]).

---

## F.2 Objeto de partido — muestras

Los equipos **no son parámetro** de ninguna llamada (no van en *path* ni en *query*), pero **sí vienen
identificados en las respuestas**. Cuatro muestras reales, elegidas para poder cruzarlas:

**Muestra 1** — Celtic Castilla, categoría A, temporada 26/27, partido **no jugado**:

```json
{
  "codacta": "5594142",
  "codigo_equipo_local": "2032",
  "equipo_local": "C.D. FUTBOL TRES CANTOS 'A'",
  "escudo_equipo_local": "/pnfg/pimg/Clubes/00100_0012158828_Escudo_Tres_Cantos_CDF.png",
  "goles_casa": "",
  "codigo_equipo_visitante": "821",
  "equipo_visitante": "CELTIC CASTILLA C.F. 'A'",
  "escudo_equipo_visitante": "/pnfg/pimg/Clubes/00100_0010940034_ESC_CELTIC_CASTILLA.png",
  "goles_visitante": "",
  "codigo_campo": "1114",
  "campo": "TRES CANTOS - JAIME MATA - FORESTA 1 (HA)(HA)",
  "fecha": "26-09-2026",
  "hora": ""
}
```

**Muestra 2** — el **mismo club** en **otra categoría**. Es la que resuelve la granularidad del identificador:

```json
{
  "codacta": "5589418",
  "codigo_equipo_local": "3349086",
  "equipo_local": "CELTIC CASTILLA C.F. 'A'",
  "escudo_equipo_local": "/pnfg/pimg/Clubes/00100_0010940034_ESC_CELTIC_CASTILLA.png",
  "codigo_equipo_visitante": "291",
  "equipo_visitante": "C.D. EL ESCORIAL",
  "escudo_equipo_visitante": "/pnfg/pimg/Clubes/00100_0011702833_escudo_CD_Escorial.png",
  "codigo_campo": "103",
  "campo": "CANAL ISABEL II (HA)(HA)",
  "fecha": "06-06-2027"
}
```

**Muestra 3** — el equipo de la muestra 2, misma categoría, **temporada anterior**, partido **ya jugado**:

```json
{
  "codacta": "5348330",
  "codigo_equipo_local": "334286",
  "equipo_local": "C.F. POZUELO DE ALARCON 'B'",
  "escudo_equipo_local": "/pnfg/pimg/Clubes/00100_0010960678_escudo_Rffm_-_CFPOZUELO.jpg",
  "goles_casa": "3",
  "codigo_equipo_visitante": "3349086",
  "escudo_equipo_visitante": "/pnfg/pimg/Clubes/00100_0010940034_ESC_CELTIC_CASTILLA.png",
  "equipo_visitante": "CELTIC CASTILLA C.F. 'A'",
  "goles_visitante": "0",
  "fecha": "14-09-2025",
  "hora": "12:00"
}
```

**Muestra 4** — el **otro** equipo del mismo club (código `821`), temporada anterior y **en otra división**:

```json
{
  "codacta": "5375152",
  "codigo_equipo_local": "821",
  "escudo_equipo_local": "/pnfg/pimg/Clubes/00100_0010940034_ESC_CELTIC_CASTILLA.png",
  "equipo_local": "CELTIC CASTILLA C.F. 'A'",
  "goles_casa": "3",
  "codigo_equipo_visitante": "2032",
  "equipo_visitante": "C.D. FUTBOL TRES CANTOS 'A'",
  "goles_visitante": "2",
  "fecha": "28-03-2026",
  "hora": "12:00"
}
```

---

## F.3 Qué identifica `codigo_equipo`

**Comparando las muestras 1 y 2** (mismo club, distinta categoría):

| Campo | Muestra 1 | Muestra 2 | Conclusión |
|-------|-----------|-----------|------------|
| `equipo_*` | `CELTIC CASTILLA C.F. 'A'` | `CELTIC CASTILLA C.F. 'A'` | **Idéntico** — el nombre **no lleva la categoría** |
| `escudo_*` | `…00100_`**`0010940034`**`_ESC_…` | `…00100_`**`0010940034`**`_ESC_…` | **Idéntico** — identifica al **club** |
| `codigo_equipo_*` | **`821`** | **`3349086`** | **Distinto** — identifica al **equipo** |

**Cruzando las cuatro muestras** para Celtic Castilla C.F. 'A' (mismo nombre y mismo escudo en todas):

| Muestra | Fecha | Temporada | `codigo_equipo` | Contexto |
|---------|-------|-----------|-----------------|----------|
| 1 | 26-09-2026 | 26/27 | **821** | categoría A |
| 4 | 28-03-2026 | 25/26 | **821** | categoría A, **otra división** |
| 2 | 06-06-2027 | 26/27 | **3349086** | categoría B |
| 3 | 14-09-2025 | 25/26 | **3349086** | categoría B |

Tres conclusiones, y las tres tienen consecuencia directa en el modelo:

1. **`codigo_equipo` identifica al EQUIPO, no al club.** Dos códigos distintos = dos equipos distintos del
   mismo club, pese a compartir nombre y escudo. → clave externa de `Team` ([D-06]).
2. **Es estable entre temporadas.** Cada código se repite en las dos campañas observadas. → `Team` es
   independiente de la temporada y el código lo acompaña toda su vida. Esta observación dejó a la antigua
   tabla pivote `Participation` sin la única columna que la habría justificado, y acabó motivando su
   eliminación ([D-27]).
3. **No depende de la competición.** `821` se repite aunque el equipo **cambió de división** entre campañas.
   Es identidad de equipo pura. → la división es atributo de *dónde compite*, no de *quién es* ([D-13]).

**Corolario: casar por nombre no era solo frágil, era incorrecto.** Como el nombre es idéntico en ambas
categorías, un emparejamiento por nombre habría **fusionado dos equipos distintos en uno**. Queda descartado
como estrategia de ingesta, no meramente desaconsejado.

---

## F.4 La clave de club está en la ruta del escudo

No hay campo de club en el objeto de partido, pero el **segmento numérico de la ruta del escudo** se comporta
como tal:

| Club | Segmento | Observado en |
|------|----------|--------------|
| Celtic Castilla | `0010940034` | muestras 1, 2, 3 y 4 — **el mismo en distintas categorías y temporadas** |
| C.D. Fútbol Tres Cantos | `0012158828` | muestras 1 y 4 |
| C.D. El Escorial | `0011702833` | muestra 2 |
| C.F. Pozuelo de Alarcón | `0010960678` | muestra 3 |

Formato observado: `{00100}_{id_club}_{etiqueta}.{png|jpg}`, donde `00100` es constante (presumiblemente el
código de la RFFM) y la extensión **varía**. → clave externa de `OpponentClub` ([D-06]).

> **Salvedad importante.** Esta clave se obtiene **parseando el nombre de un fichero**, no leyendo un campo
> de la API: es una **inferencia sobre datos observados**, no un contrato. Si un club cambia de escudo y el
> fichero se renombra, la clave podría cambiar y generaría un `OpponentClub` duplicado. Por eso la ingesta
> debe **tolerar el fallo** y degradar (§3.7 del LLD), y por eso sigue haciendo falta la operación de
> **fusión**.

**El escudo es del club, no del equipo** — la propia ruta lo dice: `/pnfg/pimg/Clubes/…`. Confirma de forma
independiente la separación `OpponentClub` / `Team` ([D-06]).

Las rutas son **relativas** al *host* de la federación (`https://appweb.rffm.es` + ruta).

---

## F.5 Rarezas de mapeo a tener en cuenta al escribir el adaptador

| Observación | Consecuencia para el mapeo |
|-------------|----------------------------|
| `goles_casa`/`goles_visitante` vienen como **cadena vacía**, no `null`, si el partido no se ha jugado (muestras 1 y 2) | Traducir `""` → `NULL` en `Match.home_score`/`away_score` |
| `hora` puede venir **vacía** aun conociéndose la `fecha` (muestra 1), y con valor en las jugadas (`"12:00"`) | Mapean a **dos columnas separadas**, `match_date` y `kickoff_time`, no a un `timestamptz` único: la hora ausente **no es un dato que falte, es un horario sin confirmar** ([D-30], y ver abajo) |
| La muestra 2 **no trae `hora` en absoluto** (campo ausente, no vacío) | El *decoder* debe tolerar campos ausentes, no solo vacíos |
| El nombre trae **la letra embebida** entre comillas simples: `"C.D. FUTBOL TRES CANTOS 'A'"` | La ingesta separa club + `letter`. `"C.D. EL ESCORIAL"` **no lleva letra** → `letter` sigue siendo opcional |
| Nombres en **mayúsculas** y con puntuación irregular (`C.D.`, `C.F.`, `CELTIC CASTILLA C.F.`) | Normalizar para el emparejamiento por nombre (paso 2 de la cadena de degradación), y dejar la grafía a corrección manual |
| Las fechas vienen como `DD-MM-AAAA` | No es ISO: parseo explícito |
| Hay **`codigo_campo` + `campo`** | Existe identificador de campo. Hoy `Match.venue?` es texto libre; si el campo llegara a merecer entidad propia, aquí está la clave. Fuera de alcance |
| `codacta` identifica el **acta** del partido | **Ya modelado** como `Match.federation_match_id` ([D-31]): anulable, porque es un campo **de la RFFM** y no del contrato genérico de federación. El *upsert* lo usa si viene y degrada a (jornada, local, visitante) si no |

**El calendario se publica en dos tiempos, y eso no es una rareza: es el ritmo de la fuente.**

Cuando arranca la temporada, la federación reparte **todos** los partidos por jornadas, pero con una fecha
**por defecto** —el **sábado**— y **sin hora**. La franja definitiva de cada jornada se fija el **domingo
anterior, al cierre**, y al fijarla la fecha puede además desplazarse **a domingo**. Es lo que explica que
`hora` venga vacía o ausente en las muestras 1 y 2 (partidos lejanos) y con valor en las 3 y 4 (ya jugados),
sin que ninguna esté mal formada.

Dos consecuencias, ambas ya recogidas en el LLD:

- **En el modelo:** `match_date` y `kickoff_time` separados, con la confirmación **derivada** de que haya
  hora ([D-30]). Un `timestamptz` único no puede representar "sábado, hora por decidir".
- **En la ingesta:** los dos campos son **volátiles** (se pisan en cada pasada) y el hito del domingo
  **ancla la cadencia** — una pasada el lunes recoge a la vez los horarios de la semana entrante y el
  resultado de la jornada recién jugada (§5.6). De martes a viernes no hay nada nuevo que traer.

> **Cuidado con leer "confirmado" como "definitivo".** Un horario ya publicado puede moverse por causa mayor
> —campo inutilizable, inundaciones, suspensión—, así que la confirmación describe **lo que la federación ha
> publicado hasta ahora**, no un compromiso. Y como `Match` no tiene `PATCH` ([D-21]), el único camino de
> vuelta es la siguiente sincronización.

---

## F.6 Pendiente de observar

Lo que falta para cerrar el contrato de ingesta (§5.6 del LLD). **Seis puntos que esta lista tenía se han
resuelto** con los volcados: cuatro en §F.12, y los dos grandes —acta y goleadores— en §F.10 y §F.13.

- **Cómo se señala un partido aplazado o suspendido *en el calendario*.** §F.10 confirma que el **acta** trae
  `suspendido`, `acta_cerrada` y `partido_en_juego`, pero el objeto de partido del calendario sigue sin campo
  de estado (§F.2). Falta ver qué hace la fuente **en el calendario** cuando un partido se aplaza de verdad:
  ¿solo mueve la fecha? Mientras no se sepa, `aplazado` y `suspendido` (§3.3 del LLD) solo son alcanzables
  **leyendo el acta**, a una petición por partido.
- **`codacta_origen` con valor.** Sigue llegando vacío en las dos actas observadas. Es la pieza que diría si
  un partido reprogramado conserva puntero a su acta original — y con ella, si la reprogramación es
  detectable sin comparar fechas. **[I]** hasta que se vea un caso real.
- **Los códigos de `tipo_gol` y `codigo_tipo_amonestacion` distintos de `"100"`.** La leyenda de la web
  demuestra que existen —tres tipos de gol y dos de tarjeta (§F.10)— pero el acta observada no los ejercita.
  **Hace falta capturar un acta con penalti, gol en propia puerta y tarjeta roja**; es lo que decide si el
  desglose de `Goal` y el tipo de `Card` pueden llegar de la fuente o siguen siendo entrada manual.
- **Si `goles_penalti[]` es la tanda de penaltis** —lo sugiere su vecindad con `hay_penaltis`,
  `penaltis_casa` y `penaltis_fuera`— o los penaltis convertidos en juego. Llega vacía en la muestra.
- **El `buildId` de la ruta de datos de Next.js** (§F.10): confirmado que cambia entre despliegues. Falta
  decidir cómo se obtiene y se refresca —o si se usa la ruta HTML, más estable pero con parseo.
- **Política de refresco del escudo**: la ruta de origen cambia detectablemente si el club lo cambia, pero no
  está decidido cada cuánto se comprueba.
- **Paginación de `/competicion/terrenosjuego`**: el nombre del parámetro de página (§F.7).
- **Si los códigos de modalidad `3`, `4` y `5` devuelven datos** — el catálogo los declara, pero solo se han
  ejercitado `1` y `2` (§F.9).
- **`puntos_sancion`** (§F.8): la fuente lo publica y el modelo no lo recoge. **Aplazado a propósito** — se
  revisará al final del diseño, no ahora.
- **El array completo de `/api/competitions` para una temporada** (§F.14). Se ha observado **un** `nombre`.
  Falta contar las variantes del marcador de género —¿siempre `FEMENINO`, siempre al final?— y comprobar si
  este campo sufre el **truncado a 40 caracteres** que §F.11 vio en `NombreCategoria`. No bloquea el diseño
  ([D-58] no depende de que la inferencia acierte), pero decide cuánto acierta el valor propuesto en el
  `/preview`.

> Lo pendiente de la **FCF** no se lista aquí: vive en su [propio anexo](./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md).

---

## F.7 Catálogo de endpoints

La RFFM tiene **dos familias** de endpoints, y conviene no confundirlas: **[C]**

- **API REST JSON**, bajo `/api/…` — devuelve JSON directamente.
- **Páginas Next.js**, bajo `/competicion/…` y `/acta-partido/…` — devuelven **HTML** del que hay que extraer
  el bloque `<script id="__NEXT_DATA__" type="application/json">`.

Transporte, común a todas: **GET** siempre, parámetros en *query string*, **sin cabeceras** (ni `Accept`, ni
*User-Agent*), **sin autenticación**, respuesta **UTF-8**. **[C]**

| Endpoint | Parámetros | Devuelve |
|----------|------------|----------|
| `GET /api/competitions` | `temporada`, `tipojuego` | Array de competiciones — **su `nombre` es la única fuente de género** (§F.14) |
| `GET /api/groups` | `competicion` | Array de grupos — **con `total_jornadas` y `total_equipos`** |
| `GET /competicion/calendario` | `temporada`, `tipojuego`, `competicion`, `grupo` | HTML → calendario **completo** (§F.1) |
| `GET /api/standings` | **`idGroup`**, `round` | Clasificación **de esa jornada** (§F.8) |
| `GET /competicion/terrenosjuego` | `search`, `codcampo`, `codtipocampo` | HTML → campos, **paginado** |
| `GET /acta-partido/{codacta}` | + `temporada`, `competicion`, `grupo` | HTML → **acta completa** (§F.10) |

Detalles que importan al escribir el adaptador:

- **`idGroup` es el único parámetro en *camelCase*** de toda la API; el resto va en minúscula
  (`codcampo`, `codtipocampo`, `competicion`, `grupo`). Y el del calendario es **`grupo`**, no `codgrupo`.
- **`temporada` es el código numérico (`21`), no la etiqueta.** La documentación del proyecto iOS afirma lo
  contrario y **se equivoca**: el volcado real muestra `"temporada": "21"`. **[C]**
- **`/api/groups` no admite `temporada` ni `tipojuego`**: el código de competición ya es único por temporada.
- **`total_jornadas` viene dado** y es el dato bueno. La app lo ignora y estima las jornadas como
  *(nº equipos − 1) × 2*, que falla en ligas de ida sola o con promoción. **Usar el campo.**
- **El catálogo de temporadas y el de modalidades no tienen endpoint propio**: van incrustados en la página
  del calendario, en `seasons[]` y `gameTypes[]`. Para arrancar la ingesta hay que pedir un calendario
  cualquiera y leerlos de ahí. **[C]**
- **`currentRound`** viene en el calendario y **la app no lo usa**. Es el mejor disparador para una ingesta
  incremental. **[C]**
- **`/competicion/terrenosjuego` está paginado** (`total_paginas`, `pagina_siguiente`) y la app **no lo
  pagina**: se queda con el primer resultado. El nombre del parámetro de página es **[N]**.
- **No hay coordenadas GPS de los campos.** La app suple esa carencia con una base local curada a mano. Si
  la geolocalización llega a hacer falta, **la federación no la da**. **[C]**
- La app **imprime el código HTTP pero no lo valida**: un 500 acabaría en el parser de JSON con un error
  engañoso. Validar `2xx` explícitamente.

**Endpoints que existen en el sitio y la app no consume** (del menú incrustado en el propio calendario):
`/competicion/goleadores`, `/competicion/clasificaciones`, `/competicion/resultados-y-jornadas`,
`/competicion/tabla-cruzada`, `/competicion/clubes`, `/competicion/comparativa-equipos`. **[N]**

---

## F.8 Clasificación: la publica la federación, y por jornada

`GET /api/standings?idGroup=24037980&round=9`. Es **histórica**: devuelve la foto de la clasificación *tras*
la jornada pedida — exactamente la granularidad que el modelo necesita (§3.2). **[C]**

```json
{ "estado": "1", "sesion_ok": "1",
  "competicion": "SEGUNDA ALEVIN F-7", "codigo_competicion": "24037935",
  "grupo": "GRUPO 17", "codigo_grupo": "24037980",
  "jornada": "9", "fecha_jornada": "20-12-2025",
  "clasificacion": [
    { "posicion": "1", "codequipo": "23995505", "nombre": "ESCUELA FUTBOL BARRIO PILAR 'C'",
      "url_img": "/pnfg/pimg/Clubes/00100_0011943963_Logo_Escuela.jpg?nova=1",
      "jugados": "9", "ganados": "8", "perdidos": "0", "empatados": "1",
      "goles_a_favor": "81", "goles_en_contra": "18",
      "puntos": "25", "puntos_sancion": "0", "puntos_local": "13", "puntos_visitante": "12",
      "racha_partidos": [ {"tipo":"G","color":"#04B431"}, {"tipo":"P","color":"#F78181"} ] } ],
  "promociones": [] }
```

| Campo destino (§3.2) | Origen | Estado |
|----------------------|--------|--------|
| `position`, `played`, `goals_for`, `goals_against`, `points` | `posicion`, `jugados`, `goles_a_favor`, `goles_en_contra`, `puntos` | ✅ directos |
| `won`, `drawn`, `lost` | `ganados`, `empatados`, `perdidos` | ✅ — pero **el orden en el JSON es `ganados, perdidos, empatados`**: leer por nombre, nunca por posición |
| **`previous_position`** | **No se publica** | ❌ Hay que **calcularlo comparando con el *snapshot* anterior**, y aceptar nulo cuando no lo haya — exactamente lo que [D-33] previó |
| Identificación del equipo | **`codequipo`** | ✅ **Coincide con el `codigo_equipo_*` del calendario** (§F.3) → unión directa por id, sin degradar a nombre |

**Lo que la fuente da y el modelo hoy no recoge:** desglose casa/fuera completo, `puntos_local` /
`puntos_visitante`, **`puntos_sancion`** (puntos descontados por sanción), `coeficiente`, `color` de fila
(promoción/descenso), `racha_partidos[]` con los últimos cinco resultados, y un array **`promociones[]`**
vacío en la muestra pero previsiblemente con las líneas de ascenso y descenso. **[C]**

> **Aviso al cuadrar.** En la jornada 9 de la muestra, `jugados` vale **8 en nueve equipos y 9 en cuatro**:
> la clasificación «a jornada N» refleja los partidos **realmente disputados**, no N por equipo. No asumir
> `jugados == round`.

---

## F.9 Modalidades: el catálogo completo, publicado por la propia fuente

Va incrustado en el calendario, en `gameTypes[]`. Resuelve la correspondencia que §F.1 dejaba abierta: **[C]**

| `codigo_tipo_juego` | `nombre` | Modalidad |
|:-------------------:|----------|-----------|
| `1` | `Futbol-11` | Fútbol 11 |
| `2` | `Futbol-7` | Fútbol 7 |
| `3` | `Fútbol Sala` | Fútbol sala |
| `4` | `Fútbol-5` | Fútbol 5 |
| `5` | `Fútbol-Playa` | Fútbol playa |

El propio catálogo es tipográficamente inconsistente (`Futbol-11` sin acento, `Fútbol Sala` con acento y con
espacio): **usar el código, nunca el nombre**. La app solo ejercita `1` y `2`; que `3`, `4` y `5` devuelvan
datos es **[I]**.

> **No confundir con `codtipocampo`**, el parámetro de `/competicion/terrenosjuego`, que solo tiene **dos**
> valores (`1` = Fútbol 11, `2` = Fútbol 7) pese a coincidir en los dos primeros.

---

## F.10 El acta del partido — **volcado real**

El endpoint que la app no usa y que contiene los **datos oficiales** del encuentro. Verificado sobre un
volcado completo del partido `5408196` (Primera Infantil, Grupo 12, jornada 1). **[C]**

### La llamada

```
https://www.rffm.es/_next/data/{buildId}/acta-partido/{codacta}.json
    ?temporada=21&competicion=24037637&grupo=24037649&codacta=5408196
```

**Es la ruta de datos de Next.js, no la página HTML.** Devuelve **JSON directo** —sin `__NEXT_DATA__` que
extraer— y es por tanto la vía preferible.

> **Pero el `buildId` cambia en cada despliegue.** El volcado nuevo trae `inlzUL9hzqhAubIvBCD2y`; el anterior,
> `qncO_Up-CDoWqLGk4miRX`. **Confirmado empíricamente [C]**, y es la trampa de esta ruta: no se puede
> codificar. Hay que leerlo del `__NEXT_DATA__` de cualquier página y **refrescarlo cuando dé 404**. La
> alternativa estable es pedir el HTML de `/acta-partido/{codacta}` y extraer el bloque, como en §F.7.
>
> Nótese que `codacta` va **dos veces**: en la ruta y como parámetro.

### Estado del partido — lo que el calendario no da

| Campo | Valor observado | Para qué sirve |
|-------|-----------------|----------------|
| `acta_cerrada` | `"1"` | El acta está firmada: resultado definitivo |
| `partido_en_juego` | `"0"` | Partido en directo |
| **`suspendido`** | `"0"` | **El campo que hace alcanzable `Match.status = suspendido`** (§3.3) |
| `codacta_origen` | `""` | **Sigue sin observarse con valor.** **[I]** apuntaría al acta original de un partido reprogramado |

El acta **se identifica a sí misma**: trae `jornada`, `nombre_competicion`, `nombre_grupo`, `fecha`, `hora`,
`campo`, `codigo_campo`, los dos `codigo_equipo_*` y los dos marcadores. No hace falta cruzarla con nada.

### Goles, tarjetas y alineaciones — formas reales

```json
"goles_equipo_local": [
  {"codjugador": "16314233", "nombre_jugador": "CARRASCO CHIROQUE, STEFANO ADRIAN", "minuto": "4",  "tipo_gol": "100"},
  {"codjugador": "20378397", "nombre_jugador": "CURIA SUAREZ, MARCEL",              "minuto": "12", "tipo_gol": "100"}
],
"tarjetas_equipo_local": [
  {"codigo_tipo_amonestacion": "100", "codjugador": "16314233", "segunda_amarilla": "0",
   "minuto": "55", "nombre_jugador": "CARRASCO CHIROQUE, STEFANO ADRIAN"}
],
"jugadores_equipo_local": [
  {"codjugador": "22877610", "foto": "", "dorsal": "13", "sexo": "0", "nombre_jugador": "GIL ALEJANDRO, JAVIER",
   "titular": "0", "suplente": "1", "capitan": "0", "portero": "1", "posicion": "",
   "posicion_jugador_abreviatura": "", "ver_estadisiticas_jugador": "1"}
],
"arbitros_partido": [
  {"cod_arbitro": "1401836", "tipo_arbitro": "ARBITRO", "nombre_arbitro": "PINTOS CANARIO, ALEJANDRO"}
]
```

Observaciones sobre estas listas:

- **`tarjetas_*` trae `segunda_amarilla`** como campo propio, además de `codigo_tipo_amonestacion`. Es
  exactamente la distinción que el modelo hace en `Card` ([D-45]).
- **`tipo_gol` y `codigo_tipo_amonestacion` valen `"100"`** en todo lo observado (nueve goles, dos tarjetas).
  Ningún otro valor **en esta muestra** — pero no son campos de un solo valor: ver abajo.
- `hay_penaltis`, `penaltis_casa` y `penaltis_fuera` llegan como **cadena vacía**, no `"0"` — coherente con
  §F.11. Junto a ellos va **`goles_penalti[]`**, vacía aquí; por su vecindad con los tres anteriores es la
  **tanda de penaltis**, no los penaltis convertidos en juego. **[I]**

### La leyenda de la web acota el espacio de valores

La página del acta pinta esta leyenda: **[C]**

> ⚽ Gol · 🔴 Gol en propia puerta · Penalti · Tarjeta amarilla · Tarjeta roja

**La leyenda no viaja en el JSON** —se renderiza en el cliente desde un mapa fijo; buscar `penalti`,
`amarilla`, `roja` o `propia` en el volcado no devuelve ninguna correspondencia código↔etiqueta—. Pero
**demuestra que los códigos existen**, aunque esta acta no los ejercite:

| Campo | Valores que la leyenda implica | Observado |
|-------|--------------------------------|-----------|
| `tipo_gol` | **≥ 3**: gol, gol en propia puerta, penalti | solo `"100"` |
| `codigo_tipo_amonestacion` | **≥ 2**: amarilla, roja | solo `"100"` |

Dado que la muestra son nueve goles de jugada y dos amarillas, `"100"` es **[I]** «gol normal» y «amarilla»
respectivamente. Los demás códigos son **[N]**: hay que capturar un acta con penalti, propia puerta o roja.

**Comparación con el modelo, que es donde esto importa** (§3.3):

| `Goal.play_type` | Icono en la leyenda |
|------------------|---------------------|
| `juego_abierto` | ⚽ Gol |
| `en_propia_puerta` | 🔴 Gol en propia puerta |
| `penalti` | Penalti |
| **`falta`** | **ninguno** |

Tres de los cuatro valores del enumerado tienen contrapartida en la fuente; **`falta` no la tiene**. La RFFM
no distingue el gol de falta directa. En `Card`, la correspondencia es completa: los dos valores del
enumerado más `segunda_amarilla` como campo aparte, igual que en el modelo.
- **`posicion` y `posicion_jugador_abreviatura` llegan vacías** en las 36 fichas de jugador, pese a existir.
- `esquema_local` / `esquema_visitante` traen la **formación** (`"1-4-4-2"`, `"1-4-3-3"`).
- Typo del proveedor que hay que respetar literalmente: **`ver_estadisiticas_jugador`**.
- Valores centinela en texto: `entrenador_visitante` = **`"No presenta"`**, y `entrenador_local` llega con un
  **espacio inicial** (`" CHUECA MANZANERO, ALEJANDRO"`). Sanear.

### Dos confirmaciones colaterales

1. **El `host` de los escudos ya no es una inferencia.** El propio `game` trae
   `"host": "https://appweb.rffm.es/"`, que era justo lo que §F.4 daba por **[I]**. Ahora es **[C]**.
2. **El sufijo `(HA)` duplicado es un artefacto del calendario.** Aquí el campo llega limpio:
   `"CANAL ISABEL II (HA)"`, con **un solo** `(HA)`, frente al `(HA)(HA)` del calendario (§F.11).

> **Advertencia de datos personales.** El acta trae **nombre, dorsal, código federativo y hueco de foto de
> jugadores de categorías infantiles**, más los de árbitros, entrenadores y delegados. Es el material más
> sensible de toda la fuente y condiciona cualquier decisión sobre ingerirlo (§8, RGPD).

**Coste:** una petición **por partido** — ~240 por grupo y temporada.

---

## F.11 Rarezas adicionales observadas en los volcados

Complementan las de §F.5, que siguen siendo válidas. **[C]** salvo indicación.

| Observación | Consecuencia |
|-------------|--------------|
| **Todo llega como cadena, sin excepción**: `posicion`, `puntos`, `goles_casa`, `currentRound`… Nunca hay números ni booleanos en JSON; las banderas son `"0"`/`"1"` | Conversión explícita en todo el adaptador |
| El parser de la app **filtra todo lo que no sea dígito** al convertir | **Un `-3` se convertiría en `3`.** Si `puntos_sancion` o una diferencia pudiera venir negativa, se corrompe: **preservar el signo** |
| Se han visto `&nbsp;` y espacios duros **dentro de campos numéricos** (el parser los limpia) | Sanear antes de convertir |
| **Dos formatos de fecha en el mismo proveedor**: `dd-MM-yyyy` en datos operativos (`fecha`, `fecha_jornada`), **`yyyy-MM-dd` ISO** en catálogos (`seasons[].fecha_inicio`, `competitions[].FechaInicio`) | Parseo explícito **según el campo** |
| **Sin huso horario en ningún payload** | Fijar `Europe/Madrid` explícitamente **[I]**; cuidado con los cambios de hora |
| `"" ` y `"0"` **no son intercambiables**, y el mismo objeto usa ambos: `puntos_sancion` llega `"0"`, `coeficiente` llega `""` | Distinguir vacío de cero |
| El sufijo `(HA)` aparece en **240 de 240** nombres de campo, con variantes `(HA)(HA)`, `(HA) (HA)` y `(H.A.)(HA)` | La limpieza literal de la app **falla** en dos de las tres. Regex: `\s*\((?:HA\|H\.A\.)\)\s*`, aplicada repetidamente |
| **Acentos inconsistentes por campo**: equipos y campos **sin** acentos (`ANGELES`, `CHAMBERI`); personas y catálogos **con** acentos (`GARCÍA`, `Fútbol Sala`) | Comparar nombres con *folding* de diacríticos |
| `calendar.rounds[].`**`equipos[]`** es la lista de **partidos**, no de equipos | Nombre engañoso del proveedor |
| El calendario asigna la jornada por **índice de array** en la app, ignorando `jornada` y `codjornada` | **Usar `jornada`**, no la posición |
| `NombreCategoria` viene **truncado a 40 caracteres** (`"PRIMERA DIVISION AUTONOMICA FEMENINO CAD"`) | El rótulo de división puede llegar cortado |
| El nombre de grupo **no tiene formato estable**: `"Grupo 1"` en un endpoint, `"GRUPO 17"` en otro | Normalizar |
| **No hay campo de género** en ninguna entidad; solo se infiere del texto (`FÚTBOL FEMENINO`) | Resuelto en **§F.14**: el género va en el **nombre de la competición**, y de ahí lo toma el modelo ([D-58]). No hay campo propio en ninguna entidad |
| `estado` y `sesion_ok` acompañan a todas las respuestas, siempre `"1"` | **[I]** `"1"` = OK. `sesion_ok` sugiere que el *backend* legacy podría devolver `"0"` con lista vacía **en vez de un error HTTP**: una lista vacía no siempre significa «no hay datos» |
| `"(No asignado)"` aparece como **nombre real** de equipo | Tolerarlo |
| Los códigos son **cadenas de longitud variable** (3 a 8 dígitos), con espacios de numeración antiguos y nuevos conviviendo | No normalizar a entero, no rellenar con ceros |
| **La etiqueta de temporada llega como `"2025-2026"`**, no `"2024/25"` | Reformatear al `label` del modelo (§3.2) |
| **`?nova=1`** aparece en la URL del escudo de forma inconsistente (0/240 en calendario, 13/13 en clasificación) | Normalizar quitando el *query* si se usa como clave |

---

## F.12 Confirmaciones que cierran cuestiones abiertas

Cuatro puntos que §F.6 daba por pendientes y los volcados resuelven: **[C]**

1. **`codacta` viene siempre y es único.** 240 de 240 partidos lo traen, con 240 valores distintos. La cadena
   de degradación de [D-31] es una **red de seguridad, no el camino habitual** — al menos en calendarios
   completos.
2. **La RFFM publica clasificación por jornada** (§F.8), con la granularidad exacta del modelo.
3. **Los rótulos de división y grupo llegan como texto** (`NombreCategoria`, `nombre_grupo_categoria`,
   `groups[].nombre`): el administrador **confirma**, no teclea. Era el único punto del alta que dependía de
   un dato sin observar.
4. **La correspondencia `tipojuego` ↔ modalidad está completa** (§F.9), y la publica la propia fuente.

---

## F.13 Goleadores — **volcado real**

Era el último hueco grande de §F.6. **Existe, es JSON, y no está donde se había inferido.** **[C]**

```
https://www.rffm.es/api/scorers?idGroup=24037649&idCompetition=24037637
```

**Es un endpoint `/api/…` JSON puro**, no la página `/competicion/goleadores` con `__NEXT_DATA__` que §F.6
suponía por simetría. Dos parámetros, **los dos en *camelCase***: `idGroup` e `idCompetition`. Sin
`temporada` ni `tipojuego` — el código de grupo ya es único por temporada, igual que en `/api/groups` (§F.7).

```json
{ "estado": "1", "sesion_ok": "1",
  "competicion": "PRIMERA INFANTIL", "grupo": "Grupo 12",
  "goles": [
    { "codigo_jugador": "19740208", "foto": "",
      "jugador": "HERRA RODRIGUEZ, RODRIGO",
      "escudo_equipo": "/pnfg/pimg/Clubes/00100_0011870589_IMG_2415.png",
      "nombre_equipo": "S.A.D. OCIO Y DEPORTE CANAL B", "codigo_equipo": "10634103",
      "partidos_jugados": "25", "goles": "45", "goles_penalti": "4", "goles_por_partidos": "1.80" } ] }
```

### Mapeo a `LeagueScorer` (§3.2)

| Campo destino | Origen | Estado |
|---------------|--------|--------|
| `full_name` | `jugador` | ✅ `"APELLIDOS, NOMBRE"` |
| `team_label` | `nombre_equipo` | ✅ Texto del proveedor, **con la letra pegada sin comillas** en la muestra (`… CANAL B`) |
| `goals` | `goles` | ✅ |
| **`rank`** | **No se publica** | ❌ **No hay campo de puesto.** La lista llega **ordenada por goles descendente** (verificado en las 208 filas) y la posición es implícita |

Que `rank` sea anulable en el modelo no era una precaución teórica: **este proveedor no lo da**. El orden de
la respuesta es la única señal, y los empates —dos jugadores con 45 goles en la muestra— quedan sin desempate
declarado.

### Lo que la fuente da de más

`codigo_jugador` (208 valores, **todos únicos y no vacíos**), **`codigo_equipo`** —que **casa con el
`codigo_equipo_*` del calendario** (§F.3) y permitiría unir el goleador con su `Team` sin emparejar por
nombre—, `escudo_equipo`, `partidos_jugados`, `goles_penalti` y `goles_por_partidos`.

`foto` llega **vacía en las 208 filas**.

### Un dato que valida la paginación

**208 goleadores en un solo grupo.** El ámbito «competición» no acota cuántos jugadores han marcado en ella,
que es exactamente el razonamiento con el que [D-49] decidió paginar este recurso frente a no paginar la
clasificación. La estimación era «potencialmente doscientos»; la realidad, 208.

---

## F.14 El género vive en el nombre de la competición

Era el último **hueco de modelo** que la fuente parecía no cubrir: §F.11 anotaba que **ninguna entidad de la
RFFM tiene campo de género**, y `Team.gender` (§3.3 del LLD) es obligatorio y **parte de la clave única de
`Team`** (§3.5). La respuesta está en `GET /api/competitions`: **[C]**

```
https://www.rffm.es/api/competitions?temporada=22&tipojuego=1
```

```json
{ "nombre": "TERCERA FEDERACION DE FÚTBOL FEMENINO" }
```

**El género es un atributo de la competición, no del equipo**, y la fuente lo publica **solo como texto
dentro del rótulo**. No hay campo, ni código, ni bandera. Es el mismo patrón que la división y el grupo
(§F.12): rótulo legible, no dato estructurado.

Consecuencia para el modelo: el género entra por la **competición** —donde el administrador lo confirma en el
alta— y de ahí lo hereda `Team`, exactamente como ya ocurre con la modalidad ([D-58]). Lo que **no** puede
hacer la ingesta es inferirlo equipo a equipo: el nombre del equipo no lo lleva (§F.2, §F.3).

### La regla de parseo, y por qué solo puede *proponer*

| Marcador en el `nombre` | Género |
|-------------------------|--------|
| contiene `FEMENINO` / `FEMENINA` (con o sin acento, con *folding* de diacríticos — §F.11) | `femenino` |
| ningún marcador | `masculino` (valor por defecto de la fuente) |
| — | **`mixto` no aparece nunca**: la RFFM no lo representa |

Tres razones por las que esta inferencia se propone al administrador en el `/preview` y **no se da por
buena** (§5.1 del LLD):

1. **`mixto` es inalcanzable desde la fuente.** El enumerado del modelo tiene tres valores y la RFFM solo
   sabe expresar dos. En fútbol base los equipos mixtos existen aunque la federación los inscriba como
   masculinos, así que el único que puede poner ese valor es el club. **[C]**
2. **El truncado a 40 caracteres puede comerse el marcador.** §F.11 observó `NombreCategoria` truncado en
   `"PRIMERA DIVISION AUTONOMICA FEMENINO CAD"` — exactamente 40 caracteres, con `FEMENINO` salvado por los
   pelos y `CADETE` decapitado. Un rótulo un poco más largo perdería el marcador y **la inferencia daría
   `masculino` sin error ninguno**. Si el truncado afecta también al `nombre` de `/api/competitions` es
   **[N]**: se ha observado en otro campo y otro endpoint. Pero basta la posibilidad para no confiar el
   valor a un `contains`.
3. **Un error aquí no da un dato feo, da un 409.** Como `gender` entra en la clave única de `Team`, una
   inferencia equivocada colisiona con el equipo ya existente en vez de degradarse en silencio.

> **Alcance de la muestra.** Un único `nombre` observado, aportado por el desarrollador. Que el marcador sea
> **siempre** `FEMENINO` y **siempre** al final del rótulo es **[I]**: convendría volcar el array completo de
> `/api/competitions` para una temporada y contar las variantes.

---

*Referencias `§x.y` → [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · `§C.x` → [Anexo FCF](./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md) · `D-nn` → [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md)*

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
[Anexo FCF]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.1]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.2]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.3]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.4]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.5]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.6]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.7]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.8]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
[Anexo FCF §C.9]: ./API_y_BBDD%20LLD-Anexo-Federacion-Catalunya-FCF.md
