// Las filas de la tabla: un equipo por fila, con todas sus competiciones (plan R1, §3.2 y decisión 1).
import type { components } from '../../api/schema'
import { formatInstant } from '../../theme/format'
import type { CompetitionCell, TeamRow } from '../../components/teamRow'
import { healthNames, teamNames } from '../../theme/names'

type Registration = components['schemas']['TeamRegistrationResponse']
type Competition = components['schemas']['CompetitionResponse']

// Junta cada inscripción con sus competiciones. El orden de las filas es el del servidor: por categoría, de
// menor a mayor edad, y por letra.
export function teamRows(registrations: Registration[], competitions: Competition[]): TeamRow[] {
  const byId = new Map(competitions.map((c) => [c.id, c]))
  // Si dos equipos se llamarían igual («Alevín A» masculino y femenino), cada uno con lo que lo distingue.
  const names = teamNames(registrations.map((registration) => registration.team))
  return registrations.map((registration) => ({
    id: registration.team.id,
    team: names.get(registration.team.id)!,
    competitions: registration.competitions.flatMap(({ competitionId }) => {
      const competition = byId.get(competitionId)
      return competition ? [cell(competition)] : []
    }),
  }))
}

function cell(competition: Competition): CompetitionCell {
  const health = competition.ingestionHealth
  return {
    // La división y el grupo: «PRIMERA CADETE · Grupo 4». Sin la categoría que el servidor pone delante en
    // `displayName`, porque en la misma fila ya la dice el equipo (bloque T del plan R2). La que repite la
    // federación dentro de su propio nombre no se recorta: cada federación escribe a su manera.
    name: `${competition.divisionLabel} · ${competition.groupLabel}`,
    health,
    healthName: health && healthNames[health],
    previousFailed: health === 'pending' && competition.previousIngestionHealth === 'failing',
    lastSynced: competition.lastSyncedAt ? formatInstant(competition.lastSyncedAt) : 'Nunca',
  }
}
