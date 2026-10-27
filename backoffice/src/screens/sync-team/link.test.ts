import { describe, expect, test } from 'vitest'
import { errorFromResponse, noConnection } from '../../api/errors'
import type { components } from '../../api/schema'
import { choicesOf, competitionName, isTeamCode, mismatchesOf, placeCheckError, placeSyncError, syncLabel, teamTitle } from './link'

const teamId = '38e114db-d5e7-40ce-b1b3-8af0c4968982'
const aTeam = {
  id: teamId,
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

// Un equipo del grupo, como lo manda el `/preview`.
function published(rawName: string, federationTeamId: string | null, takenBy?: object | null) {
  return { rawName, federationTeamId, ...(takenBy === undefined ? {} : { takenBy }) } as never
}
const ref = (teamId: string, displayName: string, isOwn: boolean) => ({ teamId, displayName, shortDisplayName: 'x', isOwn })

describe('la lista de equipos del paso 2 (decisión 4)', () => {
  test('por orden alfabético, con las reglas del español', () => {
    const choices = choicesOf(
      [published("U.D. SAN ROQUE 'B'", '1'), published("CELTIC CASTILLA C.F. 'B'", '2'), published("Ávila C.F.", '3'), published("CELTIC CASTILLA C.F. 'A'", '4')],
      teamId,
    )

    expect(choices.map((c) => c.name)).toEqual(["Ávila C.F.", "CELTIC CASTILLA C.F. 'A'", "CELTIC CASTILLA C.F. 'B'", "U.D. SAN ROQUE 'B'"])
  })

  test('libre, sin motivo; y `takenBy` puede faltar o venir nulo (LLD-B §3.8)', () => {
    const choices = choicesOf([published('A', '1'), published('B', '2', null)], teamId)

    expect(choices).toEqual([
      { code: '1', name: 'A', reason: undefined },
      { code: '2', name: 'B', reason: undefined },
    ])
  })

  test.each([
    ['sin código', published('X', null), 'La Federación no publica su código: no se puede elegir'],
    ['el mismo equipo, ya sincronizado', published('X', '1', ref(teamId, 'Celtic Alevín B', true)), 'Ya está sincronizado con este equipo'],
    ['otro equipo del club', published('X', '1', ref('otro', 'Celtic Alevín A', true)), 'Ya está sincronizado con Celtic Alevín A'],
    ['un rival', published('X', '1', ref('otro', 'Celtic Alevín B', false)), 'Ya está en el club como rival: la Federación lo trajo antes de sincronizarlo'],
  ])('%s: no se puede elegir, y dice por qué', (_, team, reason) => {
    expect(choicesOf([team], teamId)[0]!.reason).toBe(reason)
  })
})

describe('lo que no cuadra (§3.3)', () => {
  const competition: components['schemas']['CompetitionPreviewResponse'] = {
    modality: 'futbol_7',
    gender: 'masculino',
    ageCategory: 'alevin',
    divisionLabel: 'PRIMERA ALEVIN',
    groupLabel: 'Grupo 4',
    federationCompetitionId: '1',
    federationGroupId: '2',
    roundCount: 26,
    teams: [],
    alreadyRegistered: false,
  }

  test('todo igual: nada', () => {
    expect(mismatchesOf(aTeam, competition, 'masculino')).toEqual([])
  })

  test('la edad y la modalidad, con los nombres del catálogo', () => {
    expect(mismatchesOf(aTeam, { ...competition, ageCategory: 'infantil', modality: 'futbol_11' }, 'masculino')).toEqual([
      { piece: 'Edad', team: 'Alevín', competition: 'Infantil' },
      { piece: 'Modalidad', team: 'Fútbol 7', competition: 'Fútbol 11' },
    ])
  })

  test('una competición nueva: cuenta el género elegido, no el propuesto', () => {
    expect(mismatchesOf(aTeam, { ...competition, gender: 'femenino' }, 'masculino')).toEqual([])
    expect(mismatchesOf(aTeam, competition, 'femenino')).toEqual([{ piece: 'Género', team: 'Masculino', competition: 'Femenino' }])
  })

  test('una competición que ya está en el club: cuenta su género, elija lo que se elija', () => {
    expect(mismatchesOf(aTeam, { ...competition, alreadyRegistered: true, gender: 'femenino' }, 'masculino')).toEqual([
      { piece: 'Género', team: 'Masculino', competition: 'Femenino' },
    ])
  })

  test('la competición, por su división y su grupo; sin división, solo el grupo', () => {
    expect(competitionName(competition)).toBe('PRIMERA ALEVIN · Grupo 4')
    expect(competitionName({ ...competition, divisionLabel: '' })).toBe('Grupo 4')
  })
})

describe('el botón de sincronizar', () => {
  test('sin elegir, «Sincronizar»; elegido, con su nombre', () => {
    expect(syncLabel(undefined)).toBe('Sincronizar')
    expect(syncLabel({ code: '1', name: "CELTIC CASTILLA C.F. 'B'" })).toBe("Sincronizar CELTIC CASTILLA C.F. 'B'")
  })
})

describe('dónde sale un error al sincronizar (decisión 6)', () => {
  test('el equipo que ya no está, la página entera', () => {
    expect(placeSyncError(errorFromResponse(404, { status: 404, code: 'TEAM_NOT_FOUND' }))).toHaveProperty('page')
  })

  test('el resto, arriba, y sin Reintentar aunque sea pasajero', () => {
    expect(placeSyncError(errorFromResponse(504, { status: 504, code: 'FEDERATION_UNREACHABLE' }))).toEqual({
      banner: { message: 'La Federación no responde. Prueba otra vez en un rato.', code: 'FEDERATION_UNREACHABLE', retry: false },
    })
  })
})
