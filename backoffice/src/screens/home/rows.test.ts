import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import { formatInstant } from '../../theme/format'
import { teamRows } from './rows'

type Registration = components['schemas']['TeamRegistrationResponse']
type Competition = components['schemas']['CompetitionResponse']

function registration(
  id: string,
  category: 'alevin' | 'cadete',
  letter: string,
  competitionIds: string[],
  gender: 'masculino' | 'femenino' = 'masculino',
): Registration {
  return {
    seasonId: 'temporada',
    competitions: competitionIds.map((competitionId) => ({ competitionId, federationTeamId: '824' })),
    team: {
      id,
      category,
      letter,
      gender,
      modality: 'futbol_11',
      isOwn: true,
      clubName: 'Celtic',
      displayName: `Celtic ${category} ${letter}`,
      createdAt: '2026-10-09T21:50:27Z',
      updatedAt: '2026-10-09T21:50:27Z',
    },
  }
}

function competition(id: string, fields: Partial<Competition>): Competition {
  return {
    id,
    seasonId: 'temporada',
    modality: 'futbol_11',
    gender: 'masculino',
    ageCategory: 'cadete',
    divisionLabel: 'PRIMERA CADETE',
    groupLabel: 'Grupo 4',
    federationCompetitionId: '1',
    federationGroupId: '2',
    displayName: `Competición ${id}`,
    createdAt: '2026-10-09T21:50:27Z',
    updatedAt: '2026-10-09T21:50:27Z',
    ...fields,
  }
}

describe('las filas de la portada', () => {
  test('cada equipo con su nombre en español, su competición, su ingesta y su última sincronización', () => {
    const rows = teamRows(
      [registration('cadete-b', 'cadete', 'B', ['liga'])],
      [competition('liga', { ingestionHealth: 'ok', lastSyncedAt: '2026-10-17T21:40:00Z' })],
    )

    // Lo que pinta la tabla; las claves de orden las prueba order.test.ts.
    expect(rows).toMatchObject([
      {
        id: 'cadete-b',
        team: 'Cadete B',
        competitions: [
          {
            id: 'liga',
            // La división y el grupo, sin la categoría delante: el equipo ya la dice (bloque T).
            name: 'PRIMERA CADETE · Grupo 4',
            health: 'ok',
            healthName: 'Al día',
            previousFailed: false,
            lastSynced: formatInstant('2026-10-17T21:40:00Z'),
          },
        ],
      },
    ])
  })

  test('un equipo con dos competiciones sale en una sola fila, con las dos', () => {
    const rows = teamRows(
      [registration('cadete-b', 'cadete', 'B', ['liga', 'copa'])],
      [competition('liga', {}), competition('copa', { divisionLabel: 'COPA CADETE', groupLabel: 'Grupo Único' })],
    )

    expect(rows).toHaveLength(1)
    expect(rows[0]!.competitions.map((c) => c.name)).toEqual(['PRIMERA CADETE · Grupo 4', 'COPA CADETE · Grupo Único'])
  })

  test('dos equipos con la misma categoría y letra salen distinguidos por lo que los diferencia', () => {
    const rows = teamRows(
      [registration('alevin-a-m', 'alevin', 'A', []), registration('alevin-a-f', 'alevin', 'A', [], 'femenino')],
      [],
    )

    expect(rows.map((row) => row.team)).toEqual(['Alevín A · Masculino', 'Alevín A · Femenino'])
  })

  test('un equipo sin competición todavía sale con la lista vacía', () => {
    expect(teamRows([registration('alevin-a', 'alevin', 'A', [])], [])[0]!.competitions).toEqual([])
  })

  test('«La anterior tuvo fallos» solo si está en marcha y la anterior falló', () => {
    const rows = teamRows(
      [registration('cadete-b', 'cadete', 'B', ['a', 'b', 'c'])],
      [
        competition('a', { ingestionHealth: 'pending', previousIngestionHealth: 'failing' }),
        competition('b', { ingestionHealth: 'pending', previousIngestionHealth: 'ok' }),
        competition('c', { ingestionHealth: 'failing', previousIngestionHealth: 'failing' }),
      ],
    )

    expect(rows[0]!.competitions.map((c) => c.previousFailed)).toEqual([true, false, false])
  })

  test('sin sincronizar nunca, «Nunca»', () => {
    const rows = teamRows(
      [registration('cadete-b', 'cadete', 'B', ['liga'])],
      [competition('liga', { ingestionHealth: 'never', lastSyncedAt: null })],
    )

    expect(rows[0]!.competitions[0]).toMatchObject({ healthName: 'Sin datos todavía', lastSynced: 'Nunca' })
  })

  test('las filas siguen el orden en que llegan', () => {
    const rows = teamRows(
      [registration('alevin-a', 'alevin', 'A', []), registration('cadete-b', 'cadete', 'B', [])],
      [],
    )

    expect(rows.map((r) => r.team)).toEqual(['Alevín A', 'Cadete B'])
  })
})

describe('volver a traer los datos con ↻ (plan R4, decisión 7)', () => {
  const relaunched = (fields: Partial<Competition>) =>
    teamRows([registration('cadete-b', 'cadete', 'B', ['liga'])], [competition('liga', fields)], new Set(['liga']))

  test('la competición sale «En marcha» aunque el servidor diga otra cosa', () => {
    expect(relaunched({ ingestionHealth: 'ok' })[0]!.competitions[0]).toMatchObject({
      health: 'pending',
      healthName: 'En marcha',
      previousFailed: false,
    })
  })

  test('si estaba con fallos, «La anterior tuvo fallos»', () => {
    expect(relaunched({ ingestionHealth: 'failing' })[0]!.competitions[0]).toMatchObject({
      health: 'pending',
      previousFailed: true,
    })
  })

  test('si el servidor ya la tenía en marcha, la anterior es la que él dice', () => {
    expect(
      relaunched({ ingestionHealth: 'pending', previousIngestionHealth: 'failing' })[0]!.competitions[0]!.previousFailed,
    ).toBe(true)
  })

  test('para ordenar, lo que dice el servidor: la fila no cambia de sitio al pulsar', () => {
    expect(relaunched({ ingestionHealth: 'failing' })[0]!.keys.healths).toEqual(['failing'])
  })

  test('las demás competiciones, como las dice el servidor', () => {
    const rows = teamRows(
      [registration('cadete-b', 'cadete', 'B', ['liga', 'copa'])],
      [competition('liga', { ingestionHealth: 'ok' }), competition('copa', { ingestionHealth: 'ok' })],
      new Set(['copa']),
    )

    expect(rows[0]!.competitions.map((c) => c.health)).toEqual(['ok', 'pending'])
  })
})
