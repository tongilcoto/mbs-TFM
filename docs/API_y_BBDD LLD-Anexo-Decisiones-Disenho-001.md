# Anexo de Decisiones · Bitácora de decisiones de diseño

- **Estado:** vivo — se añade una entrada cada vez que se descarta una alternativa
- **Fecha:** 2026-08-14
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
| **D-30** | El calendario nace provisional: fecha y hora separadas, confirmación derivada | §3.2, §3.7, §4.1, §5.1 |
| **D-31** | `federation_match_id` se modela, pero la ingesta no puede depender de él | §3.2, §3.5, §3.7 |
| **D-33** | `previous_position` se almacena: la fila entera ya es un *snapshot* | §3.2, §5.1 |
| **D-35** | La foto del jugador es una clave de Storage, no una URL — y entra saneada por la API | §3.2, §5.1, §5.2 |
| **D-38** | `Absence.active` no es columna: la disponibilidad es una pregunta con fecha | §3.2, §4.1, §5.1, §5.2 |
| **D-39** | Dos ausencias activas sí, dos del mismo tipo no | §3.2, §3.5, §4.6 |
| **D-41** | La convocatoria que no está no es "no convocado": ausencia de fila ≠ estado | §3.2, §3.3, §5.1, §5.2 |
| **D-42** | `minutes` solo tiene sentido jugando, y nulo no es cero | §3.2, §4.6, §5.1, §5.2 |
| **D-45** | Una fila es una sanción, no una cartulina: la doble amarilla es *una* roja | §3.2, §3.3, §3.5, §4.6, §5.1, §5.2 |
| **D-46** | La tarjeta no exige convocatoria: dos registros manuales independientes | §3.2, §5.1 |
| **D-52** | El gol en propia puerta: se guarda su autor, pero no le suma | §3.2, §3.3, §3.6, §4.6, §5.1, §5.2 |
| **D-48** | El ranking de goleadores no tiene *fallback*, y su capacidad sí condiciona el dato | §3.2, §5.1, §5.2 |
| **Integración** | | |
| **D-16** | Las coordenadas de la federación son configuración tecleada, no descubrimiento | §3.7, §5.1, §5.6 |
| **D-17** | La federación es un catálogo en código, y hay una por tenant | §3.2, §3.6 |
| **D-18** | *Upsert* por tipo de campo: semilla, volátil, propiedad y emparejamiento | §3.7 |
| **D-19** | Los escudos se descargan; la clave del objeto se deriva del `slug` | §3.7 |
| **D-20** | Arranque en frío: reclamación de equipo propio como sub-recurso de estado | §3.6, §5.1 |
| **D-55** | La capacidad de clasificación es «¿por jornada?», no «¿publica?» | §3.6, §3.7, §5.1, §5.2 |
| **D-56** | «Volátil» no es «pisar siempre»: la fuente solo gana cuando dice algo | §3.7, §5.6 |
| **D-57** | El acta entra como fuente de estado, y solo para los partidos del club | §3.3, §3.7, §5.6 |
| **Contrato de la API** | | |
| **D-21** | El BFF corrige lo que la ingesta trae; nunca lo crea ni lo borra | §5.1 |
| **D-22** | `Competition` es entrada de la ingesta: tiene `POST`, y el alta es en dos pasos | §5.1 |
| **D-23** | `Club` es un *singleton* sin `POST` ni `DELETE` | §5.1 |
| **D-24** | Borrado físico de temporada: operación protegida en dos pasos | §5.4 |
| **D-29** | La clasificación no es un campo de `Round`: es una capacidad de la federación | §3.7, §5.1, §5.2 |
| **D-32** | `MatchResponse` embebe los equipos: proyección, no referencia ni expansión | §5.2, §5.3 |
| **D-34** | La clasificación es un modelo de lectura: sin acceso por id, con la racha dentro | §3.4, §4.5, §5.1 |
| **D-36** | Borrar un jugador no pregunta por su historial: *soft delete* sin guarda de dependientes | §3.5, §4.6, §5.1 |
| **D-37** | La plantilla es un hecho de (equipo, temporada): ámbito obligatorio e identidad inmutable | §3.2, §5.1, §5.2, §5.3 |
| **D-40** | Dar de alta a un lesionado es un `PATCH`: cuándo un sub-recurso de estado está justificado | §5.1, §5.2, §5.3 |
| **D-43** | Las dos puertas de `Appearance` son excluyentes, no acumulables | §5.1, §5.3 |
| **D-44** | La convocatoria se registra fila a fila: sin alta masiva, por ahora | §5.1 |
| **D-47** | Cuándo dos puertas de ámbito se combinan: la regla que faltaba | §5.1, §5.3 |
| **D-49** | Lo que decide la paginación es el techo, no el ámbito | §5.1, §5.3 |
| **D-50** | Los tramos de sanción se escriben como conjunto: cuándo el lote sí es la respuesta | §3.2, §5.1 |
| **D-51** | El cuerpo son umbrales, no tramos: lo derivable es la relación entre filas | §3.2, §5.1, §5.2, §5.3 |
| **D-53** | El marcador manda y los goles no lo contradicen: sin validación de cuadre | §3.6, §5.1 |
| **D-54** | La denormalización de `Goal` no llega al DTO: se escribe quién marca | §3.2, §5.1, §5.2 |
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

### D-30 · El calendario nace provisional: fecha y hora separadas, confirmación derivada

**El hecho de dominio que lo motiva.** Un calendario federado **no se publica cerrado**. Al arrancar la
temporada, la federación reparte los partidos por jornadas con una **fecha por defecto —el sábado— y sin
hora**; el horario real de cada jornada se fija el **domingo anterior, al cierre**, y ahí la fecha puede
además desplazarse a domingo. Es decir: durante la mayor parte de su vida, un partido tiene una fecha que es
una **conjetura del propio proveedor** y ninguna hora.

**Lo que había.** `Match.kickoff_at`, un `timestamptz` único, heredado de modelar el partido como si su
fecha-hora fuese un dato cerrado desde el principio. Con la observación de arriba, ese campo solo puede
guardar una de dos mentiras: un `00:00` de relleno indistinguible de la medianoche real, o un `NULL` que se
lleva por delante también la fecha —que sí se conoce y sí hay que pintar—.

**Alternativas consideradas:**

| Opción | Por qué se descarta |
|--------|---------------------|
| `kickoff_at` + `kickoff_time_known` (bool almacenado) | Resuelve la ambigüedad, pero el `00:00` sigue ahí y la bandera **puede contradecirlo**: nada impide `known = true` sobre un timestamp de relleno. Una columna más, un `CHECK` más y dos campos que hay que leer juntos para entender uno |
| `kickoff_at` anulable, a secas | Pierde la fecha, que es justamente lo que la app necesita para ordenar el calendario y pintar "18 MAY · VS" |
| `schedule_status` como enumerado (`provisional`/`confirmado`) | El estado **no aporta información nueva**: es exactamente "¿hay hora?". Almacenarlo crea un segundo escritor que puede desviarse del dato que describe — la deriva que [D-18] evita en integración |

**Decisión.** Dos columnas: **`match_date`** (obligatoria) y **`kickoff_time`** (anulable). La confirmación
se **deriva en lectura** (`is_kickoff_confirmed` = hay hora), como `Season.isCurrent`, `Team.isOwn` o
`Round.isCurrent`. En el dominio se encapsulan en el VO `Kickoff` (§4.1) para que la regla viva en un sitio y
no la reimplemente cada consumidor.

**El matiz que da nombre al campo: confirmado no es inmutable.** Que la federación haya publicado franja no
significa que el partido no se mueva — una inundación, un campo inutilizable o cualquier causa mayor lo
aplaza o lo reprograma, y el horario puede **volver a provisional**. Por eso:

- `match_date` y `kickoff_time` son **campos volátiles** en la política de *upsert* (§3.7): la sincronización
  los pisa **siempre**, también los ya confirmados. Tratarlos como "semilla" —escribir solo en el INSERT—
  habría congelado el calendario en su versión provisional, que es el peor resultado posible.
- El derivado se llama `isKickoffConfirmed` y **no** `isKickoffFinal`. La diferencia no es cosmética: un
  cliente que leyera "final" cachearía el horario, y un cliente que lee "confirmado" sabe que su copia
  caduca en la siguiente sincronización.
- Como `Match` no tiene `PATCH` ([D-21]), **nadie puede corregirlo a mano**: el único camino de vuelta es la
  ingesta. Es coherente con la regla del BFF, pero conviene tenerlo presente — si la federación se equivoca
  en un horario, la app se equivoca con ella hasta la siguiente pasada.

**Consecuencia fuera del modelo.** El hito semanal (domingo al cierre) **ancla la cadencia de
sincronización** (§5.6): el mínimo es una pasada el lunes, y el intervalo no puede superar la semana o la app
mostraría horarios provisionales de partidos ya jugados. Es la primera pieza concreta del contrato de ingesta
que no dependía de observar una muestra nueva.

**Lo que se asume a cambio.** Ordenar el calendario es ordenar por **dos columnas** con `NULLS LAST`, no por
una (§5.1), y el cliente lee dos campos donde antes leía uno. A cambio, el modelo no guarda ni un solo valor
inventado.

---

### D-31 · `federation_match_id` se modela, pero la ingesta no puede depender de él

**El punto de partida.** Las cuatro muestras del objeto de partido traen `codacta`, el identificador del acta
([Anexo de la Federación §F.2]), y el anexo lo tenía anotado como "candidato natural a clave externa de
`Match`, no modelado aún". Al escribir el contrato de `Match` toca resolverlo.

**Por qué modelarlo.** El *upsert* de la ingesta necesita reconocer un partido ya visto. Sin identificador
externo, la única clave son las **coordenadas** (jornada, local, visitante) — y [D-30] acaba de establecer
que **la fecha se mueve cada semana**, así que cualquier emparejamiento que la incluyera duplicaría partidos
sistemáticamente. Un identificador estable del proveedor es exactamente lo que [D-06] previó para este caso.

