# Plan launchd-001 · La ingesta corriendo sola en el Mac

> Abierto el **2026-10-04**, con la [auditoría 002](./Plan%20de%20auditor%C3%ADa-002.md) cerrada y la puerta
> de `launchd` abierta (§6-bis de aquel fichero), y **591 tests**.
>
> Convención, la misma del resto del proyecto: **`§x` remite al [LLD-001](../docs/API_y_BBDD%20LLD-001.md)**,
> `D-nn` a la [bitácora de decisiones](../docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md), `A-n`/`H-nn`
> al [Plan de auditoría-002](./Plan%20de%20auditor%C3%ADa-002.md) y «el borrador» al
> [borrador inicial del backoffice](../docs/backoffice_initial_draft.md). Las remisiones a **este** fichero van
> como `L-X.n` (bloque X, paso n), y las decisiones pendientes como `DL-n`.
>
> **Este fichero es plan y registro a la vez.** Un paso sin renglón en §5 no está hecho.

---

## 0. Qué entrega este plan

**`ingest` disparado por `launchd` en el portátil del desarrollador**, contra la base de trabajo
(`club_atleti` en el Postgres de `docker compose`), en la cadencia de `D-87`, **con una señal que una persona
llegue a ver** cuando el disparo falla o no hace nada.

Es el **prerrequisito §1 del borrador**, y su justificación no cambia: cada semana que corre, la base local se
parece más a la de un club de verdad —clasificación con huecos, aplazados, pasadas fallidas—, y es contra eso
contra lo que se van a diseñar las pantallas. **Lo que no se capture una semana no vuelve**: la clasificación
no se puede pedir hacia atrás (`D-55`, §5.6).

Y cierra los tres hallazgos que la auditoría 002 dejó con dueño *"montar `launchd`"*:

| Hallazgo | Sev. | Lo cierra |
|---|---|---|
| **H-85** · `launchd` no puede ejecutar `.build/debug/Run` | S2 | Bloque I |
| **H-59** · Las salidas de una pasada desatendida no las lee nadie, y el plan vacío sale en verde | S2 | Bloques P y L, con `DL-1`…`DL-3` |
| **H-92** · Nadie reintenta el `null` pasajero | S3 | Bloques M y R, con `DL-4` |

**No es código de la aplicación**, salvo lo que decida `DL-4`: son guiones, un `.plist` y datos. Por eso la
mayoría de los pasos **no son ciclos TDD** sino pasos con su **verificación escrita** (§3).

---

## 1. Lo que ya está decidido y NO se vuelve a discutir

### 1.1 `launchd` y no `cron` — el borrador, §1

Un disparo de `cron` con el portátil dormido **se pierde**; uno de `launchd` con `StartCalendarInterval` se
ejecuta **al despertar**. Con la clasificación irrecuperable, esa diferencia es la que decide.

> **Lo que eso NO cubre, y hay que medirlo en vez de suponerlo (`L-L.4`):** el portátil **apagado** a la hora
> del disparo. La documentación de `launchd` solo habla de *dormido*.

### 1.2 La cadencia: lunes, sábado y domingo — `D-87`

La pone quien dispara, no el proceso. Lunes trae los horarios de la semana y el resultado de la jornada; sábado
y domingo, los marcadores. De martes a viernes no hay nada nuevo. **Las horas no están decididas** (`DL-3`).

### 1.3 Lo que el código ya trae y no se rehace

- **El antirrebote** (`--min-interval-hours`, 6 h por defecto) hace inofensivo un disparo de más (`D-87`).
- **Con Postgres parado no pasa nada malo**: la pasada se detiene, lo dice y sale con código `1` (`D-86`). No
  deja nada a medias. Con Docker Desktop cerrado a la hora del disparo pasa exactamente eso, y por eso la señal
  de `DL-1` tiene que cubrirlo.
- **Un fallo no detiene el recorrido**: la unidad de aislamiento es la competición, y `exit 1` si alguna falló.

### 1.4 El binario: instalado desde un commit, nunca `.build/debug/Run` — H-85

