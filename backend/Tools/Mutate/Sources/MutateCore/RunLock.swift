/// Qué hacer con el candado de un paquete al arrancar.
///
/// **Una pasada por paquete, y ninguna otra la toca mientras corre.** Lo
/// enseñó el estreno de `A-15`: un `--dry-run` lanzado con una pasada en marcha
/// encontró su `.mutate-in-flight.json`, lo tomó por el resto de una ejecución
/// muerta y **restauró el fichero a mitad de una mutación**. La mutación se
/// probó sin saber contra qué código, y salió *"equivalente"*. El diario de
/// vuelo solo es de una ejecución muerta si el candado también lo es.
public enum LockDecision: Equatable, Sendable {
    /// Nadie lo tiene: se toma.
    case acquire
    /// Lo dejó un proceso que ya no existe: se toma, y su diario se restaura.
    case takeOverStale(pid: Int32)
    /// Lo tiene un proceso vivo: no se arranca, y no se restaura nada.
    case refuse(pid: Int32)
}

/// `holder` es el pid escrito en el candado (`nil` si no hay candado, o si no
/// se puede leer un pid de él); `isAlive` pregunta al sistema por ese pid.
public func lockDecision(holder: Int32?, ownPID: Int32,
                         isAlive: (Int32) -> Bool) -> LockDecision {
    guard let holder else { return .acquire }
    if holder != ownPID, isAlive(holder) { return .refuse(pid: holder) }
    return .takeOverStale(pid: holder)
}
