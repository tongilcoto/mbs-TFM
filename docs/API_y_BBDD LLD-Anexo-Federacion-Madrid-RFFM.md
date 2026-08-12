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
| `hora` puede venir **vacía** aun conociéndose la `fecha` (muestra 1), y con valor en las jugadas (`"12:00"`) | `fecha` + `hora` componen `kickoff_at`, pero **la hora puede faltar** |
| La muestra 2 **no trae `hora` en absoluto** (campo ausente, no vacío) | El *decoder* debe tolerar campos ausentes, no solo vacíos |
| El nombre trae **la letra embebida** entre comillas simples: `"C.D. FUTBOL TRES CANTOS 'A'"` | La ingesta separa club + `letter`. `"C.D. EL ESCORIAL"` **no lleva letra** → `letter` sigue siendo opcional |
| Nombres en **mayúsculas** y con puntuación irregular (`C.D.`, `C.F.`, `CELTIC CASTILLA C.F.`) | Normalizar para el emparejamiento por nombre (paso 2 de la cadena de degradación), y dejar la grafía a corrección manual |
| Las fechas vienen como `DD-MM-AAAA` | No es ISO: parseo explícito |
| Hay **`codigo_campo` + `campo`** | Existe identificador de campo. Hoy `Match.venue?` es texto libre; si el campo llegara a merecer entidad propia, aquí está la clave. Fuera de alcance |
| `codacta` identifica el **acta** del partido | Candidato natural a clave externa de `Match`. No modelado aún — anotado por si la ingesta lo necesita para el *upsert* |

---

## F.6 Pendiente de observar

Lo que falta para cerrar el contrato de ingesta (§5.6 del LLD):

- **Respuesta del endpoint de clasificación** — y si esta federación la ofrece siquiera; determina si
  `StandingRow` se ingiere o se calcula.
- **Respuesta del endpoint de goleadores** — mapeo a `LeagueScorer`.
- **Si el calendario devuelve `division_label` y `group_label` como texto.** Si no los devuelve, son los dos
  únicos rótulos que el administrador tendrá que **teclear** en el alta en vez de limitarse a confirmar lo
  que le muestra el *preview*. Es el único punto del diseño del alta que depende de un dato aún no observado.
- **Correspondencia `tipojuego` ↔ modalidad** más allá de `1` = fútbol-11.
- **Federación Cataluña**: host, contrato y numeración. Todo lo anterior es RFFM.
- **Política de refresco del escudo**: la ruta de origen es detectablemente distinta si el club lo cambia,
  pero no está decidido cada cuánto se comprueba.

---

*Referencias `§x.y` → [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · `D-nn` → [Anexo de Decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md)*

<!-- Definiciones de enlace -->
[D-06]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-13]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-17]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-27]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
