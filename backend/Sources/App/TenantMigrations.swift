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
/// # Y antes de tocar una que ya existe: no se toca (`D-90`)
///
/// `_fluent_migrations` guarda **el nombre** de cada migración aplicada, no su
/// contenido, así que un *schema* que ya aplicó `CreateClub` **no recibe jamás**
/// una edición posterior de su `prepare` — sin error, sin aviso y sin nada que
/// lo diga. Lo que haya que corregir va en una **migración nueva**.
///
/// No es teórico: `CreateClub.prepare` se editó un día después de nacer
/// (`8550bcb`, para derivar su `CHECK` de `FederationCode` como manda `D-02`), y
/// que hoy no se note es cuestión de dos casualidades —los valores eran los
/// mismos y el único club vivo nació después—. Lo midió el bloque `A-5` del plan
/// de auditoría (H-31), que además comprobó que **los dos caminos de §4.7
/// convergen byte a byte**: un alta limpia y un club migrado en tres lotes de
/// tres días dan el mismo esquema. Editar una migración aplicada es la **única**
/// vía real por la que eso dejaría de ser cierto.
///
/// La posición en esta lista, en cambio, **no** afecta al esquema resultante —
/// también medido—: lo que ordena es la dependencia de FK para que un alta
/// limpia pueda aplicarlas de una pasada.
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
