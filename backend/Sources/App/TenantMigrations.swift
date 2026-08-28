public import Fluent
import Persistence

/// El juego de migraciones que recibe **cada *schema* de club**.
///
/// **El orden es el de dependencia de FK** (§4.6), y es el orden de registro,
/// no el nombre del fichero:
///
/// `Club → Season → OpponentClub → Team → TeamRegistration → Competition →
///  Round → Match → StandingRow → Player → Absence → Appearance → Card → Goal →
///  LeagueScorer → CompetitionSanctionBracket → StaffMember → StaffPosition →
///  PositionPermission → StaffAssignment`
///
/// Cada fase añade las suyas **al final de la lista que le corresponda por FK**,
/// nunca al final a secas.
///
/// F0 trajo `Club`; F1, `Season` y `Competition` — la **entrada** de la ingesta
/// (`D-16`). Las que en el orden completo se intercalan entre las dos
/// (`OpponentClub`, `Team`, `TeamRegistration`) todavía no existen, y no hacen
/// falta: `Competition` solo depende de `Season`.
public enum TenantMigrations {
    public static func all() -> [any Migration] {
        [
            CreateClub(),
            CreateSeason(),
            CreateCompetition(),
        ]
    }
}
