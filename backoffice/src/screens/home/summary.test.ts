import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import { summaryCell } from './summary'

type Summary = components['schemas']['TeamCompetitionSummary']
type Match = components['schemas']['MatchResponse']
type MatchTeam = components['schemas']['MatchTeam']

const OWN = 'cadete-a'

function side(teamId: string, name: string, fields: Partial<MatchTeam> = {}): MatchTeam {
  return { teamId, nameWithLetter: name, isOwn: teamId === OWN, score: null, standing: null, ...fields } as MatchTeam
}

function match(round: number, home: MatchTeam, away: MatchTeam, fields: Partial<Match> = {}): Match {
  return {
    id: `p${round}`,
    competitionId: 'liga',
    roundId: `j${round}`,
    roundNumber: round,
    matchDate: '2026-05-16',
    kickoffTime: null,
    isKickoffConfirmed: false,
    status: 'programado',
    home,
    away,
    ...fields,
  } as Match
}

const empty: Summary = { position: null, form: [], lastMatch: null, nextMatch: null, nextOpponentPosition: null }

// El puesto con el que llegó el rival: el anterior de su fila de esa jornada (D-112).
const arrived = (previousPosition: number | null) => ({ previousPosition }) as MatchTeam['standing']

describe('el resumen de un equipo en la portada (plan R5, §3)', () => {
  test('sin nada todavía, nada', () => {
    expect(summaryCell(empty, OWN)).toEqual({ position: undefined, streak: [], last: undefined, next: undefined })
  })

  test('la posición y la racha, con el descanso como una jornada más', () => {
    const cell = summaryCell(
      { ...empty, position: 3, form: [{ roundNumber: 5, outcome: 'victoria' }, { roundNumber: 4, outcome: 'descanso' }] },
      OWN,
    )

    expect(cell.position).toBe(3)
    expect(cell.streak).toEqual([
      { round: 5, outcome: 'victoria', label: 'Victoria en la jornada 5' },
      { round: 4, outcome: 'descanso', label: 'Descansó en la jornada 4' },
    ])
  })

  test('el último, en casa: la letra, el marcador con el local primero y el rival con el puesto con el que llegó', () => {
    const last = match(5, side(OWN, 'Celtic Castilla A', { score: 5 }), side('adf', 'FUNDACION ADF B', { score: 0, standing: arrived(16) }), {
      status: 'finalizado',
    })

    expect(summaryCell({ ...empty, lastMatch: last }, OWN).last).toEqual({
      outcome: 'V',
      atHome: true,
      score: '5 - 0',
      opponent: 'FUNDACION ADF B',
      opponentPosition: 16,
    })
  })

  // Con el Cadete A del desarrollador: «4 - 2» fuera es una derrota (decisión 5).
  test('el último, fuera: el marcador sigue con el local primero, y la letra dice quién ganó', () => {
    const last = match(6, side('cobena', 'ESCUELA MUNICIPAL DE COBEÑA A', { score: 4, standing: arrived(9) }), side(OWN, 'Celtic Castilla A', { score: 2 }), {
      status: 'finalizado',
    })

    expect(summaryCell({ ...empty, lastMatch: last }, OWN).last).toMatchObject({ outcome: 'D', atHome: false, score: '4 - 2', opponentPosition: 9 })
  })

  test('el último en la primera jornada: el rival no llegó con puesto', () => {
    const last = match(1, side(OWN, 'Celtic Castilla A', { score: 1 }), side('adf', 'FUNDACION ADF B', { score: 1, standing: arrived(null) }), {
      status: 'finalizado',
    })

    expect(summaryCell({ ...empty, lastMatch: last }, OWN).last).toMatchObject({ outcome: 'E', opponentPosition: undefined })
  })

  test('el próximo: la jornada, el día, la hora, casa o fuera y el rival con su puesto de hoy', () => {
    const next = match(7, side('sanse', 'JUVENTUD SANSE B'), side(OWN, 'Celtic Castilla A'), {
      matchDate: '2026-11-14',
      kickoffTime: '16:45:00',
      isKickoffConfirmed: true,
    })

    expect(summaryCell({ ...empty, nextMatch: next, nextOpponentPosition: 5 }, OWN).next).toEqual({
      kind: 'match',
      round: 7,
      date: 'Sáb 14 nov',
      time: '16:45',
      atHome: false,
      opponent: 'JUVENTUD SANSE B',
      opponentPosition: 5,
    })
  })

  test('el próximo sin hora, ni puesto del rival: los dos, vacíos (la tabla dice «hora por fijar»)', () => {
    const next = match(1, side(OWN, 'Celtic Castilla A'), side('racing', 'RACING CENTRO A'), { matchDate: '2026-09-20' })

    expect(summaryCell({ ...empty, nextMatch: next }, OWN).next).toMatchObject({ kind: 'match', atHome: true, time: undefined, opponentPosition: undefined })
  })

  // D-105: el descanso es un partido contra el equipo ficticio de la federación.
  test('si el próximo es el descanso, solo su jornada', () => {
    const next = match(8, side(OWN, 'Celtic Castilla A'), side('ficticio', 'Equipo Fuera (No asignado)'))

    expect(summaryCell({ ...empty, nextMatch: next }, OWN).next).toEqual({ kind: 'rest', round: 8 })
  })
})
