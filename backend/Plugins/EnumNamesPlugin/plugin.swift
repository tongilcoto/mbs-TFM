import PackagePlugin

/// Al compilar `APIContract`, escribe los nombres en español de cada lista del catálogo junto a los tipos que
/// genera `swift-openapi-generator` (D-109). Lee los mismos dos ficheros que él.
@main
struct EnumNamesPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: any Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        let catalog = target.directoryURL.appending(path: "openapi.yaml")
        let config = target.directoryURL.appending(path: "openapi-generator-config.yaml")
        let output = context.pluginWorkDirectoryURL.appending(path: "EnumNames.swift")
        return [
            .buildCommand(
                displayName: "Los nombres de las listas del catálogo (D-109)",
                executable: try context.tool(named: "EnumNamesTool").url,
                // Sin codificar: `path()` escribe un espacio como `%20`, y la herramienta no encuentra el fichero
                // cuando la ruta lo tiene (`~/Library/Application Support/tfm`, donde compila `install.sh`).
                arguments: [catalog, config, output].map { $0.path(percentEncoded: false) },
                inputFiles: [catalog, config],
                outputFiles: [output]
            ),
        ]
    }
}
