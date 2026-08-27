# Del *spec* al código: cómo `openapi.yaml` se convierte en tipos Swift

Nota de comprensión sobre el *target* `APIContract`. **No es normativa**: el diseño está en
[docs/API_y_BBDD LLD-001.md](./docs/API_y_BBDD%20LLD-001.md) y las decisiones en su
[Anexo de Decisiones](./docs/API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md). Esto solo explica el
mecanismo, para quien se pregunte de dónde sale un tipo que no aparece en el repositorio.

---

## 1. Lo primero: eso no lo hace Swift

Swift no sabe nada de OpenAPI. Lo que hay es un **generador de código** que corre **antes** del
compilador:

```
openapi.yaml  ──►  swift-openapi-generator  ──►  Types.swift (texto)  ──►  swiftc
   (fuente)          (ejecutable aparte)          (en artefactos)         (compila)
```

El plugin está declarado en [`backend/Package.swift`](./backend/Package.swift) (bloque `plugins:` del
*target* `APIContract`). Es un **build tool plugin** de SwiftPM: en cada build, SwiftPM ejecuta ese
binario, que lee el YAML —con `Yams` para parsear YAML y `OpenAPIKit` para modelar el documento
OpenAPI, ambos visibles en el árbol de dependencias del paquete— y **escribe texto Swift**. Desde ahí,
el compilador trata ese fichero como si estuviera escrito a mano.

No es una macro. Las macros de Swift corren *dentro* del compilador; esto corre antes. Dos
consecuencias prácticas:

- **Ocurre automáticamente al cambiar el YAML.** No hay paso manual de regeneración que olvidar.
- **El mapeo es mecánico, no inteligente.** El generador no reinterpreta las decisiones del *spec*:
  las transcribe. De ahí las asperezas de la §4.

---

## 2. Dónde vive el generado (y cómo llegar)

**No está en git, y es correcto que no esté.** Por eso AGENTS.md dice de `APIContract` que «no se edita
a mano»: literalmente no hay nada que editar.

| Cómo compilas | Dónde aparece `Types.swift` |
|---|---|
| Xcode | `~/Library/Developer/Xcode/DerivedData/backend-<hash>/Build/Intermediates.noindex/BuildToolPluginIntermediates/backend.output/APIContract/OpenAPIGenerator/GeneratedSources/` |
| `swift build` (CLI) | `backend/.build/plugins/outputs/…/APIContract/OpenAPIGenerator/GeneratedSources/` |

El `<hash>` es de la máquina, no del proyecto. Bajo Xcode hay además una **segunda copia** en
`Index.noindex/…`: es la que alimenta al indexador para que funcione el autocompletado. Contenido
idéntico.

**Desde Xcode, la vía normal es ⌘-click** sobre cualquier símbolo generado (`Components`, `value1`,
`Operations`). Abre el fichero en modo lectura. No hace falta rebuscar en DerivedData.

> Los números de línea que se citan más abajo son de una versión concreta del *spec* y **se
> desplazarán** en cuanto crezca. Sirven para orientarse; para localizar algo, buscar por nombre.

---

## 3. La jerarquía: tres niveles, dos de ellos puro *namespace*

```swift
public enum Components {              // ~línea 121  ← enum sin casos
    public enum Schemas {             // ~línea 123  ← enum sin casos

        @frozen public enum FederationCode: String, Codable, Hashable, Sendable, CaseIterable {
            case rffm = "rffm"        // ~línea 351
            case fcf = "fcf"
        }
    }
}
```

`Components` y `Schemas` son `enum` **sin casos**: un idiom de Swift para hacer un espacio de nombres
puro (un `enum` vacío no se puede instanciar). No son tipos que se usen; son la ruta. Y esa ruta es la
traducción literal del puntero JSON del YAML: `#/components/schemas/FederationCode`.

El otro *namespace* de primer nivel es `Operations` (~línea 395), con un tipo `Input`/`Output` por
operación, más el `APIProtocol` (~línea 13) que `APIHandler` conforma.

---

## 4. El caso `FederationCode`, de punta a punta

### 4.1 Lo que hay en el *spec*

```yaml
# openapi.yaml ~3995
FederationCode:
  type: string
  description: |
    …
  enum: [rffm, fcf]
```

Y su uso dentro de `ClubResponse` (~3649), que no es un `$ref` directo:

```yaml
federation:
  allOf:
    - $ref: '#/components/schemas/FederationCode'
  readOnly: true
  description: |
    …
```

Ese `allOf` de un solo miembro es el truco habitual de OpenAPI 3.0 para poder colgarle `readOnly` y
`description` propios a una referencia. En OpenAPI 3.0 un `$ref` **ignora** cualquier hermano, así que
sin el `allOf` esa descripción se perdería.

### 4.2 Lo que sale generado

```swift
public struct ClubResponse: Codable, Hashable, Sendable {          // ~194
    …
    public struct federationPayload: Codable, Hashable, Sendable {  // ~224
        public var value1: Components.Schemas.FederationCode        // ~226

        public init(from decoder: any Swift.Decoder) throws {
            self.value1 = try decoder.decodeFromSingleValueContainer()
        }
        public func encode(to encoder: any Swift.Encoder) throws {
            try encoder.encodeToSingleValueContainer(self.value1)
        }
    }
    public var federation: Components.Schemas.ClubResponse.federationPayload   // ~246
}
```

