# Anexo de Decisiones · Bitácora de decisiones de diseño

- **Estado:** vivo — se añade una entrada cada vez que se descarta una alternativa
- **Fecha:** 2026-08-11
- **Documento principal:** [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · **Evidencia:** [Anexo de la Federación](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md)

> **Qué es este anexo.** El **por qué** del diseño: qué alternativa era tentadora, por qué se descartó, qué
> se eligió y **qué se asume a cambio**. El LLD enuncia el *qué* en una línea y enlaza aquí.
>
> **Por qué existe.** Sin él, el LLD mezclaba tres géneros —especificación, deliberación y observación— y se
> volvía ilegible como referencia de implementación. Ver [D-26].
>
> **Cómo se lee.** No linealmente: se entra por el índice o por el enlace `[D-nn]` desde el LLD o el *spec*.
> Cada entrada es autocontenida.
>
> **Ámbito.** Decisiones de **diseño** de API y base de datos. Las decisiones **tecnológicas** (qué BD, qué
> lenguaje, qué PaaS) viven en el [ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md) y no se repiten aquí.

---

## Índice

| Id | Decisión | Impacta |
|----|----------|---------|
| **Arquitectura** | | |
| **D-01** | Dominio independiente de frameworks, no *Active Record* | §2.2, §4, §8.1 |
| **D-02** | Enumerados como `text` + `CHECK`, no `ENUM` nativo de Postgres | §4.6 |
| **Modelo de datos** | | |
| **D-03** | `Team` no lleva identidad de club: se extrae `OpponentClub` | §3.2, §3.6 |
| **D-04** | `Goal` denormaliza equipo que marca y equipo que encaja | §3.2, §3.4 |
| **D-05** | `Player` lleva `season_id`: una fila por jugador, equipo y temporada | §3.2 |
| **D-06** | Doble identificador: UUID interno **y** id externo de federación | §3.2, §3.7 |
| **D-07** | La modalidad es dominio, no integración — y entra en la clave de `Team` | §3.2, §3.3, §3.5 |
| **D-08** | División: tres campos explícitos en vez de `category_label` | §3.2 |
| **D-09** | Goleadores de la liga: se ingieren, no se calculan | §3.2, §3.4 |
| **D-10** | Sanción por amarillas: tramos configurables por competición | §3.2, §3.4 |
| **D-11** | Zona de gol: partición exclusiva de tres valores | §3.3 |
| **D-12** | Copas y otras competiciones: sin entidades nuevas | §3.6 |
| **D-13** | "Primer Equipo" y filiales: `category=senior` + `letter` | §3.2 |
| **D-14** | Minutos jugados: se registran, pero opcionales | §3.2 |
| **D-15** | `StandingRow` agnóstica a la fuente; el *fallback* es cálculo, no formulario | §3.2, §5.1 |
| **D-27** | `Participation` se elimina: la composición de la liga es derivada, no un hecho | §3.4, §3.5, §4.2, §4.6, §5.1 |
| **D-28** | La temporada no se propaga: `season_id` solo donde es identidad, no atajo | §3.2, §3.5 |
| **Integración** | | |
| **D-16** | Las coordenadas de la federación son configuración tecleada, no descubrimiento | §3.7, §5.1, §5.6 |
| **D-17** | La federación es un catálogo en código, y hay una por tenant | §3.2, §3.6 |
| **D-18** | *Upsert* por tipo de campo: semilla, volátil, propiedad y emparejamiento | §3.7 |
| **D-19** | Los escudos se descargan; la clave del objeto se deriva del `slug` | §3.7 |
| **D-20** | Arranque en frío: reclamación de equipo propio como sub-recurso de estado | §3.6, §5.1 |
| **Contrato de la API** | | |
| **D-21** | El BFF corrige lo que la ingesta trae; nunca lo crea ni lo borra | §5.1 |
| **D-22** | `Competition` es entrada de la ingesta: tiene `POST`, y el alta es en dos pasos | §5.1 |
| **D-23** | `Club` es un *singleton* sin `POST` ni `DELETE` | §5.1 |
| **D-24** | Borrado físico de temporada: operación protegida en dos pasos | §5.4 |
| **D-29** | La clasificación no es un campo de `Round`: es una capacidad de la federación | §3.7, §5.1, §5.2 |
| **Documentación** | | |
| **D-25** | El *spec* OpenAPI es la fuente de verdad campo a campo; el LLD no lo duplica | §5.2, §5.5 |
| **D-26** | El LLD se queda con lo normativo; deliberación y evidencia van a anexos | — |

---

## Arquitectura

### D-01 · Dominio independiente de frameworks, no *Active Record*

**Contexto.** El borrador inicial modelaba en estilo *Active Record*: `final class Match: Model, Content` —
el modelo Fluent **era** la entidad y además se serializaba directo como DTO.

| Opción | Qué implica | Veredicto |
|--------|-------------|-----------|
| **A — Dominio independiente** | **Tres** representaciones: entidad de dominio (`struct` puro), modelo de persistencia Fluent y DTO. El repositorio mapea entidad ↔ `Record`; el controller, entidad ↔ DTO | **Elegida** |
| **B — *Active Record* pragmático** | El modelo Fluent hace de entidad; se le quita `Content` y se mantienen DTOs, pero el Dominio sigue importando Fluent | Descartada |

**Decisión: A.** La opción B **acopla el Dominio a Fluent/Vapor** y cruza la frontera con un objeto de
framework, justo lo que la Regla de dependencia y la independencia de frameworks prohíben — y es visible
para un tribunal.

**Contrapartida asumida:** más *boilerplate* de mapeo.

**Consecuencia que lo justifica más allá de lo académico (era §8.1):** con B, la lógica de negocio solo se
puede probar **a través de la BD**. Y el atajo habitual —SQLite en memoria— **no sirve en este proyecto**,
porque *schema*-por-tenant y RLS son exclusivos de Postgres: probarías con baja fidelidad justo lo que más
importa. Con A, la capa rápida de la pirámide sale de *unit tests* **sin I/O** y la integración se reserva a
Postgres real. Además la frontera la vigila **el compilador** (un `struct` sin `import Fluent` no puede tocar
persistencia), no la disciplina de quien escribe.

---

### D-02 · Enumerados como `text` + `CHECK`, no `ENUM` nativo

| Opción | Pros | Contras |
|--------|------|---------|
| **`text` + `CHECK`** *(elegida)* | Añadir un valor = migración simple y transaccional (`DROP` + `ADD CONSTRAINT`); el `enum` Swift sigue siendo la fuente de verdad | No hay catálogo de tipo en Postgres |
| **`ENUM` nativo** | Validación a nivel de tipo; algo más compacto | Un tipo `ENUM` **vive en un *schema***: en el tier gestionado (*schema* por club) habría que crear/alterar el tipo **en cada *schema* de tenant**, duplicando ese paso en cada migración por tenant |

**Decisión:** `text` + `CHECK`. Se prioriza que **añadir un valor a un enumerado sea una migración uniforme**
en los dos tiers, sin tratamiento especial por tipo Postgres.

---

## Modelo de datos

### D-03 · `Team` no lleva identidad de club: se extrae `OpponentClub`

**Contexto.** El diseño previo daba a `Team` los campos `short_name`, `crest_url` e `is_own`. **Ninguno de
los tres es un atributo del equipo**: son del **club**. `Team` mezclaba dos conceptos —*de qué club es* y
*qué equipo de ese club es*— cuando lo suyo es solo lo segundo (`category`, `letter`, `gender`).

**Consecuencias del diseño previo:**

- En equipos **propios**, `short_name`/`crest_url` **duplicaban** los de `Club` en N filas: cambias el escudo
  del club y tus equipos siguen mostrando el viejo.
- En **rivales** era peor: el mismo club rival aparece **una vez por categoría** (tu Infantil juega la liga
  infantil, tu Cadete la cadete, y el club del barrio tiene equipo en casi todas). Corregir una errata del
  proveedor obligaba a repetir el `PATCH` en una fila por categoría.

**Decisión.** Entidad `OpponentClub` (`name`, `short_name`, `crest_key?`) y `Team.opponent_club_id`
**anulable**. `Team` pierde nombre y escudo. **`is_own` desaparece como columna**: es
`opponent_club_id IS NULL`, con lo que se elimina de raíz que bandera y datos se contradigan. El nombre
mostrado se compone en lectura.

**Contrapartida asumida:** una entidad más, un *join* para componer el nombre, y la ingesta debe separar el
texto libre del proveedor ("C.D. RIVAL 'B'") en club + letra. A cambio, la corrección manual se hace **en un
solo sitio**, que es donde hacía falta.

**Confirmación independiente:** la propia API pone el escudo bajo `/pnfg/pimg/Clubes/…` y usa un id de club
distinto del de equipo ([Anexo de la Federación §F.3] y [Anexo de la Federación §F.4]).

---

### D-04 · `Goal` denormaliza equipo que marca y equipo que encaja

**Contexto.** Con solo `team_id` (quién marca), saber si un gol es **recibido** por un equipo dado exige un
*join* a `Match` para averiguar quién era el rival.

**Alternativa descartada:** un booleano `a_favor`/`en_contra`. Solo funciona con una perspectiva fija (p. ej.
"el equipo propio") y **se rompe si dos equipos propios del mismo club se enfrentan**.

**Decisión.** `Goal` guarda **dos** FKs a `Team` —`scoring_team_id` y `conceding_team_id`— copiadas del
`Match` al crear el gol. Goles a favor = `WHERE scoring_team_id = :id`; en contra =
`WHERE conceding_team_id = :id`. Ambas **directas e indexadas, sin join**.

**Contrapartida asumida:** hay que mantener ambos campos consistentes con el `Match` al escribir — lo hace la
capa de aplicación, nunca el usuario.

**Además:** todos los campos de clasificación del gol (`zone`, `side`, `body_part`, `play_type`, `assisted`)
son **opcionales**: reflejan entrada manual parcial, no todos los goles llevan desglose completo.

---

### D-05 · `Player` lleva `season_id`: una fila por jugador, equipo y temporada

**La pregunta era** si `Player` debía ser una **identidad estable** que persiste entre temporadas (un mismo
registro que se traslada de equipo cada año, con una tabla de "registro por temporada" aparte) o si cada
temporada genera directamente una fila nueva.

**Decisión: lo segundo.** `Player` lleva `season_id` además de `team_id` → **una fila = un jugador en un
equipo en una temporada**. Quien sube de categoría, cambia de equipo o continúa al año siguiente es,
simplemente, **otra fila**, sin vínculo formal entre ellas.

**Por qué:** encaja con la introducción manual (la plantilla se da de alta cada temporada) y con las
pantallas, que todas navegan con selector de temporada.

**Contrapartida asumida:** no hay identidad "persona" estable entre filas. Si algún día hiciera falta un
total de carrera multi-temporada, sería una extensión posterior.

---

### D-06 · Doble identificador: UUID interno **y** id externo de federación

**Decisión.** Las entidades con contrapartida federativa tienen **dos** identificadores, y no son
intercambiables:

| Entidad | PK interna | Identificador externo |
|---------|-----------|------------------------|
| `Season` | `id` (UUID) | `federation_season_id` |
| `Competition` | `id` (UUID) | `federation_competition_id` + `federation_group_id` |
| `Team` | `id` (UUID) | `federation_team_id` (`codigo_equipo`) |
| `OpponentClub` | `id` (UUID) | `federation_club_id` (del nombre del fichero del escudo) |

**Regla dura:** el identificador externo **nunca** es PK, **nunca** FK y **nunca** participa en un `JOIN`
interno. Dentro del *schema* se une siempre por UUID. Sirve exclusivamente para que la ingesta **reconozca**
a qué fila corresponde lo que llega de fuera.

**Por qué importa:** si la Federación cambiara su numeración, o si un endpoint dejara de traer un código, el
modelo **sigue en pie** — se degradaría la calidad del emparejamiento, no la integridad de los datos.

**Evidencia de granularidad** (qué identifica cada código): [Anexo de la Federación §F.3](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md).

---

### D-07 · La modalidad es dominio, no integración — y entra en la clave de `Team`

**Contexto.** La URL del calendario lleva `tipojuego`, con cinco valores cerrados (fútbol-11, -7, -5, sala,
playa). La tentación era tratarlo como un dato más de integración, junto a los ids opacos.

**Por qué no, argumento débil (estilo):** la modalidad **significa lo mismo en cualquier federación**; el
código `1` no. Es el mismo criterio de "portar" que separa `age_category` de `federation_competition_id`.

**Por qué no, argumento decisivo (corrección):** sin ella, la unicidad
`Team(opponent_club_id, category, letter, gender)` hace **colisionar** al "Infantil A masculino" de
fútbol-11 con el de fútbol-sala del mismo club, que son **equipos distintos** —distinta competición,
distinto `codigo_equipo`—. Un club con equipos en dos modalidades **no se podía representar**.

**Decisión.** Enumerado de dominio `modality` en `Competition` y `Team`; `modality` **entra en la clave
única** de `Team`. El código `tipojuego` **no se almacena en ninguna tabla**: se codifica al llamar, con el
mapa del catálogo de federaciones ([D-17]). La validación se amplía: un equipo solo participa en
competiciones de **su edad y su modalidad**.

---

### D-08 · División: tres campos explícitos en vez de `category_label`

**Contexto.** Al ver que un mismo equipo juega en divisiones distintas en temporadas distintas, surgió la
duda de si faltaba modelar la **división**.

**Respuesta:** `Team` **no la necesita** —y no debe tenerla—. La división es atributo de **dónde compite**,
no de **quién es**: un equipo que asciende sigue siendo el mismo, y el cambio ya queda registrado en que sus
**partidos** son de otra `Competition`. Lo confirma la evidencia: el mismo `codigo_equipo` en dos
divisiones ([Anexo de la Federación §F.3]).

**El problema real era otro y más peligroso:** `Competition` tenía un campo **`category_label`** que en el
ejemplo valía "Honor" —una **división**— mientras `Team.category` significa **categoría de edad**. Dos cosas
distintas con el mismo nombre en el mismo modelo: una trampa garantizada.

**Decisión.** Separar en tres campos explícitos: **`age_category`** (enumerado, el mismo que
`Team.category`), **`division_label`** y **`group_label`**.

**Beneficio adicional:** al ser `age_category` un enumerado y no texto libre, se puede **validar** que un
equipo solo participe en competiciones de su edad — imposible con una etiqueta libre.

**`division_label` se deja como texto libre a propósito:** los nombres varían por federación y por categoría
("Primera", "Preferente", "Honor", "Autonómica"…) y no forman un enumerado cerrado que podamos fijar hoy.
Lo mismo vale para `group_label` ("Grupo 1", "Grupo Único").

---

### D-09 · Goleadores de la liga: se ingieren, no se calculan

**Contexto.** La pantalla "LIGA" muestra el ranking de goleadores de toda la competición, incluidos jugadores
rivales — de los que **no tenemos plantilla**.

**Alternativa descartada:** modelar rosters y goles de rivales para poder calcularlo. Coste desproporcionado
y datos que nadie va a introducir a mano.

**Decisión.** Los provee el propietario de la liga vía API y se almacenan en `LeagueScorer`, **solo lectura**
y **no ligada a `Player`**. La vista derivada correspondiente lee de esta tabla, **no** de `Goal`.

---

### D-10 · Sanción por amarillas: tramos configurables por competición

**Decisión.** `CompetitionSanctionBracket` (`seq`, `yellow_from`, `yellow_to`) por competición — p. ej.
`0-5, 6-10, 11-13, 14-16…`. Sanción al alcanzar el `yellow_to` del tramo; "amarillas pendientes" = distancia
al siguiente umbral; reinicio de ciclo tras cumplir. Las **rojas** provocan sanción directa.

**Por qué configurable:** la regla varía por competición y por federación; codificarla sería garantizar que
está mal en algún caso.

**Nota:** al ser una tabla normal ligada a `competition_id`, una competición sin tramos simplemente no tiene
filas — nada que forzar en el esquema.

---

### D-11 · Zona de gol: partición exclusiva de tres valores

**Decisión.** `area_chica`, `area_penalti`, `fuera_area`, como **partición exclusiva**: cada gol tiene
exactamente una zona (o ninguna, porque el campo es opcional, [D-04]).

**Nota sobre los mockups:** los números de las pantallas de Stitch son **ilustrativos** y no siempre cuadran
entre sí (desgloses que no suman el total). El modelo trata cada dimensión de gol como atributo
independiente; no se intenta reproducir esa aritmética.

---

### D-12 · Copas y otras competiciones: sin entidades nuevas

**Decisión.** Una copa es, sencillamente, otra `Competition` dentro de la misma `Season`, con sus propias
`Round`/`Match`. **No hace falta ninguna entidad nueva.**

`StandingRow`, `LeagueScorer` y `CompetitionSanctionBracket` son tablas ligadas a `competition_id`: si una
copa de eliminatorias no tiene clasificación, no tendrá filas ahí. Los formatos de ronda (ida/vuelta,
eliminación directa) son variaciones de **cómo se generan y leen** `Round`/`Match`, no del modelo.

---

### D-13 · "Primer Equipo" y filiales: `category=senior` + `letter`

**Contexto.** Duda sobre los nombres de equipo que no siguen literalmente "categoría + letra".

**Decisión.** Se cubren con `category=senior`: **"Primer Equipo"** = `senior` + `letter` "A" (o sin letra);
**filial** = `senior` + `letter` "B". **No hace falta un campo de nombre especial.**

---

### D-14 · Minutos jugados: se registran, pero opcionales

**Decisión.** `Appearance.minutes?`, entrada manual y **no obligatoria** para contar una convocatoria o
participación. Registrarlo siempre exigiría una disciplina de datos que un club pequeño no va a sostener.

---

### D-15 · `StandingRow` agnóstica a la fuente; el *fallback* es cálculo, no formulario

**Contexto.** No todos los propietarios de liga publican clasificación por jornada.

**Decisión (modelo).** `StandingRow` es **agnóstica a la fuente**: vale igual ingerida que calculada. **No
cambia el modelo**; es tarea de la capa de ingesta.

**Decisión (contrato), posterior.** El *fallback* se resuelve como **cálculo propio desde `Match`**, no como
formulario en el backoffice. Así la tabla conserva **un único escritor** y no aparece la única casilla con
dos dueños en la matriz de propiedad ([D-21]).

---

### D-27 · `Participation` se elimina: la composición de la liga es derivada, no un hecho

**Problema.** El modelo llevaba una tabla pivote `Participation` (`competition_id`, `team_id`) para la N:N
`Competition`↔`Team`. Al revisar el modelo ya cerrado se constató que **ningún `participation_id` aparece en
ninguna parte**: no hay endpoint, ni DTO, ni campo en el spec OpenAPI que la referencie. Su único consumidor
era el filtro `?seasonId=` de `GET /v1/teams`.

**Por qué no era solo "código muerto".** La tabla no aportaba **ninguna información**:

1. **No tenía atributos propios.** Solo las dos FK. La única columna que la habría justificado —el
   `codigo_equipo`— se le negó explícitamente al comprobar que es **estable entre temporadas** y por tanto
   pertenece a `Team` ([Anexo de la Federación §F.3]).
2. **La ingesta descubre los equipos *desde* el calendario** (§3.7). Un equipo entra en el sistema porque
   aparece en un `Match`; no hay ninguna otra puerta. Así que `Participation` no podía contener una sola fila
   que `Match` no implicara ya: era un **índice de `Match`** mantenido a mano, con el coste de consistencia
   que eso conlleva y sin la garantía que da un índice de verdad.
3. **Había una segunda derivación equivalente** en `StandingRow` (`competition_id`, `team_id`), lo que
   confirma que el dato ya estaba dos veces antes de contar la tabla pivote.

**Alternativa descartada:** conservarla como **caché materializada** de la consulta. Se rechaza porque el
volumen no lo pide —una competición son ~20 equipos, y `GET /v1/teams` no está paginado por ser una colección
pequeña por club (§5.3)— y porque introduciría un segundo escritor que mantener sincronizado con `Match` en
cada sincronización, justo el tipo de deriva que [D-18] intenta evitar.

**Decisión.** Se elimina la entidad, su tabla, su `ParticipationRecord`, su migración y el `@Siblings` de
Fluent. La composición de la competición pasa a **vista derivada** (§3.4), como el rendimiento de equipo o los
goleadores: `DISTINCT` de `home_team_id` ∪ `away_team_id` sobre los `Match` de la competición, servida por
puerto de lectura (§4.5). Se añaden los índices compuestos `Match`(`competition_id`, `home_team_id`) y
(`competition_id`, `away_team_id`) que la sostienen (§4.6).

**Consecuencias que se reubican:**

- **La validación de [D-07]** —"un equipo solo compite en competiciones de su edad y su modalidad"— se
  aplicaba al insertar la `Participation`. Pasa a aplicarse **al insertar el `Match`**, que es donde equipo y
  competición se encuentran de verdad. No se pierde: cambia de sitio a uno mejor.
- **La redacción de [D-08]** ("su `Participation` apunta a otra `Competition`") se reformula sobre `Match`.
  El argumento —la división es atributo de *dónde compite*, no de *quién es*— queda intacto.
- **La decisión abierta de §4.2** sobre qué contiene `Competition` pierde una de sus tres patas.

**Lo que se asume a cambio.** Un equipo **inscrito pero sin calendario publicado** no aparecería como
participante. Pero hoy tampoco existiría como fila: la ingesta no tendría de dónde crearlo. No es una
regresión, es la misma limitación sin una tabla que aparentara cubrirla. Si alguna federación llegara a
exponer un endpoint de **inscripciones** independiente del calendario, eso sería una entidad **nueva y con
datos propios** (fecha de inscripción, estado, plaza), no la resurrección de este pivote vacío.

---

### D-28 · La temporada no se propaga: `season_id` solo donde es identidad, no atajo

**La pregunta era** si `season_id` debía bajar al resto de entidades del árbol —`Round`, `Match`,
`StandingRow`, `Goal`, `Card`, `Appearance`, incluso `Team`—, dado que `Player` ya lo lleva ([D-05]) y que
**todas** las pantallas navegan con selector de temporada (§3.6).

**Por qué la premisa engaña.** En `Player`, la temporada **no es denormalización: es identidad**. Una fila
*es* "un jugador en un equipo en una temporada", y como `Team` deliberadamente **no** tiene temporada (§3.2),
no existe ningún otro camino desde `Player` hasta `Season`: la columna es la **única** fuente. En `Round` o
`Match` sería lo contrario —un atajo derivable a **un salto** desde `Competition.season_id`—, así que [D-05]
no sirve de precedente. Tratar los dos casos como uno es justo lo que lleva a esparcir la columna por todo el
esquema.

**Decisión: no se propaga.** El árbol se recorre por sus FK. Entidad a entidad:

| Entidad | Veredicto | Razón |
|---------|-----------|-------|
| `Player` | **la lleva** (ya) | Identidad, no atajo — no hay otro camino ([D-05]) |
| `Team`, `OpponentClub` | **sería un error** | Son **estables entre temporadas** a propósito (§3.2): "Infantil A" es la misma entidad año tras año. Una columna ahí obligaría a duplicar filas por temporada y rompería el filtro `?seasonId=`, que es una **derivación por participación** ([D-27]) |
| `Goal`, `Card`, `Appearance` | **innecesaria** | Se consultan siempre vía `Player` o vía `Match`; y como `Player` ya es por temporada, **un `player_id` ya fija la temporada**. La estadística de jugador (§3.4) sale sin tocar `Season` |
| `Round`, `Match`, `StandingRow` | **defendible, pero no** | Ahorraría **un** *join* indexado contra `Competition`, tabla diminuta (una decena de filas por temporada) |

**Por qué el último caso no es [D-04].** Allí se denormalizaron los `team_id` de `Goal` porque el *join* era
contra la tabla **grande** y estaba en el camino caliente de **todas** las consultas de desglose. Aquí el
*join* es contra la tabla más pequeña del modelo. El criterio de [D-04] no se extiende por analogía de forma:
se extiende por volumen y frecuencia, y aquí no se cumplen.

**Alternativa descartada: columna plana en cada tabla para simplificar el purgado de temporada** ([D-24]).
No hace falta: con las FK en cascada el subárbol se recorre solo. El `?cascade=true` no era un argumento a
favor, sino una intuición sin coste real detrás.

**Regla que queda, para cuando vuelva a plantearse.** Toda columna denormalizada tiene un **problema de
escritor**: `Match` lo escribe la ingesta, que tendría que fijar `season_id` sin que nada garantice que jamás
contradiga a `Competition.season_id` — la deriva que [D-18] evita en integración, reintroducida en el esquema.
De ahí el criterio: **denormaliza solo si puedes hacer la deriva estructuralmente imposible.** En Postgres eso
se consigue con FK compuesta, no con disciplina en el código:

```sql
ALTER TABLE competitions ADD UNIQUE (id, season_id);
ALTER TABLE matches ADD FOREIGN KEY (competition_id, season_id)
  REFERENCES competitions (id, season_id);
```

Si la respuesta a "¿cómo evitas la deriva?" es "lo copiamos con cuidado en la capa de aplicación", la
denormalización no está justificada.

**Y si el *join* llegara a molestar,** la salida no es la columna sino un **modelo de lectura** (§4.5,
CQRS-lite), que el LLD ya prevé y que tiene una ventaja decisiva: **una vista no puede desviarse; una columna
copiada sí**.

**Lo que se asume a cambio.** Las consultas por temporada sobre `Round`, `Match` y `StandingRow` llevan un
*join* a `Competition`. Se acepta a cambio de que la temporada tenga **un solo lugar donde vive** por cada
camino del árbol.

---

## Integración

### D-16 · Las coordenadas de la federación son configuración tecleada, no descubrimiento

**Supuesto anterior, erróneo.** El diseño describía una "cadena de selección" recorrible programáticamente
—temporada → categoría+división → grupo → calendario— y dejaba pendiente "el ejemplo de esas llamadas".

**Esas llamadas no existen como API.** La cadena es la **navegación web** de la federación, para navegador y
ratón. Nadie —ni nosotros ni el club— sabe de antemano que su grupo es el `24037549`.

**Decisión.** La coordenada (cuatro parámetros, [Anexo de la Federación §F.1]) es **configuración que teclea un
administrador**, copiando la URL del navegador. `Season` y `Competition` dejan de ser "salida de la ingesta"
y pasan a ser su **entrada** ([D-22]).

**Consecuencia sobre otra decisión previa:** también cae la tesis de que `federation_group_id` era un
**identificador opaco** que envolvía categoría + división + grupo. La jerarquía viene **descompuesta en dos
ids** (`competicion` y `grupo`), confirmado por el usuario. La descomposición de dominio de [D-08] sigue
siendo necesaria, pero por *mostrar / validar / portar*, no por "hay que desempaquetar un valor opaco".

**Riesgo asumido y cómo se mitiga.** De cuatro números copiados a mano cuelga **todo** el árbol de datos, y
un dígito mal **no da error**: sincroniza otro calendario, en silencio. Mitigación en dos medidas ([D-22]):
pegar **la URL entera** (copiar de la barra de direcciones no admite errata) y un ***preview* que no
persiste** y enseña la lista de equipos para que un humano reconozca su club antes de guardar.

---

### D-17 · La federación es un catálogo en código, y hay una por tenant

**Contexto.** Al aparecer parámetros propios de cada federación (secuencial de temporada, código de
modalidad, URL base), la tentación es modelar una entidad `Federation` administrable desde el backoffice.

**Por qué no.** Dar de alta una federación **no la hace funcionar**: soportar una nueva exige **escribir un
adaptador** (ingeniería inversa de su API). Una fila sin código detrás produce una configuración que falla en
ejecución.

**Decisión.** La federación es un **catálogo en código** —enum + cliente HTTP + URL base + mapa de códigos de
modalidad—: sin tabla, sin endpoints, sin `POST`. Lo único que **sí** es dato es **cuál es la del club**:
`Club.federation`, fijado al aprovisionar.

**Corrección de un supuesto previo.** El LLD decía que había **un único proveedor** y que otras federaciones
serían una extensión futura. La versión correcta es más fuerte: **hay varias desde el día uno** (RFFM y
Cataluña ya están previstas), pero **una por club** — un club de Madrid compite en la RFFM y uno catalán en
la FCF; no son el mismo tenant. El aislamiento por *schema* hace el resto gratis.

**Escotilla prevista, no implementada.** Si algún día aparece un club con su equipo de sala en otra
federación, la salida es un `Competition.federation` opcional que sobrescriba al del club.

---

### D-18 · *Upsert* por tipo de campo: semilla, volátil, propiedad y emparejamiento

**El problema.** Si el BFF solo puede **corregir** datos ingeridos ([D-21]), esa corrección debe
**sobrevivir a la siguiente pasada**; si no, el `PATCH` es tan poco duradero como un `DELETE`. El caso
crítico es la reclamación de equipo propio: la ingesta ve `codigo_equipo = 821` y no debe volver a colgarle
un `OpponentClub`.

**Alternativa descartada:** marcar cada campo corregido (columna `..._overridden_at`, o un `jsonb` de
*overrides*). Coste alto en esquema y en código, para un problema que se resuelve por clases de campo.

**Decisión.** Regla por **tipo de campo**, sin banderas nuevas: descriptivo (solo INSERT), volátil (siempre),
de propiedad (nunca la ingesta) y de emparejamiento (solo la ingesta, solo al insertar). La tabla operativa
está en §3.7 del LLD.

---

### D-19 · Los escudos se descargan; la clave del objeto se deriva del `slug`

**Decisión 1 — descargar, no enlazar.** Las rutas de `escudo_*` son relativas al *host* de la federación. La
ingesta **descarga el fichero y lo guarda en Supabase Storage**; el modelo almacena la **clave del objeto**
(`crest_key`), no una URL. Dos razones: no depender de que un tercero siga sirviendo ese fichero, y **no
atarse a un dominio/bucket/CDN** — si cambia, se cambia la composición de la URL en la respuesta y no hay
migración de datos. La API compone la URL pública en el DTO.

**Decisión 2 — el nombre del fichero sale del `slug`, no del `federation_club_id`.** La tentación era
`crests/opponents/{federation_club_id}.png`, pero eso ataría un identificador **interno y permanente** al
valor de un sistema de terceros que puede no estar disponible (es una inferencia sobre un nombre de fichero,
[Anexo de la Federación §F.4]) ni ser estable. La clave se deriva del **`slug`**, generado al crear la fila a partir del
nombre y **inmutable** después. Así es legible (`crests/opponents/celtic-castilla.png`), no depende de la
Federación, y **sobrevive a las correcciones de nombre** — no porque se recalcule, sino porque **no se
recalcula nunca**: el fichero conserva su nombre original, algo desfasado pero estable y sin huérfanos. Un
slug interno no se muestra, así que que envejezca no molesta.

**Pendiente:** política de **refresco** del escudo.

---

### D-20 · Arranque en frío: reclamación de equipo propio como sub-recurso de estado

**Contexto.** En t=0 el club no tiene **nada**: ni equipos, ni escudos, ni rivales. Todo lo trae la ingesta —
y eso incluye **el equipo propio**, que aparece en la competición como los demás. Pero la ingesta **no puede
saber cuál eres**: los crea todos como rivales.

**Tensión.** Hace falta un acto explícito de reclamación, y choca con la regla de que el `PATCH` de `Team`
**no** puede cambiar `opponent_club_id` — regla que se mantiene, porque evita que un equipo cambie de bando
por un `PATCH` descuidado.

**Decisión.** Un **sub-recurso de estado dedicado**, `PUT`/`DELETE /v1/teams/{id}/ownership`, en la línea de
`/archive`. No es un cambio de campo sino una **orquestación**: al reclamar, el `OpponentClub` que la ingesta
había asignado resulta ser el club propio, así que de ahí salen el nombre y el escudo con los que rellenar
`Club`.

**Matiz posterior ([D-22]).** Al pasar el alta de competición a dos pasos, el administrador ve la lista de
equipos del grupo **antes** de sincronizar y puede marcar el suyo (`ownTeamFederationId`). Entonces la
ingesta lo crea **directamente como propio** y `/ownership` deja de ser el camino feliz: queda como
**mecanismo de corrección**, que es su sitio natural.

---

## Contrato de la API

### D-21 · El BFF corrige lo que la ingesta trae; nunca lo crea ni lo borra

**Contexto.** El modelo de datos es **común** al BFF y a la ingesta, pero actúan sobre él de forma distinta.
La versión anterior del contrato aplicaba la idea a medias: enunciaba "lo que crea la ingesta no se crea por
el BFF" y acto seguido abría dos excepciones, `POST /opponent-clubs` y `POST /teams`.

**Por qué la asimetría es real.** **Corregir es inocuo** frente al emparejamiento (la ingesta sigue
encontrando la fila por su `federation_*_id`). **Crear y borrar bifurcan la identidad**: una fila creada a
mano nace **sin código de federación**, así que la siguiente sincronización no la reconoce y **la duplica**;
una fila borrada que la federación sigue publicando **reaparece**.

**Por qué caen las dos excepciones:**

- **`POST /opponent-clubs`** se justificaba "para un amistoso". **Ese caso no existía:** un amistoso necesita
  un `Match`, que necesita `Competition` y `Round` que ninguna federación publica. El club rival dado de alta
  a mano no podía usarse para nada.
- **`POST /teams`** se justificaba para equipos fuera de competición federada. Además de (a) no poder tener
  partidos y (b) duplicarse al sincronizar, tenía un fallo terminal: al reclamar después la fila ingerida
  habría **dos equipos propios** con la misma categoría, letra, género y modalidad → **409 de la unicidad sin
  salida**. El alta manual no duplicaba: **bloqueaba el *onboarding***.

**Decisión.** Regla general, con matriz de propiedad operación a operación en §5.1 y **tres papeles** por
entidad: entrada de la ingesta, salida de la ingesta y dominio manual.

**Consecuencias asumidas:**
- `Team` y `OpponentClub` pierden `POST` y `DELETE`; para duplicados hace falta una **fusión** (pendiente).
- `Match` queda de **solo lectura** en el BFF: el detalle manual son sus **hijos** (`Goal`, `Card`,
  `Appearance`), no sus campos.
- **No hay amistosos.** Fuera de alcance, y es lo que retira el último argumento del `POST` de
  `OpponentClub`.

---

### D-22 · `Competition` es entrada de la ingesta: tiene `POST`, y el alta es en dos pasos

**Corrección de una decisión previa.** El contrato dejaba `Competition` **sin `POST`** "porque la crea la
ingesta al sincronizar — recorrer la cadena de selección es trabajo de la ingesta". **La premisa era falsa**
([D-16]): nadie descubre su grupo. Sin `POST` no hay forma de empezar.

**Decisión 1.** `Competition` recupera `POST`, `PATCH` y `DELETE`: es **configuración**, igual que `Season`.

**Decisión 2 — el alta es en dos pasos.** `POST /v1/competitions/preview` recibe la URL pegada, llama a la
federación **sin persistir nada** y devuelve modalidad, categoría, división, grupo, jornadas y **la lista de
equipos**; `POST /v1/competitions` confirma. Es **verificación**, no descubrimiento: no expone la navegación
de la federación, solo comprueba la coordenada ya elegida. Justificación del riesgo: [D-16].

**Decisión 3 — la coordenada admite dos formas.** URL pegada (vía del humano) **o** los tres campos
descompuestos (vía estable para semillas, *scripts* y tests, que no deben depender del formato de URL de un
tercero). Se almacenan siempre los campos; la URL no se guarda, se reconstruye.

**Decisión 4 — `PATCH` con guarda.** Los rótulos son siempre editables; las **coordenadas** solo mientras
`last_synced_at` sea nulo. Cambiarlas después es **repuntar a otro calendario** dejando los datos del
anterior colgando → 409, y la vía es borrar y recrear.

> **Matiz sobre la mutabilidad de identificadores externos.** La regla "las claves de emparejamiento son
> inmutables" vale para las de **salida** (`federation_team_id`, `federation_club_id`), que pone la ingesta.
> Las de **entrada** las teclea un humano, luego las erratas hay que poder corregirlas — con la guarda de
> arriba.

---

### D-23 · `Club` es un *singleton* sin `POST` ni `DELETE`

**Decisión.** `/v1/club` en **singular y sin `{id}`** — única excepción a la convención de plural. Hay
exactamente un registro por *schema* y el tenant lo determina el JWT, así que un `id` en la ruta sería
redundante y una colección `/v1/clubs` engañosa.

**Sin `POST` ni `DELETE`:** el alta de un club es **provisión** (crear el *schema* + migrar) y la baja es
*deprovisioning*; ambas viven en el **plano de control**, no en el BFF.

**Pero su contenido sí es dato de negocio editable**, no configuración de despliegue: `name`, `short_name`,
escudo y `settings` los consumen las apps y deben cambiarse desde el backoffice **sin redespliegue ni tocar
la BD a mano**. De ahí el `PATCH`. La distinción a retener: **el alta del club es configuración de
despliegue; su contenido no.**

---

### D-24 · Borrado físico de temporada: operación protegida en dos pasos

**Contexto.** Hay dos necesidades distintas y conviene no confundirlas: **archivar** (ocultar una temporada
vieja, reversible) y **purgar** (borrado físico, para *erasure* RGPD — datos de menores).

**Decisión.** Dos mecanismos separados: `PUT`/`DELETE /archive` (reversible, conserva datos) y
`DELETE ?cascade=true` (físico e irreversible), este último **en dos llamadas**:

1. `GET …/purge-preview` → impacto por entidad + `confirmationToken` opaco, de un solo uso y corta vida.
   Sirve además de **ancla de auditoría**: deja constancia de qué se mostró antes de confirmar.
2. `DELETE …?cascade=true` con el token en `If-Match` como **precondición** → **428** si falta, **412** si
   está caducado o no corresponde.

**Consecuencia detectada después.** La purga debe además **archivar la temporada**, o parte de lo borrado
**vuelve**: los datos personales son manuales y no reaparecen, pero `Match` y `StandingRow` los sigue
publicando la federación y la siguiente pasada los repuebla.

**Pendiente (§9):** la **política** de retención (plazos, qué se archiva y cuándo se purga). El *mecanismo*
ya está.

---

### D-29 · La clasificación no es un campo de `Round`: es una capacidad de la federación

**Contexto.** Al redactar `RoundResponse` se le puso un `hasStandings` —"¿hay clasificación para esta
jornada?"— pensando en que la app decidiera si pintaba la pestaña.

**Por qué se descarta.** Por [D-15] la clasificación **existe siempre**: si la federación no la publica, se
calcula desde `Match`, y ese *fallback* no es un modo degradado sino la vía normal. Un campo cuya respuesta
es constantemente `true` **no informa**: induce al cliente a escribir una rama que no se ejecuta nunca — o,
peor, que se dispara a principio de temporada, cuando aún no hay partidos jugados, y esconde una pestaña que
debería estar ahí. La web **siempre** muestra clasificación.

**La pregunta que sí era real** no era "¿hay?" sino "¿es **oficial** o la hemos calculado nosotros?". Es un
dato de **procedencia** (§3.7), y la observación que la desbloquea llegó después: **la RFFM publica
clasificación y la FCF no** ([Anexo de la Federación §F.6]). O sea que **la varianza es entre federaciones**,
no entre competiciones ni entre jornadas.

**Alternativa intermedia, también descartada: `Competition.standingsSource`.** Parecía el nivel natural
—hermano de `last_synced_at`—, pero como hay **una federación por tenant** ([D-17]), dentro de un *schema*
todas las competiciones tendrían **el mismo valor**: una columna constante repetida en cada fila. Es
exactamente la redundancia que [D-28] acaba de rechazar, y por el mismo motivo.

**Decisión.** La capacidad vive en el **catálogo de federaciones en código** ([D-17]), que pasa así a
describir **qué sabe hacer** cada proveedor y no solo sus coordenadas. Al contrato sale **una sola vez por
tenant**, derivada y `readOnly`: `ClubResponse.federationProvidesStandings`. Su consumidor es el
**backoffice**, para rotular "clasificación calculada" y que el administrador no la confunda con la oficial;
las apps de consulta pueden ignorarla.

**Lo que se asume a cambio.** Si alguna federación llegara a publicar clasificación en unas competiciones sí
y en otras no, el booleano por club se quedaría corto y habría que bajarlo a `Competition`. Se acepta: hoy no
hay ni un solo caso observado, y bajarlo entonces es añadir una columna, no rehacer el contrato.

---

## Documentación

### D-25 · El *spec* OpenAPI es la fuente de verdad campo a campo

**Problema.** §5.2 listaba los DTOs como `struct` Swift completos, campo a campo, **duplicando** el spec
OpenAPI. Al aplicar un cambio de diseño había que editar los mismos campos en dos sitios; la divergencia era
cuestión de tiempo.

**Decisión.** §5.2 conserva las **convenciones y decisiones** de DTOs (que cruzan la frontera, `PATCH`
parcial, qué es derivado, por qué no existe `CreateTeamRequest`) y **un ejemplo ilustrativo**; el detalle
campo a campo vive en `backend/openapi/openapi.yaml`.

**Refuerzo:** la frontera de propiedad ([D-21]) se expresa en el spec de forma **comprobable por máquina** —
`readOnly: true` en los campos de la ingesta y **ausencia del esquema de alta** en las entidades de salida—,
no solo en prosa.

---

### D-26 · El LLD se queda con lo normativo; deliberación y evidencia van a anexos

**Problema.** El LLD llegó a **17.447 palabras** mezclando tres géneros: especificación, deliberación
("opción A vs B, se elige A porque…") y observación de un sistema de terceros (muestras JSON). Tres
secciones —§3.6, §3.7 y §5.1— acumulaban el **43 %** del documento, y en ellas la parte normativa era
minoritaria.

**Alternativa descartada:** el corte **vertical** que el propio documento preveía (§3–§4 → `LLD-BBDD`, §5 →
`LLD-API`). No arreglaba el problema —cada mitad seguía siendo un cajón de sastre—, rompía **451 referencias
`§x.y`** repartidas por el LLD, el spec y el ADR, y separaba lo que el documento argumenta que va junto.

**Decisión.** Corte **horizontal**, por naturaleza del contenido: el LLD conserva lo **normativo** (no
renumera nada, ninguna referencia se rompe), este anexo recoge el **porqué** y el [Anexo de la Federación] la **evidencia**.

**Criterio para lo que venga:**

- ¿Lo necesita alguien **para escribir el código**? → **LLD**.
- ¿Es la razón por la que se **descartó otra opción**? → **Anexo de Decisiones**.
- ¿Es una **observación sobre un sistema de terceros**? → **Anexo de la Federación**.

Tres señales de que algo **no** es LLD aunque lo parezca: una **tabla de opciones con veredicto**, una
narrativa **"resuelta: antes pensábamos X"**, o un **volcado JSON**.

**Pendiente:** el corte vertical sigue disponible para cuando §5 crezca con el resto de entidades
(`Match`, `Player`, `Goal`, `Card`, `Appearance`, `Absence`, `StandingRow`…). Se hará sobre un documento ya
limpio.

---

*Referencias `§x.y` → [API_y_BBDD LLD-001](./API_y_BBDD%20LLD-001.md) · Evidencia → [Anexo de la Federación](./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md)*

<!-- Definiciones de enlace -->
[D-04]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-05]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-07]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-08]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-16]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-17]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-18]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-21]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-22]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-24]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-26]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-15]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-27]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-28]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-29]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[Anexo de la Federación]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.1]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.3]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.4]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.6]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
