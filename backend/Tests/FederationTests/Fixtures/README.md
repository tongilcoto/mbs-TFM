# *Fixtures* de federación

Volcados **reales** de las APIs de federación, contra los que corren los tests del
adaptador. Nivel 1 de la pirámide (§8.1): sin red y sin Docker.

## Son copias, y hay que saberlo

| Fichero | Copia byte a byte de | Qué contiene |
|---|---|---|
| `RFFM-calendario-temporada-sin-jugar.html` | `docs/Federation APIs examples/` + el mismo nombre | PREFERENTE AFICIONADO Grupo 1, temporada **2026-27**: 34 jornadas, 306 partidos, **ninguno jugado** |
| `RFFM-calendario-temporada-jugada.html` | `docs/Federation APIs examples/` + el mismo nombre | PRIMERA DIVISION AUTONOMICA CADETE Grupo 1, temporada **2025-26**: 30 jornadas, 240 partidos, **todos jugados** |
| `RFFM-calendario-coordenada-inexistente.html` | `docs/Federation APIs examples/` + el mismo nombre | Lo que la RFFM responde a una coordenada que **no existe**: `200` y `calendar: null` |

**El nombre dice las dos cosas que hay que saber antes de usarlos.** Son `.html`
—no `.txt`— porque la RFFM sirve el calendario como **página**, con el JSON
dentro de un `<script id="__NEXT_DATA__">` ([Anexo RFFM §F.7]); y el sufijo dice
**qué rama del código ejercita cada uno**, que es lo que los hace dos ficheros y
no uno.

## Los dos volcados son el mismo grupo en dos temporadas, y eso no es casualidad

Se capturaron con **la misma coordenada** y cambiando un solo parámetro:

```
…/competicion/calendario?temporada=NN&tipojuego=1&competicion=24037548&grupo=24037549
                                    ↑ 22 = sin jugar · 21 = jugada
```