**Por qué no puede ser obligatorio, y ahora está confirmado.** `codacta` es un campo **de la RFFM**, no del
contrato genérico de "federación". El catálogo en código ([D-17]) ya soporta dos proveedores que **difieren
en capacidades** ([D-55]), y la observación posterior lo zanjó: **la FCF no tiene identificador de partido
en absoluto** ([Anexo FCF §C.3]) — hay que emparejar por *(temporada, competición, grupo, jornada, local,
visitante)*. Dar por hecho que todos publican un identificador de acta sería repetir el error que [D-29]
corrigió: elevar una particularidad de un proveedor a
invariante del modelo. Además, la clave puede faltar **dentro** de la propia RFFM en respuestas parciales.

**Decisión.** `Match.federation_match_id`, **anulable**, único (con `NULL` que no comparan iguales, §3.5),
propiedad de la ingesta, `readOnly` en el DTO — mismo trato que `federation_team_id` y `federation_club_id`.
Y una **cadena de emparejamiento de dos pasos** (§3.7): el identificador si viene; si no, las coordenadas
(`round_id`, `home_team_id`, `away_team_id`), que pasan a ser **índice único** para poder serlo de verdad.

**En qué se diferencia de la cadena de equipos, y por qué importa.** La de equipos tiene un tercer escalón
—"alta nueva marcada para revisión manual"— porque su segundo paso, el nombre normalizado, es **inexacto**.
Aquí no hace falta: el segundo paso son FK internas ya resueltas —cuando se llega al partido, sus equipos ya
están emparejados—, así que **siempre existe y siempre es exacto**. La degradación no pierde fiabilidad,
solo robustez ante un cambio de jornada por parte de la federación.

**Alternativa descartada: no modelarlo y emparejar solo por coordenadas.** Es más simple y funcionaría el
99 % de las veces, pero deja el sistema sin defensa ante el caso que sí ocurre —la federación reubica un
partido en otra jornada—, que crearía un duplicado sin forma de detectarlo. Modelar el campo cuesta una
columna anulable; no modelarlo cuesta una operación de fusión que aún no existe (§9).

**Alternativa descartada: exponerlo como capacidad del catálogo**, al estilo de
`federationProvidesRoundStandings` ([D-29]). Se rechaza porque **no tiene consecuencia visible para el cliente**:
que el emparejamiento use una clave u otra no cambia nada de lo que la app pinta. La capacidad de
clasificación sí se expone porque el usuario ve la diferencia (oficial vs calculada). Este queda como
detalle del adaptador.

**Lo que se asume a cambio.** Dos caminos de emparejamiento que mantener y probar en vez de uno, y un campo
que en algunas federaciones estará siempre vacío.

---

### D-33 · `previous_position` se almacena: la fila entera ya es un *snapshot*

**La objeción de partida es legítima.** `StandingRow.previous_position` —la columna PREV del mockup— es la
posición de ese mismo equipo en la jornada anterior, y esa fila está en la misma tabla. Según la regla que
fijó [D-28], **denormaliza solo si puedes hacer la deriva estructuralmente imposible**, y aquí no se puede:
nada en el esquema impide que el PREV de la jornada 22 contradiga al `position` de la jornada 21.

**Por qué la regla no aplica, aunque lo parezca.** [D-28] protege **tablas de hechos** de una copia que puede
desviarse de su origen. `StandingRow` no es una tabla de hechos: es un ***snapshot* derivado de principio a
fin**. `played`, `won`, `drawn`, `lost`, `goals_for`, `goals_against` y `points` **también** salen de `Match`
—de hecho, cuando la federación no publica clasificación, la calculamos entera desde ahí ([D-15])—. Si se
aceptan esas siete columnas derivadas, singularizar la octava por ser derivable **de la propia tabla** en vez
de otra es una distinción sin diferencia. La pregunta correcta no es "¿es derivable?" —lo es todo—, sino
"¿qué escritor la produce?", y la respuesta es **uno solo**: la ingesta.

**El argumento que cierra la discusión: el alta a mitad de temporada.** Un club puede dar de alta una
competición en **marzo**. La ingesta trae entonces el calendario y la clasificación desde ese punto, y la
jornada 22 es **la primera fila que existe**. Derivar el PREV exigiría una fila de la jornada 21 que
**nunca se va a ingerir**. Y el modo de fallo es el peor posible: si además faltara una jornada intermedia,
la derivación cogería la 20 creyéndola la 21 y **mentiría sin avisar** — un dato incorrecto es peor que un
dato ausente.

**Alternativas descartadas:**

| Opción | Por qué se descarta |
|--------|---------------------|
| Derivar de la jornada N−1 | El caso del alta a mitad de temporada la deja sin datos, y un hueco en la cadena la hace mentir en silencio |
| Derivarla y *cachearla* | Dos escritores para la misma columna, que es exactamente lo que se quería evitar |
| No exponer PREV | El mockup la pinta: es información real de la pantalla de clasificación, no un adorno |

**Decisión.** Columna `previous_position`, **anulable**. Nula en la primera jornada de una competición y en
la primera jornada ingerida de un alta tardía; el cliente pinta "–", que es lo que ya hace el mockup. Cuando
la federación la publica, se ingiere; cuando la clasificación se calcula ([D-15]), sale gratis de calcular
las jornadas en orden.

**Lo que se asume a cambio.** Una columna que en teoría podría contradecir a la fila de al lado. Se acepta
porque el único escritor es la ingesta y porque la alternativa —una derivación que falla justo en el caso de
negocio real (alta a mitad de temporada)— es peor.

---

### D-35 · La foto del jugador es una clave de Storage, no una URL — y entra saneada por la API

**El modelo la traía mal desde el primer borrador.** §3.2 declaraba `Player.photo_url`, mientras que el
escudo del club era `crest_key` — la clave del objeto en Storage, no una dirección ([D-19]). Dos campos con
la misma función y forma opuesta en la misma tabla de entidades.

**La incoherencia no es de estilo.** Un `photo_url` de texto libre significa que la foto **vive donde la haya
puesto quien la pegó**: Google Fotos, WhatsApp, el servidor del club anterior. Y lo que se está alojando ahí
es la **cara de un menor**, en un producto cuya región de despliegue se eligió por el RGPD (ADR). Con la
clave, el fichero está en el Storage del tenant, se borra con él y no lo sirve nadie más.

| Opción | Por qué se descarta |
|--------|---------------------|
| `photo_url` de texto libre | Aloja datos personales de menores fuera del control del producto; el purgado ([D-24]) borra la fila y deja la foto donde estaba |
| Clave + URL pública permanente | Un identificador adivinable expone las fotos de la plantilla a quien no tiene token |
| **Clave + URL firmada de vida corta** | **Elegida** |

**Decisión.** En BD, `photo_key` (anulable). En el contrato, `photoUrl` **derivada y `readOnly`**: el
servidor firma una URL de vida corta al responder. El cliente la usa, no la cachea. Es exactamente el
reparto de [D-19] para el escudo, con un requisito extra —la firma— que allí no hacía falta: un escudo es
público, una foto de un chaval de doce años no.

**Por dónde entra el fichero: `PUT /v1/players/{id}/photo`, y no el `POST`.** La foto la sube un humano
desde su portátil, así que el contrato tiene que recibir un binario en algún sitio. Tres formas posibles:

| Opción | Por qué se descarta |
|--------|---------------------|
| El fichero **dentro del `POST`** (`multipart` con los campos) | La clave del objeto se deriva del `playerId`, que **no existe hasta que el alta responde**; y un fallo a mitad de subida tumbaría el alta entera, obligando a reteclear el formulario. Además **no ahorra el segundo endpoint**: reemplazar la foto de un jugador ya creado lo necesita igual |
| **Subida directa a Storage** con URL prefirmada | Es lo que más ahorra al servidor, y es exactamente lo que **no se puede hacer aquí** — ver abajo |
| **`PUT` a un sub-recurso**, cuerpo en crudo | **Elegida** |

**El argumento que decide no es de arquitectura, es el mismo de la decisión: el EXIF.** Una foto hecha con
un móvil lleva metadatos con la **geolocalización** de dónde se tomó — la de un menor, típicamente su casa
o su campo de entrenamiento. Si el navegador escribe directamente en Storage con una URL prefirmada, ahí
queda el fichero **tal cual**, y la URL firmada lo sirve con sus coordenadas dentro. Habría cerrado la
puerta del alojamiento (que era el problema de partida) dejando abierta la ventana de los metadatos.

Al pasar por la API, el servidor **valida los bytes contra el `Content-Type` declarado** (no la extensión:
un `.pdf` renombrado se rechaza), **recodifica a JPEG**, **redimensiona** al lado que pide la ficha y
**descarta el EXIF**. Escribir en Storage deja de ser transportar un fichero ajeno para ser producir uno
propio.

**Detalles que quedan fijados con ella:** cuerpo `image/jpeg` o `image/png` (los dos formatos que produce
cualquier portátil), tope de **5 MB** (**413** si se supera, **415** si el tipo no está admitido), clave
derivada `players/{playerId}.jpg`, y `DELETE` del mismo sub-recurso para quitarla — porque un `null`
explícito en un campo **derivado** del `PATCH` no significaría nada (mismo criterio que `/ownership`).

**Lo que se asume a cambio.** El binario **pasa por Vapor**, con su coste de memoria y ancho de banda en un
contenedor pequeño (ADR: tope de 20 $/mes). Se acepta porque el volumen es ridículo —~25 fotos por equipo,
subidas una vez por temporada— y porque es el **único punto** donde se puede sanear el fichero. Si algún día
el volumen cambiara, la salida no es la URL prefirmada sino un *worker* de post-proceso; el saneado no es
negociable. Y que el borrado lógico de un jugador ([D-36]) **no borra el objeto**: sigue en Storage hasta el
purgado de temporada ([D-24]), que es coherente con que el borrado sea recuperable.

---

### D-38 · `Absence.active` no es columna: la disponibilidad es una pregunta con fecha

**El modelo lo traía como bandera.** §3.2 declaraba `Absence.active` junto a las tres fechas. Es la cuarta
vez que aparece el mismo patrón —`is_own` ([D-03]), `is_current`, `is_kickoff_confirmed` ([D-30])— y se
resuelve igual: **una columna que puede contradecir a los datos de los que se deduce no debe existir**.