Es la salida que la auditoría dejó escrita: `swift build -c release` **desde un commit**, copiado **fuera de
`.build`**. El motivo es que `swift build`, `swift test` y cada mutación de `Tools/Mutate` reescriben el
mismo `.build`. Un disparo que cayera en mitad de una de esas pasadas ejecutaría código roto a propósito contra
`club_atleti`. **Lo que se garantiza en cada disparo no es que `main` esté en verde, sino que lo que se
ejecuta salió de un commit conocido.**

### 1.5 `LaunchAgent` del usuario, no `LaunchDaemon`

Postgres vive en **Docker Desktop**, que corre en la sesión del usuario. Un *daemon* de sistema dispararía
también sin sesión iniciada, y en ese caso no habría base a la que conectarse. Además, el agente sí puede
enseñar una notificación (`DL-1`) y el *daemon* no. Va en `~/Library/LaunchAgents/` y se carga con
`launchctl bootstrap gui/$(id -u)`.

### 1.6 Ni Fly.io, ni el CI, ni el cron de verdad

Llegan juntos con el despliegue (el borrador, §3). **Este plan monta un disparador local para acumular datos;
no es el despliegue.** El día que la ingesta corra en Fly.io contra la base de verdad, el agente local **se
desinstala** (`L-L.5` deja escrito cómo).

**Al CI no le afecta.** El CI garantiza que lo que entra en `main` está en verde (H-07). `launchd` no ejecuta
tests y garantiza otra cosa: que lo que corre **salió de un commit conocido** (H-85). En Fly.io las dos se
encadenan solas: el CI en verde, `fly deploy` construye la imagen desde ese commit y el disparo la ejecuta.
Aquí, `install.sh` hace de `fly deploy`.

**Qué se lleva a Fly.io y qué se tira**, para que la sesión que lo monte no lo vuelva a pensar:

| Sobrevive | Se tira |
|---|---|
| `Run ingest` con sus *flags*, el antirrebote y los códigos de salida. `D-87` puso el disparador fuera del proceso justo para que se pudiera cambiar | El `.plist` |
| Las horas (`DL-3`) y lo que `ingestion_runs` diga de ellas | El envoltorio y su `osascript` |
| La medida del `null` (`L-M`) y la decisión de dónde reintentar (`DL-4`) | `install.sh`: lo sustituye el `Dockerfile`, que ya existe |
| *"Vacío = fallo"* (`L-L.0`), porque es código de la aplicación | |
| El **concepto** de la señal (`DL-1`); en Fly cambia la forma (correo, chequeo de salud…) | |

**Cómo se disparará en Fly.io: se decide allí, con su documentación de ese día delante.** Hay dos candidatos.
Las *Scheduled Machines* tienen, de memoria y sin verificar, intervalos gruesos (cada hora, diario, semanal) y no
admiten hora exacta: con uno diario funcionarían gracias al antirrebote, pero preguntarían a la RFFM de martes
a viernes. El otro es un cron dentro de una máquina (p. ej. `supercronic`), que es lo más parecido a esto. Y con
servidor y cron en máquinas distintas, **el borde de reloj que A-11 dejó apuntado deja de ser teórico**: si el
reloj de quien cierra va por detrás del de quien aceptó, la fila `accepted` se queda abierta
(`IngestCalendar.swift:97`).

**Vale la pena montarlo igualmente, por dos razones.** La base local acumula semanas reales desde ya, y contra
eso se diseñan las pantallas del backoffice, que va antes que Fly.io. Y lo que se aprende aquí se lleva entero
a Fly.io. Lo desechable son un `.plist` y dos guiones.

---

## 2. Lo que decide el desarrollador, y con qué evidencia delante

Las cuatro primeras son la *"pregunta 6"* de A-11, que la auditoría dejó como **"no se mide, se decide"**
(H-59). Cada una lleva **el comando para verlo uno mismo** antes de elegir.

### `DL-1` · ¿Qué señal llega a una persona cuando un disparo falla?

Hoy las salidas son cuatro, y ninguna la lee nadie (H-59):

1. El código de salida, que lo ve `launchd` y no avisa.
2. La consola, que va a donde diga `StandardOutPath`.
3. `ingestion_runs`, pero solo mientras la base responda (`D-85`), y la lectura que lo haría visible
   (`ingestionHealth`) no existe hasta la rebanada 1 (H-58).
4. El log del servidor, que es del `202` y no de `launchd`.

