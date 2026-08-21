import Fluent
import SQLKit
import Vapor

/// DTO mínimo (§5.2). Aquí no hay dominio ni mapeo de tres capas: el spike no valida eso.
struct SeasonDTO: Content {
    var id: UUID?
    var label: String
    var federationSeasonId: Int
}

public func routes(_ app: Application) throws {
    let tenanted = app.grouped(TenantResolutionMiddleware())

    tenanted.get("seasons") { req async throws -> [SeasonDTO] in
        try await req.withTenantDB { db in
            try await SeasonRecord.query(on: db).sort(\.$label).all()
                .map { SeasonDTO(id: $0.id, label: $0.label, federationSeasonId: $0.federationSeasonID) }
        }
    }

    tenanted.post("seasons") { req async throws -> Response in
        let dto = try req.content.decode(SeasonDTO.self)
        let created = try await req.withTenantDB { db -> SeasonDTO in
            let record = SeasonRecord(label: dto.label, federationSeasonID: dto.federationSeasonId)
            try await record.create(on: db)
            return SeasonDTO(id: record.id, label: record.label, federationSeasonId: record.federationSeasonID)
        }
        return try await created.encodeResponse(status: .created, for: req)
    }

    // ── Sondas del spike ────────────────────────────────────────────────────────
    // No son API: son los testigos que hacen falsable la hipótesis de §6.2/§6.4.

    /// `search_path` efectivo **dentro** del ámbito de tenant. Debe ser el del club.
    tenanted.get("debug", "search-path") { req async throws -> String in
        try await req.withTenantDB { db in
            guard let sql = db as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
            return try await showSearchPath(on: sql)
        }
    }

    /// `search_path` de una conexión pedida al pool compartido **fuera** de todo ámbito
    /// de tenant. Si aquí aparece un schema de club, el pool está contaminado.
    app.get("debug", "pool-search-path") { req async throws -> String in
        guard let sql = req.db(.control) as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        return try await showSearchPath(on: sql)
    }
}

func showSearchPath(on sql: any SQLDatabase) async throws -> String {
    struct Row: Decodable { let search_path: String }
    guard let row = try await sql.raw("SHOW search_path").first(decoding: Row.self) else {
        return ""
    }
    return row.search_path
}