**Decisión.** `active` desaparece de la tabla. `isActive` se **deriva en lectura**: la ausencia está en curso
si **no tiene `actual_return_date`** y **su `start_date` ya llegó**.

**La segunda condición no es un adorno.** Con solo la primera, una baja apuntada por adelantado —"el
sábado empieza a cumplir sanción"— contaría como activa desde el momento de teclearla. Con las dos, **pasa
sola** a activa el día que toca y **sin que nadie la toque**, que es lo mismo que ya hace `Season.isCurrent`.
El precio es que `isActive` **depende del día en que se pregunta**: el Dominio la resuelve con el `Clock`
inyectado (§4.3), no con `Date()`, y por eso es testeable sin I/O (§8.1).

| Opción | Por qué se descarta |
|--------|---------------------|
| Columna `active` mantenida por la aplicación | Se desincroniza en cuanto alguien escribe la fecha de alta por otra vía (una migración, una corrección manual, el purgado) |
| Columna `active` con *trigger* | Segundo escritor para el mismo hecho, y lógica de dominio dentro de la BD |
| **Derivarla de las fechas** | **Elegida** |

**Consecuencia en el contrato:** el filtro `?active=true` de `GET /v1/absences` se resuelve sobre ese mismo
criterio, no sobre una columna indexable. Es una comparación de fechas sobre un conjunto ya acotado por el
ámbito (§5.1), así que no necesita índice propio.

**Y una que se decide aquí para no repetirla:** `PlayerResponse` **no lleva `isAvailable`**. Sería el mismo
dato derivado por segunda vez y con otra consulta; la plantilla pide
`GET /v1/absences?teamId=&seasonId=&active=true` y cruza por `playerId`. Una llamada más para toda la
plantilla, no una por jugador.

---

### D-39 · Dos ausencias activas sí, dos del mismo tipo no

**La pregunta.** ¿Puede un jugador tener varias ausencias abiertas a la vez?

**Sí, y el modelo tiene que admitirlo:** lesionado **y** sancionado simultáneamente es un estado real —la
sanción corre mientras se recupera— y son dos periodos con causas, fechas y altas distintas. Colapsarlos en
uno perdería información que la ficha muestra.

**Pero dos del mismo tipo, no.** Dos lesiones abiertas a la vez no son dos lesiones: son una que **nadie
cerró**. El modelo no las distingue —`Absence` no tiene descripción, solo tipo y fechas—, así que la segunda
fila no aporta un hecho nuevo, solo ruido que deja al jugador no disponible para siempre.

**Decisión.** Índice único **parcial**: `UNIQUE (player_id, type) WHERE actual_return_date IS NULL` (§3.5).
→ **409** en el `POST`, y también en el `PATCH` que reabre una baja antigua teniendo otra abierta. Es la
segunda unicidad parcial del modelo, después de la del dorsal ([D-36]), y por el motivo opuesto: allí para
**no contar** filas borradas, aquí para **contar solo** las abiertas.

**Por qué como índice y no como validación en la aplicación:** [D-28] fijó el criterio —una invariante se
lleva al esquema **cuando se puede hacer estructuralmente imposible**—. Esta se puede, así que se hace.

**Lo que se asume a cambio.** El caso raro de dos ausencias solapadas de tipo `otro` (un viaje de estudios
que se cruza con un asunto familiar) queda bloqueado. Si apareciera de verdad, la salida es **un valor nuevo
en el enumerado**, no relajar el índice: un tipo que necesita solaparse consigo mismo es un tipo que en
realidad son dos.

---

### D-41 · La convocatoria que no está no es "no convocado": ausencia de fila ≠ estado

**La pregunta, que parece de detalle y no lo es.** `Appearance.status` tiene un valor `no_convocado`. Si un
jugador de la plantilla **no tiene fila** para un partido, ¿es lo mismo?

**No, y confundirlos rompería la estadística.** `status = no_convocado` es un **hecho** —estaba disponible
y el entrenador no lo llamó— y **cuenta**; que no haya fila significa que **nadie lo apuntó** y **no
cuenta**.

Si la ausencia de fila significara `no_convocado`, un club que se salta tres jornadas —lo normal en fútbol
base— vería a toda su plantilla acumulando "no convocado" sin que nadie lo decidiera: el dato que falta se
convertiría en un juicio sobre el entrenador. Y obligar a crear las ~18 filas de cada partido exigiría una
disciplina que [D-14] ya dio por perdida.

**Decisión.** La lista **devuelve solo las filas registradas**. El cliente que pinte la convocatoria entera
cruza con `GET /v1/players?teamId=&seasonId=` por `playerId`, el mismo cruce que ya hace con las ausencias
([D-38]). La razón es la misma: **el servidor no inventa filas que nadie escribió**.

**Corolario en el borrado.** `DELETE` (lógico) y marcar `no_convocado` **no son intercambiables**, y el
backoffice tendrá los dos gestos cerca — mismo aviso que [D-40] dio para `Absence`. Marcar registra un
hecho; borrar deshace un apunte erróneo y devuelve la fila al estado *sin registrar*.

**Y la relación con `Absence`**, que es la otra confusión posible. Los enumerados se solapan a propósito
(`baja_medica` ~ `lesion`/`enfermedad`) y **ninguno se deriva del otro**: `Absence` es un **periodo** —de
ahí el distintivo NO DISPONIBLE— y `Appearance` un **hecho por partido** —de ahí los recuentos—.

Un lesionado de baja larga genera **una** `Absence` y **tantas** `Appearance` como partidos se pierda.
Derivar lo segundo cruzando fechas se descarta por lo mismo que [D-15] y [D-10]: metería un **segundo
escritor** en una tabla de dominio manual, y encima uno que se equivocaría —una baja puede empezar el sábado
por la tarde y un partido aplazado no se juega el día que dice el calendario—.

---

### D-42 · `minutes` solo tiene sentido jugando, y nulo no es cero

**Dos preguntas que van juntas.** ¿Qué son los minutos de quien no fue convocado? ¿Y los de quien jugó pero
nadie cronometró?

**La primera no tiene respuesta buena si el campo es libre.** Un `no_convocado` con `minutes = 0` se lee de
dos maneras —"no jugó" y "jugó cero minutos"— y las dos se cuelan en el promedio con resultados distintos.
La segunda ya la contestó [D-14].

**Decisión.** `minutes` es **válido solo con `status = jugado`**, y **opcional incluso entonces**. Los tres
estados posibles del campo, y lo que significan:

| `status` | `minutes` | Lectura |
|----------|-----------|---------|
| `jugado` | `67` | Jugó 67 minutos |
| `jugado` | `null` | **Jugó, no se apuntó cuánto** |
| cualquier otro | `null` | No jugó |
| cualquier otro | un número | **422** |

En el `PATCH`, bajar de `jugado` a otro estado **exige mandar `minutes: null` en la misma llamada** — el
`null` explícito que ya es la convención del contrato (§5.2). No se limpia solo: un borrado implícito en
cascada dentro de un `PATCH` parcial es justo el tipo de efecto lateral que el cliente no ve venir.

**La consecuencia para quien calcule:** `null` **no es cero**. El promedio de minutos se calcula sobre las
filas con valor, no sobre todas las de `jugado`. Está anotado en el spec, en el campo, porque es el error
que se va a cometer.

**Dónde se valida.** Es la **primera invariante entre campos** del contrato y **no va al spec**: JSON
Schema la expresaría con un `if/then` en el `POST`, pero en el `PATCH` parcial —donde `status` puede no venir
y hay que mirar el valor **almacenado**— no hay forma de escribirla, y un esquema que cubre la mitad de los
casos invita a confiar en él. Va al **dominio**, como **422**. La frontera que queda fijada: **400 es lo que
se juzga mirando solo el cuerpo; 422 es lo que necesita mirar el estado**.

El `CHECK` en BD se pone igualmente —protege de la ingesta y de los *scripts*, [D-28]— pero no sustituye a
la validación de dominio, que es la que sabe decir *cuál* de los dos campos está mal.

---

### D-45 · Una fila es una sanción, no una cartulina: la doble amarilla es *una* roja

**La pregunta.** Un jugador ve amarilla en el minuto 20, segunda amarilla en el 70 y se va expulsado.
¿Cuántas filas de `Card` son?

**La respuesta intuitiva —tres— es la que rompe la cuenta**, y el argumento es de modelo, no de reglamento:
**una fila no sabe apuntar a otra.** Con `amarilla`, `amarilla`, `roja` nada ata esas dos amarillas a esa
roja, así que la cuenta de acumulación ([D-10]) las suma y no deben sumar. Excluirlas exigiría o una FK
entre tarjetas —una entidad que se referencia a sí misma para decir "esta canceló a aquella"— o una consulta
que reste por partido, que es una regla implícita que alguien olvidará. La otra alternativa, un tercer valor
`doble_amarilla`, obliga a toda consulta de "¿expulsado?" a recordar dos valores para siempre.

**Decisión.** `type` tiene **dos valores** y la doble amarilla es una `roja` con **`is_second_yellow =
true`**; las amarillas que la causaron **no se registran ni acumulan**. Consecuencias:

- Acumulación = `COUNT(*) WHERE type = 'amarilla'`; "¿expulsado?" = `type = 'roja'`. Sin excepciones.
- `is_second_yellow` conserva lo único que la distinción aporta: **roja directa y doble amarilla no cuestan
  lo mismo**.
- **Invariante entre columnas:** `is_second_yellow = true` exige `type = roja`. Segunda del contrato, misma
  técnica que la primera ([D-42]): dominio → 422, `CHECK` de refuerzo.
- **Unicidad *(jugador, partido, tipo)*** (§3.5): ni dos expulsiones ni dos amarillas sueltas. Amarilla y
  roja directa en el mismo partido sí conviven — dos hechos independientes.
- **Una amarilla suelta ya apuntada bloquea el alta de la doble amarilla** (422): queda absorbida por la
  expulsión, así que hay que borrarla.

