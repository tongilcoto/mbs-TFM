import { describe, expect, test } from 'vitest'
import { cleanName, nameProblem, shirtNumberOf, shirtProblem, yearProblem } from './playerForm'

// Lo que la web comprueba antes de enviar el alta o la corrección (plan R6, decisión 9): las mismas reglas que el
// servidor (PlayerName, BirthYear, ShirtNumber), con los textos de los escenarios.

describe('el nombre', () => {
  test('se limpian los espacios: fuera los de los lados, y uno solo entre palabras', () => {
    expect(cleanName('  Marcos   Díaz ')).toBe('Marcos Díaz')
  })

  test('la tilde en dos piezas se junta en una, como en el servidor', () => {
    expect(cleanName('José Pérez')).toBe('José Pérez')
  })

  test('un nombre con nombre y apellido, con tildes, eñe, diéresis, guion y apóstrofo, vale', () => {
    expect(nameProblem("Íñigo Argüelles Pérez-Reverte O'Neill")).toBeUndefined()
    expect(nameProblem('Ana D’Angelo')).toBeUndefined()
  })

  test.each([
    ['vacío', '', 'Escribe el nombre y al menos un apellido'],
    ['solo espacios', '   ', 'Escribe el nombre y al menos un apellido'],
    ['de una sola palabra', 'Marcos', 'Escribe el nombre y al menos un apellido'],
    ['con un número', 'Marcos D1az', 'Solo letras, espacios, guion y apóstrofo'],
    ['con un símbolo', 'Marcos Díaz!', 'Solo letras, espacios, guion y apóstrofo'],
    ['con una palabra sin letras', 'Marcos - Díaz', 'Cada palabra tiene que llevar letras'],
  ])('%s: «%s» no vale', (_, name, problem) => {
    expect(nameProblem(name)).toBe(problem)
  })

  test('hasta 120 letras, contadas ya limpio', () => {
    const at120 = `${'a'.repeat(60)} ${'b'.repeat(59)}`
    expect(nameProblem(`  ${at120}  `)).toBeUndefined()
    expect(nameProblem(`${at120}b`)).toBe('Como mucho, 120 letras')
  })
})

describe('el año de nacimiento', () => {
  test('obligatorio', () => {
    expect(yearProblem('', 2026)).toBe('Falta el año de nacimiento')
    expect(yearProblem('  ', 2026)).toBe('Falta el año de nacimiento')
  })

  test('de 1900 al año en curso', () => {
    expect(yearProblem('1900', 2026)).toBeUndefined()
    expect(yearProblem('2026', 2026)).toBeUndefined()
    expect(yearProblem('1899', 2026)).toBe('Un año entre 1900 y 2026')
    expect(yearProblem('2027', 2026)).toBe('Un año entre 1900 y 2026')
  })

  test('solo cifras', () => {
    expect(yearProblem('20l2', 2026)).toBe('Un año entre 1900 y 2026')
    expect(yearProblem('2012.5', 2026)).toBe('Un año entre 1900 y 2026')
  })
})

describe('el dorsal', () => {
  test('opcional: vacío, sin dorsal', () => {
    expect(shirtProblem('')).toBeUndefined()
    expect(shirtNumberOf(' ')).toBeNull()
  })

  test('del 1 al 99', () => {
    expect(shirtProblem('1')).toBeUndefined()
    expect(shirtProblem('99')).toBeUndefined()
    expect(shirtProblem('0')).toBe('Del 1 al 99')
    expect(shirtProblem('100')).toBe('Del 1 al 99')
    expect(shirtProblem('7a')).toBe('Del 1 al 99')
    expect(shirtNumberOf(' 7 ')).toBe(7)
  })
})
