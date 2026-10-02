public import Domain

/// Quién ejecuta un caso de uso y sobre qué tenant.
///
/// **Existe desde F0 aunque hoy solo lleve el club dentro**, y esa es su única
/// razón de ser ahora mismo. §7.4 lo dice con todas las letras:
///
/// > *"ese contexto debe atravesar la frontera de los casos de uso desde el
/// > primer día […]. Añadir después un parámetro a todas las firmas es el
/// > refactor caro que esta decisión existe para evitar."*
///
/// Lo que llegará con §7 es **lo que dice el token**: el usuario. **No** el
/// `StaffMember` ni sus asignaciones vigentes, que son las que responden a la
/// pregunta de D-62 —*¿existe alguna asignación que conceda este verbo sobre un
/// ámbito que contenga este objetivo?*—: esas las carga el caso de uso dentro de
/// su ámbito (`D-98`). Así este tipo sigue siendo lo que es hoy, un valor que se
/// construye sin tocar la base.
public struct ActorContext: Sendable {
    /// Tenant sobre el que se ejecuta. Autoritativo: sale del *claim* firmado,
    /// no de la cabecera `Host` (§6.1).
    public let clubSlug: Slug

    /// El actor de sistema: la ingesta (§2.3-b) no tiene usuario detrás.
    ///
    /// No es un rol con permisos ilimitados; es la constatación de que ese
    /// camino **no pasa por HTTP** y por tanto no tiene `StaffMember`. Cuando
    /// §7 aterrice, la política tendrá que distinguirlo explícitamente en vez de
    /// tropezarse con un `nil`.
    public let isSystem: Bool

    public init(clubSlug: Slug, isSystem: Bool = false) {
        self.clubSlug = clubSlug
        self.isSystem = isSystem
    }
}