**Lo que se asume a cambio, y no es menor.** El recuento de amarillas de la ficha **no coincide con las
cartulinas que el jugador vio**: al expulsado por doble amarilla le faltan dos. Se acepta porque el recuento
que importa es el que decide la sanción, y una cifra que mezclara ambas no serviría para ninguna. El número
literal sale de `COUNT(amarilla) + 2 × COUNT(roja con is_second_yellow)` sin tocar el modelo.

**Fuera a propósito:** cuántos partidos cuesta cada sanción. Es reglamento por competición y hoy nadie lo
pide; la ausencia se registra a mano con sus fechas ([D-10]).

---

### D-46 · La tarjeta no exige convocatoria: dos registros manuales independientes

**La tentación.** Si `Appearance` dice quién jugó y `Card` dice quién fue sancionado, parece que lo segundo
debería validarse contra lo primero: no se puede ver una tarjeta en un partido al que no fuiste convocado.

**Por qué no.** La premisa es cierta en el campo y falsa en los datos. `Appearance` es **entrada manual y
opcional** —[D-41]: la ausencia de fila significa *no registrado*, no *no convocado*—, así que validar
contra ella haría que apuntar una tarjeta **fallase según si el entrenador rellenó antes la convocatoria**,
con un 422 sobre un dato que no es el que se está metiendo. Impondría además un **orden de entrada** que
ninguna pantalla pide.

**Decisión.** `Card` valida que el **equipo del jugador dispute el partido** —contra `Match`, no contra otro
registro manual— y **nada más**. La coherencia entre convocatoria y eventos es de quien introduce los datos,
no del esquema. Vale igual para `Goal`.

**Lo que se asume a cambio.** Que puede existir una tarjeta de un jugador marcado como `no_convocado`. Es
una incoherencia detectable —y una buena candidata a **aviso** en el backoffice, que es donde corresponde:
señalar, no bloquear—. Bloquearla costaría más de lo que evita.

---

### D-48 · El ranking de goleadores no tiene *fallback*, y por eso su capacidad sí condiciona el dato

**El paralelismo aparente.** `StandingRow` y `LeagueScorer` se parecen: los dos son modelos de lectura, los
escribe solo la ingesta y vienen de la misma API. Tratarlos igual sería un error.

**Dónde se rompe.** La clasificación **siempre se puede calcular** desde los `Match` con marcador — por eso
[D-15] la declaró agnóstica a la fuente y [D-29] dejó `federationProvidesRoundStandings` como dato de
**procedencia** que las apps pueden ignorar.

El ranking de goleadores **no se puede calcular**: incluye jugadores rivales y [D-09] descartó modelar sus
*rosters*. Calcularlo desde `Goal` daría un ranking de nuestra plantilla presentado como ranking de la liga,
que es peor que no tener ranking.

**Decisión.** `ClubResponse.federationProvidesScorers`, hermano de `federationProvidesRoundStandings` —mismo
origen ([D-17]: catálogo en código), misma granularidad (una federación por tenant)— pero con un **peso
distinto que conviene no aplanar**:

| | `federationProvidesRoundStandings` | `federationProvidesScorers` |
|---|---|---|
| Qué dice | De dónde **viene** el dato | **Si hay** dato |
| Si es `false` | La clasificación existe igual, calculada ([D-15]) | `GET /v1/league-scorers` devuelve **siempre** vacío |
| ¿Pueden ignorarlo las apps? | Sí | **No** |

**Consecuencia para el cliente, que es el motivo del campo.** Con `false` la app **oculta la pantalla** en
vez de pintar una lista vacía. Sin el campo, un vacío es ambiguo —¿no publica?, ¿no se ha sincronizado?— y
la lectura razonable del usuario es "está roto".

**Lo que se asume a cambio.** Un segundo *booleano* de capacidad en `ClubResponse`. Si llegan tres o cuatro,
la salida es agruparlos en un `federationCapabilities` — pero **cuando pase**, con el criterio de [D-32]: se
generaliza al segundo o tercer caso, no por anticipado.

---

### D-52 · El gol en propia puerta: se guarda su autor, pero no le suma

**La pregunta.** Un defensa nuestro marca en propia. `scoring_team_id` es el **rival** —es quien se lleva el
gol— y `conceding_team_id` somos nosotros. ¿Y `scorer_player_id`?

**El coste está repartido.** Dejarlo nulo conserva limpia la invariante "el goleador es del equipo que
marca", pero **pierde el dato** de quién lo hizo. Guardarlo lo conserva a costa de romper esa invariante.

**Decisión.** Se **guarda el autor**, y el gol **no le suma**. Perder información para preservar la
elegancia de una invariante sería cambiar dato por comodidad de esquema.

**Lo que obliga a aceptar: la pertenencia del goleador pasa a depender de un enumerado.**

- `play_type != en_propia_puerta` → `scorer_player_id` es del equipo de `scoring_team_id`
- `play_type == en_propia_puerta` → `scorer_player_id` es del equipo de `conceding_team_id`

Es la única invariante del contrato en la que **un enumerado decide contra qué se valida una FK**, y tiene
el corolario habitual en el `PATCH` (§5.2): `playType` y `scorerPlayerId` **viajan juntos** cuando el cambio
cruza `en_propia_puerta`, o la operación devuelve 422. Igual que `status`/`minutes` en [D-42] y
`type`/`isSecondYellow` en [D-45].

**El "no le suma" es de la consulta, no de una columna.** El conteo de goleador excluye
`play_type = 'en_propia_puerta'` en el modelo de lectura (§3.4, §4.5). **No** hay una bandera
`counts_for_scorer` almacenada, por lo mismo que no hay `is_own` ni `active`: una bandera puede contradecir
al campo del que depende, y la consulta no ([D-03], [D-38]).

**Y el gol en propia no admite asistencia** → 422. Atribuirla es ambiguo en cualquier sistema —¿al que
centró, al que desvió?— y toda respuesta sería una convención inventada. Se prefiere el hueco al dato dudoso.

**Lo que se asume a cambio.** Que `GET /v1/goals?scorerPlayerId=` devuelve también sus goles en propia, y
quien cuente sin filtrar `playType` contará de más. Anotado en el spec, en el propio parámetro.

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

### D-55 · La capacidad no es «¿publica clasificación?» sino «¿puede recuperar una jornada pasada?»

**La observación en la que se apoyaba [D-29] era falsa.** Decía que la RFFM publica clasificación y la FCF
no. Los volcados demuestran que **las dos la publican** — la FCF incluso con más detalle (desglose
casa/fuera, coeficiente, racha). Lo que las separa es otra cosa:

| | RFFM | FCF |
|---|---|---|
| Endpoint | `/api/standings?idGroup=…&round=9` | `/classificacio/…` |
| **Granularidad** | **histórica, por jornada** | **solo la actual** |

**Por qué importa tanto.** El modelo es un ***snapshot* por jornada** ([D-33], [D-34]). Con la RFFM se puede
pedir la jornada 9 dos años después; con la FCF, lo que no se capturó esa semana **no se recupera nunca**.

**Decisión.** La capacidad del catálogo ([D-17]) pasa a ser
**`federationProvidesRoundStandings`**: *«¿puede la ingesta recuperar la clasificación de una jornada
pasada?»*. RFFM `true`, FCF `false`.

**Lo que esto cambia en la operación, que es menos de lo que parece.** Con la FCF, cada pasada semanal
ingiere la clasificación vigente y **la guarda como el *snapshot* de la jornada en curso**. En régimen
estacionario, por tanto, **todas las jornadas acaban teniendo clasificación oficial**: lo que no se puede es
**rellenar hacia atrás**. El *fallback* calculado de [D-15] sigue existiendo, pero su disparador ya no es «la
federación no publica» sino **«esta jornada es anterior a nuestra primera sincronización»**.

**Y eso salva la premisa de [D-29].** El riesgo era que la procedencia pasara a variar **por jornada** dentro
del mismo tenant, que es justo lo que [D-29] descartó al rechazar `Round.hasStandings`. No ocurre: la
varianza queda confinada a la **ventana de arranque**, que es el mismo hueco que [D-33] ya contemplaba para
`previous_position` cuando un club da de alta la competición a mitad de temporada. No es una capacidad, es un
*backfill*.

**Lo que se asume a cambio.** Que en la FCF una jornada pasada que nadie capturó tiene clasificación
**calculada**, con las limitaciones conocidas: sin desempate por enfrentamiento directo y **sin sanciones
administrativas**. Es peor dato que el oficial, pero es el único posible, y afecta solo al histórico previo
al alta.

---

### D-56 · «Volátil» no es «pisar siempre»: la fuente solo gana cuando dice algo

**El caso que rompe [D-18].** `match_date` y `kickoff_time` están clasificados como **volátiles**: la ingesta
los pisa en cada pasada, incluso ya confirmados, porque una suspensión los mueve ([D-30]). La FCF obliga a
matizarlo: **cuando un partido se juega, su página deja de publicar la fecha y la hora** y las sustituye por
el marcador ([Anexo FCF §C.6]). Pisar «siempre» significaría **borrar el dato el lunes siguiente al
partido**, para siempre.

No es una rareza catalana: la app de Madrid tiene una función dedicada a defenderse del mismo caso, aunque no
se haya reproducido en los volcados de la RFFM.

**Decisión.** «Volátil» se redefine como **la fuente gana cuando la fuente dice algo**. Un campo **ausente o
vacío no es un valor**: es ausencia de información, y **nunca sobrescribe** lo que ya hay. Vale para toda la
ingesta, no solo para la FCF.

**El matiz que hace falta para no romper [D-30].** Un `kickoff_time` vacío **sí es significativo** mientras el
partido no se ha jugado —es «horario aún sin confirmar», y una suspensión debe poder devolverlo a nulo—. Lo
que lo desambigua es el marcador:

| Estado del partido | `kickoff_time` vacío significa | La ingesta |
|--------------------|--------------------------------|------------|
| **Sin marcador** | horario **no confirmado** todavía | **lo escribe**: es el dato real ([D-30]) |
| **Con marcador** | la fuente **dejó de publicarlo** | **lo ignora**: conservar lo que hay |

