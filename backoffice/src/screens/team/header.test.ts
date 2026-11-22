import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import { competitionPath, notPlayingText, playerPath, positionIn, roundBoxIn, roundsToLookIn, standingsSource, tabPath, teamHeading } from './header'

type Team = components['schemas']['TeamResponse']
type Round = components['schemas']['RoundResponse']
type Standing = components['schemas']['StandingResponse']

const team: Team = {
  id: 'equipo',
  category: 'infantil',
  letter: 'A',
  gender: 'masculino',
  modality: 'futbol_11',
  isOwn: true,
  clubName: 'Celtic',
  displayName: 'Celtic Infantil A',
  createdAt: '2026-10-09T21:50:27Z',
  updatedAt: '2026-10-09T21:50:27Z',
}

function round(number: number, isCurrent = false): Round {
  return {
    id: `j${number}`,
    competitionId: 'liga',
    number,
    startDate: '2026-10-03',
    endDate: '2026-10-04',
    isCurrent,
    createdAt: '2026-10-09T21:50:27Z',
    updatedAt: '2026-10-09T21:50:27Z',
  }
}

function row(teamId: string, position: number): Standing {
  return {
    id: `fila-${teamId}`,
    competitionId: 'liga',
    roundId: 'j5',
    team: { teamId, displayName: teamId, shortDisplayName: teamId, nameWithLetter: teamId, isOwn: false },
    position,
    played: 5,
    won: 1,
    drawn: 0,
    lost: 4,
    goalsFor: 7,
    goalsAgainst: 13,
    points: 3,
    form: [],
    createdAt: '2026-10-09T21:50:27Z',
    updatedAt: '2026-10-09T21:50:27Z',
  }
}

describe('la cabecera de la ficha', () => {
  test('el título, con la categoría y la letra; debajo, el género y la modalidad', () => {
    expect(teamHeading(team)).toEqual({ title: 'Infantil A', subtitle: 'Masculino · Fútbol 11' })
  })

  test('el aviso de la temporada que no juega, con el nombre del club', () => {
    expect(notPlayingText(team, '2024/25')).toBe('Celtic Infantil A no jugó la temporada 2024/25.')
  })

  test('los caminos, con la temporada con guion', () => {
    expect(tabPath('resultados', '2025/26', 'equipo')).toBe('/temporadas/2025-26/equipos/equipo/resultados')
    expect(tabPath('plantilla', '2025/26', 'equipo')).toBe('/temporadas/2025-26/equipos/equipo/plantilla')
    expect(competitionPath('2025/26', 'liga')).toBe('/temporadas/2025-26/competiciones/liga')
    expect(playerPath('2025/26', 'fila')).toBe('/temporadas/2025-26/jugadores/fila')
  })
})

describe('dónde se busca la posición (§3.2)', () => {
  test('desde la jornada en curso hacia atrás, aunque lleguen desordenadas', () => {
    expect(roundsToLookIn([round(3), round(1), round(4), round(2, true)]).map((r) => r.number)).toEqual([2, 1])
  })

  test('sin jornada en curso, la competición ha terminado: desde la última', () => {
    expect(roundsToLookIn([round(1), round(3), round(2)]).map((r) => r.number)).toEqual([3, 2, 1])
  })

  test('sin jornadas, ninguna', () => {
    expect(roundsToLookIn([])).toEqual([])
  })
})

describe('el puesto en una clasificación', () => {
  test('el del equipo, y de cuántos', () => {
    expect(positionIn([row('otro', 1), row('equipo', 2), row('tercero', 3)], 'equipo')).toEqual({ position: 2, of: 3 })
  })

  test('sin él en la tabla, nada', () => {
    expect(positionIn([row('otro', 1)], 'equipo')).toBeUndefined()
  })
})

// De dónde sale la clasificación de una jornada (D-29, D-55; R6.19c).
describe('de dónde sale la clasificación', () => {
  // En curso la 5: la última clasificación es la de la 5 o, si aún no tiene tabla, la de la 4.
  const rounds = [round(1), round(2), round(3), round(4), round(5, true)]

  test('con la de cada jornada (la RFFM), todas de la Federación', () => {
    expect([1, 3, 5].map((n) => standingsSource(n, rounds, true))).toEqual(['Federación', 'Federación', 'Federación'])
  })

  test('sin ella, la última, de la Federación; las anteriores, calculadas', () => {
    expect([1, 3, 4, 5].map((n) => standingsSource(n, rounds, false))).toEqual(['Calculada', 'Calculada', 'Federación', 'Federación'])
  })

  test('sin ella y con la competición acabada, la última jornada, de la Federación', () => {
    const ended = [round(1), round(2), round(3)]
    expect([1, 2, 3].map((n) => standingsSource(n, ended, false))).toEqual(['Calculada', 'Federación', 'Federación'])
  })
})

// La jornada de la caja Posición, en su cuadro del color del resultado (R6.19f).
describe('el cuadro de la jornada de la caja Posición', () => {
  const withForm = (form: Standing['form']): Standing => ({ ...row('equipo', 2), form })

  test('el de esa jornada en la racha del equipo, con su resultado', () => {
    const table = [row('otro', 1), withForm([{ roundNumber: 5, outcome: 'victoria' }, { roundNumber: 4, outcome: 'derrota' }])]
    expect(roundBoxIn(table, 'equipo', 5)).toEqual({ round: 5, outcome: 'victoria', label: 'Victoria en la jornada 5' })
  })

  test('si descansó esa jornada, el descanso', () => {
    expect(roundBoxIn([withForm([{ roundNumber: 5, outcome: 'descanso' }])], 'equipo', 5)?.outcome).toBe('descanso')
  })

  test('sin esa jornada en su racha, o sin él en la tabla, nada', () => {
    expect(roundBoxIn([withForm([{ roundNumber: 4, outcome: 'empate' }])], 'equipo', 5)).toBeUndefined()
    expect(roundBoxIn([row('otro', 1)], 'equipo', 5)).toBeUndefined()
  })
})

