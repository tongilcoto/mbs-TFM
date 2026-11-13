// Lo que decide la cabecera de la ficha del equipo sin pintar nada (plan R4, §3.2 y decisión 4).
import type { components } from '../../api/schema'
import { namesOf, teamName } from '../../theme/names'
import { toAddress } from '../home/seasons'

type Team = components['schemas']['TeamResponse']
type Round = components['schemas']['RoundResponse']
type Standing = components['schemas']['StandingResponse']

const genderNames = namesOf('Gender')
const modalityNames = namesOf('Modality')

// El título, «Infantil A», y debajo «Masculino · Fútbol 11», como en la pantalla de sincronizar. Sin el nombre del
// club, que ya está en la cabecera de la web.
export function teamHeading(team: Team): { title: string; subtitle: string } {
  return { title: teamName(team.category, team.letter), subtitle: `${genderNames[team.gender]} · ${modalityNames[team.modality]}` }
}

// El aviso de la temporada en la que el equipo no juega: «Celtic Infantil A no jugó la temporada 2024/25.»
export function notPlayingText(team: Team, seasonLabel: string): string {
  return `${team.clubName} ${teamName(team.category, team.letter)} no jugó la temporada ${seasonLabel}.`
}

// Los caminos de la ficha (LLD-B §6.5): la temporada va en ellos con guion, «2025-26».
export function resultsPath(seasonLabel: string, teamId: string): string {
  return `/temporadas/${toAddress(seasonLabel)}/equipos/${teamId}/resultados`
}

export function competitionPath(seasonLabel: string, competitionId: string): string {
  return `/temporadas/${toAddress(seasonLabel)}/competiciones/${competitionId}`
}

// En qué orden se busca la clasificación de la posición (§3.2): la de la jornada en curso; si esa todavía no tiene
// tabla, la anterior, y así hacia atrás. Sin jornada en curso, la competición ha terminado: desde la última.
export function roundsToLookIn(rounds: Round[]): Round[] {
  const byNumber = [...rounds].sort((a, b) => a.number - b.number)
  const current = byNumber.findIndex((round) => round.isCurrent)
  const from = current === -1 ? byNumber.length - 1 : current
  return byNumber.slice(0, from + 1).reverse()
}

// El puesto del equipo en una clasificación, y de cuántos. Sin él en la tabla, nada.
export function positionIn(table: Standing[], teamId: string): { position: number; of: number } | undefined {
  const row = table.find((standing) => standing.team.teamId === teamId)
  return row && { position: row.position, of: table.length }
}
