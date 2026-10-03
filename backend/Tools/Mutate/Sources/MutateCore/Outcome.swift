/// El desenlace de una mutación.
///
/// **Cuatro respuestas y no dos.** Una superviviente puede ser *"falta un
/// test"*, *"sobra el código"* o, a veces, ninguna de las dos (F5: el programa
/// mutado es el mismo programa), y eso se declara en el catálogo como
/// `equivalent`. Y una mutación que no llegó a probarse —no se aplicó, no
/// compiló, no corrió nada— es **inválida**, que es lo contrario de un
/// resultado: no suma ni resta, y mientras haya una la cifra no se cita.
public enum Outcome: Equatable, Sendable {
    case killed
    case survived
    case equivalent
    case invalid(Invalid)

    public enum Invalid: Equatable, Sendable, CustomStringConvertible {
        case notApplied(NotApplied)
        /// F7: un `$0` sin escapar no compilaba y se contó como *"sobrevive"*.
        /// Lo que no compila no se ha probado.
        case doesNotCompile
        case run(InvalidRun)

        public var description: String {
            switch self {
            case .notApplied(let reason): "no se aplicó: \(reason)"
            case .doesNotCompile: "no compila"
            case .run(let reason): "\(reason)"
            }
        }
    }
}

/// Junta los tres pasos —aplicar, compilar, probar— en un desenlace.
///
/// `test` es `nil` exactamente cuando no se llegó a probar: si la mutación no se
/// aplicó o no compiló, lo que diga la batería no importa, porque la batería
/// estaría midiendo el código sin mutar.
public func outcome(applied: Result<String, NotApplied>, compiled: Bool,
                    test: TestRunVerdict?, declaredEquivalent: Bool) -> Outcome {
    if case .failure(let reason) = applied { return .invalid(.notApplied(reason)) }
    guard compiled else { return .invalid(.doesNotCompile) }
    switch test {
    case .failed?: return .killed
    case .passed?: return declaredEquivalent ? .equivalent : .survived
    case .invalid(let reason)?: return .invalid(.run(reason))
    case nil: return .invalid(.doesNotCompile)
    }
}
