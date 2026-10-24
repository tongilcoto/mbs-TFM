import { describe, expect, test } from 'vitest'
import type { Season } from '../home/seasons'
import { hasChanges, initialSeason, toRequest } from './form'

function season(label: string, fields: Partial<Season> = {}): Season {
  const year = Number(label.slice(0, 4))
  return {
    id: `id-${label}`,
    label,
    startDate: `${year}-07-01`,
    endDate: `${year + 1}-06-30`,
    isCurrent: false,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...fields,
  }
}

const today = '2026-10-24'
const seasons = [season('2027/28'), season('2026/27', { isCurrent: true }), season('2025/26')]

describe('qué temporada viene elegida (decisión 5)', () => {
  test('el club sin temporadas: ninguna', () => {
    expect(initialSeason([], '2026/27', today)).toBeUndefined()
  })

  test('la que enseñaba la portada, si sigue en la lista, aunque no sea la en curso', () => {
    expect(initialSeason(seasons, '2025/26', today)?.label).toBe('2025/26')
  })

  test('sin temporada de la portada (escrita la dirección a mano), la en curso', () => {
    expect(initialSeason(seasons, undefined, today)?.label).toBe('2026/27')
  })

  test('la de la portada ya no está: la en curso, sin error', () => {
    expect(initialSeason(seasons, '2024/25', today)?.label).toBe('2026/27')
  })

  test('sin ninguna en curso, la más reciente, como la portada', () => {
    expect(initialSeason([season('2024/25'), season('2025/26')], undefined, today)?.label).toBe('2025/26')
  })
})

describe('lo que se envía', () => {
  const filled = { category: 'alevin', gender: 'femenino', modality: 'futbol_7', seasonId: 'id-2026/27' } as const

  test('la letra en blanco no se manda', () => {
    expect(toRequest({ ...filled, letter: '' })).toEqual(filled)
  })

  test('la letra se manda tal cual, también si son espacios: los rechaza el servidor', () => {
    expect(toRequest({ ...filled, letter: 'B' })).toEqual({ ...filled, letter: 'B' })
    expect(toRequest({ ...filled, letter: ' ' }).letter).toBe(' ')
  })

  test('lo que no se ha elegido sale sin rellenar, para que la comprobación lo marque', () => {
    expect(toRequest({ letter: '' })).toEqual({})
  })
})

describe('los cambios sin guardar', () => {
  test('recién abierto, con la temporada que puso la web, no hay', () => {
    expect(hasChanges({ letter: '', seasonId: 'id-2026/27' }, 'id-2026/27')).toBe(false)
  })

  test.each([
    ['la categoría', { category: 'cadete' as const }],
    ['la letra', { letter: 'A' }],
    ['el género', { gender: 'mixto' as const }],
    ['la modalidad', { modality: 'futbol_sala' as const }],
    ['otra temporada', { seasonId: 'id-2027/28' }],
  ])('cambiar %s es un cambio', (_, change) => {
    expect(hasChanges({ letter: '', seasonId: 'id-2026/27', ...change }, 'id-2026/27')).toBe(true)
  })
})
