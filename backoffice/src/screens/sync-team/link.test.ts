import { describe, expect, test } from 'vitest'
import { errorFromResponse, noConnection } from '../../api/errors'
import { isTeamCode, placeCheckError, teamTitle } from './link'

const aTeam = {
  id: '38e114db-d5e7-40ce-b1b3-8af0c4968982',
  category: 'alevin',
  letter: 'B',
  gender: 'masculino',
  modality: 'futbol_7',
  isOwn: true,
  clubName: 'Celtic',
  displayName: 'Celtic Alevín B',
  createdAt: '2026-10-09T21:50:27Z',
  updatedAt: '2026-10-09T21:50:27Z',
} as const

describe('el código del equipo en la dirección (LLD-B §6.7)', () => {
  test('un UUID es un código, en mayúsculas o minúsculas', () => {
    expect(isTeamCode('38e114db-d5e7-40ce-b1b3-8af0c4968982')).toBe(true)
    expect(isTeamCode('38E114DB-D5E7-40CE-B1B3-8AF0C4968982')).toBe(true)
  })

  test.each(['abc', '', '38e114db-d5e7-40ce-b1b3-8af0c496898', '38e114db-d5e7-40ce-b1b3-8af0c4968982x'])(
    '«%s» no lo es',
    (id) => {
      expect(isTeamCode(id)).toBe(false)
    },
  )
})

describe('el equipo debajo del título', () => {
  test('categoría y letra, género y modalidad, con los nombres del catálogo', () => {
    expect(teamTitle(aTeam)).toBe('Alevín B · Masculino · Fútbol 7')
  })

  test('sin letra, sin hueco', () => {
    expect(teamTitle({ ...aTeam, letter: undefined })).toBe('Alevín · Masculino · Fútbol 7')
  })
})

describe('dónde sale un error al comprobar la dirección (decisión 6)', () => {
  const placed = (status: number, code: string) => placeCheckError(errorFromResponse(status, { status, code }))

  test('la dirección que no es de un calendario, y la que no lleva a ninguno, junto al campo', () => {
    expect(placed(400, 'UNREADABLE_FEDERATION_URL')).toBe('field')
    expect(placed(502, 'FEDERATION_COORDINATE_NOT_FOUND')).toBe('field')
  })

  test('el equipo que ya no está, la página entera', () => {
    expect(placed(404, 'TEAM_NOT_FOUND')).toBe('page')
  })

  test.each([
    [504, 'FEDERATION_UNREACHABLE'],
    [502, 'FEDERATION_UNEXPECTED_STATUS'],
    [501, 'FEDERATION_ADAPTER_MISSING'],
    [400, 'SEASON_LABEL_UNAVAILABLE'],
    [409, 'SEASON_ALREADY_LINKED'],
  ])('un %i %s, arriba', (status, code) => {
    expect(placed(status, code)).toBe('banner')
  })

  test('sin conexión con el servidor, arriba', () => {
    expect(placeCheckError(noConnection)).toBe('banner')
  })
})
