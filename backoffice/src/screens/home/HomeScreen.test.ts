import { fireEvent, render, screen, waitFor } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { primeVueOptions } from '../../theme/primevue'
import HomeScreen from './HomeScreen.vue'
import type { Season } from './seasons'

// Lo que añaden las rebanadas 2 y 3 a la portada: el botón «Dar de alta un equipo» (plan R2, §3.1) y adónde llevan
// las acciones de la fila (plan R3, §3.1). El resto de la portada lo prueban sus escenarios.

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

// El resumen de cada competición (D-113), vacío: el servidor siempre lo manda; estas pruebas no lo miran.
const noSummary = { position: null, form: [], lastMatch: null, nextMatch: null, nextOpponentPosition: null }

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

// Lo que recibe la pantalla a la que se va desde la portada: la dirección y el estado de la navegación.
let opened: { path: string; state: unknown } | undefined

// Una pantalla de mentira que apunta adónde se ha llegado y con qué.
function landing(title: string) {
  return defineComponent({
    setup() {
      opened = { path: router.currentRoute.value.path, state: router.options.history.state }
      return () => h('h1', title)
    },
  })
}
let router: ReturnType<typeof createRouter>

async function openHome(address = '/') {
  opened = undefined
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: HomeScreen },
      { path: '/equipos/nuevo', component: landing('Dar de alta un equipo') },
      { path: '/equipos/:id/federacion', component: landing('Sincronizar con la Federación') },
      { path: '/temporadas/:temporada/equipos/:id/resultados', component: landing('Resultados') },
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
    competitions: competitionIds.map((competitionId) => ({ competitionId, federationTeamId: '1', summary: noSummary })),
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

describe('las acciones de la fila (plan R3, §3.1)', () => {
  test('el icono lleva a sincronizar el equipo, con la temporada que se ve', async () => {
    fakeServer([season('2026/27', true), season('2025/26')], [aTeam])
    await openHome('/?temporada=2025-26')

    await fireEvent.click(await screen.findByRole('link', { name: 'Sincronizar con la Federación, Alevín A' }))

    await waitFor(() => expect(opened?.path).toBe('/equipos/equipo/federacion'))
    expect(opened?.state).toMatchObject({ seasonLabel: '2025/26' })
  })

  test('el enlace del equipo sin competición, igual', async () => {
    fakeServer([season('2026/27', true)], [aTeam])
    await openHome('/')

    await fireEvent.click(await screen.findByRole('link', { name: 'Sincronizar con la Federación' }))

    await waitFor(() => expect(opened?.path).toBe('/equipos/equipo/federacion'))
    expect(opened?.state).toMatchObject({ seasonLabel: '2026/27' })
  })
})

describe('el nombre del equipo (plan R4, §3.1)', () => {
  test('lleva a su ficha en la temporada que se ve', async () => {
    fakeServer([season('2026/27', true), season('2025/26')], [aTeam])
    await openHome('/?temporada=2025-26')

    expect(await screen.findByRole('link', { name: 'Alevín A' })).toHaveAttribute(
      'href',
      '/temporadas/2025-26/equipos/equipo/resultados',
    )
  })
})

// ── Volver a traer los datos con ↻ (plan R4, decisión 7) ──