| Opción | Lo que cuesta | Lo que no cubre |
|---|---|---|
| **a.** Solo el log en `~/Library/Logs/tfm/` | Nada | Es la ceguera de A-4 con otro nombre: nadie lo abre |
| **b.** Notificación de macOS (`osascript -e 'display notification …'`) desde el envoltorio, más el log | Una línea; depende de que el Terminal / `osascript` tenga permiso de notificaciones | Si el portátil está cerrado se ve al abrirlo, que aquí basta |
| **c.** (b) y además un fichero `~/Library/Logs/tfm/ULTIMO_FALLO` que no se borra hasta que lo borre una persona | Dos líneas | — |

**Propuesta: (c).** La notificación avisa y el fichero se queda ahí aunque la notificación se pierda.

### `DL-2` · ¿Un recorrido vacío cuenta como fallo?

```sh
.build/debug/Run ingest; echo $?
# → "0 competición(es) sincronizada(s), 0 con fallo · 1 club(es) sincronizados"  y  0
```

Esto es lo que saldría hoy, porque la base solo tiene `2025/26`:

```sh
docker exec backend-db-1 psql -U tfm -d tfm -c "select label from club_atleti.seasons;"
```

Hay que distinguir dos casos de *"0 sincronizadas"*. En el primero, **el antirrebote lo ha saltado todo**: es
legítimo, es un disparo de más. En el segundo, **no había nada que recorrer**: es el verde engañoso de H-59.
Hoy la salida no separa uno de otro.

**Propuesta:** el envoltorio trata **"0 sincronizadas y 0 con fallo"** como fallo **solo si en el mismo
disparo no hubo nada saltado por el antirrebote**. Para separarlos, `ingest` tiene que decir cuántas saltó, y
eso **es código de la aplicación**. Si se decide así, es un ciclo TDD en `IngestCommand` (`L-L.0`) y va antes
del envoltorio. La alternativa barata es que el envoltorio cuente las competiciones de la temporada vigente
con `psql`, pero eso lleva SQL al guion y conocimiento del esquema fuera de la aplicación. **No la recomiendo.**

### `DL-3` · ¿A qué hora dispara?

Lo medido:

- A-10: la RFFM devolvió `504` tras 60 s en `/api/scorers`, **un domingo de partido**.
- A-11 / H-61: un `null` pasajero **un miércoles a las 17:44 UTC**, así que también falla fuera de los días de
  partido.

**Propuesta:** **sábado y domingo a las 23:30** (con los marcadores ya puestos y la fuente fuera de su pico) y
**lunes a las 08:00**, en hora local. Es una propuesta sin medir. `L-M` mide la duración del `null`, no a qué
hora contesta peor la fuente. Si al cabo de un mes `ingestion_runs` enseña un patrón, la hora se mueve.

### `DL-4` · ¿Dónde se reintenta el `null` pasajero? — **se decide después de `L-M`, no antes**

**Lo que el plan encontró al leer el código, y que cambia la pregunta.** Pensé que un **segundo disparo**
una o dos horas después serviría de reintento gratis, porque el antirrebote solo salta lo sincronizado con
éxito. **No es así para la parte que falla.** `last_synced_at` lo escribe **solo la pasada de calendario**
(`CalendarPass.swift:122-127`), y el antirrebote filtra por **competición** con ese campo
(`IngestClubCalendars.swift:327-333`). El `null` pasajero cae en **clasificación y goleadores** (H-61). Por
tanto, una competición con calendario bueno y clasificación en `null` **queda saltada por el antirrebote
durante 6 h**, y el segundo disparo no la reintenta. *(Esto está leído, no ejecutado. `L-M.3` lo confirma
contra la base.)*

Las salidas posibles, que se eligen con la medida de `L-M` delante:

| Opción | Dónde | Cuándo sirve |
|---|---|---|
| **a.** Reintento con espera **en el adaptador RFFM** | Código, cabe en `D-97` (es conocimiento del universo RFFM; el puerto no cambia) | Si el `null` dura **segundos** |
| **b.** Segundo disparo de `launchd` con `--force`, o con `--min-interval-hours` menor que el hueco | El `.plist` | Si dura **minutos u horas**. Coste: rehace el calendario de todas, que es idempotente (§3.7) |
| **c.** Segundo disparo **solo de lo que falló** (`ingest -c <las fallidas>`) | El envoltorio, leyendo la salida | Más fino que (b), pero el envoltorio pasa a parsear la salida de `ingest` |
| **d.** Que el antirrebote mire **la última pasada con éxito de cada clase** y no `last_synced_at` | Código, en `IngestClubCalendars.due` | Es lo correcto a la larga, y toca `D-87` y el significado de `D-89` (H-58), así que pertenece a la rebanada 1. **Se apunta y no se hace aquí** |

