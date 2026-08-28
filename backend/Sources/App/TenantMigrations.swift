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
/// Hoy solo está la primera: F0 es andamiaje. Cada fase añade las suyas **al
/// final de la lista que le corresponda por FK**, nunca al final a secas.
public enum TenantMigrations {
    public static func all() -> [any Migration] {
        [
            CreateClub(),
        ]
    }
}