`match_date` no necesita ese matiz: es `NOT NULL` en el modelo (§3.2) y un partido siempre tiene fecha
nominal, así que **vacío nunca es un valor válido** para ella.

**Consecuencia operativa: la ingesta tiene que ser incremental de verdad.** Un partido que no se sincroniza
**antes** de jugarse pierde su fecha real de forma irrecuperable en la FCF. Refuerza el anclaje semanal de
§5.6 y convierte el *«no puede ser mayor que una semana»* de una recomendación en un requisito.

**Lo que se asume a cambio.** Que la ingesta ya no puede escribirse como un `UPDATE` ciego de los campos
volátiles: hay que distinguir **ausente**, **vacío** y **con valor**, que es justo lo que los dos anexos
documentan campo a campo. Es más código, y es inevitable.

---

### D-57 · El acta entra como fuente de **estado**, y solo para los partidos del club

**Qué desbloquea.** El calendario **no trae estado de partido** (§F.2): la ingesta deriva
`programado`/`finalizado` de que haya marcador, y por eso `aplazado` y `suspendido` (§3.3) llevan desde el
principio siendo **valores inalcanzables**. El acta sí lo trae: `suspendido`, `acta_cerrada` y
`partido_en_juego` ([Anexo RFFM §F.10]). Y se actualiza **antes** que el calendario.

**Qué cuesta.** Una petición **por partido**. Pedir el acta de todos los partidos de un grupo son ~240 por
temporada; multiplicado por los grupos de un club, se dispara.

**Decisión.** El acta se consulta **solo para los partidos en los que juega un equipo propio**, y **solo**
para escribir `Match.status`. Dos consecuencias:

- El coste cae a la escala del club —sus equipos, sus partidos— en vez de la de la competición. Es
  exactamente el mismo recorte de alcance que §3.7 aplica al detalle manual: **lo que no es del club, no se
  detalla**.
- `Match.status` deja de derivarse del marcador **para los partidos propios** y pasa a ser dato ingerido de
  verdad. Para los ajenos sigue derivándose, y por tanto sigue sin poder valer `aplazado`. Se acepta: la
  clasificación no necesita ese matiz y ninguna pantalla lo pide para partidos de terceros.

**Sigue habiendo un solo escritor.** El acta es ingesta, y `Match` ya era salida de la ingesta ([D-21]). No
se abre ninguna frontera nueva.

**Lo que el acta trae y de momento NO se ingiere, con sus dos bloqueos.** El acta contiene goles con autor y
minuto, tarjetas con `segunda_amarilla`, y alineaciones. Es tentador, porque llenaría solo `Goal`, `Card` y
`Appearance` — pero **no es decidible todavía**:

1. **No sabemos los códigos.** `tipo_gol` y `codigo_tipo_amonestacion` valen `"100"` en todo lo observado. La
   leyenda de la web demuestra que hay al menos tres tipos de gol y dos de tarjeta (§F.10), pero **falta
   capturar un acta con penalti, gol en propia puerta y roja**. Sin eso no se puede mapear nada.
2. **No hay forma de atar `codjugador` a nuestro `Player`.** El acta identifica al jugador con el código
   federativo; nuestro `Player` es **dominio manual y no tiene identificador de federación** ([D-05]).
   Ingerir un gol dejaría `scorer_player_id` sin resolver. Habilitarlo exigiría **añadir
   `Player.federation_player_id`**, que es un cambio de modelo con consecuencias propias —y que de paso
   permitiría lo que [D-09] dio por imposible: unir `LeagueScorer` con la plantilla—.

Y aunque se desbloqueen los dos, quedaría lo de fondo: **sería un segundo escritor** en tablas donde el
contrato garantiza uno solo (§2.1), la misma línea que sostienen [D-10], [D-41], [D-46] y [D-53]. La salida
previsible es **propiedad por campo**, como ya hace [D-18] dentro de una fila: el acta pondría el esqueleto
—quién, cuándo, de qué tipo— y el club el desglose que la federación no publica —zona, lado, parte del
cuerpo, asistencia—. Es la división de §3.7 aplicada un nivel más abajo. **Pero no se decide aquí:** se
decide cuando existan los dos datos que faltan.

**Lo que se asume a cambio.** Que durante un tiempo se llama a un endpoint rico y se aprovecha un 5 % de lo
que devuelve. Es deliberado: el alcance ampliado depende de una observación pendiente, y ampliarlo a ciegas
—mapeando `"100"` a «gol normal» por conjetura— metería datos mal clasificados en las tablas que sostienen
toda la estadística.

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
dato de **procedencia** (§3.7), y la varianza es **entre federaciones**, no entre competiciones ni entre
jornadas.

> **Corrección.** Esta decisión se apoyaba en que «la RFFM publica clasificación y la FCF no». **Era falso**:
> las dos la publican, y lo que las separa es poder pedirla **por jornada pasada** ([D-55]). La conclusión
> aguanta —la varianza sigue siendo entre federaciones y el campo sigue siendo uno por tenant— pero el campo
> se llamó de otro modo: **`federationProvidesRoundStandings`**.

**Alternativa intermedia, también descartada: `Competition.standingsSource`.** Parecía el nivel natural
—hermano de `last_synced_at`—, pero como hay **una federación por tenant** ([D-17]), dentro de un *schema*
todas las competiciones tendrían **el mismo valor**: una columna constante repetida en cada fila. Es
exactamente la redundancia que [D-28] acaba de rechazar, y por el mismo motivo.

**Decisión.** La capacidad vive en el **catálogo de federaciones en código** ([D-17]), que pasa así a
describir **qué sabe hacer** cada proveedor y no solo sus coordenadas. Al contrato sale **una sola vez por
tenant**, derivada y `readOnly`: `ClubResponse.federationProvidesRoundStandings` ([D-55]). Su consumidor es el
**backoffice**, para rotular "clasificación calculada" y que el administrador no la confunda con la oficial;
las apps de consulta pueden ignorarla.

**Lo que se asume a cambio.** Si alguna federación llegara a publicar clasificación en unas competiciones sí
y en otras no, el booleano por club se quedaría corto y habría que bajarlo a `Competition`. Se acepta: hoy no
hay ni un solo caso observado, y bajarlo entonces es añadir una columna, no rehacer el contrato.

---

### D-32 · `MatchResponse` embebe los equipos: proyección, no referencia ni expansión

**El problema es de aritmética de llamadas.** La pantalla de jornada (mockup 3) pinta **cinco partidos**, y
cada fila necesita escudo y nombre corto de **dos** equipos. Con un DTO fiel a la tabla —`homeTeamId` y
`awayTeamId` como UUID—, pintarla cuesta **1 + 10 llamadas**, o bien obliga a cada cliente (iOS, Android,
backoffice) a mantener su propia caché de equipos y a invalidarla cuando la ingesta corrige un nombre. Es el
*N+1* clásico, trasladado del ORM al cliente móvil.

**Alternativas consideradas:**

| Opción | Por qué se descarta |
|--------|---------------------|
| UUID planos | La aritmética de arriba. Traslada a **tres** clientes un trabajo que el servidor hace una vez, con un *eager loading* que §4.5 ya prevé para este caso exacto |
| UUID + `?expand=teams` | Introduce en el contrato una **convención de expansión** que ningún otro recurso usa, y con ella dos formas de la misma respuesta que documentar, generar y testear. El coste no se paga: no hay ni un consumidor que quiera la forma plana |
| Devolver `TeamResponse` completo anidado | Arrastra `category`, `gender`, `modality`, `federationTeamId`, `opponentClubId`, `createdAt`… que dentro de una competición son **constantes** (§3.2). Veinte repeticiones por página de datos que no distinguen una fila de otra |

**Decisión.** `home` y `away` son objetos **`MatchTeam`**: `teamId`, `displayName`, `shortDisplayName`,
`crestUrl`, `isOwn` y `score`. Es `Team` **recortado a lo que cabe en una fila de resultado**.

**Por qué esto no rompe la disciplina de agregados** (§4.2). `MatchTeam` **no es un recurso**: no tiene
endpoint, ni identidad propia, ni escritura. Es una **proyección de lectura**, exactamente la salida que
§4.2 dejó prevista para la tensión entre agregados limpios y una app intensiva en lectura, y el mismo
compromiso que ya se aceptó al denormalizar `Goal` ([D-04]) y al engordar `TeamResponse` de derivados. La
diferencia con una FK expuesta es que `teamId` **sigue ahí**: quien necesite el equipo completo tiene la
puerta abierta.

**Dos detalles que se deciden con ello:**

- **`shortDisplayName` no lleva categoría** ("CD Ejemplo A"), `displayName` sí ("CD Ejemplo Juvenil A"). En
  una jornada todos los equipos son de la misma categoría —rotularla en cada fila es ruido—, pero el
  calendario de un equipo puede mezclar liga y copa ([D-12]), donde el nombre largo sí distingue. Los dos
  son derivados en lectura, como el `displayName` de `TeamResponse`.
- **El marcador vive dentro de `home`/`away`**, no como `homeScore`/`awayScore` paralelos. Ata cada número a
  su equipo en la estructura misma, en vez de en una convención de nombres que el cliente puede cruzar mal.

**Lo que se asume a cambio.** Un nombre de equipo corregido por `PATCH` (§5.1) queda **duplicado en cada
partido que lo menciona** dentro de las respuestas ya servidas — el precio habitual de una proyección. Como
no se almacena, la siguiente lectura ya sale corregida: es caché de cliente, no deriva de datos.

> **Adenda (al redactar `StandingRow`).** La proyección se extrajo a un esquema propio, **`TeamRef`**, con
> los cinco campos comunes; `MatchTeam` pasa a ser `TeamRef` **+ `score`**, y `StandingResponse.team` lo usa
> tal cual. Se hizo al aparecer el **segundo** consumidor, no antes: es el criterio general para las
> proyecciones de este contrato, porque compartir por anticipado habría terminado con `TeamResponse` y
> `TeamRef` fundidos en un esquema con la mitad de los campos opcionales — que es justo lo que ninguno de
> los dos quiere ser.

---

