import { describe, expect, test } from 'vitest'
import { canChange, chooseSeason, newestFirst, type Season, seasonPhase, toAddress } from './seasons'

function season(label: string, isCurrent = false): Season {
  const start = Number(label.slice(0, 4))
  return {
    id: `id-${label}`,
    label,
    federationSeasonId: '22',
    startDate: `${start}-07-01`,
    endDate: `${start + 1}-06-30`,
    isCurrent,
    createdAt: '2026-10-09T21:33:02Z',
    updatedAt: '2026-10-09T21:33:02Z',
  }
}

const today = '2026-10-20'

describe('qué temporada enseña la portada', () => {
  test('sin ?temporada=, la que está en curso', () => {
    const seasons = [season('2025/26'), season('2026/27', true)]

    expect(chooseSeason(seasons, undefined, today)).toEqual({ kind: 'chosen', season: seasons[1] })
  })

  test('con ?temporada=2025-26, esa, aunque haya otra en curso', () => {
    const seasons = [season('2025/26'), season('2026/27', true)]

    expect(chooseSeason(seasons, '2025-26', today)).toEqual({ kind: 'chosen', season: seasons[0] })
  })

  test('una temporada de la dirección que no existe, o que no se entiende, es «desconocida», con barra', () => {
    const seasons = [season('2026/27', true)]

    expect(chooseSeason(seasons, '2019-20', today)).toEqual({ kind: 'unknown', asked: '2019/20' })
    expect(chooseSeason(seasons, 'abc', today)).toEqual({ kind: 'unknown', asked: 'abc' })
  })

  test('sin ninguna en curso, la más reciente: «terminada» si ya acabó', () => {
    const seasons = [season('2024/25'), season('2025/26')]

    expect(chooseSeason(seasons, undefined, today)).toEqual({ kind: 'chosen', season: seasons[1], note: 'terminada' })
  })

  test('sin ninguna en curso, la más reciente: «todavía no ha empezado» si se creó por adelantado', () => {
    const seasons = [season('2027/28'), season('2025/26')]

    expect(chooseSeason(seasons, undefined, today)).toEqual({
      kind: 'chosen',
      season: seasons[0],
      note: 'todavía no ha empezado',
    })
  })

  test('el club sin temporadas', () => {
    expect(chooseSeason([], undefined, today)).toEqual({ kind: 'none' })
    expect(chooseSeason([], '2025-26', today)).toEqual({ kind: 'none' })
  })
})

test('en la dirección, la temporada va con guion', () => {
  expect(toAddress('2025/26')).toBe('2025-26')
})

test('el selector las ordena de la más reciente a la más antigua', () => {
  const seasons = [season('2024/25'), season('2026/27'), season('2025/26')]

  expect(newestFirst(seasons).map((s) => s.label)).toEqual(['2026/27', '2025/26', '2024/25'])
})

describe('pasada, en curso o futura (decisión 3 de R6.16)', () => {
  test('la que marca el servidor como en curso es la en curso', () => {
    expect(seasonPhase(season('2026/27', true), today)).toBe('current')
  })

  test('la que acabó antes de hoy es pasada; la que acaba hoy, todavía no', () => {
    expect(seasonPhase(season('2024/25'), today)).toBe('past')
    expect(seasonPhase(season('2025/26'), '2026-06-30')).toBe('future')
    expect(seasonPhase(season('2025/26'), '2026-07-01')).toBe('past')
  })

  test('la que empieza después de hoy es futura', () => {
    expect(seasonPhase(season('2027/28'), today)).toBe('future')
  })
})

describe('qué temporadas se pueden cambiar (decisión 4 de R6.14)', () => {
  test('la en curso y la futura, sí', () => {
    expect(canChange(season('2026/27', true), today)).toBe(true)
    expect(canChange(season('2027/28'), today)).toBe(true)
  })

  test('una pasada, archivada o no, no', () => {
    expect(canChange(season('2024/25'), today)).toBe(false)
    expect(canChange({ ...season('2024/25'), archivedAt: '2026-01-01T00:00:00Z' }, today)).toBe(false)
  })

  test('una archivada, aunque no sea pasada, tampoco', () => {
    expect(canChange({ ...season('2027/28'), archivedAt: '2026-01-01T00:00:00Z' }, today)).toBe(false)
  })
})