**Y devuelven competiciones distintas** — PREFERENTE AFICIONADO una, PRIMERA
DIVISION AUTONOMICA CADETE la otra. No es un error de captura: **son dos competiciones
distintas con coordenadas distintas** (`D-84`, enmendada el 2026-09-02 — los códigos **no** se
reutilizan entre temporadas; lo que pasa es que la RFFM **reutiliza
los códigos de competición y grupo entre temporadas**. Dos consecuencias, las dos
con dato real detrás por primera vez:

- confirma la regla de §3.5 de que `Competition` se identifica por
  (`season_id`, `federation_group_id`) y **nunca por el grupo a secas**;
- y **una coordenada caducada no da 404**: devuelve un calendario perfectamente
  parseable **de otra cosa**. Es lo que obligó a que el canario de Plan §4.4 tenga
  **tres** señales y no dos, y a que la ingesta compare el nombre que trae la
  fuente contra `Competition.federation_name` antes de escribir nada.

### Qué ejercita cada uno

| | sin jugar (temporada 22) | jugada (temporada 21) |
|---|---|---|
| Marcador | **0 de 306** — `goles_casa` y `goles_visitante` vacíos | **240 de 240** |
| Hora | **0 de 306** — `hora` vacía en todos | **240 de 240** |
| Día de la semana | los 306 en **domingo** (es competición senior) | 171 sábado, 65 domingo y **4 entre semana** |
| Fechas por jornada | **una sola**, igual al rótulo | **dos** en 26 de las 30 jornadas |

Ese último par de filas es de donde sale la regla de `Round.start_date` /
`end_date`: **mínimo y máximo de las fechas de sus partidos**, que en la jugada da
sábado→domingo sin inventar nada, y en la que no ha arrancado **colapsa en un solo
día** — porque es lo único que la federación ha dicho todavía.

> **Ojo con el atajo "el calendario nace en sábado".** [Anexo RFFM §F.5] lo dice y
> el volcado sin jugar lo **desmiente** para esta competición: sus 306 partidos
> nacen en **domingo**. El día por defecto es de la competición, no de la
> federación, y por eso no se cablea en ningún sitio.

**El original vive en `docs/`, que es donde está la evidencia** sobre la que se
escriben los anexos de federación. Aquí hay una copia porque **SwiftPM solo
empaqueta recursos que vivan dentro del directorio del *target***: no puede
referenciar un fichero de fuera. Un enlace simbólico lo resolvería, pero el
Plan §6 ya los descartó por frágiles al decidir dónde vive el *spec*, y no
conviene tener dos criterios.

**Consecuencia: pueden derivar.** Si se recaptura un volcado, hay que copiarlo a
los dos sitios:

```sh
for f in RFFM-calendario-temporada-sin-jugar.html RFFM-calendario-temporada-jugada.html \
         RFFM-calendario-coordenada-inexistente.html; do
  cp "docs/Federation APIs examples/$f" "backend/Tests/FederationTests/Fixtures/$f"
  diff -q "docs/Federation APIs examples/$f" "backend/Tests/FederationTests/Fixtures/$f"
done
```

## No intentes leerlos en Xcode

Los dos son **~380 KB en una sola línea, sin un solo salto** — es la
respuesta HTTP tal cual, y así la manda el servidor. El resaltador de Xcode se
rinde con líneas de ese tamaño y deja el texto sin estilo, que **en modo oscuro es
invisible**. No está corrupto: está sin colorear.

Para mirarlo, desde la raíz del repositorio:

```sh
# el JSON de dentro del __NEXT_DATA__, indentado
python3 -c "
import json
raw = open('backend/Tests/FederationTests/Fixtures/RFFM-calendario-temporada-sin-jugar.html', encoding='utf-8').read()
data, _ = json.JSONDecoder().raw_decode(raw[raw.find('{'):])
print(json.dumps(data['props']['pageProps']['calendar'], ensure_ascii=False, indent=2))
" | less
```

## Por qué se guardan en crudo y no *pretty-printed*

Porque su valor **es** ser lo que el servidor mandó. Reformatearlos los volvería
más cómodos de leer y los inutilizaría para lo único que no puede hacer otra cosa:
poder recapturar la misma llamada dentro de un año y **comparar**. La comodidad se
resuelve con el comando de arriba; la evidencia, no se resuelve luego.

La estructura de este volcado, campo a campo, está descrita en
[Anexo RFFM §F.15](../../../../docs/API_y_BBDD%20LLD-Anexo-Federacion-Madrid-RFFM.md) —
incluidas las tres cosas que corrigió del anexo anterior.

## El tercer volcado: cómo dice la RFFM que no

Se capturó al escribir el canario de F5, y **desmiente una premisa del plan**.
Plan §4.4 daba por hecho que una coordenada caducada daría **404** —*"un 404
tiene que decir una cosa y un parseo fallido otra"*—. Medido: **la RFFM no da 404
nunca** en la ruta del calendario. Dice que no de dos maneras, y las dos son
`200`:

| Coordenada mala | Qué responde |
|---|---|
| `competicion`/`grupo` inexistentes | `200` con **`calendar: null`** — es este volcado |
| `temporada` inexistente | `200` con **el calendario entero de otra temporada** y `temporada: ""`. Ignora el parámetro |

La segunda es la peligrosa: 30 jornadas perfectamente parseables que **no son de
la temporada que se pidió**. Por eso el parser mira las dos cosas antes de
interpretar nada, y las llama `coordinateNotFound` y no `malformedResponse` —
si no, el canario gritaría *"¡han cambiado la forma!"* cada vez que alguien se
equivoque de número.

Del segundo caso **no hay volcado**: son 392 KB byte a byte iguales al de
temporada jugada salvo un campo, y su rama se prueba con un `__NEXT_DATA__`
mínimo escrito a mano en el test. La evidencia de que se comporta así es esta
tabla y el comando con el que se midió.

## El canario

Vive aquí al lado y **no corre con `swift test`** (Plan §4.4): pregunta *"¿han
cambiado ellos?"*, que no es determinista.

```sh
FEDERATION_LIVE=1 swift test --filter RFFMCanaryTests
```

La coordenada por defecto es la del volcado de temporada jugada, para que el
canario y el *fixture* hablen de lo mismo. **Caduca**, así que se puede cambiar
sin tocar código:

```sh
FEDERATION_LIVE=1 \
  FEDERATION_LIVE_SEASON=22 \
  FEDERATION_LIVE_COMPETITION=26737701 \
  FEDERATION_LIVE_GROUP=26737702 \
  FEDERATION_LIVE_NAME="PREFERENTE AFICIONADO" \
  swift test --filter RFFMCanaryTests
```

**El filtro es `RFFMCanaryTests`** —el nombre del tipo—, no el rótulo del
*suite*: `--filter FederationCanary` no casa con nada y se queda en
*"0 tests"*, que se lee como verde.
