# `mutate` · el instrumento de mutación del backend

Una mutación rompe una línea a propósito y exige que caiga el test que dice cubrirla. Con esta herramienta
se midieron las cifras que cierran cada fase (*"57/57"*, *"14/14"*…). Hasta `A-15`·H-52 el guion **no estaba en
el repositorio**: falló cinco veces, cada vez el fallo se leyó como resultado, y ninguna cifra se podía
repetir. Ahora el guion está aquí, sus cinco fallos son tests suyos, y **cada cifra que se cite tiene su
catálogo** en `Catalogs/`.

## Uso

Desde `backend/`, con Docker arriba (las mutaciones de Persistencia y API lo necesitan):

```sh
swift build -c release --package-path Tools/Mutate          # una vez; ver abajo por qué release
Tools/Mutate/.build/release/mutate Tools/Mutate/Catalogs/A-13.json --dry-run   # ¿casan todos los cambios?
Tools/Mutate/.build/release/mutate Tools/Mutate/Catalogs/A-13.json             # la pasada
Tools/Mutate/.build/release/mutate Tools/Mutate/Catalogs/A-13.json --only H80-a,H80-b
```

- **El resumen sale por stdout y queda en `.build/mutation-reports/<catálogo>-<fecha>/summary.md`**, con los
  *logs* de cada compilación y cada `swift test` al lado. El progreso va por stderr: se puede pasar por `tail`
  sin perder el resumen (lección de F5).
- **Código de salida**: `0` todas cazadas (o equivalentes declaradas) · `1` alguna sobrevive · `2` hay
  inválidas o la batería no cerró en verde, **y la cifra no se cita** · `3` no se pudo empezar.
- **Por qué `release`**: el guion compila el paquete que muta. Contra sí mismo (`Catalogs/self.json`,
  `--package-path Tools/Mutate`) el binario en `debug` sería el que está reescribiendo.

## Qué hace, en orden

1. **Toma el candado del paquete** (`.mutate.lock`): si otra pasada viva lo tiene, se niega a arrancar,
   también en `--dry-run`. Después **restaura** lo que una ejecución **muerta** dejara mutado
   (`.mutate-in-flight.json`). Ctrl-C restaura en el acto.
2. **La batería sin mutar, en verde**, por cada filtro del catálogo. Sin un verde de partida no hay nada que
   medir, y así un filtro que no casa con nada se descubre antes de empezar.
3. Por cada mutación: **aplica** → **compila** (`swift build --build-tests`) → **prueba**
   (`REQUIRE_DB=1 swift test --skip-build --filter … --xunit-output …`) → **restaura**, y comprueba que lo
   restaurado es lo original.
4. **La batería sin mutar otra vez**, al final. Si el entorno se cae a mitad, lo que se leyó como *"cazada"*
   pudo ser Postgres, y la pasada entera no vale.

## Las reglas, y el fallo del que sale cada una

Cada una tiene su test en `Tests/MutateCoreTests/`, y `Catalogs/self.json` mete cada fallo de vuelta en el
guion para comprobar que esos tests lo cazan (**15/15**).