Leído de dentro afuera:

| Expresión | Tipo |
|---|---|
| `club` | `Components.Schemas.ClubResponse` |
| `club.federation` | `Components.Schemas.ClubResponse.federationPayload` |
| `club.federation.value1` | `Components.Schemas.FederationCode` |

### 4.3 Por qué `value1` y por qué `federationPayload` en minúscula

Las dos son transcripción mecánica, no criterio:

- **`federationPayload`** copia el nombre de la propiedad del YAML (`federation`) y le añade el sufijo.
  De ahí que arranque en minúscula, contra la convención Swift de tipos en PascalCase.
- **`value1`** numera los miembros del `allOf`. El generador no aprovecha que aquí solo hay uno: si
  hubiera tres, serían `value1`, `value2`, `value3`.

### 4.4 El envoltorio es invisible en el cable

Fíjate en el `Codable` escrito a mano del generado: `decodeFromSingleValueContainer` /
`encodeToSingleValueContainer`. Un *single value container* serializa el *struct* **como su único
miembro**. En el JSON real:

```json
"federation": "rffm"
```

y **no** `"federation": {"value1": "rffm"}`. Así que `.value1` es puro artefacto de Swift: molesta al
escribir código y no se ve en la API.

### 4.5 Hay dos `FederationCode`, y no son el mismo tipo

Esto sorprende la primera vez, sobre todo en los tests, donde los dos aparecen a pocas líneas:

| Tipo | Módulo | Declarado en |
|---|---|---|
| `Domain.FederationCode` | `Domain` | [`Sources/Domain/FederationCode.swift`](./backend/Sources/Domain/FederationCode.swift) — escrito a mano |
| `Components.Schemas.FederationCode` | `APIContract` | **generado** de `openapi.yaml` |

Mismos casos, escritos igual, **sin ninguna relación de tipos entre ellos**. El puente lo hace a mano
el `switch` exhaustivo de `toContract()` en
[`Sources/HTTPAdapter/ClubHandler.swift`](./backend/Sources/HTTPAdapter/ClubHandler.swift), y que sea
exhaustivo es deliberado (`D-61`): añadir una federación al Dominio **no compila** hasta declararla
también en el *spec*.

En un mismo fichero, entonces, `.rffm` puede significar dos cosas distintas según el contexto. Es
*implicit member expression* normal de Swift —la misma cosa que `.blue` o `.leading`—: el compilador
resuelve el miembro contra el tipo que ya espera en esa posición. Como los dos tipos se llaman igual,
la ambigüedad es visual, no del compilador.

---

## 5. Lo importante: qué del *spec* se hace cumplir y qué no

AGENTS.md avisa: **«el generador emite tipos, no validación»**. Ignora `pattern`, longitudes, rangos,
`readOnly`, `default`, `minProperties`, `tags` y `security`.

`enum: [rffm, fcf]` es una de las **pocas excepciones**, y por una razón concreta: es la única de esas
restricciones que Swift puede expresar **como tipo**. El generador no escribe ningún `if` de
validación; escribe un `enum` de dos casos y deja el trabajo al sistema de tipos y a `Codable`. Si
llegara `"rfef"` en un JSON de entrada, el decode falla solo.

El contraste está tres campos más arriba, en el mismo `ClubResponse`:

| En el *spec* | Tipo generado | ¿Se hace cumplir? |
|---|---|---|
| `federation` → `enum: [rffm, fcf]` | `enum FederationCode: String` | **Sí**, por el tipo |
| `slug` → `pattern: '^[a-z0-9]+(-[a-z0-9]+)*$'` | `Swift.String` | **No**. El `pattern` se descarta |

Ese `pattern` no desaparece del sistema: lo hace cumplir el *Value Object*
[`Domain.Slug`](./backend/Sources/Domain/Slug.swift). Pero la garantía vive en el **Dominio**, no en el
contrato — que es exactamente la tabla de reparto del LLD §5.5.

### Regla de bolsillo

Al escribir en el *spec*, preguntarse si lo que se declara es una **forma** o una **regla**:

- **Forma** (`type`, `enum`, `required`, `$ref`, `nullable`) → viaja al código sola.
- **Regla** (`pattern`, `minimum`, `maxLength`, `readOnly`, `default`) → es documentación para el
  cliente y **tarea pendiente** en el Dominio o el *handler*.

---

## 6. Por qué el generado es pequeño (y qué implica al añadir un endpoint)

El *spec* pasa de 4.000 líneas y cubre las 20 entidades del LLD §3.2. El `Types.swift` generado ronda
las 550. La diferencia es `D-69`:
[`openapi-generator-config.yaml`](./backend/Sources/APIContract/openapi-generator-config.yaml) lleva un
`filter` que lista **solo las operaciones implementadas**.

La razón es que `APIProtocol` obliga a implementar **todo** lo que se genera. Si se generase el *spec*
entero, `APIHandler` no compilaría hasta tener los ~80 endpoints escritos.

**Corolario práctico:** al añadir un endpoint, el primer sitio donde se escribe **no es el *spec*** —ya
está completo—, sino esa lista del `filter`. Esa lista **es** el alcance entregado.
