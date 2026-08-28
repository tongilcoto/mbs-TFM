public import Domain

/// Caso de uso: modificar parcialmente el club (§5.1).
///
/// Es la plantilla del **camino de escritura** que reutilizarán las fases
/// siguientes: cargar el agregado, aplicarle el cambio —donde el Dominio
/// revalida sus invariantes— y guardarlo. La validación **no** está aquí: está
/// en `Club.applying`, para que la ruta de ingesta (§2.3-b), que no pasa por
/// HTTP, quede sujeta a la misma regla.
public struct UpdateClub: Sendable {
    private let clubs: any ClubRepository

    public init(clubs: any ClubRepository) {
        self.clubs = clubs
    }

    public func execute(actor: ActorContext, command: Command) async throws -> Club {
        guard let current = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        // TODO(§7): aquí irá la comprobación de ámbito. `Club` lo escribe la
        // administración del club (§7.3), y la decisión vive en el caso de uso
        // (D-63), no en el controlador ni en el repositorio.
        let updated = try current.applying(name: command.name, shortName: command.shortName)
        try await clubs.save(updated)
        return updated
    }

    /// Lo que el caso de uso acepta. **No es el DTO**: el DTO es del contrato y
    /// vive en el adaptador (§2.2). `nil` significa "no se modifica" (§5.5).
    public struct Command: Sendable {
        public let name: String?
        public let shortName: String?

        public init(name: String?, shortName: String?) {
            self.name = name
            self.shortName = shortName
        }

        /// `minProperties: 1` del *spec* — que **el generador ignora** (D-65), así
        /// que lo comprueba el adaptador antes de construir esto.
        public var isEmpty: Bool { name == nil && shortName == nil }
    }
}