### `DL-5` · ¿Cómo corre el canario programado?

H-85 dejó apuntado que el canario cabe en `launchd` desde el primer día. **Pero el canario es un test**
(`FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests`), así que ejecutarlo programado **es ejecutar
`swift test` en el árbol de trabajo**, que es justo lo que §1.4 aparta del disparador.

| Opción | Lo que cuesta |
|---|---|
| **a.** Un **clon aparte**, de solo lectura, en el commit instalado, y `swift test` ahí | Un segundo `.build` (varios GB) y unos minutos de compilación en cada disparo, o cada vez que se reinstala |
| **b.** Un subcomando `Run canary` que reutilice las comprobaciones del test | Código nuevo, y la lógica del canario en dos sitios, o movida a un *target* compartido |
| **c.** No programarlo todavía: el disparo de `ingest` ya es un canario de hecho (un parser roto da `failed` y la señal de `DL-1`) | Nada. Se pierde solo distinguir *"ha cambiado la fuente"* de *"la fuente falla"* |

**Propuesta: (c) por ahora.** El bloque C queda condicionado a que la experiencia con (c) diga que hace falta.

---

## 3. El método

**Cada paso lleva su verificación, escrita antes de hacerlo y ejecutada al hacerlo.** La mayoría no son
ciclos TDD porque no hay regla de dominio que afirmar: hay un guion que hace lo que dice o no. Los que tocan
código de la aplicación (`L-L.0` y, según `DL-4`, `L-R.1`) **sí** son ciclos, con el bucle de siempre (Plan
§5.1): test, esqueleto que devuelve mal a propósito, rojo de aserción, implementación, mutación con
`Tools/Mutate` y su catálogo.

**Los avisos, los de siempre más dos de aquí:**

1. **`REQUIRE_DB=1 swift test`**, nunca `swift test` a secas (A-7, H-07).
2. **No tumbar el Postgres del desarrollador.** Trabaja con la app y TablePlus conectados. Las pruebas de
   *"con Docker parado"* se hacen con **otro** puerto (`DB_PORT=1` en el entorno del disparo), no parando el
   contenedor.
3. **La regla 9 de la auditoría**: antes de cualquier paso que escriba en `club_atleti`,
   `pg_dump -n club_atleti` a la carpeta de *scratch*.
4. **Un `launchctl` que no se queja no ha cargado nada.** `bootstrap` sobre un `.plist` mal formado o
   con una ruta inexistente puede fallar en silencio. **La verificación es siempre `launchctl print
   gui/$(id -u)/<label>`**, y que en el log aparezca la línea del disparo.

### La plantilla del prompt de entrada

```
Ejecuta el bloque <X> del plan de launchd en `backend/Plan launchd-001.md`.

Lee §0 a §3 y §5 de ese fichero, y el «Leer antes» de tu bloque.

Cuatro límites:
  1. Cada paso con su verificación ejecutada; si es código de la aplicación, ciclo TDD (§3).
  2. No amplíes el alcance: lo que descubras que falta va a §7.
  3. Lo decidido en §1 no se rediscute; lo de §2 lo decide el desarrollador.
  4. No pares el Postgres del desarrollador.

Al terminar: pon tus pasos al día en §5.
```

---

## 4. Los bloques

El orden es **P → M → I → L → R**, y C queda condicionado a `DL-5`. **P va primero** porque sin datos que
recorrer todo lo demás se verifica contra un recorrido vacío, que sale en verde (H-59). **M va antes que L**
porque mide algo que solo se puede medir mirando, y lo que mide decide la forma de L y de R.

### Bloque P · Prerrequisito de datos — la temporada 2026/27 enganchada

**Leer antes:** `README.md` §4.1 (el enganche) y §6.3 (`seed-team`); la nota de cierre de A-11 en la auditoría.

