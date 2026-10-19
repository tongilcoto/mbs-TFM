# `census` · el censo del contrato

Cuenta dos cosas de la frontera HTTP y las compara con los huecos que ya se saben:

1. **Códigos `Problem`**: cada `code: "X"` y `code: .X` de `Sources/`, qué ficheros de `Tests/` lo nombran, y
   si está en **la lista cerrada del catálogo** (`ProblemCode`, desde R1.5).
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

**Código de salida**: `0` los huecos de hoy son exactamente los de `known-gaps.json`, y cada código emitido está en
la lista del catálogo · `1` hay un hueco nuevo, una entrada de la lista ya no es hueco, o **el servidor emite un
código que no está en `ProblemCode`** · `3` no se pudo hacer el censo (un fichero que falta, una operación del
`filter` que no está en el *spec*, o el *spec* sin la lista de códigos).

## La lista de códigos del catálogo

Desde R1.4, `code` tiene una lista cerrada en el catálogo: el esquema `ProblemCode`. La web genera de ella sus
tipos y exige un mensaje para cada código. Los *handlers* ya construyen el error con esa lista, así que un código
que no esté en ella no compila; pero `ProblemMiddleware` escribe el código como texto, y uno nuevo que se olvide en
el catálogo compilaría igual. **El censo lo vigila**: si un código emitido no está en la lista, lo dice y sale con
`1`. Se arregla añadiéndolo al `enum` de `ProblemCode` en `openapi.yaml`.

Al revés no es un fallo: un código de la lista que el censo no ve emitido se enseña como información. Hoy es
`NOT_FOUND`, que sale de una condición en `ProblemMiddleware` y no de un `code: …` que el censo pueda leer.

## El trinquete: `known-gaps.json`

Cada hueco conocido, **con su motivo**. Al añadir un endpoint en una rebanada:

- si el censo sale con `1` por un **hueco nuevo**, se escribe su test o se apunta en la lista con el motivo;
- si sale con `1` porque **la lista caducó**, se quita la entrada: ya tiene test, o el código ya no existe.

Un motivo es una afirmación como cualquier otra: **se comprueba antes de escribirlo**. Al estrenar la lista,
tres de nueve motivos estaban mal, porque se escribieron de memoria.

## El método, regla a regla

| Qué | Cómo | Por qué así |
|---|---|---|
| Código emitido | `code: "[A-Z_]+"` o `code: .[A-Z_]+` en `Sources/`, línea a línea | Es el `grep` de A-14 (H-72), más la forma de los *handlers* desde R1.4, que reciben el código de la lista. Un código interpolado o sacado de una condición no saldría: hoy, solo `NOT_FOUND` |
| Código nombrado | `"X"` **entre comillas**, o `.X` con borde de identificador, en `Tests/` | Las comillas son el borde: `"NOT_FOUND"` no está dentro de `"TEAM_NOT_FOUND"`. Con `.X`, el punto es el de delante y el de un identificador de Swift el de detrás: `.TEAM_NOT_FOUND` no nombra ni `NOT_FOUND` ni `TEAM` |
| En la lista | el `enum` de `components.schemas.ProblemCode` del *spec* | Es la lista que leen los clientes generados. Sin ella, el censo no se puede hacer (`3`) |
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

22 tests en `Tests/CensusCoreTests/`, uno por regla. `Tools/Mutate/Catalogs/census.json` rompe cada regla en el
código del censo y exige que caiga su test: **19/19** (17/17 antes de R1.5). **No entran en la batería del backend**, por lo mismo que
los de `Tools/Mutate`.
