import { describe, expect, test } from 'vitest'
import { rosterRows } from './roster'

// Lo que dice cada fila de la plantilla (plan R6, §3 y decisión 7), sin pintar nada.

function player(fields: Record<string, unknown> = {}) {
  return {
    id: 'fila-1',
    profileId: 'perfil-1',
    teamId: 'equipo',
    seasonId: 'temporada',
    fullName: 'JUAN CARLOS GARCÍA DE LA FUENTE',
    birthYear: 2011,
    shirtNumber: 7,
    position: 'delantero',
    federated: null,
    lastListedAt: null,
    photoUrl: '/api/v1/player-photos/abc.jpg?expires=1&signature=x',
    createdAt: '2026-11-16T00:00:00Z',
    updatedAt: '2026-11-16T00:00:00Z',
    ...fields,
  } as Parameters<typeof rosterRows>[0][number]
}

describe('cada fila de la plantilla', () => {
  test('el dorsal, el nombre como «Nombre Apellidos», la demarcación por su nombre y el año', () => {
    expect(rosterRows([player()])).toEqual([
      {
        id: 'fila-1',
        name: 'Juan Carlos García de la Fuente',
        initials: 'JC',
        photoUrl: '/api/v1/player-photos/abc.jpg?expires=1&signature=x',
        shirtNumber: '7',
        position: 'Delantero',
        birthYear: '2011',
      },
    ])
  })

  test('sin dorsal ni demarcación, una raya en las dos', () => {
    const [row] = rosterRows([player({ shirtNumber: null, position: null })])
    expect(row).toMatchObject({ shirtNumber: '—', position: '—' })
  })

  test('sin año en su perfil, «Sin año»', () => {
    expect(rosterRows([player({ birthYear: null })])[0]!.birthYear).toBe('Sin año')
  })

  test('sin foto, ninguna dirección: se pintan las iniciales', () => {
    expect(rosterRows([player({ photoUrl: null })])[0]!.photoUrl).toBeUndefined()
  })

  test('un nulo que llega como clave ausente vale lo mismo (DW-21)', () => {
    const [row] = rosterRows([player({ shirtNumber: undefined, position: undefined, birthYear: undefined, photoUrl: undefined })])
    expect(row).toMatchObject({ shirtNumber: '—', position: '—', birthYear: 'Sin año', photoUrl: undefined })
  })

  test('«Federado» si la última sincronización lo listó, «No federado» si no (D-120)', () => {
    expect(rosterRows([player({ federated: true })])[0]!.federation).toBe('Federado')
    expect(rosterRows([player({ federated: false })])[0]!.federation).toBe('No federado')
  })

  test('sin sincronizar nunca, ni «Federado» ni «No federado», también si llega como clave ausente', () => {
    expect(rosterRows([player({ federated: null })])[0]!.federation).toBeUndefined()
    const missing: Record<string, unknown> = { ...player() }
    delete missing.federated
    expect(rosterRows([missing as never])[0]!.federation).toBeUndefined()
  })

  test('en el orden en que llegan', () => {
    const rows = rosterRows([player({ id: 'a', shirtNumber: 9 }), player({ id: 'b', shirtNumber: 1 })])
    expect(rows.map((row) => row.id)).toEqual(['a', 'b'])
  })
})
