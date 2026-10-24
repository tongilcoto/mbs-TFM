import EnumNamesCore
import Foundation

// Lo lanza `EnumNamesPlugin` al compilar `APIContract` (D-109): lee el catálogo y la configuración del generador,
// y escribe los nombres de cada lista. Si algo no cuadra, para la compilación diciendo qué.
let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("uso: EnumNamesTool <openapi.yaml> <openapi-generator-config.yaml> <salida.swift>\n".utf8))
    exit(2)
}

do {
    let catalog = try String(contentsOfFile: arguments[1], encoding: .utf8)
    let config = try String(contentsOfFile: arguments[2], encoding: .utf8)
    let swift = try EnumNames.swiftSource(catalog: catalog, generatorConfig: config)
    try swift.write(toFile: arguments[3], atomically: true, encoding: .utf8)
} catch let problems as EnumNames.Problems {
    FileHandle.standardError.write(Data("error: los nombres de las listas del catálogo no cuadran (D-108, D-109):\n\(problems)\n".utf8))
    exit(1)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
