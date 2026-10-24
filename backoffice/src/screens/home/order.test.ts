import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import { sortRows } from '../../sorting'
import { columns, rules } from './order'
import { teamRows } from './rows'

type Registration = components['schemas']['TeamRegistrationResponse']
type Competition = components['schemas']['CompetitionResponse']
type Category = components['schemas']['TeamCategory']

// Un equipo inscrito en unas competiciones; y una competición con su ingesta y su última sincronización.
function team(id: string, category: Category, letter: string | null, competitionIds: string[]): Registration {
  return {
    seasonId: 'temporada',
    competitions: competitionIds.map((competitionId) => ({ competitionId, federationTeamId: '1' })),
    team: {
      id,
      category,
      letter,
      gender: 'masculino',
      modality: 'futbol_11',
      isOwn: true,
      clubName: 'Celtic',
      displayName: id,
      createdAt: '2026-10-09T21:50:27Z',
      updatedAt: '2026-10-09T21:50:27Z',
    },
  }
}

function competition(id: string, division: string, fields: Partial<Competition> = {}): Competition {
  return {
    id,
    seasonId: 'temporada',
    modality: 'futbol_11',
    gender: 'masculino',
    ageCategory: 'cadete',
    divisionLabel: division,
    groupLabel: 'Grupo 1',
    federationCompetitionId: '1',
    federationGroupId: '2',
    displayName: id,
    createdAt: '2026-10-09T21:50:27Z',
    updatedAt: '2026-10-09T21:50:27Z',
    ...fields,
  }
}

const ids = (rows: { id: string }[]) => rows.map((row) => row.id)

describe('las columnas de la portada', () => {
  test('son cuatro, con su nombre en la dirección', () => {
    expect(columns).toEqual(['equipo', 'competicion', 'ingesta', 'sincronizacion'])
  })
})

describe('Equipo: por edad, de menor a mayor, y después por letra', () => {
  const rows = teamRows(
    [
      team('juvenil-a', 'juvenil', 'A', []),
      team('alevin-b', 'alevin', 'B', []),
      team('alevin', 'alevin', null, []),
      team('benjamin-a', 'benjamin', 'A', []),
      team('alevin-a', 'alevin', 'A', []),
    ],
    [],
  )

  test('la edad no es el alfabeto: Benjamín va antes que Alevín, al revés que en el diccionario', () => {
    expect(ids(sortRows(rows, rules.equipo, false))).toEqual(['benjamin-a', 'alevin', 'alevin-a', 'alevin-b', 'juvenil-a'])
  })

  test('al revés, de mayor a menor', () => {
    expect(ids(sortRows(rows, rules.equipo, true))).toEqual(['juvenil-a', 'alevin-b', 'alevin-a', 'alevin', 'benjamin-a'])
  })
})

describe('Competición: por orden alfabético, y los equipos sin competición al final', () => {
  const rows = teamRows(
    [
      team('sin', 'alevin', 'A', []),
      team('segunda', 'alevin', 'B', ['segunda']),
      team('dos', 'alevin', 'C', ['tercera', 'autonomica']),
      team('primera', 'alevin', 'D', ['primera']),
    ],
    [competition('segunda', 'SEGUNDA'), competition('tercera', 'TERCERA'), competition('autonomica', 'AUTONÓMICA'), competition('primera', 'PRIMERA')],
  )

  test('un equipo con dos competiciones se coloca por la primera de las suyas en el alfabeto', () => {
    expect(ids(sortRows(rows, rules.competicion, false))).toEqual(['dos', 'primera', 'segunda', 'sin'])
  })

  test('al revés, y el que no tiene competición sigue al final', () => {
    expect(ids(sortRows(rows, rules.competicion, true))).toEqual(['segunda', 'primera', 'dos', 'sin'])
  })

  test('las tildes no descolocan: «Ámbito» va con la A', () => {
    const accented = teamRows(
      [team('b', 'alevin', 'A', ['b']), team('a', 'alevin', 'B', ['a'])],
      [competition('b', 'BETA'), competition('a', 'ÁMBITO')],
    )

    expect(ids(sortRows(accented, rules.competicion, false))).toEqual(['a', 'b'])
  })
})

describe('Ingesta: de peor a mejor, y cada equipo por la peor de las suyas', () => {
  const rows = teamRows(
    [
      team('al-dia', 'alevin', 'A', ['ok']),
      team('sin', 'alevin', 'B', []),
      team('con-fallos', 'alevin', 'C', ['ok2', 'failing']),
      team('sin-datos', 'alevin', 'D', ['never']),
      team('en-marcha', 'alevin', 'E', ['pending']),
      team('desactualizada', 'alevin', 'F', ['stale']),
    ],
    [
      competition('ok', 'A', { ingestionHealth: 'ok' }),
      competition('ok2', 'A', { ingestionHealth: 'ok' }),
      competition('failing', 'A', { ingestionHealth: 'failing' }),
      competition('never', 'A', { ingestionHealth: 'never' }),
      competition('pending', 'A', { ingestionHealth: 'pending' }),
      competition('stale', 'A', { ingestionHealth: 'stale' }),
    ],
  )

  test('con fallos, desactualizada, en marcha, sin datos, al día; el de dos, por su peor', () => {
    expect(ids(sortRows(rows, rules.ingesta, false))).toEqual([
      'con-fallos',
      'desactualizada',
      'en-marcha',
      'sin-datos',
      'al-dia',
      'sin',
    ])
  })

  test('al revés, de mejor a peor, y el que no tiene competición sigue al final', () => {
    expect(ids(sortRows(rows, rules.ingesta, true))).toEqual([
      'al-dia',
      'sin-datos',
      'en-marcha',
      'desactualizada',
      'con-fallos',
      'sin',
    ])
  })
})

describe('Última sincronización: de la más antigua a la más reciente, con «Nunca» arriba', () => {
  const rows = teamRows(
    [
      team('reciente', 'alevin', 'A', ['oct']),
      team('sin', 'alevin', 'B', []),
      team('antigua', 'alevin', 'C', ['sep']),
      team('nunca', 'alevin', 'D', ['nunca']),
      team('dos', 'alevin', 'E', ['oct2', 'ago']),
    ],
    [
      competition('oct', 'A', { lastSyncedAt: '2026-10-20T10:00:00Z' }),
      competition('oct2', 'A', { lastSyncedAt: '2026-10-21T10:00:00Z' }),
      competition('sep', 'A', { lastSyncedAt: '2026-09-15T10:00:00Z' }),
      competition('ago', 'A', { lastSyncedAt: '2026-08-01T10:00:00Z' }),
      competition('nunca', 'A', {}),
    ],
  )

  test('«Nunca» primero, y el de dos competiciones, por la más antigua de las suyas', () => {
    expect(ids(sortRows(rows, rules.sincronizacion, false))).toEqual(['nunca', 'dos', 'antigua', 'reciente', 'sin'])
  })

  test('al revés, la más reciente primero y «Nunca» la última de las que tienen competición', () => {
    expect(ids(sortRows(rows, rules.sincronizacion, true))).toEqual(['reciente', 'antigua', 'dos', 'nunca', 'sin'])
  })
})