| Paso | Qué | Verificación |
|---|---|---|
| `L-P.1` | Respaldo: `pg_dump -n club_atleti` al *scratch* | El fichero existe y no está vacío |
| `L-P.2` | Por cada equipo a seguir: `seed-team` si no existe, después `/preview` y `federation-link` con la URL de la RFFM de 2026/27. **Las URLs las da el desarrollador** | El `202` de cada uno, y `select label from club_atleti.seasons` → aparece `2026/27` |
| `L-P.3` | `ingest` a mano, sin `--force` | Salida con **N > 0** competiciones sincronizadas, `exit 0`, y filas nuevas en `ingestion_runs` de las tres clases |
| `L-P.4` | Comprobar que la vigente es la nueva: `ingest` sin `--season` recorre 2026/27 y no 2025/26 | Los `competition_id` de las filas del paso anterior son los de 2026/27 |

### Bloque M · Medir el `null` pasajero — H-92

**Leer antes:** H-61 y H-92 en la auditoría; `README.md` §5.1 (el canario).

| Paso | Qué | Verificación |
|---|---|---|
| `L-M.1` | Bucle en el *scratch*: el canario (o un `curl` a `/api/standings` y `/api/scorers` de una coordenada de 2026/27) **cada 30 s**, con hora y resultado por línea | El fichero crece con una línea por intento |
| `L-M.2` | Dejarlo correr **varias horas, incluido un fin de semana** de partido. Anotar cada racha de `null`: cuándo empieza, cuánto dura y qué endpoint | Una tabla en §5 con las rachas. **Si en todo el periodo no aparece ningún `null`, se escribe así y `DL-4` se decide sin el dato** |
| `L-M.3` | Confirmar contra la base el hallazgo de `DL-4`: calendario bueno y clasificación `failed` → un segundo `ingest` dentro de las 6 h **salta** esa competición | La salida del segundo `ingest` y su `ingestion_runs`. Si no la salta, se corrige `DL-4` |

**El guion de medida no se versiona** (como las sondas de A-11). Lo que se versiona son las cifras, aquí.

### Bloque I · El binario instalado — H-85

**Leer antes:** H-85; `Tools/Mutate/README.md` (por qué comparte `.build`).

| Paso | Qué | Verificación |
|---|---|---|
| `L-I.1` | `Tools/Deploy/install.sh [<ref>]`. **Compila un commit, no el árbol**: `git archive <sha> backend` a un directorio aparte y `swift build -c release --scratch-path $TFM_HOME/build`, fuera de `.build`. Copia `Run` a `~/Library/Application Support/tfm/releases/<sha>/Run`, escribe `VERSION` (commit, rama, fecha) y mueve el enlace `current` de forma atómica. Lo que no está commiteado **no entra, y el guion lo avisa**; también avisa si no se instala desde `main`. Guarda las 5 últimas versiones | Con una referencia que no existe: sale con `≠ 0` y no crea nada. Con una buena: el binario existe, `current/Run --help` lista `ingest`, y con un cambio sin commitear en `Sources/` sale el aviso |
| `L-I.2` | El instalado no depende de `.build`: compilar algo distinto en `.build` (o borrarlo) y volver a ejecutar `current/Run ingest --help` | Funciona igual, y `shasum` del instalado no ha cambiado |
| `L-I.3` | El binario *release* contra la base de trabajo: `current/Run ingest` (el antirrebote evita repetir lo de `L-P.3`) | `exit 0`, y la salida dice cuántas saltó o cuántas sincronizó |

**¿Desde qué rama?** La propuesta es **solo desde `main`**, para que *"lo que corre"* sea siempre algo
fusionado. Pero eso impide probar este mismo plan antes de fusionarlo. Por eso el guion **avisa** si no está en
`main` y no se niega. El `VERSION` dice de dónde salió.

### Bloque L · El agente — H-59

**Leer antes:** `DL-1`, `DL-2` y `DL-3` **ya decididas**; `IngestCommand.swift` (la línea de resumen, 290-315).

