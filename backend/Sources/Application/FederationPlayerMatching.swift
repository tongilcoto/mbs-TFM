public import Domain

/// Uno de los nuestros, para casar (`D-126`): el perfil, su nombre y su código en la federación si lo tiene. Es
/// lo que la aplicación le pasa al conector, que **no lee la base**.
public struct FederationMatchCandidate: Equatable, Sendable {
    public let profileID: PlayerProfileID
    public let fullName: PlayerName
    public let federationPlayerID: String?

    public init(profileID: PlayerProfileID, fullName: PlayerName, federationPlayerID: String?) {
        self.profileID = profileID
        self.fullName = fullName
        self.federationPlayerID = federationPlayerID
    }

    public init(_ profile: PlayerProfile) {
        self.init(profileID: profile.id, fullName: profile.fullName, federationPlayerID: profile.federationPlayerID)
    }
}

/// Uno de los de la federación, para casar: su código, si lo publica, y su nombre **ya como lo guarda el sistema**
/// —vuelto, validado y con las tildes del castellano (`D-123`)—, o nulo si no se lee. Dejarlo así es de la
/// aplicación, que tiene el diccionario; el conector solo compara.
public struct FederationMatchQuery: Equatable, Sendable {
    public let federationPlayerID: String?
    public let name: PlayerName?

    public init(federationPlayerID: String?, name: PlayerName?) {
        self.federationPlayerID = federationPlayerID
        self.name = name
    }
}

/// Con quién de los nuestros es un jugador de la federación (`D-126`).
public enum FederationPlayerMatch: Equatable, Sendable {
    /// Por su código: es él, aunque el club le haya corregido el nombre.
    case byCode(PlayerProfileID)
    /// Por el mismo nombre (`sameNameKey`), y solo con uno.
    case byName(PlayerProfileID)
    /// Por el mismo nombre, con varios: no se elige (`D-120`).
    case ambiguousName([PlayerProfileID])
    /// Con nadie.
    case none
}

/// **Las reglas de casar, escritas una vez** (`D-126`, punto 4): la sincronización de la plantilla y la carga del
/// acta las usan por igual. Cada conector elige la suya según lo que publica su federación: la RFFM, primero por
/// el código; una federación sin código, solo por el nombre. Funciones puras: entran las dos listas, sale una
/// respuesta por cada jugador publicado, en su orden.
public enum FederationPlayerMatching {

    /// **Primero por el código y, si no casa, por el mismo nombre.** Un perfil nuestro que ya tiene **otro**
    /// código es otro jugador de la federación aunque se llame igual —dos chavales con el mismo nombre—, así que
    /// no entra en el casado por el nombre.
    public static func byCodeThenName(
        _ published: [FederationMatchQuery], against ours: [FederationMatchCandidate]
    ) -> [FederationPlayerMatch] {
        published.map { query in
            if let code = query.federationPlayerID,
               let found = ours.first(where: { $0.federationPlayerID == code }) {
                return .byCode(found.profileID)
            }
            let free = ours.filter { candidate in
                guard let code = query.federationPlayerID, let theirs = candidate.federationPlayerID else { return true }
                return code == theirs
            }
            return byName(query, against: free)
        }
    }

    /// **Solo por el mismo nombre**: para la federación que no publica el código del jugador.
    public static func byNameOnly(
        _ published: [FederationMatchQuery], against ours: [FederationMatchCandidate]
    ) -> [FederationPlayerMatch] {
        published.map { byName($0, against: ours) }
    }

    private static func byName(
        _ query: FederationMatchQuery, against ours: [FederationMatchCandidate]
    ) -> FederationPlayerMatch {
        guard let name = query.name else { return .none }
        let same = ours.filter { $0.fullName.sameNameKey == name.sameNameKey }
        switch same.count {
        case 0: return .none
        case 1: return .byName(same[0].profileID)
        default: return .ambiguousName(same.map(\.profileID))
        }
    }
}