| Regla | De dónde sale |
|---|---|
| **El reemplazo es literal**: ni expresiones regulares ni `perl`. `$0` es `$0` | F7: un `$0` sin escapar no compilaba y se contó como *"sobrevive"* |
| **Cada búsqueda casa exactamente una vez**; si no, la mutación es **inválida** | F4 y F7: un patrón que no casaba dio *"sobrevive"* sin haber mutado nada |
| **Lo que no compila es inválido**, no superviviente | F7, el mismo `$0` |
| **Manda el código de salida, y lo confirma el `✘` o el XML.** Nunca se raspa el nombre del test | F1: los parametrizados escriben *"with 6 test cases failed"* |
| **La palabra `error:` no se lee nunca** | F7: un fallo de Postgres la trae y dos cazadas se leyeron como fallos de compilación. F10-bis: está en los *logs* de la suite de API y escondió **dos supervivientes reales** como *"inválidas"*. El XML de swift-testing pone `(error)` en cada expectativa fallida |
| ***"No hay `✘`"* solo es sobrevivir si la batería salió con `0` y corrió algo** | F10-bis; y README §5.1: un filtro que no casa sale con `0` |
| **Los omitidos no cuentan como ejecutados**, y siempre `REQUIRE_DB=1` | `A-7`·H-07: sin la variable, con Docker parado, la salida es idéntica a un verde |
| **Los tests se cuentan por `<testcase>`, no por el atributo `tests`** | El estreno de este guion: en swift-testing `tests` ya excluye los omitidos, y restarlos otra vez contaba de menos |
| **Una pasada por paquete**: el candado va antes que el diario de vuelo | `A-15`·H-89: un `--dry-run` en paralelo tomó el diario de la pasada en curso por el de una muerta, y restauró el fichero a mitad de una mutación |
| **El resumen va a un fichero**, y el progreso por otro canal | F5: el resumen se perdió detrás de un `tail` |

> **Y lo que el candado no cubre:** un `swift test` lanzado a mano mientras corre una pasada usa la misma
> `tfm_test`, y cada batería **barre al arrancar** los *schemas* de la otra. No lances nada contra el backend
> hasta que la pasada acabe. Y si `launchd` dispara `.build/debug/Run`, ejecutará el binario mutado (H-85).

## Cuatro desenlaces, no dos

| Desenlace | Qué significa |
|---|---|
| ✅ **cazada** | Algún test cayó |
| ❌ **sobrevive** | *"Falta un test"* o *"sobra el código"* (F1, F2) |
| ➖ **equivalente** | Sobrevive y el catálogo lo declara con su razón: el programa mutado es el mismo programa (F5). Si una declarada equivalente cae, el informe lo marca: la declaración sobra |
| ⚠️ **inválida** | No se probó: no casó, no compiló, no corrió ningún test, o la salida se contradice. **No suma ni resta**, y mientras haya una la cifra no se cita |

## Escribir un catálogo

Un catálogo por fase o por ronda de arreglos, con el nombre del bloque: `Catalogs/A-13.json`. Las rutas son
relativas al paquete que se prueba (`backend/`).

```json
{
  "title": "A-13 · ronda de arreglos",
  "filter": "MigrationIntegrityTests",
  "mutations": [
    { "id": "H80-b", "description": "guarda laxa",
      "file": "Sources/App/TenantCommands.swift",
      "find": "confirmOverride == true", "replace": "confirmOverride != false" },
    { "id": "H82-a", "description": "se renombra un rawValue congelado",
      "file": "Sources/Domain/Enumerations.swift",
      "find": "case futbolPlaya = \"futbol_playa\"", "replace": "case futbolPlaya = \"playa\"",
      "filter": "FrozenEnumCheckTests" },
    { "id": "M3", "description": "cruzar los dos marcadores",
      "file": "Sources/Domain/Match.swift",
      "edits": [ { "find": "…", "replace": "…" }, { "find": "…", "replace": "…" } ],
      "equivalent": "Kickoff solo pregunta si hay marcador, y esa pregunta es simétrica" }
  ]
}
```

- `filter` es el `--filter` de `swift test` (una expresión regular sobre **identificadores** de Swift, README
  §5). El de la mutación manda sobre el del catálogo; sin ninguno, la batería entera.
- `find`/`replace` para un cambio; `edits` para varios, que se aplican en orden.
- **Antes de la pasada, `--dry-run`**: dice qué cambio no casa sin compilar nada.

## Los tests del guion

```sh
swift test --package-path Tools/Mutate
```

**No entran en la batería del backend** (`REQUIRE_DB=1 swift test` desde `backend/`), y es a propósito: miden
el instrumento, no el producto, y el recuento de la batería es la cifra que cierra cada fase.
