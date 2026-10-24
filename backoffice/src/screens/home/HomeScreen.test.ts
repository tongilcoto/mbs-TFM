import { fireEvent, render, screen, waitFor } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { primeVueOptions } from '../../theme/primevue'
import HomeScreen from './HomeScreen.vue'
import type { Season } from './seasons'

// Lo que añade la rebanada 2 a la portada (plan R2, §3.1): el botón «Dar de alta un equipo». El resto de la
// portada lo prueban sus escenarios.

function season(label: string, isCurrent = false): Season {
  const year = Number(label.slice(0, 4))
  return {
    id: `id-${year}`,
    label,
    startDate: `${year}-07-01`,
    endDate: `${year + 1}-06-30`,
    isCurrent,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  }
}

const aTeam = {
  seasonId: 'id-2026',
  competitions: [],
  team: {
    id: 'equipo',
    category: 'alevin',
    letter: 'A',
    gender: 'masculino',
    modality: 'futbol_11',
    isOwn: true,
    clubName: 'Celtic',
    displayName: 'Celtic Alevín A',
    createdAt: '2026-10-09T21:50:27Z',
    updatedAt: '2026-10-09T21:50:27Z',
  },
}

// El servidor de mentira: las temporadas y, de cualquiera, los equipos que diga la prueba y ninguna competición.
function fakeServer(seasons: Season[], registrations: unknown[]) {
  vi.stubGlobal('fetch', async (request: Request) => {
    const path = new URL(request.url).pathname
    if (path === '/api/v1/seasons') return Response.json(seasons)
    if (path.endsWith('/registrations')) return Response.json(registrations)
    if (path === '/api/v1/competitions') return Response.json([])
    throw new Error(`Petición no esperada: ${path}`)
  })
}

// Lo que recibe el formulario al abrirse desde la portada: la dirección y el estado de la navegación.
let opened: { path: string; state: unknown } | undefined

async function openHome(address = '/') {
  opened = undefined
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: HomeScreen },
      {
        path: '/equipos/nuevo',
        component: defineComponent({
          setup() {
            opened = { path: '/equipos/nuevo', state: router.options.history.state }
            return () => h('h1', 'Dar de alta un equipo')
          },
        }),
      },
    ],
  })
  await router.push(address)
  render(RouterView, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
  return router
}

const newTeamLink = () => screen.findByRole('link', { name: 'Dar de alta un equipo' })

afterEach(() => vi.unstubAllGlobals())

describe('«Dar de alta un equipo»', () => {
  test('con equipos, está junto al selector, y lleva al formulario con la temporada que se ve', async () => {
    fakeServer([season('2026/27', true), season('2025/26')], [aTeam])
    const router = await openHome('/?temporada=2025-26')
    await screen.findByRole('table')

    const link = await newTeamLink()
    expect(link).toHaveAttribute('href', '/equipos/nuevo')
    await fireEvent.click(link)

    await waitFor(() => expect(router.currentRoute.value.path).toBe('/equipos/nuevo'))
    expect(opened?.state).toMatchObject({ seasonLabel: '2025/26' })
  })

  test('el club sin temporadas: el mensaje, cómo empezar y el botón', async () => {
    fakeServer([], [])
    await openHome()

    expect(await screen.findByText('Todavía no hay ninguna temporada.', { exact: true })).toBeInTheDocument()
    expect(
      screen.getByText('Para empezar, da de alta el primer equipo. La temporada se crea desde el mismo formulario.'),
    ).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: 'Dar de alta un equipo' })).toHaveLength(1)
    await fireEvent.click(await newTeamLink())
    await waitFor(() => expect(opened?.path).toBe('/equipos/nuevo'))
    expect(opened?.state).not.toHaveProperty('seasonLabel')
  })

  test('la temporada sin equipos: el mensaje y, debajo, el botón, además del de junto al selector', async () => {
    fakeServer([season('2026/27', true)], [])
    await openHome()

    expect(await screen.findByText('No hay equipos en la temporada 2026/27.', { exact: true })).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: 'Dar de alta un equipo' })).toHaveLength(2)
  })
})

