// Lo que la web tiene que enseñar de una competición inventada (plan R4), calculado aquí y no leído de la web: el
// nombre de cada equipo, las fechas, las jornadas jugadas y la clasificación de cada una.
import { standingsAfter, type Competition, type FederationTeam, type Fixture, type Round, type Team } from './invented.ts'

/** El nombre con el que se crea el club de cada escenario (clubs.ts). */
export const CLUB_NAME = 'Club de pruebas'

/** El equipo del club en un partido: el nombre del club, no el corto, y su letra (`D-111`). */
export function ownName(team: Team): string {
  return team.letter ? `${CLUB_NAME} ${team.letter}` : CLUB_NAME
}

/** Un rival, con el nombre de su club y su letra: `C.D. LAS ROZAS 'A'` → «C.D. LAS ROZAS A». */
export function rivalName(rival: FederationTeam): string {
  return rival.rawName.replace(/ '([A-Z])'$/, ' $1')
}

/** El nombre de un equipo del grupo, como sale en la web. El primero es el del club. */
export function nameIn(plays: Competition, team: Team, of: FederationTeam): string {
  return of.code === plays.teams[0]!.code ? ownName(team) : rivalName(of)
}

const weekdays = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']
const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic']

/** El día de un partido, como lo escribe la web: «Sáb 24 oct». Las fechas inventadas van a medianoche UTC. */
export function matchDay(date: Date): string {
  return `${weekdays[date.getUTCDay()]} ${date.getUTCDate()} ${months[date.getUTCMonth()]}`
}

/** Una jornada en el selector: «Jornada 5 · 24 oct». Las inventadas son de un solo día. */
export function roundLabel(round: Round): string {
  return `Jornada ${round.number} · ${round.date.getUTCDate()} ${months[round.date.getUTCMonth()]}`
}

/** Una diferencia de goles con su signo, como la web: «+3», «−2», «0». */
export function goalDifference(difference: number): string {
  return difference > 0 ? `+${difference}` : difference < 0 ? `−${-difference}` : '0'
}

export function rounds(plays: Competition): Round[] {
  if (!plays.schedule) throw new Error('La competición no tiene calendario propio (no es `playedCompetition`)')
  return plays.schedule
}

/** Las jornadas jugadas: las que tienen todos sus marcadores. */
export function playedRounds(plays: Competition): Round[] {
  return rounds(plays).filter((round) => round.matches.every((m) => m.score))
}

/** La jornada en curso: la siguiente a la última jugada (`playedCompetition`). */
export function currentRound(plays: Competition): Round {
  return rounds(plays)[playedRounds(plays).length]!
}

export function roundNumbered(plays: Competition, number: number): Round {
  const round = rounds(plays).find((r) => r.number === number)
  if (!round) throw new Error(`La competición no tiene jornada ${number}`)
  return round
}

/** El partido del club en una jornada: juega todas. */
export function ownFixture(plays: Competition, round: Round): Fixture {
  const own = plays.teams[0]!.code
  return round.matches.find((m) => m.home.code === own || m.away.code === own)!
}

/** El puesto de cada equipo tras una jornada; vacío si no tiene tabla. */
export function positionsAfter(plays: Competition, number: number): Map<string, number> {
  return new Map(standingsAfter(plays, number).map((row) => [row.team.code, row.position]))
}

/** La racha de un equipo tras una jornada: sus partidos jugados, del más reciente al más antiguo, hasta cinco. */
export function formOf(plays: Competition, code: string, upTo: number): { round: number; outcome: 'Victoria' | 'Empate' | 'Derrota' }[] {
  return rounds(plays)
    .filter((round) => round.number <= upTo)
    .flatMap((round) =>
      round.matches
        .filter((m) => m.score && (m.home.code === code || m.away.code === code))
        .map((m) => {
          const [mine, theirs] = m.home.code === code ? [m.score!.home, m.score!.away] : [m.score!.away, m.score!.home]
          return { round: round.number, outcome: mine > theirs ? ('Victoria' as const) : mine < theirs ? ('Derrota' as const) : ('Empate' as const) }
        }),
    )
    .reverse()
    .slice(0, 5)
}
