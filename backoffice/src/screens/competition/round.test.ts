import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import { askedRound, competitionDetails, roundMatchRows, roundOptions, standingLines } from './round'

type Competition = components['schemas']['CompetitionResponse']
type Round = components['schemas']['RoundResponse']
type Match = components['schemas']['MatchResponse']
type Standing = components['schemas']['StandingResponse']

const competition = {
  id: 'liga',
  ageCategory: 'cadete',
  gender: 'masculino',
  modality: 'futbol_11',
  divisionLabel: 'PREFERENTE CADETE',
  groupLabel: 'Grupo 2',
} as Competition

function round(number: number, startDate: string, endDate: string, isCurrent = false): Round {
  return { id: `j${number}`, competitionId: 'liga', number, startDate, endDate, isCurrent } as Round
}

const rounds = [round(3, '2026-10-10', '2026-10-11'), round(1, '2026-09-26', '2026-09-27'), round(2, '2026-10-03', '2026-10-04', true)]

function side(name: string, isOwn = false, score?: number) {
  return { teamId: name, displayName: name, shortDisplayName: name, nameWithLetter: name, isOwn, score }
}

function match(id: string, date: string, time: string | undefined, home: ReturnType<typeof side>, away: ReturnType<typeof side>, status = 'programado'): Match {
  return { id, competitionId: 'liga', roundId: 'j5', roundNumber: 5, matchDate: date, kickoffTime: time, status, home, away } as Match
}

describe('la cabecera de la competición', () => {
  test('la edad, el género, la modalidad y la temporada', () => {
    expect(competitionDetails(competition, '2026/27')).toBe('Cadete · Masculino · Fútbol 11 · 2026/27')
  })
})

describe('el selector de jornada', () => {
  test('por número, con sus fechas', () => {
    expect(roundOptions(rounds)).toEqual([
      { value: 1, label: 'Jornada 1 · 26 – 27 sept' },
      { value: 2, label: 'Jornada 2 · 3 – 4 oct' },
      { value: 3, label: 'Jornada 3 · 10 – 11 oct' },
    ])
  })
})

describe('la jornada de la dirección', () => {
  test('la que se pide', () => {
    expect(askedRound(rounds, '3')).toMatchObject({ number: 3 })
  })

  test('una que no existe, o que no es un número', () => {
    expect(askedRound(rounds, '40')).toBe('unknown')
    expect(askedRound(rounds, 'abc')).toBe('unknown')
  })
})

describe('los partidos de la jornada', () => {
  test('por fecha y hora; la hora en su columna, el marcador en el resultado; el del club, señalado', () => {
    const rows = roundMatchRows([
      match('b', '2026-10-25', '13:30:00', side('C'), side('D')),
      match('a', '2026-10-24', '18:38', side('Celtic Castilla A', true, 2), side('COLEGIO EL PRADO A', false, 3), 'finalizado'),
      match('c', '2026-10-24', '09:30', side('E'), side('F')),
    ])

    expect(rows.map((r) => r.id)).toEqual(['c', 'a', 'b'])
    expect(rows[1]).toMatchObject({
      date: 'Sáb 24 oct',
      time: '18:38',
      home: { name: 'Celtic Castilla A', own: true },
      away: { name: 'COLEGIO EL PRADO A', own: false },
      result: { kind: 'score', text: '2 - 3' },
      own: true,
      rest: false,
    })
    // Por jugar: la hora en su columna, y nada en el resultado.
    expect(rows[2]).toMatchObject({ time: '13:30', result: undefined, own: false })
  })

  test('sin hora, al final de su día y sin hora', () => {
    const rows = roundMatchRows([match('sin', '2026-10-24', undefined, side('A'), side('B')), match('con', '2026-10-24', '20:00', side('C'), side('D'))])

    expect(rows.map((r) => [r.id, r.time])).toEqual([
      ['con', '20:00'],
      ['sin', undefined],
    ])
  })

  test('aplazado y suspendido, como en Resultados', () => {
    const rows = roundMatchRows([
      match('ap', '2026-10-24', undefined, side('A'), side('B'), 'aplazado'),
      match('su', '2026-10-25', '10:00', side('C', false, 1), side('D', false, 0), 'suspendido'),
    ])

    expect(rows.map((r) => r.result)).toEqual([{ kind: 'postponed' }, { kind: 'suspended', text: '1 - 0' }])
  })

  test('el descanso de un grupo impar, marcado (D-105)', () => {
    expect(roundMatchRows([match('d', '2026-10-24', undefined, side('Celtic Castilla A', true), side('Equipo Fuera (No asignado)'))])[0]!.rest).toBe(true)
  })
})

describe('la clasificación', () => {
  function row(position: number, previousPosition: number | null, fields: Partial<Standing> = {}): Standing {
    return {
      position,
      previousPosition,
      team: side(`Equipo ${position}`),
      played: 5,
      won: 3,
      drawn: 1,
      lost: 1,
      goalsFor: 12,
      goalsAgainst: 5,
      points: 10,
      form: [],
      ...fields,
    } as Standing
  }

  test('en orden de puesto, con cada número y la diferencia de goles con su signo', () => {
    const lines = standingLines([row(2, 1, { goalsFor: 4, goalsAgainst: 9 }), row(1, 3)])

    expect(lines.map((l) => l.position)).toEqual([1, 2])
    expect(lines[0]).toMatchObject({ played: 5, won: 3, drawn: 1, lost: 1, goalsFor: 12, goalsAgainst: 5, goalDifference: '+7', points: 10 })
    expect(lines[1]!.goalDifference).toBe('−5')
  })

  test('el puesto anterior y cuánto subió, bajó o siguió igual; sin él, nada', () => {
    const lines = standingLines([row(1, 3), row(2, 1), row(3, 3), row(4, null)])

    expect(lines.map((l) => l.previous)).toEqual([
      { position: 3, change: 2 },
      { position: 1, change: -1 },
      { position: 3, change: 0 },
      undefined,
    ])
  })

  test('el del club, señalado', () => {
    expect(standingLines([row(13, 13, { team: side('Celtic Castilla A', true) })])[0]).toMatchObject({ name: 'Celtic Castilla A', own: true })
  })

  test('la racha, en el orden en que llega (la más reciente primero), con lo que dice al lector', () => {
    const lines = standingLines([
      row(1, 3, {
        form: [
          { roundNumber: 5, outcome: 'victoria' },
          { roundNumber: 4, outcome: 'derrota' },
          { roundNumber: 3, outcome: 'empate' },
        ],
      }),
    ])

    expect(lines[0]!.form).toEqual([
      { round: 5, outcome: 'victoria', label: 'Victoria en la jornada 5' },
      { round: 4, outcome: 'derrota', label: 'Derrota en la jornada 4' },
      { round: 3, outcome: 'empate', label: 'Empate en la jornada 3' },
    ])
  })
})
