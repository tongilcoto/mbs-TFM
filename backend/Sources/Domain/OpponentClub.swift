public import struct Foundation.Date

/// El club rival (§3.2). **Identidad del club, separada de sus equipos** (§3.6):
/// un club rival suele tener equipo en varias categorías, y todas esas filas
/// `Team` apuntan a esta misma.
///
/// Es **salida de la ingesta** (§5.1): la crea la pasada y el BFF solo la
/// corrige. No tiene `POST` ni `DELETE` en el contrato, y por eso su `merging`
/// de abajo es la única forma de que cambie desde este lado.
public struct OpponentClub: Identifiable, Equatable, Sendable {
    public let id: OpponentClubID

    /// Como lo publica la fuente la primera vez: mayúsculas y puntuación
    /// irregular ([Anexo RFFM §F.5]). **Descriptivo** (§3.7): el valor bueno
    /// acaba siendo el del administrador.
    public let name: String

    /// Para mostrar. El *spec* dice que se inicializa desde `name` si no se
    /// aporta, y la ingesta nunca lo aporta: nace igual que `name` y lo acorta
    /// un humano.
    public let shortName: String

    /// **Inmutable** (§3.2, *spec*): se deriva del nombre al crear la fila
    /// (`D-82`) y no se recalcula nunca. Por eso **no es parámetro de
    /// `merging`** — la regla no es "no lo pises", es que no hay por dónde.
    public let slug: Slug

    /// El segmento numérico de la ruta del escudo ([Anexo RFFM §F.4]).
    /// **Anulable**: es una inferencia sobre un nombre de fichero, no un campo
    /// publicado, así que puede no extraerse (§3.7).
    public let federationClubID: String?

    /// La clave del objeto en Storage, **no una URL** (`D-19`).
    ///
    /// **Hoy siempre nula**: descargar el escudo y subirlo exige un adaptador de
    /// Storage que F5 no trae. El campo existe porque su regla de *upsert* sí se
    /// decide aquí —es descriptivo (§3.7)— y porque dejarlo fuera obligaría a
    /// tocar la entidad y su tabla cuando llegue.
    public let crestKey: String?

    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: OpponentClubID,
        name: String,
        shortName: String,
        slug: Slug,
        federationClubID: String? = nil,
        crestKey: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard !name.trimmed.isEmpty else {
            throw DomainError.invalidValue(field: "name", reason: "no puede estar vacío")
        }
        guard !shortName.trimmed.isEmpty else {
            throw DomainError.invalidValue(field: "shortName", reason: "no puede estar vacío")
        }

        self.id = id
        self.name = name
        self.shortName = shortName
        self.slug = slug
        self.federationClubID = federationClubID
        self.crestKey = crestKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// El nombre reducido a clave de comparación, para el **paso 2** de la
    /// cadena de §3.7.
    ///
    /// Se deriva de `name` y no de `shortName` porque `name` es el campo que la
    /// fuente siembra, así que las dos formas normalizadas coinciden **mientras
    /// nadie corrija**.
    ///
    /// # Y una advertencia que hay que leer entera (H-21)
    ///
    /// La redacción anterior de este comentario decía que `NormalizedName`
    /// *"existe precisamente para que la corrección del administrador no rompa el
    /// emparejamiento"*. **Es falso, y lo midió el bloque `A-2` del plan de
    /// auditoría.** `NormalizedName` quita acentos, puntuación y caja (`D-80`) —
    /// **no palabras**: corregir `"C.D. GALAPAGAR"` a `"Club Deportivo
    /// Galapagar"` produce otra clave, y el paso 2 deja de reconocer a ese club.
    ///
    /// Es el roce de las dos mitades de §3.7: la política clasifica `name` como
    /// **descriptivo** —la fuente no lo reescribe nunca (`D-18`)—, así que a
    /// partir de la corrección lo que hay guardado **ya no es lo que la fuente
    /// manda cada semana**, que es exactamente el supuesto sobre el que el paso 2
    /// se apoya.
    ///
    /// **Lo que hoy lo sostiene es el paso 1**, y por eso `D-76` no es cosmética:
    /// con `federation_club_id` guardado la clave resuelve y nada de esto importa.
    /// Sin él —§F.4 avisa de que la inferencia puede fallar— la pasada cae al paso
    /// 3 y **da de alta un club duplicado sin reportarlo**, porque ni el
    /// `UNIQUE(name)` de §3.5 lo ve (son dos nombres distintos) ni el desempate de
    /// *slug* lo distingue del caso legítimo. Medido: 3 filas donde había 2.
    ///
    /// **No se parchea aquí**: elegir otra clave de comparación es una decisión de
    /// la cadena, y sus tres opciones están en H-21. Lo que no puede pasar es que
    /// se decida **después** de abrir el `PATCH` que corrige el nombre — hoy no
    /// existe, y esa es toda la razón por la que esto no es urgente.
    public var matchingName: NormalizedName { NormalizedName(name) }

    /// La proyección a candidato de la cadena de §3.7 (F4).
    ///
    /// Existe aquí y no en el caso de uso por lo que Plan §4.6 dejó escrito: los
    /// candidatos llevan **solo claves de emparejamiento**, así que la entidad
    /// se proyecta a ellos en vez de pasarse entera. Es el "mapeo trivial" que
    /// F4 se dejó de deber, y es lo que hace estructural —y no disciplinar— que
    /// por la cadena no pase nada más que lo que empareja.
    public var candidate: OpponentClubCandidate {
        OpponentClubCandidate(id: id, federationClubID: federationClubID, name: matchingName)
    }
}

extension OpponentClub {
    /// El *upsert* del club rival (§3.7), campo a campo por su clase.
    ///
    /// | Campo | Clase | Qué hace |
    /// |---|---|---|
    /// | `name`, `shortName`, `crestKey` | **descriptivo** | la fuente siembra y no vuelve a tocar |
    /// | `federationClubID` | **de emparejamiento** | no sobrescribe; rellena hueco (`D-76`) |
    /// | `slug` | **inmutable** | ni siquiera es parámetro |
    ///
    /// Que `slug` no esté en la firma no es un descuido: es la misma técnica con
    /// la que `MatchCandidate` no lleva fecha. Lo que no se puede nombrar no se
    /// puede pisar.
    public func merging(
        name incomingName: String?,
        shortName incomingShortName: String?,
        crestKey incomingCrestKey: String?,
        federationClubID incomingFederationClubID: String?
    ) throws -> OpponentClub {
        try OpponentClub(
            id: id,
            name: UpsertPolicy.descriptive(existing: name, incoming: incomingName),
            shortName: UpsertPolicy.descriptive(
                existing: shortName, incoming: incomingShortName),
            slug: slug,
            federationClubID: UpsertPolicy.matching(
                existing: federationClubID, incoming: incomingFederationClubID),
            crestKey: UpsertPolicy.descriptive(existing: crestKey, incoming: incomingCrestKey),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
