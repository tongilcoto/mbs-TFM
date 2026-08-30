import Fluent
import Foundation
public import Application
public import Domain

/// Adaptador secundario: **implementa** el puerto `ClubRepository` (§4.3), así
/// que la dependencia está invertida — la Aplicación no sabe que existe Fluent.
///
/// Recibe la `Database` **ya dentro del ámbito de tenant** (§6.2): quien la
/// obtiene es `withSearchPath`, y por eso aquí no hay ni rastro de *schemas*.
/// El repositorio "se queda tonto" a propósito (§7.4).
public struct FluentClubRepository: ClubRepository {
    private let database: any Database

    public init(database: any Database) {
        self.database = database
    }

    public func current() async throws -> Club? {
        // `Club` es *singleton* del tenant (§4.2): dentro de este *schema* hay
        // exactamente una fila, así que no hay filtro que aplicar.
        guard let record = try await ClubRecord.query(on: database).first() else {
            return nil
        }
        return try record.toDomain()
    }

    public func save(_ club: Club) async throws {
        // **`UPDATE` directo por id, sin releer la fila.** La versión anterior
        // hacía un `SELECT` para traerse el `Record` y luego lo guardaba, así que
        // un `PATCH` acababa emitiendo **dos** `SELECT` sobre `clubs`: el del
        // caso de uso al cargar el agregado y éste. El segundo no aportaba nada
        // —la entidad ya venía cargada y su id es la clave—.
        //
        // Se escriben **solo los campos que el contrato deja escribir** (§5.2).
        // `slug`, `federation` y `crest_key` no se tocan: sus dueños son la
        // provisión y la ingesta, no este camino. Un `record.update()` completo
        // los reescribiría todos, que es justo lo que no se quiere.
        //
        // `updated_at` va explícito porque `@Timestamp(on: .update)` solo actúa
        // al guardar un modelo, no en un `update` de constructor de consulta.
        // TODO(§4.3): cuando exista el puerto `Clock`, ese `Date()` sale de él.
        let updated = try await ClubRecord.query(on: database)
            .filter(\.$id == club.id.raw)
            .set(\.$name, to: club.name)
            .set(\.$shortName, to: club.shortName)
            .set(\.$updatedAt, to: Date())
            .update()
        _ = updated
    }
}

extension ClubRecord {
    /// Mapeo `Record → Entidad`, que es trabajo del repositorio (§4.4).
    func toDomain() throws -> Club {
        guard let federation = FederationCode(rawValue: federation) else {
            // Inalcanzable mientras exista el `CHECK` de la migración; si un día
            // salta, es que alguien escribió en la tabla saltándose el esquema.
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "federation", value: self.federation
            )
        }
        // Sin `?? Date()`: rellenar una marca de tiempo ausente inventaría el
        // dato en silencio. Un `@Timestamp` nulo significa que la fila entró sin
        // pasar por Fluent, y eso es corrupción, no un valor por defecto.
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(table: Self.schema, id: try requireID().uuidString)
        }
        return try Club(
            id: .init(raw: try requireID()),
            name: name,
            shortName: shortName,
            slug: Slug(slug),
            crestKey: crestKey,
            federation: federation,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public enum PersistenceError: Error, Equatable, Sendable {
    /// La columna guarda un valor fuera del dominio de su enumerado, pese al
    /// `CHECK` (§4.6). No es un error de negocio: es corrupción.
    case corruptEnumeration(table: String, column: String, value: String)
    /// `created_at`/`updated_at` nulos: la fila no pasó por Fluent.
    case missingTimestamp(table: String, id: String)
    /// No hay fila que actualizar. En `clubs` significa *schema* sin aprovisionar.
    case notFound(table: String)
    /// Un par de columnas que el Dominio modela como **una sola cosa** llegó a
    /// medias. Hoy solo `matches.home_score`/`away_score`, que son `MatchResult`
    /// —"los dos goles o ninguno"— repartido en dos columnas anulables porque el
    /// esquema no sabe expresar el par. Es corrupción, no un caso de negocio.
    case corruptPair(table: String, columns: String, id: String)
}
