import { fireEvent, render, screen, waitFor, within } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { primeVueOptions } from '../../theme/primevue'
import TeamScreen from './TeamScreen.vue'

// La ficha del equipo: su cabecera, con sus estados (plan R4, §3.2). Lo demás lo prueban sus escenarios.

const TEAM = '11111111-1111-4111-8111-111111111111'

function season(label: string, isCurrent = false) {
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

const theTeam = {
  id: TEAM,
  category: 'cadete',
  letter: 'A',
  gender: 'masculino',
  modality: 'futbol_11',
  isOwn: true,
  clubName: 'Celtic',
  displayName: 'Celtic Cadete A',
  createdAt: '2026-10-09T21:50:27Z',
  updatedAt: '2026-10-09T21:50:27Z',
}

function competition(id: string, divisionLabel: string, ingestionHealth = 'ok') {
  return {
    id,
    seasonId: 'id-2026',
    modality: 'futbol_11',
    gender: 'masculino',
    ageCategory: 'cadete',
    divisionLabel,
    groupLabel: 'Grupo 2',
    federationCompetitionId: '1',
    federationGroupId: '2',
    displayName: 'x',
    ingestionHealth,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  }
}

const round = (competitionId: string, number: number, isCurrent = false) => ({
  id: `${competitionId}-j${number}`,
  competitionId,
  number,
  startDate: '2026-10-03',
  endDate: '2026-10-04',
  isCurrent,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
})

// Una tabla de `size` equipos con el nuestro en `position`.
function table(size: number, position: number) {
  return Array.from({ length: size }, (_, index) => ({
    id: `fila-${index}`,
    team: { teamId: index + 1 === position ? TEAM : `otro-${index}` },
    position: index + 1,
  }))
}

// El servidor de mentira. Lo que cada prueba cambia: el equipo, las temporadas, en qué temporada juega y con qué
// competiciones, el estado de su ingesta, sus jornadas (la 6 en curso) y las clasificaciones de cada jornada.
// Apunta lo que se le pidió; la pasada de ↻ espera a que la prueba la suelte.
function fakeServer(fields: Partial<typeof defaults> = {}) {
  const server = {
    ...defaults,
    ...fields,
    asked: [] as string[],
    finish: (() => {}) as (answer: Response) => void,
  }
  vi.stubGlobal('fetch', async (request: Request) => {
    const url = new URL(request.url)
    const path = url.pathname.replace('/api/v1', '')
    server.asked.push(`${request.method} ${path}${url.search}`)
    if (path === '/seasons') return Response.json(server.seasons)
    const registration = path.match(/^\/teams\/.+\/registrations\/(.+)$/)
    if (registration) {
      if (!server.playsIn.includes(registration[1]!)) return problem(404, 'TEAM_NOT_REGISTERED')
      return Response.json({
        team: server.team,
        seasonId: registration[1],
        competitions: server.competitions.map((c) => ({ competitionId: c.id, federationTeamId: '824' })),
      })
    }
    if (path === `/teams/${TEAM}`) return Response.json(server.team)
    if (path.startsWith('/teams/')) return problem(404, 'TEAM_NOT_FOUND')
    if (path === '/competitions') return Response.json(server.competitions)
    if (path === '/rounds') {
      const id = url.searchParams.get('competitionId')!
      return Response.json([1, 2, 3, 4, 5, 6, 7].map((n) => round(id, n, n === 6)))
    }
    if (path === '/standings') return Response.json(server.tables[url.searchParams.get('roundId')!] ?? [])
    if (path === '/matches') {
      if (server.matchesFail) return problem(503, 'DATABASE_UNAVAILABLE')
      const page = Number(url.searchParams.get('page'))
      const perPage = Number(url.searchParams.get('perPage'))
      const data = server.matches.slice((page - 1) * perPage, page * perPage)
      return Response.json({ page, perPage, total: server.matches.length, data })
    }
    if (path === '/ingestion-runs' && request.method === 'POST') return new Promise<Response>((resolve) => (server.finish = resolve))
    throw new Error(`Petición no esperada: ${request.method} ${path}`)
  })
  return server
}

const defaults = {
  team: theTeam as typeof theTeam,
  seasons: [season('2026/27', true), season('2025/26')],
  playsIn: ['id-2026'],
  competitions: [competition('liga', 'PREFERENTE CADETE')],
  // Jugadas hasta la 5; la 6, la en curso, sin tabla todavía.
  tables: { 'liga-j5': table(16, 13), 'liga-j4': table(16, 11) } as Record<string, unknown[]>,
  matches: [match('liga', 5, 2, 1), match('liga', 6)] as unknown[],
  matchesFail: false,
}

// Un partido del equipo en casa contra un rival; con marcador, jugado.
function match(competitionId: string, number: number, own?: number, other?: number) {
  const playedNow = own !== undefined
  return {
    id: `${competitionId}-p${number}`,
    competitionId,
    roundId: `${competitionId}-j${number}`,
    roundNumber: number,
    matchDate: '2026-10-24',
    isKickoffConfirmed: false,
    status: playedNow ? 'finalizado' : 'programado',
    home: {
      teamId: TEAM,
      nameWithLetter: 'Celtic Castilla A',
      score: own,
      standing: playedNow ? { position: 13, played: 5, won: 1, drawn: 0, lost: 4, goalsFor: 7, goalsAgainst: 13, points: 3 } : undefined,
    },
    away: { teamId: 'rival', nameWithLetter: 'COLEGIO EL PRADO A', score: other },
  }
}

const problem = (status: number, code: string) => Response.json({ type: 'about:blank', title: 'x', status, code }, { status })

// Lo que recibe la pantalla a la que se va: la dirección y el estado de la navegación.
let opened: { path: string; state: unknown } | undefined
function landing(title: string) {
  return defineComponent({
    setup() {
      opened = { path: router.currentRoute.value.fullPath, state: router.options.history.state }
      return () => h('h1', title)
    },
  })
}
let router: ReturnType<typeof createRouter>

async function openTeam(address = `/temporadas/2026-27/equipos/${TEAM}/resultados`) {
  opened = undefined
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: landing('Equipos') },
      { path: '/equipos/:id/federacion', component: landing('Sincronizar con la Federación') },
      { path: '/temporadas/:temporada/equipos/:id/resultados', component: TeamScreen },
      { path: '/equipos/:id', component: TeamScreen },
    ],
  })
  await router.push(address)
  render(RouterView, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
  return router
}

