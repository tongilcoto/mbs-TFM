# `census` · el censo del contrato

Cuenta dos cosas de la frontera HTTP y las compara con los huecos que ya se saben:

1. **Códigos `Problem`**: cada `code: "X"` de `Sources/`, y qué ficheros de `Tests/` lo nombran entre comillas.
2. **Campos del contrato**: los que un cliente alcanza desde las respuestas **2xx** de las operaciones del
   `filter` del generador, y cuáles nombra algún test de `Tests/APITests/`.

Hasta `A-15` (punto 7, H-72) estos dos recuentos se hacían a mano con `grep` y `ruby -ryaml`, y no se guardaban:
F10-ter contó 52 campos, A-14 contó 61, y nadie podía saber por qué. Ahora el método está escrito aquí, y
**una cifra de cobertura del contrato se afirma con este comando**.

## Uso

Desde `backend/`:

```sh
swift build --package-path Tools/Census
Tools/Census/.build/debug/census            # el censo por stdout
swift test --package-path Tools/Census      # los tests del censo
```

**Código de salida**: `0` los huecos de hoy son exactamente los de `known-gaps.json` · `1` hay un hueco nuevo, o
una entrada de la lista ya no es hueco · `3` no se pudo hacer el censo (un fichero que falta, o una operación
del `filter` que no está en el *spec*).

## El trinquete: `known-gaps.json`

Cada hueco conocido, **con su motivo**. Al añadir un endpoint en una rebanada:

- si el censo sale con `1` por un **hueco nuevo**, se escribe su test o se apunta en la lista con el motivo;
- si sale con `1` porque **la lista caducó**, se quita la entrada: ya tiene test, o el código ya no existe.

Un motivo es una afirmación como cualquier otra: **se comprueba antes de escribirlo**. Al estrenar la lista,
tres de nueve motivos estaban mal, porque se escribieron de memoria.

## El método, regla a regla

| Qué | Cómo | Por qué así |
|---|---|---|
| Código emitido | `code: "[A-Z_]+"` en `Sources/`, línea a línea | Es el `grep` de A-14 (H-72). Un código interpolado o sacado de una tabla no saldría; hoy los 31 son literales |
| Código nombrado | `"X"` **entre comillas** en `Tests/` | Las comillas son el borde: `"NOT_FOUND"` no está dentro de `"TEAM_NOT_FOUND"` |
| Operaciones | `filter.operations` de `openapi-generator-config.yaml` | Es el alcance entregado. Una operación que no está en el *spec* es **error**, no un censo más corto |
| Respuestas | toda clave que empieza por `2` (el enganche y el disparador responden **202**), resolviendo `components/responses` | Las de error tienen forma `Problem`, y lo que se censa de ellas es el código |
| Recorrido | `$ref`, `allOf`/`oneOf`/`anyOf`, `properties`, `items`, `additionalProperties`, en profundidad | |
| Un campo | el par **esquema.propiedad**. Un objeto anidado sin nombre se nombra por su ruta (`Run.counters.created`) | Dos operaciones que devuelven el mismo esquema **no** duplican sus campos |
| Campo nombrado | `.propiedad` o `"propiedad"` en `Tests/APITests/`, con borde de **identificador de Swift** | **No** el `\b` de Unicode: con él, un punto entre letras no separa palabras, y `.competition.ageCategory` no casaba (el fallo del estreno) |

## Lo que **no** dice, y conviene tener delante

- **Nombrar no es afirmar** (`A-7`·H-47). Un `"TEAM_NOT_FOUND"` dentro de un comentario cuenta, y `.id` lo nombra
  media batería. Esto **encuentra huecos**, no certifica cobertura; lo que cierra la pregunta *"¿lo prueba
  algo?"* es la mutación (`Tools/Mutate`).
- **Un campo obligatorio está más cubierto de lo que el censo dice**: el decodificador generado exige que esté
  (H-72), así que un test que decodifica la respuesta caería si faltara. Lo que nadie comprueba es su
  **valor**. Por eso `createdAt` y compañía están en la lista, con ese motivo.
- **El 52 de F10-ter sigue sin explicación.** F10-ter no dejó escrito su método. El 61 de A-14 sí se reproduce:
  61 el 2026-10-01, más `ageCategoryChecked`, que llegó con H-75 el 2026-10-03.

## Los tests del censo

17 tests en `Tests/CensusCoreTests/`, uno por regla. `Tools/Mutate/Catalogs/census.json` rompe cada regla en el
código del censo y exige que caiga su test: **14/14**. **No entran en la batería del backend**, por lo mismo que
los de `Tools/Mutate`.
