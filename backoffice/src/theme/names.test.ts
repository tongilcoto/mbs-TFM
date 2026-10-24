import { describe, expect, test } from 'vitest'
import catalog from '../api/schemas.json'
import { namesOf, optionsOf, teamName, teamNames } from './names'

test('un equipo se nombra por su categoría, en español, y su letra', () => {
  expect(teamName('cadete', 'B')).toBe('Cadete B')
  expect(teamName('prebenjamin', 'A')).toBe('Prebenjamín A')
})

test('un equipo sin letra, solo con su categoría', () => {
  expect(teamName('alevin', null)).toBe('Alevín')
  expect(teamName('senior')).toBe('Senior')
})

// Los nombres y el orden salen del catálogo (D-108); las pruebas los comparan con él, no con una copia.
const schemas = catalog.components.schemas

test('las opciones de un selector van en el orden del catálogo, con el nombre de su tabla', () => {
  expect(optionsOf('TeamCategory').map((o) => o.value)).toEqual(schemas.TeamCategory.enum)
  expect(optionsOf('Modality')).toContainEqual({ value: 'futbol_7', label: 'Fútbol 7' })
  expect(optionsOf('TeamCategory')[0]).toEqual({ value: 'prebenjamin', label: 'Prebenjamín' })
})

test('cada valor de una lista tiene su nombre, y no hay ninguno de más', () => {
  const names = namesOf('IngestionHealth')

  expect(Object.keys(names)).toEqual(schemas.IngestionHealth.enum)
  expect(names.stale).toBe('Desactualizada')
})

describe('los nombres de los equipos de una lista, distinguidos cuando hace falta (bloque T)', () => {
  type T = Parameters<typeof teamNames>[0][number]
  const team = (id: string, fields: Partial<T>): T => ({
    id,
    category: 'alevin',
    letter: 'A',
    gender: 'masculino',
    modality: 'futbol_7',
    ...fields,
  })

  test('sin otro igual, cada equipo con su categoría y su letra, como siempre', () => {
    const names = teamNames([team('a', {}), team('b', { category: 'cadete', letter: 'B' })])

    expect(names.get('a')).toBe('Alevín A')
    expect(names.get('b')).toBe('Cadete B')
  })

  test('dos con la misma categoría y letra y distinto género: cada uno con su género', () => {
    const names = teamNames([team('m', {}), team('f', { gender: 'femenino' })])

    expect(names.get('m')).toBe('Alevín A · Masculino')
    expect(names.get('f')).toBe('Alevín A · Femenino')
  })

  test('distinta modalidad: cada uno con su modalidad, y no con el género, que es el mismo', () => {
    const names = teamNames([team('7', {}), team('11', { modality: 'futbol_11' })])

    expect(names.get('7')).toBe('Alevín A · Fútbol 7')
    expect(names.get('11')).toBe('Alevín A · Fútbol 11')
  })

  test('si en el grupo cambian las dos cosas, los dos datos, a todos los del grupo', () => {
    const names = teamNames([team('m7', {}), team('f7', { gender: 'femenino' }), team('m11', { modality: 'futbol_11' })])

    expect(names.get('m7')).toBe('Alevín A · Masculino · Fútbol 7')
    expect(names.get('f7')).toBe('Alevín A · Femenino · Fútbol 7')
    expect(names.get('m11')).toBe('Alevín A · Masculino · Fútbol 11')
  })

  test('sin letra también: dos «Alevín» se distinguen igual', () => {
    const names = teamNames([team('m', { letter: null }), team('f', { letter: null, gender: 'femenino' })])

    expect(names.get('m')).toBe('Alevín · Masculino')
    expect(names.get('f')).toBe('Alevín · Femenino')
  })

  test('el «Alevín A» y el «Alevín B» no son iguales: ninguno lleva nada más', () => {
    const names = teamNames([team('a', {}), team('b', { letter: 'B', gender: 'femenino' })])

    expect(names.get('a')).toBe('Alevín A')
    expect(names.get('b')).toBe('Alevín B')
  })
})