const box = (title: string) => screen.getByRole('region', { name: title })
const positionShown = () => waitFor(() => expect(box('Posición')).toHaveTextContent('13º'))
const relaunchButton = () =>
  screen.findByRole('button', { name: 'Volver a traer los datos de la Federación, PREFERENTE CADETE · Grupo 2' })

afterEach(() => {
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

describe('la cabecera de un equipo que ha jugado', () => {
  test('el título con su género y su modalidad, y las tres cajas', async () => {
    fakeServer()
    await openTeam()

    expect(await screen.findByRole('heading', { level: 1, name: 'Cadete A' })).toBeInTheDocument()
    expect(screen.getByText('Masculino · Fútbol 11')).toBeInTheDocument()
    expect(screen.getByRole('combobox', { name: 'Temporada' })).toHaveTextContent('2026/27')
    expect(within(box('Competición')).getByRole('link', { name: 'PREFERENTE CADETE · Grupo 2' })).toHaveAttribute(
      'href',
      '/temporadas/2026-27/competiciones/liga',
    )
    expect(box('Competición')).toHaveTextContent('Al día')
    expect(box('Posición')).toHaveTextContent('13º')
    expect(box('Posición')).toHaveTextContent('de 16 · tras la jornada 5')
  })

  test('la posición, de la jornada en curso; sin tabla, de la anterior, y ahí para', async () => {
    const server = fakeServer()
    await openTeam()
    await positionShown()

    expect(server.asked.filter((a) => a.startsWith('GET /standings'))).toEqual([
      'GET /standings?roundId=liga-j6',
      'GET /standings?roundId=liga-j5',
    ])
  })

  test('«← Equipos» vuelve a la portada en la misma temporada', async () => {
    fakeServer()
    await openTeam(`/temporadas/2025-26/equipos/${TEAM}/resultados`)
    await screen.findByRole('heading', { name: 'Cadete A' })

    expect(screen.getByRole('link', { name: '← Equipos' })).toHaveAttribute('href', '/?temporada=2025-26')
  })
})

describe('los otros estados de la cabecera', () => {
  test('mientras llega el equipo, «Cargando equipo…»', async () => {
    vi.stubGlobal('fetch', () => new Promise(() => {}))
    await openTeam()

    expect(await screen.findByRole('status')).toHaveTextContent('Cargando equipo…')
  })

  test('sincronizado sin jornadas jugadas: posición «—» y «aún no se ha jugado»', async () => {
    fakeServer({ tables: {} })
    await openTeam()

    await waitFor(() => expect(box('Posición')).toHaveTextContent('—'))
    expect(box('Posición')).toHaveTextContent('aún no se ha jugado')
    expect(box('Competición')).toHaveTextContent('PREFERENTE CADETE · Grupo 2')
  })

  test('inscrito sin sincronizar: «Sincronizar con la Federación», sin estado ni ↻, y posición «—»', async () => {
    fakeServer({ competitions: [] })
    await openTeam()

    const link = await within(await screen.findByRole('region', { name: 'Competición' })).findByRole('link', {
      name: 'Sincronizar con la Federación',
    })
    expect(screen.queryByRole('button', { name: /^Volver a traer/ })).not.toBeInTheDocument()
    expect(box('Posición')).toHaveTextContent('—')
    expect(box('Posición')).not.toHaveTextContent('aún no se ha jugado')

    await fireEvent.click(link)
    await waitFor(() => expect(opened?.path).toBe(`/equipos/${TEAM}/federacion`))
    expect(opened?.state).toMatchObject({ seasonLabel: '2026/27' })
  })

  test('una temporada en la que no juega: el aviso y el selector, sin las otras cajas', async () => {
    fakeServer()
    await openTeam(`/temporadas/2025-26/equipos/${TEAM}/resultados`)

    expect(await screen.findByText('Celtic Cadete A no jugó la temporada 2025/26.')).toBeInTheDocument()
    expect(screen.getByRole('combobox', { name: 'Temporada' })).toHaveTextContent('2025/26')
    expect(screen.queryByRole('region', { name: 'Competición' })).not.toBeInTheDocument()
  })

  test('una temporada que el club no tiene: el error, y el selector para cambiarla', async () => {
    fakeServer()
    await openTeam(`/temporadas/2019-20/equipos/${TEAM}/resultados`)

    expect(await screen.findByRole('alert')).toHaveTextContent('No hay ninguna temporada 2019/20')
    expect(screen.getByRole('combobox', { name: 'Temporada' })).toBeInTheDocument()
  })

  test.each([
    ['un equipo que no existe', '22222222-2222-4222-8222-222222222222', {}],
    ['un rival', TEAM, { team: { ...theTeam, isOwn: false } }],
    ['un código que no es un UUID', 'abc', {}],
  ])('%s: «No se ha encontrado el equipo» y el enlace a la portada', async (_, id, fields) => {
    fakeServer(fields)
    await openTeam(`/temporadas/2026-27/equipos/${id}/resultados`)

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado el equipo')
    expect(screen.getByRole('link', { name: 'Ir a la portada' })).toHaveAttribute('href', '/')
  })

  test('un error que puede ser pasajero, con «Reintentar»', async () => {
    const server = fakeServer()
    vi.stubGlobal('fetch', async (request: Request) =>
      new URL(request.url).pathname === '/api/v1/seasons' ? problem(503, 'DATABASE_UNAVAILABLE') : Response.json(server.team),
    )
    await openTeam()

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha podido conectar con el servidor')
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
  })
})

describe('la temporada', () => {
  test('sin temporada en la dirección, la en curso, puesta en la dirección', async () => {
    fakeServer()
    const router = await openTeam(`/equipos/${TEAM}`)

    await waitFor(() => expect(router.currentRoute.value.path).toBe(`/temporadas/2026-27/equipos/${TEAM}/resultados`))
    await positionShown()
  })

  test('el selector, con todas las temporadas del club, cambia la dirección', async () => {
    fakeServer()
    const router = await openTeam()
    await positionShown()

    await fireEvent.click(screen.getByRole('combobox', { name: 'Temporada' }))
    await fireEvent.mouseDown(await screen.findByRole('option', { name: '2025/26' }))

    await waitFor(() => expect(router.currentRoute.value.path).toBe(`/temporadas/2025-26/equipos/${TEAM}/resultados`))
    expect(await screen.findByText('Celtic Cadete A no jugó la temporada 2025/26.')).toBeInTheDocument()
  })
})

describe('con más de una competición (liga y copa)', () => {
  test('se elige en un selector, y la posición es la de la elegida', async () => {
    fakeServer({
      competitions: [competition('liga', 'PREFERENTE CADETE'), competition('copa', 'COPA CADETE')],
      tables: { 'liga-j5': table(16, 13), 'copa-j5': table(8, 2) },
    })
    await openTeam()
    await positionShown()

    await fireEvent.click(within(box('Competición')).getByRole('combobox', { name: 'Competición' }))
    await fireEvent.mouseDown(await screen.findByRole('option', { name: 'COPA CADETE · Grupo 2' }))

    await waitFor(() => expect(box('Posición')).toHaveTextContent('2º'))
    expect(box('Posición')).toHaveTextContent('de 8 · tras la jornada 5')
    expect(within(box('Competición')).getByRole('link', { name: 'Jornada y clasificación' })).toHaveAttribute(
      'href',
      '/temporadas/2026-27/competiciones/copa',
    )
  })
})

describe('volver a traer los datos desde la ficha (decisión 7)', () => {
  test('«En marcha» y bloqueado mientras; al acabar, la competición y la posición otra vez', async () => {
    const server = fakeServer({ competitions: [competition('liga', 'PREFERENTE CADETE', 'failing')] })
    await openTeam()
    await fireEvent.click(await relaunchButton())

    await waitFor(() => expect(server.asked).toContain('POST /ingestion-runs'))
    expect(box('Competición')).toHaveTextContent('En marcha')
    expect(box('Competición')).toHaveTextContent('La anterior tuvo fallos')
    expect(await relaunchButton()).toBeDisabled()

    server.competitions = [competition('liga', 'PREFERENTE CADETE', 'ok')]
    server.tables = { 'liga-j6': table(16, 9) }
    server.finish(Response.json({}))

    await waitFor(() => expect(box('Competición')).toHaveTextContent('Al día'))
    expect(box('Posición')).toHaveTextContent('9º')
    expect(await relaunchButton()).toBeEnabled()
    expect(screen.queryByText('Cargando equipo…')).not.toBeInTheDocument()
  })

  test('si falla, el aviso arriba con su texto y la competición', async () => {
    const server = fakeServer()
    await openTeam()
    await fireEvent.click(await relaunchButton())
    await waitFor(() => expect(server.asked).toContain('POST /ingestion-runs'))

    server.finish(problem(502, 'INGESTION_FAILED'))

    const alert = await screen.findByRole('alert')
    expect(alert).toHaveTextContent('No se han podido traer los datos de la Federación.')
    expect(alert).toHaveTextContent('Al volver a traer los datos de PREFERENTE CADETE · Grupo 2.')
  })
})

describe('mientras la ingesta está «En marcha», se refresca sola', () => {
  test('a los 10 s, la competición y la posición, sin «Cargando…»', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const server = fakeServer({ competitions: [competition('liga', 'PREFERENTE CADETE', 'pending')] })
    await openTeam()
    await waitFor(() => expect(box('Competición')).toHaveTextContent('En marcha'))

    server.competitions = [competition('liga', 'PREFERENTE CADETE', 'ok')]
    server.tables = { 'liga-j6': table(16, 10) }
    await vi.advanceTimersByTimeAsync(10_000)

    await waitFor(() => expect(box('Competición')).toHaveTextContent('Al día'))
    expect(box('Posición')).toHaveTextContent('10º')
    expect(screen.queryByText('Cargando equipo…')).not.toBeInTheDocument()
  })
})

describe('la pestaña Resultados (§3.3)', () => {
  const matchesTable = () => screen.findByRole('table', { name: 'Partidos de Cadete A en la temporada 2026/27' })

  test('la pestaña, con la etiqueta «Federación», y la tabla con un partido por fila', async () => {
    fakeServer()
    await openTeam()

    const table = await matchesTable()
    expect(screen.getByRole('link', { name: 'Resultados' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByText('Federación')).toBeInTheDocument()
    const rows = within(table).getAllByRole('row').slice(1)
    expect(rows).toHaveLength(2)
    expect(rows[0]).toHaveTextContent('Celtic Castilla A')
    expect(rows[0]).toHaveTextContent('2 - 1')
    expect(rows[1]).toHaveTextContent('por fijar')
  })

  test('el puesto de hoy de los partidos por jugar sale de la clasificación de la cabecera: ninguna petición más', async () => {
    const server = fakeServer()
    await openTeam()
    const table = await matchesTable()

    // El propio, 13º en la tabla de la jornada 5, que es la que encontró la cabecera.
    expect(within(table).getAllByRole('row')[2]).toHaveTextContent('13º')
    expect(server.asked.filter((a) => a.startsWith('GET /standings'))).toHaveLength(2)
  })

  test('☰ lleva a la jornada del partido en su competición', async () => {
    fakeServer()
    await openTeam()
    await matchesTable()

    expect(screen.getByRole('link', { name: 'Ver la jornada 5 y la clasificación' })).toHaveAttribute(
      'href',
      '/temporadas/2026-27/competiciones/liga?jornada=5',
    )
  })

  test('mientras llegan, «Cargando partidos…»; la cabecera ya está', async () => {
    fakeServer()
    const real = globalThis.fetch
    vi.stubGlobal('fetch', (request: Request) =>
      new URL(request.url).pathname === '/api/v1/matches' ? new Promise(() => {}) : real(request),
    )
    await openTeam()

    expect(await screen.findByText('Cargando partidos…')).toBeInTheDocument()
    expect(box('Posición')).toHaveTextContent('13º')
  })

  test('si fallan, el error con «Reintentar», y la cabecera se queda', async () => {
    const server = fakeServer({ matchesFail: true })
    await openTeam()

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha podido conectar con el servidor')
    expect(box('Posición')).toHaveTextContent('13º')

    server.matchesFail = false
    await fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(await matchesTable()).toBeInTheDocument()
  })

  test('sin sincronizar: «Este equipo aún no tiene partidos.» y el enlace para sincronizarlo', async () => {
    const server = fakeServer({ competitions: [] })
    await openTeam()

    expect(await screen.findByText('Este equipo aún no tiene partidos.')).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: 'Sincronizar con la Federación' })).toHaveLength(2)
    expect(server.asked.some((a) => a.startsWith('GET /matches'))).toBe(false)
  })

  test('sincronizado y sin partidos, con la ingesta en marcha: «Trayendo el calendario…»', async () => {
    fakeServer({ matches: [], competitions: [competition('liga', 'PREFERENTE CADETE', 'pending')], tables: {} })
    await openTeam()

    expect(await screen.findByText('Trayendo el calendario de la Federación…')).toBeInTheDocument()
  })

  test('sincronizado y sin partidos, con la ingesta parada: la Federación aún no los ha publicado', async () => {
    fakeServer({ matches: [], tables: {} })
    await openTeam()

    expect(await screen.findByText('La Federación aún no ha publicado partidos de este equipo.')).toBeInTheDocument()
  })

  test('al acabar la ingesta que estaba en marcha, los partidos salen solos', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    const server = fakeServer({ matches: [], competitions: [competition('liga', 'PREFERENTE CADETE', 'pending')], tables: {} })
    await openTeam()
    await screen.findByText('Trayendo el calendario de la Federación…')

    server.competitions = [competition('liga', 'PREFERENTE CADETE', 'ok')]
    server.matches = [match('liga', 1), match('liga', 2)]
    await vi.advanceTimersByTimeAsync(10_000)

    const table = await matchesTable()
    expect(within(table).getAllByRole('row').slice(1)).toHaveLength(2)
  })

  test('con liga y copa, solo los de la elegida', async () => {
    fakeServer({
      competitions: [competition('liga', 'PREFERENTE CADETE'), competition('copa', 'COPA CADETE')],
      tables: { 'liga-j5': table(16, 13), 'copa-j5': table(8, 2) },
      matches: [match('liga', 1, 2, 0), match('liga', 2), match('copa', 1, 0, 1)],
    })
    await openTeam()
    expect(within(await matchesTable()).getAllByRole('row').slice(1)).toHaveLength(2)

    await fireEvent.click(within(box('Competición')).getByRole('combobox', { name: 'Competición' }))
    await fireEvent.mouseDown(await screen.findByRole('option', { name: 'COPA CADETE · Grupo 2' }))

    await waitFor(async () => expect(within(await matchesTable()).getAllByRole('row').slice(1)).toHaveLength(1))
    expect(screen.getByRole('link', { name: 'Ver la jornada 1 y la clasificación' })).toHaveAttribute(
      'href',
      '/temporadas/2026-27/competiciones/copa?jornada=1',
    )
  })

  test('más de una página: las pide todas', async () => {
    const server = fakeServer({ matches: Array.from({ length: 101 }, (_, i) => match('liga', i + 1)) })
    await openTeam()

    await waitFor(async () => expect(within(await matchesTable()).getAllByRole('row').slice(1)).toHaveLength(101))
    expect(server.asked.filter((a) => a.startsWith('GET /matches'))).toEqual([
      `GET /matches?teamId=${TEAM}&seasonId=id-2026&page=1&perPage=100`,
      `GET /matches?teamId=${TEAM}&seasonId=id-2026&page=2&perPage=100`,
    ])
  })
})
