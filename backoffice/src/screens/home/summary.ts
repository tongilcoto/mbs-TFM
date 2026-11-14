// El resumen de un equipo en una competición, ya en español, para las cuatro columnas de la portada (plan R5, §3;
// decisiones 3 a 5). Lo manda el servidor en la lista de equipos de la temporada (D-113).
import type { components } from '../../api/schema'
import type { LastMatchCell, NextMatchCell, SummaryCell } from '../../components/teamRow'
import { formatKickoff, formatMatchDay } from '../../theme/format'
import { streakBoxes } from '../competition/round'
import { restDayName } from '../team/matches'

type Summary = components['schemas']['TeamCompetitionSummary']
type Match = components['schemas']['MatchResponse']

// `teamId`, el equipo de la fila: dice de qué lado del partido está.
export function summaryCell(summary: Summary, teamId: string): SummaryCell {
  return {
    position: summary.position ?? undefined,
    streak: streakBoxes(summary.form),
    last: summary.lastMatch ? lastCell(summary.lastMatch, teamId) : undefined,
    next: summary.nextMatch ? nextCell(summary.nextMatch, teamId, summary.nextOpponentPosition) : undefined,
  }
}

function sides(match: Match, teamId: string) {
  const atHome = match.home.teamId === teamId
  return { atHome, own: atHome ? match.home : match.away, other: atHome ? match.away : match.home }
}

// El servidor no manda como último un partido sin marcador (es el jugado); si faltara, no se inventa la letra.
function lastCell(match: Match, teamId: string): LastMatchCell | undefined {
  const { atHome, own, other } = sides(match, teamId)
  if (own.score == null || other.score == null) return undefined
  return {
    outcome: own.score > other.score ? 'V' : own.score < other.score ? 'D' : 'E',
    atHome,
    score: `${match.home.score} - ${match.away.score}`,
    opponent: other.nameWithLetter,
    opponentPosition: other.standing?.previousPosition ?? undefined,
  }
}

// El descanso (D-105) es el partido contra el equipo ficticio, que la web reconoce por el nombre, como en Resultados.
function nextCell(match: Match, teamId: string, opponentPosition?: number | null): NextMatchCell {
  const { atHome, other } = sides(match, teamId)
  if (other.nameWithLetter.includes(restDayName)) return { kind: 'rest', round: match.roundNumber }
  return {
    kind: 'match',
    round: match.roundNumber,
    date: formatMatchDay(match.matchDate),
    time: match.kickoffTime ? formatKickoff(match.kickoffTime) : undefined,
    atHome,
    opponent: other.nameWithLetter,
    opponentPosition: opponentPosition ?? undefined,
  }
}
