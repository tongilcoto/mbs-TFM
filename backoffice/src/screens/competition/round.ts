// Lo que decide la pantalla de jornada y clasificación sin pintar nada (plan R4, §3.4).
import type { components } from '../../api/schema'
import { formatDayRange, formatGoalDifference, formatKickoff, formatMatchDay } from '../../theme/format'
import { namesOf } from '../../theme/names'
import { type ResultCell, restDayName, resultOf } from '../team/matches'

type Competition = components['schemas']['CompetitionResponse']
type Round = components['schemas']['RoundResponse']
type Match = components['schemas']['MatchResponse']
type Standing = components['schemas']['StandingResponse']
type MatchOutcome = components['schemas']['MatchOutcome']

const categoryNames = namesOf('TeamCategory')
const genderNames = namesOf('Gender')
const modalityNames = namesOf('Modality')
const outcomeNames = namesOf('MatchOutcome')

// Debajo del título: «Cadete · Masculino · Fútbol 11 · 2026/27».
export function competitionDetails(competition: Competition, seasonLabel: string): string {
  return [categoryNames[competition.ageCategory], genderNames[competition.gender], modalityNames[competition.modality], seasonLabel].join(
    ' · ',
  )
}

// Cada jornada en el selector: «Jornada 5 · 24 – 25 oct». Ordenadas por número.
export function roundOptions(rounds: Round[]): { value: number; label: string }[] {
  return [...rounds]
    .sort((a, b) => a.number - b.number)
    .map((round) => ({ value: round.number, label: `Jornada ${round.number} · ${formatDayRange(round.startDate, round.endDate)}` }))
}

// La jornada de la dirección (`?jornada=5`). `unknown`, si no existe o no es un número. Sin jornada en la dirección,
// la pantalla busca la de la última clasificación, desde la en curso hacia atrás (`roundsToLookIn`, §3.4).
export function askedRound(rounds: Round[], asked: string): Round | 'unknown' {
  return rounds.find((round) => String(round.number) === asked) ?? 'unknown'
}

// ── Los partidos de la jornada ──

export interface RoundMatchRow {
  id: string
  date: string
  // La hora, o nada si no está fijada (la columna dice «por fijar»).
  time?: string
  home: { name: string; own: boolean }
  away: { name: string; own: boolean }
  // El marcador o el estado; la hora va en su columna, así que un partido por jugar no lleva nada aquí.
  result?: ResultCell
  // El del club, resaltado.
  own: boolean
  // La jornada de descanso de un grupo impar (D-105), apagada como en Resultados.
  rest: boolean
}

export function roundMatchRows(matches: Match[]): RoundMatchRow[] {
  return [...matches]
    .sort((a, b) => a.matchDate.localeCompare(b.matchDate) || (a.kickoffTime ?? '99').localeCompare(b.kickoffTime ?? '99'))
    .map((match) => {
      const result = resultOf(match)
      return {
        id: match.id,
        date: formatMatchDay(match.matchDate),
        time: match.kickoffTime ? formatKickoff(match.kickoffTime) : undefined,
        home: { name: match.home.nameWithLetter, own: match.home.isOwn },
        away: { name: match.away.nameWithLetter, own: match.away.isOwn },
        result: result.kind === 'time' || result.kind === 'unset' ? undefined : result,
        own: match.home.isOwn || match.away.isOwn,
        rest: [match.home, match.away].some((side) => side.nameWithLetter.includes(restDayName)),
      }
    })
}

// ── La clasificación ──

export interface FormBox {
  round: number
  outcome: MatchOutcome
  // Para el lector y al pasar el ratón: «Victoria en la jornada 5». El color es lo único que lo dice a la vista.
  label: string
}

export interface StandingLine {
  position: number
  name: string
  own: boolean
  played: number
  won: number
  drawn: number
  lost: number
  goalsFor: number
  goalsAgainst: number
  goalDifference: string
  points: number
  // El puesto anterior y cuánto subió (positivo) o bajó (negativo); sin él, «–».
  previous?: { position: number; change: number }
  form: FormBox[]
}

// En orden de puesto, aunque lleguen de otra manera. La racha, la más reciente a la izquierda: el servidor ya la
// manda así.
export function standingLines(table: Standing[]): StandingLine[] {
  return [...table]
    .sort((a, b) => a.position - b.position)
    .map((row) => ({
      position: row.position,
      name: row.team.nameWithLetter,
      own: row.team.isOwn,
      played: row.played,
      won: row.won,
      drawn: row.drawn,
      lost: row.lost,
      goalsFor: row.goalsFor,
      goalsAgainst: row.goalsAgainst,
      goalDifference: formatGoalDifference(row.goalsFor - row.goalsAgainst),
      points: row.points,
      previous: row.previousPosition == null ? undefined : { position: row.previousPosition, change: row.previousPosition - row.position },
      form: row.form.map((entry) => ({
        round: entry.roundNumber,
        outcome: entry.outcome,
        label: `${outcomeNames[entry.outcome]} en la jornada ${entry.roundNumber}`,
      })),
    }))
}
