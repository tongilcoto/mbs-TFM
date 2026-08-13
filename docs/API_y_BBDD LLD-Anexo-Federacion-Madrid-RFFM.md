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
> **Salvedad general.** Nada de esto es un contrato publicado. Es **ingeniería inversa** de la app iOS
> existente y de la web pública (RFFM Madrid; queda por explorar la Federación Cataluña). Todo lo que sigue
> puede cambiar sin aviso, y por eso el modelo trata estos identificadores como **datos de integración**,
> nunca como claves de unión (§3.7 del LLD).

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

Lo que falta para cerrar el contrato de ingesta (§5.6 del LLD):

- **Respuesta del endpoint de clasificación** — *forma* de la respuesta, aún sin muestra. Lo que **ya está
  confirmado** es que **existe**: la RFFM **sí** publica clasificación. La **FCF (Cataluña) no**, y ahí
  `StandingRow` se calcula desde `Match` ([D-15]).

  **Qué hay que buscar en la muestra, ahora que el contrato está escrito** (§3.2, §5.1):

  | Campo destino | Qué comprobar en la respuesta |
  |---------------|-------------------------------|
  | `position`, `played`, `won`, `drawn`, `lost`, `goals_for`, `goals_against`, `points` | Se dan por seguros; confirmar nombres y que `points` venga **calculado por la fuente** y no haya que deducirlo (sanciones con descuento de puntos) |
  | **`previous_position`** | **El más incierto.** Si la RFFM no lo publica, hay que calcularlo al ingerir comparando con el *snapshot* anterior — y aceptar que sea nulo cuando no lo haya ([D-33]) |
  | Identificación del equipo | Si viene `codigo_equipo` (como en el calendario, §F.3) el emparejamiento es directo; si solo viene el nombre, hay que degradar como en §3.7 |
  | Granularidad | **Si la respuesta es por jornada o solo la clasificación actual.** Es la pregunta que más condiciona: el modelo es un *snapshot* **por jornada**, y si la fuente solo da la última, las jornadas pasadas habrá que calcularlas desde `Match` o construirlas incrementalmente pasada a pasada |

  > Esta es la **primera diferencia de capacidad observada entre federaciones**, y por eso no es solo un
  > dato de integración: fija que el catálogo en código ([D-17]) describa **qué sabe hacer** cada
  > proveedor, no solo sus coordenadas. Consecuencia en el contrato: se descartó `Round.hasStandings` y
  > la procedencia se expone una sola vez por tenant, en `ClubResponse` ([D-29]).
- **Respuesta del endpoint de goleadores** — mapeo a `LeagueScorer`.
- **Si el calendario devuelve `division_label` y `group_label` como texto.** Si no los devuelve, son los dos
  únicos rótulos que el administrador tendrá que **teclear** en el alta en vez de limitarse a confirmar lo
  que le muestra el *preview*. Es el único punto del diseño del alta que depende de un dato aún no observado.
- **Correspondencia `tipojuego` ↔ modalidad** más allá de `1` = fútbol-11.
- **Cómo se señala un partido aplazado o suspendido.** El objeto de partido **no trae campo de estado**
  (§F.2): solo goles vacíos o llenos, de donde la ingesta deriva `programado`/`finalizado`. Los otros dos
  valores del enumerado `Match.status` (§3.3 del LLD) **no se han observado**, y como `Match` no tiene
  `PATCH` ([D-21]) hoy son **inalcanzables**: nadie puede fijarlos. Falta ver qué hace la fuente cuando un
  partido se aplaza de verdad — ¿mueve la fecha y ya está, o lo marca de algún modo? Si resultara que no
  hay forma de distinguirlo, **lo que sobra son los dos valores, no el campo**.
- **Si `codacta` viene siempre.** Se ha visto en las cuatro muestras, todas de calendario completo. Falta
  confirmar que no falta en respuestas parciales — es lo que decide si el segundo paso de la cadena de
  emparejamiento de partidos ([D-31]) es un recurso excepcional o el camino habitual.
- **Federación Cataluña**: host, contrato y numeración. Todo lo anterior es RFFM. Ya se sabe una cosa: **no
  publica clasificación** (ver arriba).
- **Política de refresco del escudo**: la ruta de origen es detectablemente distinta si el club lo cambia,
  pero no está decidido cada cuánto se comprueba.

---

*Referencias `§x.y` → [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · `D-nn` → [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md)*

<!-- Definiciones de enlace -->
[D-06]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-13]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-15]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-17]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-21]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-27]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-30]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-31]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-33]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-29]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
