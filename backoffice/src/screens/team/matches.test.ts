import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import { matchRows } from './matches'

type Match = components['schemas']['MatchResponse']
type MatchStanding = components['schemas']['MatchStanding']
type Standing = components['schemas']['StandingResponse']

const OWN = 'propio'

function standing(position: number, fields: Partial<MatchStanding> = {}): MatchStanding {
  return { position, played: 5, won: 1, drawn: 0, lost: 4, goalsFor: 7, goalsAgainst: 13, points: 3, ...fields }
}

// Un partido del equipo en casa (`home`) o fuera, contra «RIVAL A».
function match(round: number, fields: Partial<Match> & { ownHome?: boolean; ownScore?: number; otherScore?: number } = {}): Match {
  const { ownHome = true, ownScore, otherScore, ...rest } = fields
  const own = { teamId: OWN, displayName: 'x', shortDisplayName: 'Celtic A', nameWithLetter: 'Celtic Castilla A', isOwn: true, score: ownScore }
  const other = { teamId: 'rival', displayName: 'y', shortDisplayName: 'RIVAL A', nameWithLetter: 'RIVAL A', isOwn: false, score: otherScore }
  return {
    id: `p${round}`,
    competitionId: 'liga',
    roundId: `j${round}`,
    roundNumber: round,
    matchDate: '2026-03-01',
    isKickoffConfirmed: false,
    status: 'programado',
    home: ownHome ? own : other,
    away: ownHome ? other : own,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...rest,
  }
}

function played(round: number, ownScore: number, otherScore: number, ownHome = true): Match {
  const m = match(round, { status: 'finalizado', ownScore, otherScore, ownHome })
  const [own, other] = ownHome ? [m.home, m.away] : [m.away, m.home]
  return {
    ...m,
    home: { ...(ownHome ? own : other), standing: ownHome ? standing(2, { points: 10, goalsFor: 9, goalsAgainst: 4 }) : standing(7) },
    away: { ...(ownHome ? other : own), standing: ownHome ? standing(7) : standing(2, { points: 10, goalsFor: 9, goalsAgainst: 4 }) },
  }
}

// La clasificación de hoy, la que pidió la cabecera: el propio 4º y el rival 9º.
const today = [
  { team: { teamId: OWN }, position: 4 },
  { team: { teamId: 'rival' }, position: 9 },
] as Standing[]

describe('las filas de la pestaña Resultados', () => {
  test('en orden de jornada, aunque lleguen por fecha', () => {
    const rows = matchRows(
      [match(3, { matchDate: '2026-03-01' }), match(1, { matchDate: '2026-03-08', status: 'aplazado' }), match(2)],
      OWN,
      today,
    )

    expect(rows.map((r) => r.round)).toEqual([1, 2, 3])
  })

  test('un jugado: la jornada, el día, el nombre del club y su letra, el marcador, la letra y la línea del propio', () => {
    const [row] = matchRows([played(4, 3, 1)], OWN, today)

    expect(row).toEqual({
      id: 'p4',
      competitionId: 'liga',
      round: 4,
      date: 'Dom 1 mar',
      home: { name: 'Celtic Castilla A', position: 2, own: true },
      away: { name: 'RIVAL A', position: 7, own: false },
      result: { kind: 'score', text: '3 - 1' },
      outcome: 'V',
      line: { position: 2, points: 10, won: 1, drawn: 0, lost: 4, goalDifference: '+5' },
      rest: false,
    })
  })

  test('la letra, vista desde el propio: también cuando juega fuera', () => {
    const outcomes = matchRows([played(1, 1, 1), played(2, 0, 2), played(3, 2, 0, false)], OWN, today).map((r) => r.outcome)

    expect(outcomes).toEqual(['E', 'D', 'V'])
  })

  test('el marcador es local primero, juegue donde juegue el propio', () => {
    expect(matchRows([played(1, 2, 0, false)], OWN, today)[0]!.result).toEqual({ kind: 'score', text: '0 - 2' })
  })

  test('por jugar con hora: la hora, sin letra ni línea, y el puesto de hoy de cada uno', () => {
    const [row] = matchRows([match(6, { kickoffTime: '12:00:00', isKickoffConfirmed: true })], OWN, today)

    expect(row!.result).toEqual({ kind: 'time', text: '12:00' })
    expect(row!.outcome).toBeUndefined()
    expect(row!.line).toBeUndefined()
    expect([row!.home.position, row!.away.position]).toEqual([4, 9])
  })

  test('por jugar sin hora: «por fijar»', () => {
    expect(matchRows([match(7)], OWN, today)[0]!.result).toEqual({ kind: 'unset' })
  })

  test('sin clasificación de hoy, sin puesto', () => {
    const [row] = matchRows([match(1)], OWN, [])

    expect([row!.home.position, row!.away.position]).toEqual([undefined, undefined])
  })

  test('aplazado: «Aplazado», en su jornada', () => {
    expect(matchRows([match(5, { status: 'aplazado', matchDate: '2026-05-30' })], OWN, today)[0]).toMatchObject({
      round: 5,
      result: { kind: 'postponed' },
    })
  })

  test('suspendido: el marcador al suspender, y «Suspendido»; sin letra ni línea', () => {
    const [row] = matchRows([match(5, { status: 'suspendido', ownScore: 1, otherScore: 0 })], OWN, today)

    expect(row!.result).toEqual({ kind: 'suspended', text: '1 - 0' })
    expect(row!.outcome).toBeUndefined()
    expect(row!.line).toBeUndefined()
  })

  test('suspendido antes de empezar: solo «Suspendido»', () => {
    expect(matchRows([match(5, { status: 'suspendido' })], OWN, today)[0]!.result).toEqual({ kind: 'suspended', text: undefined })
  })

  test('un jugado sin la tabla de su jornada: sin puestos ni línea, con el marcador y la letra', () => {
    const [row] = matchRows([match(4, { status: 'finalizado', ownScore: 2, otherScore: 2 })], OWN, today)

    expect(row).toMatchObject({ result: { kind: 'score', text: '2 - 2' }, outcome: 'E', line: undefined })
    expect([row!.home.position, row!.away.position]).toEqual([undefined, undefined])
  })

  test('la diferencia de goles negativa, con el menos de verdad', () => {
    const m = played(1, 0, 3)
    const own = { ...m.home, standing: standing(13, { goalsFor: 7, goalsAgainst: 13 }) }

    expect(matchRows([{ ...m, home: own }], OWN, today)[0]!.line?.goalDifference).toBe('−6')
  })

  test('la jornada de descanso: el rival ficticio de la RFFM, juegue en casa o fuera (D-105)', () => {
    const rest = (name: string, ownHome: boolean) => {
      const m = match(8, { ownHome })
      return ownHome ? { ...m, away: { ...m.away, nameWithLetter: name } } : { ...m, home: { ...m.home, nameWithLetter: name } }
    }
    const rows = matchRows([rest('Equipo Fuera (No asignado)', true), rest('Equipo Casa (No asignado)', false), match(9)], OWN, today)

    expect(rows.map((r) => r.rest)).toEqual([true, true, false])
  })
})