| Paso | Qué | Verificación |
|---|---|---|
| `L-L.0` | **Dos ciclos TDD** (`DL-2`). **(1)** `ClubIngestionReport.skippedByDebounce`: el informe cuenta lo que saltó el antirrebote, y la línea de resumen lo dice. **(2)** `ingest --fail-if-empty`: un club sin nada recorrido, fallido ni saltado (`TenantIngestion.isEmpty`) cuenta como incompleto y el proceso sale con `1`. Es opcional para que quien lo lanza a mano no vea rojo con un club recién dado de alta. **El envoltorio solo lee el código de salida**: no analiza la salida | Rojo de aserción → verde en los dos; catálogo `Tools/Mutate/Catalogs/launchd-L0.json`. El cableado de `run()` (una `Signature` no se construye en un test) se prueba a mano contra la base vacía: sin el flag `exit 0`, con él `exit 1` |
| `L-L.1` | `Tools/Deploy/run-ingest.sh`, el envoltorio: pone el entorno `DB_*`, antepone hora y `<sha>` a cada línea, ejecuta `current/Run ingest` y traduce el resultado a la señal de `DL-1` (fallo, base caída o recorrido vacío según `DL-2`) | Ejecutado a mano tres veces: **éxito** (sin señal), **base inalcanzable** con `DB_PORT=1` (señal) y **vacío** con `-t` de un club sin competiciones vigentes o equivalente (señal según `DL-2`) |
| `L-L.2` | `Tools/Deploy/com.tongilcoto.tfm.ingest.plist` (plantilla versionada) con `StartCalendarInterval` según `DL-3`, `StandardOutPath`/`StandardErrorPath` en `~/Library/Logs/tfm/`, y `install.sh` copiándolo y cargándolo (`bootout` + `bootstrap`) | `plutil -lint` limpio; `launchctl print gui/$(id -u)/com.tongilcoto.tfm.ingest` muestra los disparos programados |
| `L-L.3` | Disparo forzado: `launchctl kickstart gui/$(id -u)/com.tongilcoto.tfm.ingest` | Línea nueva en el log con `<sha>`, filas en `ingestion_runs` y `last exit code` en `launchctl print` |
| `L-L.4` | **Dormido y apagado**: programar un disparo de prueba a +5 min, dormir el portátil, despertarlo después; repetir **apagándolo** | Dormido: el disparo aparece al despertar (§1.1). Apagado: **se escribe lo que pase**, y si no se ejecuta, va a §7 como riesgo conocido para los fines de semana |
| `L-L.5` | Desinstalar y reinstalar limpio (`bootout`, borrar, `install.sh`) | `launchctl print` no lo encuentra tras el `bootout`, y vuelve tras la reinstalación |

### Bloque R · El reintento — H-92

**Leer antes:** la tabla de `L-M.2` y `DL-4` **ya decidida**.

| Paso | Qué | Verificación |
|---|---|---|
| `L-R.1` | Según `DL-4`: (a) ciclo TDD en el adaptador RFFM con el doble de transporte devolviendo `null` *n* veces; o (b)/(c) segundo `StartCalendarInterval` y/o lógica en el envoltorio | (a) rojo de aserción y catálogo de mutación. (b)/(c) un disparo con una competición `failed` previa la vuelve a pedir, visto en `ingestion_runs` |
| `L-R.2` | Corregir la promesa de `FederationError.swift:10` (*"degrada y reintenta (§3.7)"*) para que diga lo que hace de verdad | `grep` del comentario |

### Bloque C · El canario programado — **condicionado a `DL-5`**

Vacío mientras `DL-5` sea (c). Si se reabre, sus pasos se escriben aquí antes de empezar.

### Bloque D · Documentación y cierre

| Paso | Qué |
|---|---|
| `L-D.1` | `README.md`: sección nueva *"La ingesta programada"* (instalar, desinstalar, dónde mirar el log, qué significa la señal), y quitar *"Hoy no hay cron"* de §6.3 |
| `L-D.2` | Auditoría 002: H-59, H-85 y H-92 a **cerrado**, cada uno con su paso de aquí |
| `L-D.3` | `AGENTS.md`: «Estado actual» y la tabla de documentación clave, enlazando este plan |

---

## 5. Estado

