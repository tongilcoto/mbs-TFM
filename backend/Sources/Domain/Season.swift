public import struct Foundation.Date

/// La temporada. **Raíz de agregado** (§4.2).
///
/// No es salida de la ingesta sino su **entrada** (`D-16`): la coordenada con la
/// que se llama a la federación es configuración que teclea un administrador o
/// que descubre el `/preview`, no algo que la ingesta traiga.
public struct Season: Identifiable, Equatable, Sendable {
    public let id: SeasonID

    /// Lleva `UNIQUE` (§3.5) y es lo que ve el usuario.
    public let label: SeasonLabel

    /// Identificador de la temporada en la API de la federación (`temporada=21`).
    ///
    /// **Obligatorio** (§3.2): toda temporada tiene contrapartida federativa.
    /// Es un **secuencial propio de cada federación** —`21` no guarda relación
    /// con "2024/25"— y **cambia cada temporada**: es la única pieza de
    /// configuración que hay que actualizar cada año.
    ///
    /// Nunca es clave de unión (`D-06`): la PK y las FK son el `id` UUID.
    public let federationSeasonID: String

    /// Archivado **reversible**, y deliberadamente distinto del *soft delete*
    /// (§4.4): oculta la temporada y, de facto, su subárbol. `Season` **sí**
    /// admite borrado físico, que es otra operación.
    public let archivedAt: Date?

    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: SeasonID,
        label: SeasonLabel,
        federationSeasonID: String,
        archivedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard !federationSeasonID.trimmed.isEmpty else {
            throw DomainError.invalidValue(
                field: "federationSeasonId", reason: "no puede estar vacío"
            )
        }
        self.id = id
        self.label = label
        self.federationSeasonID = federationSeasonID
        self.archivedAt = archivedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 1 de julio del año de inicio. **Derivada de `label`, no almacenada aquí**
    /// (§3.2): si fuera una propiedad más, alguien podría escribirla desalineada.
    public var startDate: Date { label.startDate }

    /// 30 de junio del año de fin. Misma regla que `startDate`.
    public var endDate: Date { label.endDate }

    public var isArchived: Bool { archivedAt != nil }
}

extension Season {
    /// Aplica una modificación **parcial** (§5.5): campo ausente (`nil`) no se toca.
    ///
    /// Mismo patrón que `Club.applying` — devuelve una entidad nueva para que el
    /// resultado de un cambio pase por la misma puerta que un alta.
    public func applying(
        label: SeasonLabel? = nil,
        federationSeasonID: String? = nil
    ) throws -> Season {
        try Season(
            id: id,
            label: label ?? self.label,
            federationSeasonID: federationSeasonID ?? self.federationSeasonID,
            archivedAt: archivedAt,   // se cambia con `archived`/`restored`, no por PATCH
            createdAt: createdAt,
            updatedAt: updatedAt      // lo pone la BD (@Timestamp on: .update)
        )
    }

    /// Archiva. **No es borrar** (§3.5): es reversible y conserva el subárbol.
    public func archived(at instant: Date) throws -> Season {
        try Season(
            id: id, label: label, federationSeasonID: federationSeasonID,
            archivedAt: instant, createdAt: createdAt, updatedAt: updatedAt
        )
    }

    /// Deshace el archivado.
    /// Comprueba que el calendario que llega es **de esta temporada** (`D-91`).
    ///
    /// # Por qué hace falta una segunda guarda, y por qué no la vio F5
    ///
    /// `requireSameSource` (`D-84`) compara el **nombre** de la competición, y
    /// eso caza *"me he equivocado de competición"*. No caza el error que ocurre
    /// **cada verano** —copiar los códigos del año pasado al dar de alta la
    /// temporada nueva—, porque la coordenada de la RFFM **lleva la temporada
    /// dentro** (cada año es un bloque nuevo) y **el nombre es idéntico entre
    /// temporadas**: medido el 2026-09-13 sobre PRIMERA CADETE Grupo 4, los
    /// rótulos `competicion` y `grupo` no cambian de un año a otro
    /// ([Anexo RFFM §F.17]). Ni el nombre ni la etiqueta de temporada valen: esa
    /// etiqueta es **el eco del parámetro que enviamos** (§F.16), así que
    /// compararla con la nuestra sería comparar un dato consigo mismo.
    ///
    /// # La mediana, y por qué no las otras dos formas
    ///
    /// Lo que no puede ser eco son **las fechas de los partidos**, que en un
    /// desfase de temporada se van doce meses. La regla es *"la temporada de un
    /// calendario es la de **la mitad** de sus partidos"*:
    ///
    /// - **Todas dentro** tumbaría la competición entera —y para siempre— por un
    ///   partido aplazado a julio, que es un caso real y no se va a deshacer.
    /// - **Que los rangos solapen** tolera el aplazado pero depende de **un solo
    ///   valor**: un calendario de 25-26 con un partido reprogramado en julio de
    ///   2026 solaparía con la 26-27 y pasaría la guarda.
    /// - Un **umbral** (*"el 80% dentro"*) obliga a justificar un número que
    ///   ningún dato justifica.
    ///
    /// La mediana no tiene umbral que discutir y es inmune a los extremos.
    ///
    /// # Un calendario sin fechas no opina
    ///
    /// Una competición recién publicada puede no tener ni una fecha. Eso **no es
    /// evidencia de nada**, y pararla sería el error que `D-56` evita: tratar un
    /// silencio como un dato.
    ///
    /// - Parameter matchDates: las fechas de **todos** los partidos del
    ///   calendario que llega, en cualquier orden.
    public func requireOwnsCalendar(matchDates: [Date]) throws {
        guard !matchDates.isEmpty else { return }
        // Con un número **par** de fechas se toma la superior de las dos
        // centrales. Da igual cuál: la regla no depende de un día, y lo que
        // separa una temporada de otra son doce meses.
        let median = matchDates.sorted()[matchDates.count / 2]
        guard median < startDate || median > endDate else { return }
        throw DomainError.federationSeasonMismatch(
            seasonLabel: label.value, calendarMedian: median)
    }

    public func restored() throws -> Season {
        try Season(
            id: id, label: label, federationSeasonID: federationSeasonID,
            archivedAt: nil, createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

extension Collection<Season> {
    /// La temporada **vigente**: la de `endDate` más próximo que aún es ≥ la
    /// fecha dada (§3.2).
    ///
    /// **`isCurrent` se deriva en lectura y no se almacena**, y por eso vive
    /// aquí y no en `Season`: no es una propiedad de una temporada sino su
    /// posición **relativa** al resto. Como el tiempo no retrocede, hay
    /// exactamente una y no queda invariante que mantener — que es justo lo que
    /// una columna `is_current` sí obligaría a mantener.
    ///
    /// **Las archivadas no cuentan.** Archivar oculta la temporada (§3.5), y una
    /// temporada oculta que resultara ser la vigente dejaría al cliente sin
    /// ninguna.
    ///
    /// Se resuelve en memoria y no en SQL a propósito: un club tiene un puñado
    /// de temporadas, así que la lista completa cabe de sobra y la regla se
    /// prueba en el nivel 1 de la pirámide, sin contenedor (§8.1).
    public func current(on date: Date) -> Season? {
        self.filter { !$0.isArchived && $0.endDate >= date }
            .min { $0.endDate < $1.endDate }
    }
}