### D-34 · La clasificación es un modelo de lectura: sin acceso por id, con la racha dentro

**Tres preguntas que se responden juntas** porque tienen la misma raíz: `StandingRow` **no es un agregado**
(§4.2), es un **modelo de lectura** cuya unidad de consumo es *la tabla de una jornada*, no la fila.

**1 · No hay `GET /v1/standings/{id}`.** Es el único recurso del contrato sin acceso por identificador.
"La fila 4 de la jornada 22" no la pide ninguna pantalla, no se puede enlazar desde ningún sitio y no se
puede editar. Publicar la ruta sería **superficie sin consumidor**, exactamente lo que [D-27] eliminó al
retirar `Participation`. La fila tiene `id` en la tabla porque toda tabla lo tiene (§3.5); eso no obliga a
darle URL.

**2 · El ámbito es `?roundId=` y solo `?roundId=`.** Una clasificación existe **respecto de una jornada** —es
un *snapshot*—, así que el filtro no es opcional. Lo interesante es lo que **se descarta**: admitir
`?competitionId=` a secas para devolver "la clasificación actual de la liga".

| Opción | Por qué se descarta |
|--------|---------------------|
| `?competitionId=` ⇒ última jornada **con datos** | Inventa un **tercer concepto** que no existe en el dominio: no es la jornada actual (que puede no tener aún clasificación, con los partidos sin jugar) ni la última (que puede estar vacía). Un concepto que el servidor define y el cliente no puede predecir |
| `?competitionId=` ⇒ jornada **actual** | Devolvería vacío justo en el caso más pedido —lunes por la mañana, jornada en curso sin ingerir— sin que el nombre del parámetro lo insinúe |
| Sub-recurso `/rounds/{id}/standings` | Expresa mejor la contención, pero rompe la convención de rutas planas con filtros que sigue **todo** el contrato, y que ya se justificó al diseñar `Round` (§5.1) |

**Decisión:** `?roundId=` obligatorio, **400** si falta. La "clasificación actual" la resuelve el cliente,
que ya tiene `Round.isCurrent` en el payload del selector de jornada: **no le cuesta una llamada extra**. Y
si esa jornada devuelve lista vacía, retrocede una — comportamiento que **ya tiene que implementar** para el
caso de competición terminada, donde ninguna jornada es `isCurrent` (§5.1). El contrato no gana un concepto;
el cliente no gana una rama.

**3 · La racha viaja dentro de la clasificación.** La columna RACHA del mockup vive en la tabla de
clasificación, y `form` viaja en cada `StandingResponse`: los últimos **5** resultados con su número de
jornada. Es la misma aritmética de llamadas de [D-32] pero peor —sin ella, pintar la racha exige traerse
**varias jornadas completas de partidos** para cruzarlas contra veinte equipos en el cliente—.

- **Se calcula desde `Match`, no diferenciando *snapshots* consecutivos.** La segunda vía es tentadora
  (`won[N] − won[N−1]` da el resultado de la jornada N sin tocar `Match`), pero **depende de que la cadena de
  clasificaciones esté completa**, y [D-33] acaba de establecer que no lo está: en un alta a mitad de
  temporada faltan las jornadas anteriores. Desde `Match` la consulta está acotada por los índices de §4.6 y
  no depende de ningún *snapshot*.
- **N fijo (5), sin `?form=N`.** Se consideró parametrizarlo —incluso `form=0` para no pagar el cálculo—,
  pero el contrato no tiene ni un solo parámetro de forma de respuesta hoy, y estrenarlo para ahorrar una
  consulta acotada no compensa. El cliente que pinte tres distintivos recorta la lista.
- **`MatchOutcome` (`victoria`/`empate`/`derrota`) es relativo al equipo de la fila**, y por eso es un
  enumerado distinto de `MatchStatus`, que es absoluto: un partido es `finalizado` para los dos equipos,
  pero `victoria` para uno y `derrota` para el otro.

**Consecuencia de conjunto: sin paginación y sin `?sort=`.** El ámbito trae techo (~20 equipos), igual que
en `Round`, así que se aplica el criterio de §5.3. Y el orden es **fijo por `position`**: una clasificación
desordenada no es una clasificación.

**Lo que se asume a cambio.** Un cliente que quisiera solo la fila de su equipo se trae las veinte. Es una
respuesta pequeña, y tenerlas todas es precisamente lo que permite pintar la tabla — que es la única
pantalla que consume esto.

---

### D-36 · Borrar un jugador no pregunta por su historial: *soft delete* sin guarda de dependientes

**La pregunta.** `Season` y `Competition` devuelven **409** si tienen datos colgando (§5.1). ¿Debería
`DELETE /v1/players/{id}` hacer lo mismo cuando el jugador ya tiene goles, tarjetas o convocatorias?

**Por qué no, y no es una excepción caprichosa.** El 409 de `Season` protege una **integridad real**: su
borrado es **físico** y en cascada ([D-24]), así que negarse es la única forma de que un `DELETE` distraído
no se lleve media temporada por delante. El de `Player` es **lógico** (`deleted_at`, §3.5): las filas de
`Goal`, `Card` y `Appearance` **siguen ahí y siguen apuntando a la misma PK**. No hay nada que romper, así
que no hay nada que guardar. Poner un 409 aquí sería copiar la forma de la otra decisión sin su motivo.

**El caso de negocio decide.** El borrado que de verdad ocurre en un club es *"me equivoqué al dar de alta a
este chaval"* o *"este ya no viene"*, y a menudo se descubre **después** del primer partido. Con guarda de
dependientes, ese jugador **no se puede quitar nunca** de la plantilla: la pantalla arrastra una ficha
muerta el resto de la temporada.

| Opción | Por qué se descarta |
|--------|---------------------|
| **409** si tiene eventos | Deja sin salida el caso real (alta errónea descubierta tarde) y protege una integridad que el *soft delete* no pone en riesgo |
| Borrado **físico** en cascada de sus eventos | Falsea la estadística del **equipo**: los goles se marcaron y el partido se ganó con ellos. El historial no es del jugador, es del equipo |
| **Soft delete sin guarda** | **Elegida** |

**Decisión.** `DELETE` → **204** siempre; marca `deleted_at` y el jugador desaparece de todas las lecturas.
Sus eventos sobreviven y **siguen contando para el equipo**. Sin `?force=`, sin 409, sin parámetro para
listar borrados: el borrado lógico sirve a la **auditoría y la recuperación** (§3.5), no al cliente.

**Consecuencia dura, y es la parte que hay que implementar bien:** el índice único del dorsal tiene que ser
**parcial** — `UNIQUE (team_id, season_id, shirt_number) WHERE deleted_at IS NULL` (§3.5, §4.6). Sin el
filtro, el jugador borrado seguiría ocupando el `9` y nadie podría reasignarlo, que es justo lo que se
espera al borrar una ficha equivocada.

**Lo que se asume a cambio.** Que las estadísticas de un equipo pueden incluir goles de alguien que ya no
aparece en su plantilla. Es correcto —el gol se marcó—, pero conviene saberlo antes de que alguien lo
reporte como descuadre. Y que **esto no es el "derecho al olvido"**: borrar lógicamente no elimina el dato
personal de un menor; para eso está el purgado de temporada ([D-24]).

---

### D-37 · La plantilla es un hecho de (equipo, temporada): ámbito obligatorio e identidad inmutable

**Una sola decisión con dos caras**, y verlas juntas es lo que la hace obvia. [D-05] estableció que una fila
de `Player` es *un jugador en un equipo en una temporada*. De ahí salen las dos:

**1 · En la lectura, `?teamId=` y `?seasonId=` son obligatorios los dos.** No son filtros: son la
coordenada. Pedir `/v1/players` a secas devolvería todas las plantillas de todos los equipos de todos los
años mezcladas, que no es una colección que pida ninguna pantalla —igual que el `GET /v1/rounds` sin
competición o la clasificación sin jornada ([D-34])—. Con las dos, el techo es de ~25 filas → sin
paginación, orden fijo por dorsal (§5.3). **Y sin `?q=`**: la colección entera cabe en una pantalla, así que
buscar por nombre es superficie sin consumidor.

**2 · En la escritura, esos mismos dos campos no se pueden cambiar.** Van en `CreatePlayerRequest` y **no**
en `UpdatePlayerRequest`. El motivo no es de propiedad —los escribe el mismo administrador que hace el
`PATCH`— sino de **historial**: los goles y tarjetas del jugador cuelgan de esta fila, y mover su `team_id`
haría que eventos ya emitidos pasaran a contar para otro equipo. Un `PATCH` que reescribe el pasado no es
una corrección.

| Opción | Por qué se descarta |
|--------|---------------------|
| `?teamId=` opcional, `?seasonId=` opcional | La lista sin acotar no la pide ninguna pantalla y pierde el techo que permite no paginar |
| Ruta anidada `/teams/{id}/players` | Expresa mejor la contención, pero rompe la convención de rutas planas de **todo** el contrato y sigue necesitando la temporada por *query* |
| `PATCH` con `teamId` (traslado entre equipos) | Reasigna el historial ya emitido. El traslado correcto es **fila nueva** en el equipo nuevo, como el cambio de temporada ([D-05]) |

**Decisión.** Ámbito obligatorio en `GET /v1/players` (**400** si falta), `teamId`/`seasonId` solo en el
alta, y **422** si el equipo no es propio, no existe o la temporada está archivada. El 422 —y no 404— porque
el equipo llega en el **cuerpo**: `/players` sí existe, y un 404 respondería sobre el recurso equivocado.
En el `GET` de lista el 404 **sí** es del ámbito, como en `Round` y `Match`.

**Lo que se asume a cambio.** Un jugador que sube de equipo a mitad de temporada queda partido en dos filas
sin vínculo, y sus totales no se suman solos. Es la **misma contrapartida que [D-05] ya aceptó** para el
cambio de temporada, extendida al cambio de equipo — no una nueva. Y que cada verano hay que volver a
teclear la plantilla: el alta en bloque queda anotada como cuestión abierta (§9), no resuelta aquí.

---

### D-40 · Dar de alta a un lesionado es un `PATCH`: cuándo un sub-recurso de estado está justificado

