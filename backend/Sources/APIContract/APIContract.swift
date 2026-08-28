// Este target no tiene código escrito a mano: su contenido lo genera el plugin
// de `swift-openapi-generator` a partir de `openapi.yaml` (D-65).
//
// El fichero existe porque **SwiftPM descarta un target sin ningún `.swift`**,
// y lo hace en silencio: el target desaparece de `swift package describe` y
// `swift build --target APIContract` responde "no target named". Los YAML son
// recursos, no fuentes, y la validación ocurre antes de que el plugin corra.
//
// Qué se genera y qué no lo aplica el código generado: LLD §5.5 y D-65.
// Qué operaciones entran hoy: el `filter` de `openapi-generator-config.yaml`.
