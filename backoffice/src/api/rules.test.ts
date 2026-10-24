import { describe, expect, test } from 'vitest'
import { checkForm, requiredFields } from './rules'

// Las pruebas usan los esquemas de verdad del catálogo: si una regla cambia allí, se nota aquí.
const SEASON_ID = '0b7e7a52-4c1d-4f7e-9a51-3f7f0c2b8d11'

describe('el alta de equipo, contra CreateTeamRequest', () => {
  test('vacío, nombra sus cuatro campos obligatorios a la vez, y no la letra, que no lo es', () => {
    expect(checkForm('CreateTeamRequest', {})).toEqual({
      category: 'Este campo es obligatorio',
      gender: 'Este campo es obligatorio',
      modality: 'Este campo es obligatorio',
      seasonId: 'Este campo es obligatorio',
    })
  })

  test('bien rellenado, no falla nada; con la letra o sin ella', () => {
    const team = { category: 'alevin', gender: 'masculino', modality: 'futbol_7', seasonId: SEASON_ID } as const
    expect(checkForm('CreateTeamRequest', team)).toEqual({})
    expect(checkForm('CreateTeamRequest', { ...team, letter: 'A' })).toEqual({})
    expect(checkForm('CreateTeamRequest', { ...team, letter: null })).toEqual({})
  })

  test('los fallos de tipos distintos salen juntos, cada uno junto a su campo', () => {
    // `category` fuera de la lista, como mandaría una web más vieja que el catálogo.
    const form = { category: 'veterano', letter: '', gender: 'masculino', modality: 'futbol_7', seasonId: 'sin-formato' }
    expect(checkForm('CreateTeamRequest', form as never)).toEqual({
      category: 'Elige un valor de la lista',
      letter: 'No puede estar vacío',
      seasonId: 'El formato no es válido',
    })
  })

  test('un campo que incumple dos reglas sale con un solo mensaje, el de la primera', () => {
    // Un número donde va la categoría no es texto (primera regla) ni está en la lista (segunda).
    expect(checkForm('CreateTeamRequest', { category: 5 } as never).category).toBe('El valor no es válido')
  })
})

describe('cada tipo de regla, con su mensaje', () => {
  test('el formato de un dato con ejemplo en el catálogo lleva el ejemplo', () => {
    expect(checkForm('CreateSeasonRequest', { label: '2026-27' })).toEqual({
      label: 'El formato no es válido. Por ejemplo: 2024/25',
    })
  })

  test('que los años de la temporada sigan no lo dice el catálogo: «2026/28» pasa, y lo rechaza el servidor', () => {
    expect(checkForm('CreateSeasonRequest', { label: '2026/28' })).toEqual({})
  })

  test('el máximo de caracteres', () => {
    expect(checkForm('CreatePlayerRequest', { fullName: 'a'.repeat(121) }).fullName).toBe('Como máximo 120 caracteres')
  })

  test('el valor mínimo y el máximo', () => {
    expect(checkForm('CreatePlayerRequest', { shirtNumber: 0 }).shirtNumber).toBe('Como mínimo 1')
    expect(checkForm('CreatePlayerRequest', { shirtNumber: 100 }).shirtNumber).toBe('Como máximo 99')
  })
})

test('los obligatorios de un esquema salen de su `required` en el catálogo', () => {
  expect(requiredFields('CreateTeamRequest')).toEqual(['category', 'gender', 'modality', 'seasonId'])
  expect(requiredFields('UpdateClubRequest')).toEqual([])
})
