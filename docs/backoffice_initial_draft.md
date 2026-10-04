# Backoffice — borrador inicial

> **Qué es esto:** el encuadre acordado el **2026-09-25**, antes de escribir una línea. **No es un plan de
> fases** —el [Plan de desarrollo-001](./Plan%20de%20desarrollo-001.md) cubre solo la ingesta (F0–F10)— ni
> sustituye al ADR ni al LLD del módulo, que **siguen sin escribir**. Es lo que hay que tener delante para
> abrirlos.

**De dónde se parte:** la ingesta está **entregada de punta a punta** (F10, 47 ciclos, 541 tests). El
contrato de la API está **escrito entero** desde F0 y el `filter` del generador es el que decide qué parte se
sirve: **la lista de operaciones implementadas *es* el alcance entregado** ([D-69]). Hoy son seis.

---

## 1. Prerrequisito · la ingesta corriendo en local

**Decisión: se monta con `launchd` en el Mac, no con `crontab`.**

No bloquea nada —ya hay 480 partidos en la base local— y aun así va primero, porque **es lo único que paga
por empezarlo pronto**: cada semana que corre, la base local se parece más a la de un club de verdad
(clasificación con huecos, nombres con la letra embebida, aplazados, alguna pasada fallida). Es contra eso
contra lo que se van a diseñar las pantallas, y este proyecto ya ha pagado cuatro veces por diseñar contra
montajes hechos a mano, que solo contienen lo que uno ya sabía.

**Por qué `launchd` y no `cron`:** un disparo de `cron` que caiga con el portátil dormido **se pierde**;
`launchd` con `StartCalendarInterval` lo ejecuta **al despertar**. Importa más aquí que en otros sitios: §5.6
pide lunes + fin de semana porque **la clasificación no se puede pedir hacia atrás**, así que la semana que
se salta no se recupera.

Dos cosas que ya están resueltas y no hay que rehacer:

- **El antirrebote** (`--min-interval-hours`, 6 por defecto) hace inofensivo un disparo de más. No es el tope
  semanal: eso lo pone el calendario de disparos ([D-87]).
- **Con Postgres parado no pasa nada malo**: la pasada se detiene, lo dice y sale con código distinto de cero
  ([D-86]). No deja nada a medias.

---

## 2. Método · rebanadas verticales, no capas

**Una pantalla con los endpoints que necesita**, y no *"todo el BFF y luego todo el backoffice"*.

Dos razones, las dos del propio proyecto:

- **La maquinaria ya es incremental.** El `filter` del generador existe precisamente para esto ([D-69]): se
  añade la operación cuando se implementa, y el contrato no se toca porque ya está escrito.
- **Las pantallas encuentran lo que falta; los endpoints en abstracto, no.** §9.12 —*"ninguna lectura sirve
  la terna (equipo, temporada, competición)"*, que es lo que el backoffice llama «un equipo»— **se descubrió
  diseñando una pantalla**, no leyendo el modelo.

### Las dos primeras rebanadas

| # | Pantalla | Por qué ésta |
|---|---|---|
| 1 | **La portada**: los equipos del club con su competición | El modelo **ya está hecho** —la enmienda de [D-68] la hace servible sin tocar `Match` y desde el instante del enganche—; es **de solo lectura**, así que no abre superficie de escritura ni urgencia de autenticación; demuestra que la ingesta hizo su trabajo; y **cierra §9.12**, el único hueco de lectura conocido |
| 2 | **Alta de equipo**: `POST /v1/teams` + inscripciones | Es la puerta que F10 señaló una y otra vez. **Aviso**: tiene el mismo agujero de identidad que documentó `C-A.3` — es la otra puerta que afirma a mano la correspondencia equipo↔competición. La guarda ya existe en el Dominio (`Team.requireIdentityMatches`, `C-C.15`) y **se reutiliza, no se reescribe**: por eso se puso allí |

---

## 3. Autenticación · al final, y con los ojos abiertos

**Decisión: va la última.** Mientras tanto, **web y API en local**, con el club resuelto por subdominio
(`atleti.localhost:8080`) como hasta ahora.

Lo que eso significa, dicho una vez para que no se olvide: **hoy la API no tiene ningún control de acceso** —
es la deuda declarada de F0—, así que cualquiera que la alcance distingue un club que existe de uno que no, y
puede pedir los datos de cualquiera cambiando el subdominio. En local eso es aceptable; **el día que sea
alcanzable desde fuera, no**.

**La costura ya está puesta** y eso abarata el final: `C-E.2` sacó el actor a un puerto (`ActorResolver`), así
que montar la autenticación es **cambiar el adaptador de producción**, no el middleware ni los *handlers*. Lo
que hoy lee el `Host` pasará a leer el `club_id` del JWT de Supabase Auth ([D-59]: el club sí viaja en el
*claim*, el rol no).

Y cae en el mismo momento que el resto del despliegue: **Fly.io trae a la vez la autenticación, el cron de
verdad y el CI**, que son los tres deberes que no son de ninguna fase.

---

## 4. Lo que hay que decidir antes de la primera rebanada

- **El *stack* de la web.** La tabla de módulos de [AGENTS.md](../AGENTS.md) tiene el ADR y el LLD del
  backoffice **en blanco**. Es lo primero que se escribe.
- **Si el backoffice estrena su propio plan de fases** o vive como rebanadas sueltas. Por el tamaño, esto
  segundo — pero la regla 2 del plan de auditoría sigue valiendo: **lo que toque más de un *target* o cambie
  una API pública es mini-fase con su renglón**.

---

## 5. Dos datos que ya llegan de la federación y se pierden en la ingesta

Anotado el **2026-10-04** desde la auditoría 002 (A-9, sospecha 5). El puerto de federación ya los recibe,
pero **ningún caso de uso los lee**, así que no llegan ni al modelo ni al contrato. El puerto los conserva
como excepción declarada a su regla *"un campo sin lector no se transporta"*. Lo que falta está detrás:
recogerlos en la ingesta, guardarlos y exponerlos.

| Dato | En el puerto | Quién lo necesitará | Lo que falta |
|---|---|---|---|
| **La jornada en curso** | `FederationCalendar.currentRound` | **El backoffice** | Que `IngestCalendar` lo lea, un sitio en el modelo (`Competition` o `Round`) y su campo en el contrato |
| **El código del campo de juego** | `FederationMatch.venueCode` | **No es de la UI del backoffice**: es la clave de las **consultas de direcciones para los mapas** | Que `IngestCalendar` lo lea, un sitio en el modelo (hoy `Match.venue` es solo texto) y su campo en el contrato |
