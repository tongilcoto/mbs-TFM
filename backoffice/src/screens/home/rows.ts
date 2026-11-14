// Las filas de la tabla: un equipo por fila, con todas sus competiciones (plan R1, §3.2 y decisión 1).
import type { components } from '../../api/schema'
import { formatInstant } from '../../theme/format'
import type { CompetitionCell, TeamRow } from '../../components/teamRow'
import { shownHealth } from '../../relaunch'
import { competitionLabel, type IngestionHealth, optionsOf, teamNames } from '../../theme/names'
import { summaryCell } from './summary'

type Registration = components['schemas']['TeamRegistrationResponse']
type Competition = components['schemas']['CompetitionResponse']
type Summary = components['schemas']['TeamCompetitionSummary']

// Una fila de la portada, con lo que necesita para ordenarse (bloque T del plan R2): la tabla pinta la fila, y las
// reglas de orden (order.ts) miran sus claves, que son los datos de verdad y no los textos que se ven.
export interface HomeRow extends TeamRow {
  keys: SortKeys
}

export interface SortKeys {
  // La categoría por edad, de menor a mayor, en el orden del catálogo; y la letra, vacía si no tiene.
  age: number
  letter: string
  // De sus competiciones (vacías, si no tiene): los nombres como se ven, cómo va cada ingesta y cuándo se
  // sincronizó cada una (`null`, nunca).
  competitionNames: string[]
  healths: (IngestionHealth | undefined)[]
  lastSynced: (string | null)[]
  // El puesto en cada una (`null`, sin clasificación todavía), del resumen (plan R5).
  positions: (number | null)[]
}

// Junta cada inscripción con sus competiciones. El orden de las filas es el del servidor: por categoría, de
// menor a mayor edad, y por letra. `relaunched`, las competiciones cuyos datos se están volviendo a traer desde la
// portada (plan R4, decisión 7): salen «En marcha» aunque el servidor aún no lo diga.
export function teamRows(
  registrations: Registration[],
  competitions: Competition[],
  relaunched: ReadonlySet<string> = new Set(),
): HomeRow[] {
  const byId = new Map(competitions.map((c) => [c.id, c]))
  // Si dos equipos se llamarían igual («Alevín A» masculino y femenino), cada uno con lo que lo distingue.
  const names = teamNames(registrations.map((registration) => registration.team))
  return registrations.map((registration) => {
    // Cada competición, con el resumen del equipo en ella.
    const entries = registration.competitions.flatMap(({ competitionId, summary }) => {
      const competition = byId.get(competitionId)
      return competition ? [{ competition, summary }] : []
    })
    const own = entries.map((entry) => entry.competition)
    const cells = entries.map((entry) => cell(entry.competition, entry.summary, registration.team.id, relaunched.has(entry.competition.id)))
    return {
      id: registration.team.id,
      team: names.get(registration.team.id)!,
      competitions: cells,
      keys: {
        age: ages.indexOf(registration.team.category),
        letter: registration.team.letter ?? '',
        competitionNames: cells.map((c) => c.name),
        healths: own.map((c) => c.ingestionHealth),
        lastSynced: own.map((c) => c.lastSyncedAt ?? null),
        positions: entries.map((entry) => entry.summary.position ?? null),
      },
    }
  })
}

// Las categorías de menor a mayor edad: el orden del catálogo.
const ages = optionsOf('TeamCategory').map((option) => option.value)

// Lo que se ordena sigue siendo lo que dice el servidor (`keys.healths`): la fila no salta de sitio al pulsar ↻.
function cell(competition: Competition, summary: Summary, teamId: string, relaunched: boolean): CompetitionCell {
  return {
    id: competition.id,
    name: competitionLabel(competition),
    ...shownHealth(competition, relaunched),
    lastSynced: competition.lastSyncedAt ? formatInstant(competition.lastSyncedAt) : 'Nunca',
    summary: summaryCell(summary, teamId),
  }
}
