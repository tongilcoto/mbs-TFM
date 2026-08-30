/// Puerto de salida: **el único punto de paso a datos de tenant** (§6.2).
///
/// Abre el ámbito transaccional del club del actor y entrega dentro los
/// repositorios. Lo implementa el adaptador de persistencia con
/// `SET LOCAL search_path` (§6.4, estrategia A); la Aplicación no sabe eso — de
/// hecho no sabe ni que hay *schemas*.
///
/// Existe como puerto, y no como una `Database` que se pasa por ahí, porque
/// §6.2 exige que **todo** acceso entre por un único sitio. Si el ámbito fuese
/// opcional, la corrección volvería a depender de que alguien se acuerde.
public protocol TenantUnitOfWork: Sendable {
    func withRepositories<T: Sendable>(
        actor: ActorContext,
        _ work: @escaping @Sendable (any Repositories) async throws -> T
    ) async throws -> T
}

// `@escaping` no es una concesion de estilo: el ambito de tenant ES una
// transaccion (§6.2) y `Database.transaction` de Fluent exige que la clausura
// escape. Declararlo en el puerto mantiene honesta la firma en vez de que el
// adaptador tenga que retorcerse para cumplirla.

/// Los puertos de salida disponibles dentro de un ámbito de tenant.
///
/// Crece con cada fase: F0 trajo `clubs`; F1, la entrada de la ingesta (`D-16`);
/// F5, su **salida** — las cuatro entidades que la pasada del calendario escribe.
public protocol Repositories: Sendable {
    var clubs: any ClubRepository { get }
    var seasons: any SeasonRepository { get }
    var competitions: any CompetitionRepository { get }
    var rounds: any RoundRepository { get }
    var opponentClubs: any OpponentClubRepository { get }
    var teams: any TeamRepository { get }
    var matches: any MatchRepository { get }
    var ingestionRuns: any IngestionRunRepository { get }
}