| Bloque | Estado | Pasos | Fecha |
|---|---|---|---|
| **P** · Datos 2026/27 | ⏳ pendiente — **espera las URLs del desarrollador** | 0/4 | — |
| **M** · Medir el `null` | ⏳ pendiente | 0/3 | — |
| **I** · Binario instalado | ✅ entregado — adelantado a P y M porque no depende de ellos | 3/3 | 2026-10-05 |
| **L** · El agente | 🔄 en curso — falta `L-L.4` (dormir/apagar; lo hace el desarrollador) | 5/6 | 2026-10-05 |
| **R** · El reintento | ⏳ pendiente — **espera `L-M` y `DL-4`** | 0/2 | — |
| **C** · Canario programado | ⏸ condicionado a `DL-5` | — | — |
| **D** · Documentación | 🔄 en curso — `L-D.1` entregado (README §6.3 y §6.4) | 1/3 | 2026-10-05 |

| Decisión | Estado |
|---|---|
| `DL-1` · Señal | ✅ **(c)**: notificación + log + `ULTIMO_FALLO` — decidido el 2026-10-05 |
| `DL-2` · Vacío = fallo | ✅ **sí, salvo lo saltado por el antirrebote**, con `L-L.0` — decidido el 2026-10-05 |
| `DL-3` · Horas | ✅ **sáb y dom 23:30, lun 08:00**, hora local — decidido el 2026-10-05 |
| `DL-4` · Reintento | **se decide tras `L-M`** |
| `DL-5` · Canario | propuesta (c); **sin decidir** |

**Punto de partida: 591 tests.**

**`L-L.1` a `L-L.3` y `L-L.5` (2026-10-05).** Tres ficheros en `Tools/Deploy/`: `run-ingest.sh` (el
envoltorio), la plantilla `com.tongilcoto.tfm.ingest.plist` y `agent.sh install|uninstall|status|run`. **Un
cambio respecto al plan**: el envoltorio **tampoco** se ejecuta desde el árbol. `install.sh` lo copia **del
mismo commit** que el binario, a `releases/<sha>/run-ingest.sh`, y el `.plist` apunta a `current/`. Es H-85
otra vez: un cambio de rama no puede cambiar lo que dispara `launchd`. Medido:

- **`L-L.1`**, a mano con el log en el *scratch*: éxito (`--season <2025/26> --min-interval-hours 100000`) →
  `exit 0`, *"2 saltada(s) por el antirrebote"*, sin señal. Base inalcanzable (`DB_PORT=1`) → `exit 1` con
  señal. Vacío → `exit 1` con señal. `ULTIMO_FALLO` acumula y no sobrescribe.
- **`L-L.2`**: `plutil -lint` OK; `launchctl print` muestra los tres disparos de `DL-3` (`Weekday` 6 y 0 a las
  23:30, 1 a las 08:00).
- **`L-L.3`**: `agent.sh run` (`kickstart`) → `runs = 1`, `last exit code = 1` (el vacío de hoy), la línea en
  `~/Library/Logs/tfm/ingest.log` con el commit, la entrada en `ULTIMO_FALLO`, y `launchd.log` vacío.
- **`L-L.5`**: `uninstall` → el `.plist` desaparece y `launchctl print` no lo encuentra; `install` lo vuelve a
  dejar cargado.
- **Reinstalar con dependencias ya compiladas: 19 s** (frente a los 3 min 15 s de la primera vez).
- **La notificación se ve**: el desarrollador recibió las tres de estas pruebas. **Eran idénticas**, y de ahí
  el cambio siguiente.

**Después, a petición del desarrollador**: el aviso y `ULTIMO_FALLO` llevan **el motivo**, sacado de la salida
del disparo (*"la base no responde: ¿está Docker parado?"*, *"atleti: nada que recorrer…"*), y `agent.sh
status` lista los disparos que `launchd` tiene cargados. Lo que decide si hay aviso sigue siendo **solo el
código de salida**. Probado otra vez con los tres casos de `L-L.1`.

**Queda cargado desde el 2026-10-05**, con `81b1cea`. Para actualizarlo basta `install.sh`: el `.plist` apunta a
`current/`, así que no hay que recargar el agente. Hasta que P dé de alta 2026/27, **cada disparo avisará de
que está vacío**, y es lo correcto: es el verde de H-59 convertido en rojo.