describe('ordenar la tabla (bloque T)', () => {
  const competitions = [
    { id: 'c-ok', seasonId: 'id-2026', modality: 'futbol_11', gender: 'masculino', ageCategory: 'cadete', divisionLabel: 'PRIMERA', groupLabel: 'Grupo 1', federationCompetitionId: '1', federationGroupId: '2', displayName: 'x', ingestionHealth: 'ok', createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z' },
    { id: 'c-mal', seasonId: 'id-2026', modality: 'futbol_11', gender: 'masculino', ageCategory: 'cadete', divisionLabel: 'SEGUNDA', groupLabel: 'Grupo 1', federationCompetitionId: '3', federationGroupId: '4', displayName: 'y', ingestionHealth: 'failing', createdAt: '2026-01-01T00:00:00Z', updatedAt: '2026-01-01T00:00:00Z' },
  ]
  const teamIn = (id: string, category: string, letter: string, competitionIds: string[]) => ({
    ...aTeam,
    competitions: competitionIds.map((competitionId) => ({ competitionId, federationTeamId: '1' })),
    team: { ...aTeam.team, id, category, letter, displayName: id },
  })
  // El orden del servidor: por edad. El alevín, al día; el cadete, con fallos.
  const registrations = [teamIn('alevin', 'alevin', 'A', ['c-ok']), teamIn('cadete', 'cadete', 'B', ['c-mal'])]

  function serverWithTeams() {
    vi.stubGlobal('fetch', async (request: Request) => {
      const path = new URL(request.url).pathname
      if (path === '/api/v1/seasons') return Response.json([season('2026/27', true), season('2025/26')])
      if (path.endsWith('/registrations')) return Response.json(registrations)
      if (path === '/api/v1/competitions') return Response.json(competitions)
      throw new Error(`Petición no esperada: ${path}`)
    })
  }

  const teamOrder = () => screen.getAllByRole('rowheader').map((cell) => cell.textContent?.trim())

  test('sin orden en la dirección, el del servidor', async () => {
    serverWithTeams()
    await openHome()
    await screen.findByRole('table')

    expect(teamOrder()).toEqual(['Alevín A', 'Cadete B'])
  })

  test('con ?orden=ingesta, de peor a mejor; y la cabecera lo dice', async () => {
    serverWithTeams()
    await openHome('/?orden=ingesta')
    await screen.findByRole('table')

    expect(teamOrder()).toEqual(['Cadete B', 'Alevín A'])
    expect(screen.getByRole('columnheader', { name: 'Ingesta' })).toHaveAttribute('aria-sort', 'ascending')
  })

  test('pinchar la cabecera pone el orden en la dirección, y «Atrás» vuelve al anterior', async () => {
    serverWithTeams()
    const router = await openHome('/?temporada=2026-27')
    await screen.findByRole('table')

    await fireEvent.click(screen.getByRole('button', { name: 'Ingesta' }))
    await waitFor(() => expect(router.currentRoute.value.query).toEqual({ temporada: '2026-27', orden: 'ingesta' }))
    expect(teamOrder()).toEqual(['Cadete B', 'Alevín A'])

    await fireEvent.click(screen.getByRole('button', { name: 'Ingesta' }))
    await waitFor(() => expect(router.currentRoute.value.query.orden).toBe('ingesta-inverso'))
    expect(teamOrder()).toEqual(['Alevín A', 'Cadete B'])

    await fireEvent.click(screen.getByRole('button', { name: 'Ingesta' }))
    await waitFor(() => expect(router.currentRoute.value.query).toEqual({ temporada: '2026-27' }))

    router.back()
    await waitFor(() => expect(router.currentRoute.value.query.orden).toBe('ingesta-inverso'))
  })

  test('cambiar de temporada conserva el orden', async () => {
    serverWithTeams()
    const router = await openHome('/?temporada=2026-27&orden=equipo-inverso')
    await screen.findByRole('table')

    await fireEvent.click(screen.getByRole('combobox', { name: 'Temporada' }))
    await fireEvent.mouseDown(await screen.findByRole('option', { name: '2025/26' }))

    await waitFor(() => expect(router.currentRoute.value.query).toEqual({ temporada: '2025-26', orden: 'equipo-inverso' }))
  })
})