**La tentación era clara.** El contrato ya tiene tres sub-recursos de estado —`PUT /seasons/{id}/archive`,
`PUT /teams/{id}/ownership` ([D-20]), `PUT /players/{id}/photo` ([D-35])—, y "dar de alta al jugador" **suena**
igual: un verbo del negocio, algo que el entrenador *hace*. `PUT /v1/absences/{id}/return` encajaba a la
vista.

**Por qué no.** Los tres que existen comparten una propiedad que este no tiene: **hacen algo que escribir un
campo no hace**.

| Sub-recurso | Qué hace que un campo no haría |
|-------------|--------------------------------|
| `/archive` | Oculta **el subárbol entero** de la temporada, y su reverso (`DELETE`) lo restaura |
| `/ownership` | **Orquesta entre entidades**: pone `opponent_club_id` a nulo *y* copia nombre y escudo del `OpponentClub` al `Club` |
| `/photo` | Recibe un **binario**, lo valida, lo recodifica y lo escribe en Storage |
| ~~`/return`~~ | **Escribe una fecha.** Nada más |

**Decisión.** Cerrar una ausencia es `PATCH {"actualReturnDate": "2025-01-06"}`. Y **reabrirla** —el caso de
haberla cerrado por error— es `PATCH {"actualReturnDate": null}`, que ya significa "borra el valor" en la
convención de `PATCH` del contrato (§5.2): no hace falta inventarle semántica.

**El criterio que queda fijado para lo que venga:** un sub-recurso de estado se justifica cuando la
operación **orquesta, oculta o transporta**; no cuando pone un valor. Envolver una asignación en un `PUT`
con nombre bonito no la hace más auditable —el `updated_at` y la auditoría son los mismos—, solo añade una
ruta que mantener y una decisión que el cliente tiene que aprender.

**Corolario del mismo razonamiento, en la dirección contraria: `DELETE` no es "cerrar".** Los dos botones
caerán cerca en el backoffice y no son intercambiables. Una baja **que ocurrió** se cierra y queda en el
historial; una **registrada por error** se borra ([D-36]). Cerrar la falsa dejaría en la ficha un periodo de
indisponibilidad que nunca existió, y las dos fechas lo harían pasar por real.

**Alcance de la lista, que es la otra mitad de la forma del recurso.** `GET /v1/absences` exige ámbito y
admite **dos**: `?playerId=` (la ficha del jugador) o `?teamId=` **+** `?seasonId=` (la plantilla entera).
La segunda no es comodidad: sin ella, pintar el distintivo de disponibilidad de 25 fichas cuesta **25
llamadas** — el N+1 que [D-32] y [D-34] ya combatieron. Un ámbito **a medias** (`teamId` sin `seasonId`) es
**400**, no un filtro parcial: no acota nada, y devolvería las bajas de todos los años del equipo.

**Lo que se asume a cambio.** Que el `PATCH` de `Absence` mezcla dos intenciones muy distintas —corregir una
errata y dar el alta— bajo el mismo verbo. Es exactamente lo que el contrato ya acepta en `Season` o
`Player`, y el precio de no tener un endpoint por transición.

---

### D-43 · Las dos puertas de `Appearance` son excluyentes, no acumulables

**El contrato ya tenía dos formas de ámbito y esta es la tercera.** Conviene distinguirlas, porque se
parecen y no son lo mismo:

| Recurso | Ámbito | Combinar dos puertas |
|---------|--------|----------------------|
| `Round`, `StandingRow`, `Player` | **fijo** (obligatorio y único) | no aplica |
| `Match`, `Absence` | **alternativo y acumulable** — acotan progresivamente | legítimo: `?teamId=` + `?seasonId=` acota más |
| **`Appearance`** | **alternativo y excluyente** | **400** |

**Por qué.** `?matchId=` **+** `?playerId=` devuelve **como mucho una fila**, porque el par es único
(§3.5): un `GET` por identificador escrito de la forma más cara posible. Admitirlo sería publicar dos
caminos al mismo recurso.

**Decisión.** Exactamente una de las dos → **400** si no viene ninguna **y** si vienen las dos. `?teamId=`
sigue siendo un **filtro**, no una puerta: acompaña a `?matchId=` y solo hace falta en el derbi entre dos
equipos propios, donde la convocatoria trae las dos plantillas.

**El orden también depende de la puerta**: por dorsal con `?matchId=` —se lee como una plantilla— y por
fecha de partido descendente con `?playerId=` —se lee como un historial—. No es inconsistencia: son **dos
pantallas distintas** que comparten tabla, y un orden común dejaría a una de las dos ordenada por un criterio
que no significa nada en ella.

**Lo que se asume a cambio.** Que la regla de ámbito pasa a tener dos variantes. Documentado en §5.3.

---

### D-44 · La convocatoria se registra fila a fila: sin alta masiva, por ahora

**El caso incómodo, dicho sin adornos.** Registrar la convocatoria de un partido son ~18 `POST`. Es la
operación más repetitiva del backoffice y la única del contrato donde una pantalla se traduce en decenas de
llamadas de escritura.

**Lo que se consideró.** Un `PUT /v1/appearances?matchId=` que recibiera la lista entera y la sustituyera
—*replace set*—, que es la forma habitual de resolverlo.

**Por qué no, hoy.**

| | Fila a fila | `PUT` masivo |
|---|---|---|
| Superficie del contrato | La que ya tienen `Player` y `Absence` | Un verbo y una semántica **nuevos**, sin precedente aquí |
| Errores parciales | Cada fila responde lo suyo (409, 422) | Hay que inventar un cuerpo de error por índice, o abortar las 18 por una |
| Borrado | Explícito | **Implícito**: lo que no viene en la lista desaparece — justo el efecto lateral que [D-42] rechazó |
| Concurrencia | Última escritura por fila | Dos entrenadores guardando pisan la lista entera |

El coste real es además menor de lo que parece: la convocatoria se rellena **una vez** por partido y luego
se corrige de una en una, que es lo que el `PATCH` ya sirve bien. Optimizar el alta inicial a costa de la
superficie del contrato es optimizar el gesto menos frecuente.

**Decisión.** CRUD fila a fila. El backoffice encadena las llamadas tras un único botón de *Guardar*, igual
que ya encadena alta de jugador y subida de foto ([D-35]).

**Qué la haría cambiar.** Una latencia inaceptable medida en el backoffice, o un **segundo** consumidor con
la misma necesidad. En ese caso la salida es un mecanismo **genérico** de lotes para los tres hijos de
`Match`, no un `PUT` a medida: **se generaliza cuando coinciden dos, no por anticipado** (§5.2).

---

### D-47 · Cuándo dos puertas de ámbito se combinan: la regla que faltaba

**El problema.** [D-43] declaró excluyentes las puertas de `Appearance` y en `Card` la misma pregunta se
responde al revés. Sin un criterio explícito eso es una incoherencia, y cada recurso nuevo volvería a
deliberarse desde cero.

**El criterio.** No es el recurso, es la **clave única**:

> Dos puertas de ámbito se **combinan** salvo que su intersección sea la **clave única** de la tabla.

Cuando la intersección colapsa a una fila, combinar las puertas es un `GET` por identificador escrito de la
forma más cara posible: **dos caminos al mismo recurso**, uno sin `id` en la URL y por tanto no enlazable.
Cuando no colapsa, es un subconjunto legítimo que alguna pantalla pedirá.

**Aplicado a lo que hay:**

| Recurso | Puertas | ¿Clave única? | Combinables |
|---------|---------|---------------|-------------|
| `Match` | `roundId`, `competitionId`, `teamId` | no | **sí** |
| `Absence` | `playerId` \| `teamId`+`seasonId` | no (un jugador tiene varias) | **sí** |
| `Appearance` | `matchId`, `playerId` | **sí** — único(jugador, partido) | **no** → 400 ([D-43]) |
| `Card` | `matchId`, `playerId` | no — único es *(jugador, partido, **tipo**)* | **sí** |

La diferencia entre las dos últimas filas es **una columna en el índice**, y sale del modelo, no del gusto:
un jugador ve una amarilla y una roja directa en el mismo partido y son dos hechos distintos ([D-45]),
mientras que hace exactamente una cosa por partido en cuanto a convocatoria ([D-41]).

**Decisión.** El criterio queda enunciado en §5.3 y se aplica sin volver a deliberar. `Goal` lo heredó: su
clave no incluye jugador —hay goles sin `scorer_player_id` ([D-04])— así que sus cuatro puertas se combinan.

**Lo que se asume a cambio.** Que la regla de ámbito tiene dos variantes y hay que mirar la tabla. La
alternativa —permitir siempre la combinación y devolver la única fila— se descartó por lo mismo que
`GET /standings/{id}` ([D-34]): **superficie sin consumidor**.

---

### D-49 · Lo que decide la paginación es el techo, no el ámbito — y en un ranking la paginación es el top-N

**La confusión que este recurso destapa.** El contrato venía aplicando una regla implícita —"si exige
ámbito, no se pagina"— que funcionó hasta ahora porque dos cosas distintas coincidían. `LeagueScorer` las
separa: exige `?competitionId=` igual que `StandingRow` exige `?roundId=`, y **sí** se pagina.

**El criterio real** ya estaba escrito en §5.3 al comparar `Round` y `Match`: *el ámbito acota **qué** se
pide; la paginación, **cuánto** llega*. Lo que decide es si el ámbito trae **techo**:

| Recurso | Ámbito | Techo que trae | Pagina |
|---------|--------|----------------|:------:|
| `Round` | competición | ~34 jornadas, **por definición** | no |
| `StandingRow` | jornada | ~20 equipos | no |
| `Player` | equipo + temporada | ~25 jugadores | no |
| `Appearance` / `Card` | partido o jugador | ~18 filas / una temporada | no |
| `Match` | competición o equipo | **ninguno** (~380, o sin límite) | **sí** |
| **`LeagueScorer`** | competición | **ninguno** — cuántos marcaron no lo acota nada | **sí** |

Una competición acota los **equipos** a veinte; no acota los **jugadores que han marcado en ella**, que
pueden ser doscientos.

