public import struct Foundation.Date

/// La competición: una instancia de liga por temporada ("Infantil · Primera ·
/// Grupo 1"). **Raíz de agregado** (§4.2).
///
/// Como `Season`, es **entrada** de la ingesta y no salida (`D-16`): las dos
/// coordenadas con las que se llama a la federación las teclea un administrador
/// pegando la URL del calendario, o las descubre el `/preview` (`D-22`, `D-67`).
public struct Competition: Identifiable, Equatable, Sendable {
    public let id: CompetitionID

    /// FK al **UUID interno** de `Season`, no al `federationSeasonID` (`D-06`).
    ///
    /// Es la única propagación de temporada del modelo junto con la de `Player`
    /// (`D-28`): en el resto del árbol se alcanza por FK.
    public let seasonID: SeasonID

    // ── Identidad heredable ──────────────────────────────────────────────────
    // Las dos las copia la ingesta a cada `Team` que crea, donde entran en la
    // clave única (§3.5). Por eso `gender` no se edita como un rótulo (D-58).

    public let modality: Modality
    public let gender: Gender

    // ── Coordenada de la federación ──────────────────────────────────────────
    // **No son intercambiables** (§3.7) y las dos son obligatorias.

    /// `competicion=24037548`: designa **categoría de edad + división**.
    public let federationCompetitionID: String

    /// `grupo=24037549`: designa **solo el grupo**. Con `seasonID` forma la clave
    /// única de la entidad (§3.5).
    public let federationGroupID: String

    // ── Rótulos ──────────────────────────────────────────────────────────────
    // Nuestros y siempre editables. Se **muestran**; no se llaman.

    /// Mismo enumerado que `Team.category`, lo que permite **validar** que un
    /// equipo solo participe en una competición de su edad (§3.2).
    public let ageCategory: TeamCategory

    /// Nivel competitivo ("Primera", "Preferente", "Honor"…). **Texto libre**:
    /// varía por federación y por categoría (§3.6).
    public let divisionLabel: String

    /// Rótulo del grupo ("Grupo 1", "Grupo Único"). **Texto libre y no deducible
    /// de `federationGroupID`**: uno se muestra, el otro se llama (§3.7).
    public let groupLabel: String

    /// El nombre que la federación le da a la competición, **literal**.
    ///
    /// **Es evidencia, no rótulo** (`D-72`): se guarda tal cual, no se corrige y
    /// no se muestra — lo que se muestra es `displayName`, compuesto de los tres
    /// rótulos de arriba, que sí son nuestros.
    ///
    /// Existe por lo que sostiene: de este texto sale la inferencia de `gender`
    /// ([Anexo RFFM §F.14]), que entra en la clave única de `Team`. Cuando un
    /// alta reviente con 409 porque la inferencia falló —el anexo avisa de que el
    /// truncado a 40 caracteres puede comerse el marcador `FEMENINO` sin dar
    /// error—, esto es lo que hay que poder mirar.
    ///
    /// **Anulable, y a menudo nulo**: el alta por ids (semillas, *scripts*,
    /// tests) no pasa por la federación y no tiene nombre que guardar.
    public let federationName: String?

    /// Última sincronización **con éxito**. `nil` ⇒ nunca sincronizada, que es la
    /// condición bajo la cual las coordenadas siguen siendo editables (§3.7).
    public let lastSyncedAt: Date?

    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: CompetitionID,
        seasonID: SeasonID,
        modality: Modality,
        gender: Gender,
        federationCompetitionID: String,
        federationGroupID: String,
        ageCategory: TeamCategory,
        divisionLabel: String,
        groupLabel: String,
        federationName: String? = nil,
        lastSyncedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        try Self.requireNonEmpty(federationCompetitionID, field: "federationCompetitionId")
        try Self.requireNonEmpty(federationGroupID, field: "federationGroupId")
        try Self.requireNonEmpty(divisionLabel, field: "divisionLabel")
        try Self.requireNonEmpty(groupLabel, field: "groupLabel")