describe('volver a traer los datos de una competición', () => {
  const liga = (ingestionHealth: string) => ({
    id: 'liga',
    seasonId: 'id-2026',
    modality: 'futbol_11',
    gender: 'masculino',
    ageCategory: 'alevin',
    divisionLabel: 'PRIMERA ALEVIN',
    groupLabel: 'Grupo 8',
    federationCompetitionId: '1',
    federationGroupId: '2',
    displayName: 'Liga',
    ingestionHealth,
    createdAt: '2026-10-09T21:50:27Z',
    updatedAt: '2026-10-09T21:50:27Z',
  })
  const inscribed = { ...aTeam, competitions: [{ competitionId: 'liga', summary: noSummary }] }

  // Las competiciones salen con `health`, que la prueba cambia; la pasada responde cuando la prueba la suelta
  // (`finish`), con lo que diga. Apunta lo que se le pidió.
  function serverWithRun(health: string) {
    const server: { health: string; competitionsAsked: number; runs: unknown[]; finish: (answer: Response) => void } = {
      health,
      competitionsAsked: 0,
      runs: [],
      finish: () => {},
    }
    vi.stubGlobal('fetch', async (request: Request) => {
      const path = new URL(request.url).pathname
      if (path === '/api/v1/seasons') return Response.json([season('2026/27', true)])
      if (path.endsWith('/registrations')) return Response.json([inscribed])
      if (path === '/api/v1/competitions') {
        server.competitionsAsked++
        return Response.json([liga(server.health)])
      }
      if (path === '/api/v1/ingestion-runs' && request.method === 'POST') {
        server.runs.push(await request.json())
        return new Promise<Response>((resolve) => (server.finish = resolve))
      }
      throw new Error(`Petición no esperada: ${request.method} ${path}`)
    })
    return server
  }
  const ingestion = () => screen.getAllByRole('cell')[5]!
  const relaunch = () => screen.findByRole('button', { name: 'Volver a traer los datos de la Federación, PRIMERA ALEVIN · Grupo 8' })
  const problem = (status: number, code: string) => Response.json({ type: 'about:blank', title: 'x', status, code }, { status })

  test('pide la pasada de esa competición; mientras, «En marcha» y bloqueado; al acabar, lo nuevo sin «Cargando…»', async () => {
    const server = serverWithRun('failing')
    await openHome('/')
    await fireEvent.click(await relaunch())

    await waitFor(() => expect(server.runs).toEqual([{ competitionIds: ['liga'] }]))
    expect(ingestion()).toHaveTextContent('En marcha')
    expect(ingestion()).toHaveTextContent('La anterior tuvo fallos')
    expect(await relaunch()).toBeDisabled()

    server.health = 'ok'
    server.finish(Response.json({}))

    await waitFor(() => expect(ingestion()).toHaveTextContent('Al día'))
    expect(server.competitionsAsked).toBe(2)
    expect(await relaunch()).toBeEnabled()
    expect(screen.queryByText('Cargando equipos…')).not.toBeInTheDocument()
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  test('si falla: el aviso arriba con su texto, su código y la competición, y la celda como quedó', async () => {
    const server = serverWithRun('ok')
    await openHome('/')
    await fireEvent.click(await relaunch())
    await waitFor(() => expect(server.runs).toHaveLength(1))

    server.health = 'failing'
    server.finish(problem(502, 'INGESTION_FAILED'))

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('No se han podido traer los datos de la Federación. Prueba otra vez en un rato.')
    expect(alert).toHaveTextContent('Al volver a traer los datos de PRIMERA ALEVIN · Grupo 8.')
    expect(alert).toHaveTextContent('Código: INGESTION_FAILED')
    await waitFor(() => expect(ingestion()).toHaveTextContent('Con fallos'))
    // La tabla sigue a la vista.
    expect(screen.getByRole('table')).toBeInTheDocument()
  })

  test('«Reintentar» vuelve a pedir la misma, y el aviso se va', async () => {
    const server = serverWithRun('ok')
    await openHome('/')
    await fireEvent.click(await relaunch())
    await waitFor(() => expect(server.runs).toHaveLength(1))
    server.finish(problem(502, 'INGESTION_FAILED'))

    await fireEvent.click(await screen.findByRole('button', { name: 'Reintentar' }))

    await waitFor(() => expect(server.runs).toHaveLength(2))
    expect(server.runs[1]).toEqual({ competitionIds: ['liga'] })
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  test('un error que no es pasajero, sin «Reintentar»: el ↻ de la celda sigue ahí', async () => {
    const server = serverWithRun('ok')
    await openHome('/')
    await fireEvent.click(await relaunch())
    await waitFor(() => expect(server.runs).toHaveLength(1))
    server.finish(problem(501, 'FEDERATION_ADAPTER_MISSING'))

    expect(await screen.findByRole('alert')).toHaveTextContent('Todavía no se puede sincronizar con la federación de este club.')
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
    await waitFor(async () => expect(await relaunch()).toBeEnabled())
  })
})

// ── El refresco (plan R3, decisión 5) ──

describe('la portada se refresca sola mientras algo está en marcha', () => {
  // Con un reloj de mentira que también avanza solo: así las esperas de Testing Library siguen funcionando.
  afterEach(() => vi.useRealTimers())

  const liga = (ingestionHealth: string) => ({
    id: 'liga',
    seasonId: 'id-2026',
    modality: 'futbol_11',
    gender: 'masculino',
    ageCategory: 'alevin',
    divisionLabel: 'PRIMERA ALEVIN',
    groupLabel: 'Grupo 8',
    federationCompetitionId: '1',
    federationGroupId: '2',
    displayName: 'Liga',
    ingestionHealth,
    createdAt: '2026-10-09T21:50:27Z',
    updatedAt: '2026-10-09T21:50:27Z',
  })
  const inscribed = { ...aTeam, competitions: [{ competitionId: 'liga', summary: noSummary }] }

  // Las competiciones, una respuesta por petición, en orden; la última se repite. Apunta cuántas se pidieron.
  function serverWith(answers: (() => Response)[]) {
    const asked = { competitions: 0, registrations: 0 }
    vi.stubGlobal('fetch', async (request: Request) => {
      const path = new URL(request.url).pathname
      if (path === '/api/v1/seasons') return Response.json([season('2026/27', true)])
      if (path.endsWith('/registrations')) {
        asked.registrations++
        return Response.json([inscribed])
      }
      if (path === '/api/v1/competitions') return answers[Math.min(asked.competitions++, answers.length - 1)]!()
      throw new Error(`Petición no esperada: ${path}`)
    })
    return asked
  }
  const json = (health: string) => () => Response.json([liga(health)])
  const ingestion = () => screen.getAllByRole('cell')[5]!

  test('«En marcha»: a los 10 s pide las competiciones otra vez, y la fila sale «Al día» sin «Cargando…»', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const asked = serverWith([json('pending'), json('ok')])
    await openHome('/')
    await waitFor(() => expect(ingestion()).toHaveTextContent('En marcha'))

    await vi.advanceTimersByTimeAsync(10_000)

    await waitFor(() => expect(ingestion()).toHaveTextContent('Al día'))
    expect(screen.queryByText('Cargando equipos…')).not.toBeInTheDocument()
    // Solo las competiciones: los equipos inscritos no cambian con una ingesta.
    expect(asked).toEqual({ competitions: 2, registrations: 1 })
  })

  test('sin nada en marcha, no vuelve a pedir nada', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const asked = serverWith([json('ok')])
    await openHome('/')
    await waitFor(() => expect(ingestion()).toHaveTextContent('Al día'))

    await vi.advanceTimersByTimeAsync(60_000)

    expect(asked.competitions).toBe(1)
  })

  test('al acabar, para', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const asked = serverWith([json('pending'), json('ok')])
    await openHome('/')
    await vi.advanceTimersByTimeAsync(10_000)
    await waitFor(() => expect(ingestion()).toHaveTextContent('Al día'))

    await vi.advanceTimersByTimeAsync(60_000)

    expect(asked.competitions).toBe(2)
  })

  test('un refresco que falla no pinta un error: se deja lo que había y se prueba en el siguiente', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const asked = serverWith([json('pending'), () => Response.json({ code: 'INTERNAL', status: 500 }, { status: 500 }), json('ok')])
    await openHome('/')
    await waitFor(() => expect(ingestion()).toHaveTextContent('En marcha'))

    await vi.advanceTimersByTimeAsync(10_000)
    await waitFor(() => expect(asked.competitions).toBe(2))
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
    expect(ingestion()).toHaveTextContent('En marcha')

    await vi.advanceTimersByTimeAsync(10_000)
    await waitFor(() => expect(ingestion()).toHaveTextContent('Al día'))
  })

  test('el foco se queda donde estaba: la fila es la misma', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    serverWith([json('pending'), json('ok')])
    await openHome('/')
    const action = await screen.findByRole('link', { name: /^Sincronizar otra competición, / })
    action.focus()

    await vi.advanceTimersByTimeAsync(10_000)
    await waitFor(() => expect(ingestion()).toHaveTextContent('Al día'))

    expect(action).toHaveFocus()
  })
})

