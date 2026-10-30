import { describe, expect, test } from 'vitest'
import type { components } from '../../api/schema'
import { competitionPath, notPlayingText, positionIn, resultsPath, roundsToLookIn, teamHeading } from './header'

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
    expect(resultsPath('2025/26', 'equipo')).toBe('/temporadas/2025-26/equipos/equipo/resultados')
    expect(competitionPath('2025/26', 'liga')).toBe('/temporadas/2025-26/competiciones/liga')
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
