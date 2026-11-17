import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import type { Season } from '../home/seasons'
import { canSyncRoster, lastSyncText, summaryLines } from './rosterSync'

type RosterSync = components['schemas']['RosterSyncResponse']

function season(label: string, fields: Partial<Season> = {}): Season {
  const start = Number(label.slice(0, 4))
  return {
    id: `id-${start}`,
    label,
    federationSeasonId: '22',
    startDate: `${start}-07-01`,
    endDate: `${start + 1}-06-30`,
    isCurrent: false,
    createdAt: 'x',
    updatedAt: 'x',
    ...fields,
  }
}

const today = '2026-11-17'
const current = season('2026/27', { isCurrent: true })

describe('cuándo se ofrece «Sincronizar con la Federación»', () => {
  test('en la temporada en curso, con una federación que publica plantillas y el equipo enganchado', () => {
    expect(canSyncRoster({ season: current, today, providesRoster: true, linked: true })).toBe(true)
  })

  test('no, si la federación no publica plantillas', () => {
    expect(canSyncRoster({ season: current, today, providesRoster: false, linked: true })).toBe(false)
  })

  test('no, si el equipo no está enganchado esa temporada', () => {
    expect(canSyncRoster({ season: current, today, providesRoster: true, linked: false })).toBe(false)
  })

  test('no, en una temporada pasada ni en una futura (decisión 1 de R6.14)', () => {
    expect(canSyncRoster({ season: season('2025/26'), today, providesRoster: true, linked: true })).toBe(false)
    expect(canSyncRoster({ season: season('2027/28'), today, providesRoster: true, linked: true })).toBe(false)
  })

  test('no, en una archivada', () => {
    const archived = { ...current, archivedAt: '2026-11-01T00:00:00Z' }
    expect(canSyncRoster({ season: archived, today, providesRoster: true, linked: true })).toBe(false)
  })
})

describe('la fecha junto al botón', () => {
  test('cuándo se sincronizó por última vez, con fecha y hora', () => {
    expect(lastSyncText('2026-11-17T17:30:00Z')).toMatch(/^Última sincronización: 17\/11\/2026 \d\d:30$/)
  })

  test('sin sincronizar nunca, lo dice', () => {
    expect(lastSyncText(null)).toBe('Todavía no se ha sincronizado con la Federación')
    expect(lastSyncText(undefined)).toBe('Todavía no se ha sincronizado con la Federación')
  })
})

function summary(fields: Partial<RosterSync> = {}): RosterSync {
  return {
    syncedAt: '2026-11-17T17:30:00Z',
    added: 0,
    alreadyInRoster: 0,
    withoutBirthYear: 0,
    deletedInClub: 0,
    duplicateName: [],
    inOtherTeam: [],
    invalidName: [],
    ...fields,
  }
}

const team = { teamId: 't', displayName: 'Celtic Castilla Cadete B', shortDisplayName: 'Celtic B' } as never

describe('el resumen de la sincronización', () => {
  test('la primera línea dice siempre los añadidos y los que ya estaban, aunque sean cero', () => {
    expect(summaryLines(summary())).toEqual(['0 añadidos y 0 que ya estaban.'])
  })

  test('uno o varios, con su número', () => {
    expect(summaryLines(summary({ added: 1, alreadyInRoster: 1 }))[0]).toBe('1 añadido y 1 que ya estaba.')
    expect(summaryLines(summary({ added: 3, alreadyInRoster: 21 }))[0]).toBe('3 añadidos y 21 que ya estaban.')
  })

  test('los sin año y los dados de baja, solo si hay', () => {
    expect(summaryLines(summary({ added: 2, withoutBirthYear: 2, deletedInClub: 1 })).slice(1)).toEqual([
      '2 añadidos sin año de nacimiento: se pone desde su ficha.',
      '1 dado de baja en el club: no se vuelve a añadir.',
    ])
    expect(summaryLines(summary({ deletedInClub: 2 }))[1]).toBe('2 dados de baja en el club: no se vuelven a añadir.')
  })

  test('nombra a los de nombre repetido, como en la tabla', () => {
    const lines = summaryLines(summary({ added: 1, duplicateName: [{ playerId: 'p', fullName: 'JUAN GARCÍA DE LA FUENTE' }] }))
    expect(lines[1]).toBe('Con nombre repetido en el club, dado de alta como jugador nuevo; para revisarlo: Juan García de la Fuente.')
  })

  test('nombra a los de otro equipo, con su equipo', () => {
    const lines = summaryLines(
      summary({
        inOtherTeam: [
          { profileId: 'a', fullName: 'HUGO PEÑA RUIZ', team },
          { profileId: 'b', fullName: 'NOÉ SIGÜENZA', team },
        ],
      }),
    )
    expect(lines[1]).toBe(
      'En otro equipo del club esta temporada, no añadidos: Hugo Peña Ruiz (Celtic Castilla Cadete B), Noé Sigüenza (Celtic Castilla Cadete B).',
    )
  })

  test('nombra a los de un nombre que no vale, tal cual los escribe la federación', () => {
    const lines = summaryLines(summary({ invalidName: ['TORRES, IÑAKI/'] }))
    expect(lines[1]).toBe('Con un nombre que no vale, no añadido; para darlo de alta a mano: «TORRES, IÑAKI/».')
  })
})