**Y el hallazgo que abarata la decisión:** como el orden **es** el ranking y es fijo, la paginación ya
resuelve el top-N. `?perPage=20` **es** "los veinte máximos goleadores", sin `?limit=`, `?top=` ni endpoint
aparte para la portada.

**Decisión.** Se pagina por techo, no por ámbito. Fue la vara con la que se midió `Goal`: `?matchId=` trae
techo pero `?scoringTeamId=` o `?scorerPlayerId=` no, así que pagina.

**Lo que se asume a cambio.** Que dos recursos con ámbito obligatorio se comporten distinto. Se mitiga con
el sobre `{ data, page, perPage, total }`, que hace la diferencia **visible en la respuesta**: no hay forma
de paginar por accidente creyendo que llegó la lista entera.

---

### D-50 · Los tramos de sanción se escriben como conjunto: cuándo el lote sí es la respuesta

**El problema con el CRUD por fila, en concreto.** §5.1 daba a `CompetitionSanctionBracket` las cuatro
operaciones como al resto del dominio manual. Al escribir el contrato se ve que no funciona, porque los
tramos (`0-5, 6-10, 11-13, 14-16`) **son una secuencia contigua**, no cuatro filas independientes:

| Operación por fila | Qué habría que inventar |
|--------------------|-------------------------|
| `DELETE` del tramo intermedio (`6-10`) | Queda `0-5, 11-13`: un **hueco**. ¿Se rechaza? ¿Se reflota el siguiente? ¿Se renumera `seq`? |
| `PATCH` de `yellow_to` en `6-10` | El `yellow_from` del **siguiente** deja de cuadrar → o se cascadea, o se devuelve 422 |
| `POST` de un tramo | Solo es válido al final, y solo si `yellow_from` es el `yellow_to` anterior más uno |

Son tres reglas, ninguna evidente, para editar **cuatro filas que se tocan una vez por temporada**. Y cada
estado intermedio inválido es alcanzable: quien borra el tramo 2 para recrearlo deja la competición sin
sentido entre las dos llamadas.

**Decisión.** `PUT /v1/sanction-brackets?competitionId=` **sustituye el conjunto entero**. Sin `POST`, sin
`PATCH`, sin `DELETE`, sin ruta por `{id}`. `{"thresholds": []}` borra los tramos, que es un estado
legítimo ([D-10]). Idempotente, atómico, sin estados intermedios.

**Por qué esto no contradice [D-44]**, que rechazó la escritura por lotes en `Appearance`. Es el mismo eje,
leído en los dos extremos:

| | `Appearance` ([D-44]) | `SanctionBracket` |
|---|---|---|
| ¿La fila significa algo sola? | **Sí** — "Juan no fue convocado el domingo" | **No** — "el tramo 6-10" no dice nada sin los demás |
| Borrado implícito del lote | **Efecto lateral no deseado**: lo que no viene desaparece | **La semántica que se busca** |
| Errores parciales | Cada fila responde lo suyo | No existen: o el conjunto vale o no vale |
| Concurrencia | Dos entrenadores pisándose la lista entera | Configuración que toca una persona |

La regla que queda: **el lote es la respuesta correcta cuando la unidad de consistencia es el conjunto, no
cuando solo es más cómodo.** [D-44] sigue en pie para los hijos de `Match`.

**Corolario sobre los identificadores.** El `id` de cada tramo **no direcciona nada y no es estable entre
escrituras** —un `PUT` puede devolver ids nuevos con los mismos umbrales—. Vale como clave de lista, igual
que en `StandingRow` ([D-34]), y para nada más.

---

### D-51 · El cuerpo son umbrales, no tramos: cuando lo derivable es la relación entre filas

**Lo que queda por decidir una vez el `PUT` es del conjunto** ([D-50]): qué lleva. Lo natural era la lista
de tramos tal cual se almacenan —`[{seq: 1, yellowFrom: 0, yellowTo: 5}, …]`—, y sigue estando mal: se
pueden expresar huecos, solapes, `seq` repetidos y `seq` que no case con el orden. Cuatro validaciones para
un dato que **no tiene esos grados de libertad**.

**La observación.** Un conjunto de tramos contiguos que empieza en 0 queda **completamente determinado por
la lista ascendente de sus `yellow_to`**. `[5, 10, 13, 16]` solo puede significar `0-5, 6-10, 11-13, 14-16`.
Todo lo demás es derivable: `seq` es la posición en el array, `yellow_from` es el anterior más uno (o 0).

**Decisión.** El cuerpo es `{"thresholds": [5, 10, 13, 16]}`. El servidor deriva `seq` y `yellow_from`; la
**respuesta devuelve los tramos completos**, para que el cliente pinte `0-5, 6-10` sin rehacer la cuenta.
De las cuatro validaciones queda **una**: umbrales estrictamente ascendentes — y es **400**, no 422, porque
se juzga mirando solo el cuerpo (§5.4).

Es [D-28] —*una invariante se lleva a la estructura cuando se puede hacer imposible*— aplicado por primera
vez **al DTO** en vez de al esquema. Y es "derivar en lectura" un paso más allá: hasta ahora lo derivado era
un **campo**; aquí es la **relación entre filas**, así que lo que se recorta del DTO de escritura es la fila
entera. **El criterio general: el DTO de escritura lleva lo mínimo que determina el estado**, no un reflejo
del de lectura.

**Lo que se asume a cambio.** El cuerpo no se parece a la respuesta, asimetría que ningún otro recurso tiene.
Se acepta porque la alternativa admite cuatro formas de estar mal, y porque el backoffice ya piensa en
umbrales: el formulario pregunta "¿a las cuántas amarillas hay sanción?", no "¿dónde empieza el tramo 3?".

**Y una consecuencia del modelo que conviene tener escrita, porque no se ve venir: cambiar los tramos es
retroactivo.** Las amarillas pendientes se calculan **en vivo** sobre `Card` ([D-10]); no hay contador
almacenado que congele el pasado. Corregir a mitad de temporada una configuración mal metida reinterpreta
las tarjetas ya registradas, y **alguien puede pasar a estar sancionado sin que haya ocurrido nada en el
campo**. Es el comportamiento correcto —el contador vive en las tarjetas, que son el hecho— y no se
versionan los tramos: para un club pequeño, un histórico de configuraciones de sanción es maquinaria muy por
encima del problema.

---

### D-53 · El marcador manda y los goles no lo contradicen: sin validación de cuadre

**La pregunta que hará cualquiera que lea el contrato.** Si un `Match` dice 3-1 y solo hay dos `Goal`
registrados, ¿es un error?

**No, y no puede serlo**: el marcador es de la federación y es **completo y autoritativo** ([D-21]); los
goles son **entrada manual y parcial por diseño** ([D-04]). Un club que apunta el resultado el domingo y el
desglose el miércoles pasa días con la tabla incompleta; uno que nunca apunta los goles del rival tiene ese
bloque vacío para siempre, y su clasificación sigue bien.

Validar el cuadre convertiría el estado **normal** del sistema en un error, y obligaría además a apuntar los
goles en un orden concreto o a admitir estados inválidos temporalmente — que es no validar, pero con más
código.

**Decisión.** **No se valida**, ni en `POST` ni en `PATCH` ni en `DELETE`.

**Dónde sí vive la comprobación: en el backoffice, como aviso.** Es el criterio de [D-46] —**señalar, no
bloquear**— y su segunda aplicación, así que ya es convención: **las incoherencias entre registros manuales,
o entre uno manual y uno ingerido, se avisan en la interfaz; no se imponen en el contrato.**

**Corolario en el borrado.** Borrar un gol **no descuadra el marcador**, porque nunca estuvo cuadrado por
contrato. Es lo que permite que el `DELETE` sea el borrado lógico simple del resto del dominio manual
([D-36]) en vez de una operación con guarda.

---

### D-54 · La denormalización de [D-04] no llega al DTO: se escribe quién marca, se deriva quién encaja

**El problema que [D-04] dejó abierto.** `Goal` guarda **dos** FKs a `Team` —el que marca y el que encaja—
copiadas del `Match`, para que "goles a favor" y "goles en contra" sean filtros directos sin *join*. [D-04]
dijo que mantenerlas consistentes es tarea de la capa de aplicación, "nunca del usuario". Faltaba
materializarlo en el contrato.

**Si las dos estuvieran en el DTO de alta**, el cliente podría enviar un par que no son los del partido, o
invertidos, o uno bien y otro mal: tres validaciones para reconstruir algo que **el servidor ya sabe**. Los
dos equipos están en el `Match`, y con saber cuál marcó, el otro queda determinado.

**Decisión.** El cuerpo lleva **`scoringTeamId`** y no `concedingTeamId`. El servidor lo deriva del `Match`.
Queda **una** validación —que `scoringTeamId` sea uno de los dos equipos del partido— en vez de tres, y la
incoherencia entre las dos columnas **deja de ser expresable**. Es el criterio de [D-28] aplicado al DTO,
como en [D-51].

**Una categoría nueva que conviene nombrar.** El contrato distinguía *derivado en lectura* (`isOwn`,
`displayName`: se calcula al responder, no se almacena) y *propiedad de la ingesta* (`federationTeamId`: se
almacena, lo escribe otro módulo). `concedingTeamId` no es ninguna: **se almacena** —esa es la gracia de
[D-04]— y **lo escribe el servidor** en la misma operación que el resto. Llamémoslo **denormalización de
servidor**: se guarda, se lee, y el cliente no la toca.

**Lo que se asume a cambio.** Que los DTOs de escritura y lectura difieren en un campo, cosa que solo pasa
además en `SanctionBracket` ([D-51]). La alternativa —aceptar el campo y rechazarlo si no cuadra— sería
pedirle al cliente un dato que no le corresponde para luego decirle que se equivocó.

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
[D-30]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-31]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-32]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-33]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-34]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-19]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-35]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-36]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-37]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-03]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-06]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-12]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-10]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-20]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-38]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-39]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-40]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[Anexo de la Federación]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.1]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.2]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.3]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.4]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
[Anexo de la Federación §F.6]: ./API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md
