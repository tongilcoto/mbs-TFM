// Las filas de la pestaña Resultados: un partido por fila, ya en español (plan R4, §3.3 y decisiones 1, 2 y 6).
import type { components } from '../../api/schema'
import { formatGoalDifference, formatKickoff, formatMatchDay } from '../../theme/format'

type Match = components['schemas']['MatchResponse']
type MatchTeam = components['schemas']['MatchTeam']
type Standing = components['schemas']['StandingResponse']

// Un equipo del partido: el nombre de su club y su letra (decisión 1), su puesto al lado y si es el de la ficha. El
// puesto es **con el que llega al partido**, el de la clasificación de la jornada anterior (enmienda a D-112, pedida
// al revisar R4.12): ninguno en la primera. En los que faltan, solo en la jornada siguiente a la última con tabla;
// más allá, nadie sabe todavía con qué puesto se llegará.
export interface SideCell {
  name: string
  position?: number
  own: boolean
}

// Lo que va en «Resultado», según el estado del partido (decisión 6).
export type ResultCell =
  | { kind: 'score'; text: string }
  | { kind: 'time'; text: string }
  | { kind: 'unset' }
  | { kind: 'postponed' }
  | { kind: 'suspended'; text?: string }

export type Outcome = 'V' | 'E' | 'D'

// La línea del equipo tras la jornada: solo en los jugados.
export interface OwnLine {
  position: number
  points: number
  won: number
  drawn: number
  lost: number
  goalDifference: string
}

export interface MatchRow {
  id: string
  competitionId: string
  round: number
  date: string
  home: SideCell
  away: SideCell
  result: ResultCell
  outcome?: Outcome
  line?: OwnLine
  // La jornada de descanso de un grupo impar: se pinta apagada, con los mismos textos.
  rest: boolean
}

// La jornada de descanso (D-105): la RFFM empareja al que descansa con un equipo ficticio, «Equipo Casa (No
// asignado)» o «Equipo Fuera (No asignado)». El adaptador lo sabe, pero el servidor no lo manda; la web lo reconoce
// por el nombre, decidido así por el desarrollador a sabiendas de que es una costumbre de la RFFM (R4.12).
export const restDayName = '(No asignado)'

// La última clasificación que hay, la que ya pidió la cabecera, y su jornada: da el puesto de los partidos de la
// jornada siguiente, que aún no se han jugado, sin pedir nada más (§3.3).
export interface LatestTable {
  round: number
  table: Standing[]
}

// En orden de jornada, no de fecha: el servidor los da por fecha, y un aplazado se iría a su fecha nueva; se queda
// en la fila de su jornada (decisión 6).
export function matchRows(matches: Match[], teamId: string, latest?: LatestTable): MatchRow[] {
  const latestPositions = new Map((latest?.table ?? []).map((row) => [row.team.teamId, row.position]))
  return [...matches]
    .sort((a, b) => a.roundNumber - b.roundNumber || a.matchDate.localeCompare(b.matchDate))
    .map((match) => {
      const played = match.status === 'finalizado'
      const side = (team: MatchTeam): SideCell => ({
        name: team.nameWithLetter,
        position: played
          ? (team.standing?.previousPosition ?? undefined)
          : match.roundNumber === (latest?.round ?? 0) + 1
            ? latestPositions.get(team.teamId)
            : undefined,
        own: team.teamId === teamId,
      })
      const own = match.home.teamId === teamId ? match.home : match.away
      const other = own === match.home ? match.away : match.home
      return {
        id: match.id,
        competitionId: match.competitionId,
        round: match.roundNumber,
        date: formatMatchDay(match.matchDate),
        home: side(match.home),
        away: side(match.away),
        result: resultOf(match),
        outcome: played ? outcomeOf(own.score, other.score) : undefined,
        line: played ? lineOf(own) : undefined,
        rest: other.nameWithLetter.includes(restDayName),
      }
    })
}

// Lo que va en «Resultado» según el estado; también en los partidos de una jornada (§3.4).
export function resultOf(match: Match): ResultCell {
  const score = scoreOf(match)
  if (match.status === 'finalizado' && score) return { kind: 'score', text: score }
  if (match.status === 'aplazado') return { kind: 'postponed' }
  if (match.status === 'suspendido') return { kind: 'suspended', text: score }
  return match.kickoffTime ? { kind: 'time', text: formatKickoff(match.kickoffTime) } : { kind: 'unset' }
}

// «3 - 1», local primero. Sin los dos goles, nada.
function scoreOf(match: Match): string | undefined {
  const home = match.home.score
  const away = match.away.score
  return home == null || away == null ? undefined : `${home} - ${away}`
}

function outcomeOf(own?: number | null, other?: number | null): Outcome | undefined {
  if (own == null || other == null) return undefined
  return own > other ? 'V' : own < other ? 'D' : 'E'
}

function lineOf(own: MatchTeam): OwnLine | undefined {
  const standing = own.standing
  if (!standing) return undefined
  return {
    position: standing.position,
    points: standing.points,
    won: standing.won,
    drawn: standing.drawn,
    lost: standing.lost,
    goalDifference: formatGoalDifference(standing.goalsFor - standing.goalsAgainst),
  }
}
