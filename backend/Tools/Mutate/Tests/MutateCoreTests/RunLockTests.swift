import Testing
@testable import MutateCore

@Suite("El candado: una pasada por paquete (el estreno de A-15)")
struct RunLockTests {

    @Test("sin candado, se toma")
    func free() {
        #expect(lockDecision(holder: nil, ownPID: 10, isAlive: { _ in true }) == .acquire)
    }

    @Test("el candado de un proceso vivo no se pisa: ni se arranca ni se restaura nada")
    func liveHolderIsRefused() {
        #expect(lockDecision(holder: 42, ownPID: 10, isAlive: { $0 == 42 }) == .refuse(pid: 42))
    }

    @Test("el candado de un proceso muerto se recupera, y con él su diario")
    func staleHolderIsTakenOver() {
        #expect(lockDecision(holder: 42, ownPID: 10, isAlive: { _ in false })
                == .takeOverStale(pid: 42))
    }

    @Test("un candado con el propio pid es de una ejecución anterior que reutilizó el número")
    func ownPIDIsStale() {
        #expect(lockDecision(holder: 10, ownPID: 10, isAlive: { _ in true })
                == .takeOverStale(pid: 10))
    }
}