> *(Estas notas tenían que haber entrado en `3ed2dde`, cuyo mensaje las anuncia. No entraron porque un `grep`
> de comprobación falló y cortó la cadena de comandos antes de editar este fichero. El commit solo llevó
> `agent.sh`. Se vio el mismo día, al ir a añadir la nota siguiente.)*

**`L-L.0` (2026-10-05): 591 → 599 tests, 12/12 mutaciones**, contadas en el XML (`<testcase>`: 599, 0 fallos,
3 omitidos, que son los del canario). Ocho tests: dos del informe y uno ampliado en `IngestClubCalendarsTests`
(el de sin intervalo mínimo afirma además `skippedByDebounce == 0`, porque sin esa aserción `S3` sobrevivía), y
seis en `IngestEmptyTraversalTests`, de nivel 1. Dos cosas que salieron por el camino:

- **El `error == nil` de `isEmpty` era una mutación equivalente**: `ingest` nunca construye un club con
  informe y error a la vez. Se quitó en vez de declararlo, para que el código no prometa una comprobación que no
  hace nada.
- **El mensaje final mentía en el caso vacío**: *"El motivo de cada pasada está en su fila de
  `ingestion_runs`"*, y un recorrido vacío no deja fila. Se vio lanzándolo contra la base de trabajo, no en un
  test.
- **El README (§6.3) no lista todavía `--fail-if-empty`**: va con `L-D.1`. Lo dice el `--help`.

**Bloque I (2026-10-05).** Cambio respecto al plan: `L-I.1` decía *"se niega con el árbol sucio"*, y eso dejaba
una carrera entre comprobar y compilar (una mutación de `Tools/Mutate` podía empezar en medio). Compilar el
**commit** con `git archive` la elimina y permite instalar cualquier `<ref>`. Medido:

- **`L-I.1`**: la primera instalación tarda **3 min 15 s** (*release* desde cero, dependencias incluidas) y
  ocupa **59,5 MB**. Reinstalar un commit que ya está instalado tarda **0,06 s** (solo mueve `current`).
  `no-existe` → `exit 1` sin crear `TFM_HOME`. El aviso de `Sources/` sucio sale (probado con una línea
  temporal en `Enumerations.swift`, restaurada después).
- **`L-I.2`**: después de un `swift build` en el árbol de trabajo, `shasum -c` del instalado → `OK`.
- **`L-I.3`**: `current/Run ingest`, lanzado desde `/tmp` contra `club_atleti` (respaldo previo con
  `pg_dump`, 560 KB) → *"0 competición(es) sincronizada(s), 0 con fallo"*, `exit 0`, **ninguna fila nueva**
  en `ingestion_runs` (183). Es el verde vacío de H-59, tal como se esperaba hasta que P dé de alta 2026/27.

---

## 6. Lo que este plan NO hace, para que nadie lo confunda con un olvido

- **Fly.io, el CI y el cron de verdad.** §1.6.
- **`ingestionHealth` y el umbral de `D-89`.** Son de la rebanada 1 (H-58). Este plan deja datos reales con
  los que decidirlo, que es lo que H-58 pedía.
- **El antirrebote por clase de pasada** (`DL-4` d). Toca `D-87` y `D-89`, y va a la rebanada 1.
- **Rotar los logs.** Con tres disparos por semana crecen unos KB al mes. Si hiciera falta, `newsyslog`.
- **Avisos fuera del Mac** (correo, móvil). Si el portátil está cerrado una semana, no hay nadie a quien
  avisar y nada que disparar.
- **Los dos deberes de §9.3** (`TenantPools`, versión de migración por club). La auditoría midió que
  `launchd` no los encarece.

---

## 7. Lo que el plan descubra y no sea suyo

Va aquí, con una línea y a quién pertenece.

**De la redacción del plan (2026-10-04) · el antirrebote es por competición y solo lo mueve el calendario.**
Una clasificación o unos goleadores `failed` con el calendario bueno no se reintentan durante 6 h por ningún
disparador con antirrebote (`DL-4`). No es un defecto del antirrebote, que hace lo que `D-87` dice. Pero
`D-87` se escribió cuando la pasada era solo de calendario (F6), antes de que F7 y F8 añadieran las otras dos
clases. **A quién pertenece**: a `DL-4` en lo que toca al reintento, y a la rebanada 1, con H-58, en lo que
toca a qué significa *"sincronizada"*.
