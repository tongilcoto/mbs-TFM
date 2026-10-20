// Las filas de la tabla: un equipo por fila, con todas sus competiciones (plan R1, §3.2 y decisión 1).
import type { components } from '../../api/schema'
import { formatInstant } from '../../theme/format'
import type { CompetitionCell, TeamRow } from '../../components/teamRow'
import { healthNames, teamName } from '../../theme/names'

type Registration = components['schemas']['TeamRegistrationResponse']
type Competition = components['schemas']['CompetitionResponse']

// Junta cada inscripción con sus competiciones. El orden de las filas es el del servidor: por categoría, de
// menor a mayor edad, y por letra.
export function teamRows(registrations: Registration[], competitions: Competition[]): TeamRow[] {
  const byId = new Map(competitions.map((c) => [c.id, c]))
  return registrations.map((registration) => ({
    id: registration.team.id,
    team: teamName(registration.team.category, registration.team.letter),
    competitions: registration.competitions.flatMap(({ competitionId }) => {
      const competition = byId.get(competitionId)
      return competition ? [cell(competition)] : []
    }),
  }))
}

function cell(competition: Competition): CompetitionCell {
  const health = competition.ingestionHealth
  return {
    name: competition.displayName,
    health,
    healthName: health && healthNames[health],
    previousFailed: health === 'pending' && competition.previousIngestionHealth === 'failing',
    lastSynced: competition.lastSyncedAt ? formatInstant(competition.lastSyncedAt) : 'Nunca',
  }
}