        self.id = id
        self.seasonID = seasonID
        self.modality = modality
        self.gender = gender
        self.federationCompetitionID = federationCompetitionID
        self.federationGroupID = federationGroupID
        self.ageCategory = ageCategory
        self.divisionLabel = divisionLabel
        self.groupLabel = groupLabel
        self.federationName = federationName
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private static func requireNonEmpty(_ value: String, field: String) throws {
        guard !value.trimmed.isEmpty else {
            throw DomainError.invalidValue(field: field, reason: "no puede estar vacío")
        }
    }

    /// **Derivado en lectura** (§5.2): `ageCategory · divisionLabel · groupLabel`.
    ///
    /// No hay columna detrás. La federación sí publica un nombre propio, pero
    /// llega truncado a 40 caracteres y con formato inestable ([Anexo RFFM
    /// §F.11]), así que el rótulo que se muestra se compone de piezas nuestras.
    public var displayName: String {
        "\(ageCategory.displayLabel) · \(divisionLabel) · \(groupLabel)"
    }

    /// `true` en cuanto ha habido una sincronización con éxito. Es lo que cierra
    /// la puerta a editar coordenadas y género (`D-22`).
    public var isSynced: Bool { lastSyncedAt != nil }
}

extension Competition {
    /// Aplica una modificación **parcial** (§5.5), con la guarda de `D-22`.
    ///
    /// # Dos grupos de campos con dos reglas distintas
    ///
    /// | Campos | Regla |
    /// |---|---|
    /// | `ageCategory`, `divisionLabel`, `groupLabel` | **siempre** editables: solo se muestran |
    /// | `federationCompetitionID`, `federationGroupID`, **`gender`** | solo mientras `lastSyncedAt` sea `nil` |
    ///
    /// Cambiar una coordenada después de sincronizar es **repuntar a otro
    /// calendario** con datos ya colgando. Y `gender` sigue esa misma regla
    /// aunque no sea coordenada (`D-58`) —es el único campo que lo hace— porque
    /// **ya se propagó** a cada `Team` que creó la ingesta, donde forma parte de
    /// la clave única (§3.5): cambiarlo después dejaría la competición diciendo
    /// una cosa y sus equipos otra.
    ///
    /// `seasonID` y `modality` no aparecen: una competición no se muda de
    /// temporada, y cambiar la modalidad invalidaría la identidad de sus equipos.
    ///
    /// La guarda vive **aquí y no en el caso de uso** para que la ruta de ingesta
    /// (§2.3-b), que no pasa por HTTP, quede sujeta a la misma regla.
    public func applying(
        gender: Gender? = nil,
        ageCategory: TeamCategory? = nil,
        divisionLabel: String? = nil,
        groupLabel: String? = nil,
        federationCompetitionID: String? = nil,
        federationGroupID: String? = nil
    ) throws -> Competition {
        if isSynced {
            try requireUnchanged(gender, self.gender, field: "gender")
            try requireUnchanged(
                federationCompetitionID, self.federationCompetitionID,
                field: "federationCompetitionId")
            try requireUnchanged(
                federationGroupID, self.federationGroupID, field: "federationGroupId")
        }

        return try Competition(
            id: id,
            seasonID: seasonID,
            modality: modality,
            gender: gender ?? self.gender,
            federationCompetitionID: federationCompetitionID ?? self.federationCompetitionID,
            federationGroupID: federationGroupID ?? self.federationGroupID,
            ageCategory: ageCategory ?? self.ageCategory,
            divisionLabel: divisionLabel ?? self.divisionLabel,
            groupLabel: groupLabel ?? self.groupLabel,
            federationName: federationName,  // lo escribe la ingesta, no un PATCH
            lastSyncedAt: lastSyncedAt,      // lo escribe la ingesta al terminar
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Reenviar el **mismo** valor no es un cambio, así que no se rechaza: un
    /// `PATCH` que repite lo que ya hay es idempotente, no un conflicto.
    private func requireUnchanged<T: Equatable>(
        _ incoming: T?, _ current: T, field: String
    ) throws {
        guard let incoming, incoming != current else { return }
        throw DomainError.notEditableAfterSync(field: field)
    }
}
