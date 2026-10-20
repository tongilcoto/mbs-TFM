import { expect, test } from 'vitest'
import { teamName } from './names'

test('un equipo se nombra por su categoría, en español, y su letra', () => {
  expect(teamName('cadete', 'B')).toBe('Cadete B')
  expect(teamName('prebenjamin', 'A')).toBe('Prebenjamín A')
})

test('un equipo sin letra, solo con su categoría', () => {
  expect(teamName('alevin', null)).toBe('Alevín')
  expect(teamName('senior')).toBe('Senior')
})
