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
/// (`D-16`); F5, su **salida**: `OpponentClub`, `Team`, `Round` y `Match`.
///
/// **Las dos primeras se intercalan *antes* de `CreateCompetition`**, que es su
/// sitio en el orden canónico, y sobre una base ya migrada eso no rompe nada:
/// Fluent aplica solo las que faltan, y ni `Team` ni `OpponentClub` tienen FK
/// hacia `Competition` ni al revés. `TeamRegistration` sigue sin existir (es
/// `D-68`, y su llamante es el `POST /v1/teams` de otra fase).
public enum TenantMigrations {
    public static func all() -> [any Migration] {
        [
            CreateClub(),
            CreateSeason(),
            CreateOpponentClub(),
            CreateTeam(),
            CreateCompetition(),
            CreateRound(),
            CreateMatch(),
            CreateIngestionRun(),
        ]
    }
}
