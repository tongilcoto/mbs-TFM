public import Domain

/// Puerto de salida (§4.3): un repositorio **por raíz de agregado** (§4.2).
///
/// **No lleva `delete`, y es deliberado.** La FK de `competitions` es
/// `ON DELETE CASCADE` (`D-73`), así que borrar una temporada se llevaría su
/// subárbol por delante; lo que impide que eso ocurra por accidente es la guarda
/// de "cero dependientes → 409" del *spec*, que vive en el caso de uso. El
/// borrado y su guarda **nacen juntos**, en la fase que traiga
/// `DELETE /v1/seasons/{id}`. Un `delete` suelto ahora sería un arma cargada sin
/// seguro.
public protocol SeasonRepository: Sendable {
    func find(_ id: SeasonID) async throws -> Season?

    /// Por el identificador **de la federación** (`temporada=21`), no por el UUID.
    ///
    /// Es la consulta de la cascada de `/federation-link` (`D-67`): *"crear la
    /// `Season` si el `temporada=…` de la URL no corresponde a ninguna del club"*.
    func findByFederationID(_ federationSeasonID: String) async throws -> Season?

    /// Todas las del club. **Las archivadas se excluyen por defecto** (§3.5): las
    /// lecturas aplican ese *scope* salvo que se pidan explícitamente.
    ///
    /// Sin paginación a propósito: un club tiene un puñado de temporadas, y es lo
    /// que permite derivar la vigente en memoria (§3.2) en vez de en SQL.
    func list(includingArchived: Bool) async throws -> [Season]

    /// *Upsert* del agregado (§4.3).
    ///
    /// A diferencia de `ClubRepository.save` —que solo actualiza, porque el club
    /// es *singleton* del tenant y su alta es provisión— aquí el alta sí es una
    /// operación normal: la hace el administrador o la cascada de `D-67`.
    func save(_ season: Season) async throws
}

extension SeasonRepository {
    /// **La temporada de un enganche, en dos pasos** (`D-106`): por el código de la
    /// URL y, si no está, por la **etiqueta**.
    ///
    /// La temporada que el club crea en julio desde el alta de equipo no tiene
    /// código; el primer enganche la reconoce por su etiqueta y se lo pone. Devuelve
    /// esa temporada **sin código** —quien la recibe decide si escribirlo: el
    /// enganche sí, el `/preview` no— o `nil` si no hay ninguna de las dos.
    ///
    /// **Si la de esa etiqueta ya tiene otro código, no se pisa**: se lanza
    /// `seasonAlreadyLinked`. La etiqueta es la del Dominio, traducida por el
    /// conector de la federación, nunca por el catálogo. Se busca **con las
    /// archivadas**, como `createSeason`: la etiqueta sigue siendo suya.
    func findForLink(federationSeasonID code: String, label: SeasonLabel?) async throws -> Season? {
        if let byCode = try await findByFederationID(code) { return byCode }
        guard let label,
              let byLabel = try await list(includingArchived: true).first(where: { $0.label == label })
        else { return nil }
        if let other = byLabel.federationSeasonID {
            throw ApplicationError.seasonAlreadyLinked(
                label: label.value, existing: other, incoming: code)
        }
        return byLabel
    }
}
