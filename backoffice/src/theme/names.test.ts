import { expect, test } from 'vitest'
import catalog from '../api/schemas.json'
import { namesOf, optionsOf, teamName } from './names'

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
