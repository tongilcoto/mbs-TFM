# *Fixtures* de federación

Volcados **reales** de las APIs de federación, contra los que corren los tests del
adaptador. Nivel 1 de la pirámide (§8.1): sin red y sin Docker.

## Son copias, y hay que saberlo

| Fichero | Copia byte a byte de | Qué contiene |
|---|---|---|
| `RFFM-calendario-temporada-sin-jugar.html` | `docs/Federation APIs examples/` + el mismo nombre | El calendario de PREFERENTE AFICIONADO Grupo 1, temporada 2026-27: 34 jornadas, 306 partidos |

**El nombre dice las dos cosas que hay que saber antes de usarlo.** Es `.html`
—no `.txt`— porque la RFFM sirve el calendario como **página**, con el JSON
dentro de un `<script id="__NEXT_DATA__">` ([Anexo RFFM §F.7]); y lleva
`sin-jugar` porque la temporada **no ha arrancado**: los 306 partidos vienen sin
marcador y sin hora, así que **esta muestra no ejercita la rama de "partido
jugado"**. Para eso hace falta un volcado de temporada en curso, que F5 necesita
y todavía no tenemos (Plan §4.3).

**El original vive en `docs/`, que es donde está la evidencia** sobre la que se
escriben los anexos de federación. Aquí hay una copia porque **SwiftPM solo
empaqueta recursos que vivan dentro del directorio del *target***: no puede
referenciar un fichero de fuera. Un enlace simbólico lo resolvería, pero el
Plan §6 ya los descartó por frágiles al decidir dónde vive el *spec*, y no
conviene tener dos criterios.

**Consecuencia: pueden derivar.** Si se recaptura un volcado, hay que copiarlo a
los dos sitios:

```sh
cp "docs/Federation APIs examples/RFFM-calendario-temporada-sin-jugar.html" \
   "backend/Tests/FederationTests/Fixtures/RFFM-calendario-temporada-sin-jugar.html"
diff -q  # y comprobar que siguen idénticos
```

## No intentes leerlos en Xcode

`RFFM-calendario-temporada-sin-jugar.html` son **379 KB en una sola línea, sin un solo salto** — es la
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
