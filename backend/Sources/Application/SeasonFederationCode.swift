import Domain

extension Season {
    /// **El código con el que se llama a la federación**, o el error si la
    /// temporada todavía no lo tiene (`D-106`, punto 7).
    ///
    /// Desde `D-106` la temporada puede nacer en la web sin código, y solo el
    /// enganche se lo pone. Como una competición solo nace en un enganche, una
    /// pasada no debería encontrarse nunca una temporada sin él; si se la
    /// encuentra, **falla con un error que lo dice**, en vez de llamar a la
    /// federación con `temporada=` vacío y apuntar lo que conteste.
    ///
    /// Lo usan las tres pasadas —calendario, clasificación y goleadores—, que
    /// son las que construyen una `FederationCoordinate` desde la temporada.
    func requireFederationCode() throws -> String {
        guard let federationSeasonID else {
            throw ApplicationError.seasonWithoutFederationCode(label: label.value)
        }
        return federationSeasonID
    }
}
