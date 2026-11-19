import { fireEvent, render, screen, waitFor, within } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { club } from '../../club'
import { notice } from '../../notice'
import { primeVueOptions } from '../../theme/primevue'
import TeamScreen from './TeamScreen.vue'

// La ficha del equipo: su cabecera, con sus estados (plan R4, §3.2). Lo demás lo prueban sus escenarios.

const TEAM = '11111111-1111-4111-8111-111111111111'

function season(label: string, isCurrent = false): Record<string, unknown> {
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
    if (path.endsWith('/roster-sync') && request.method === 'POST') return server.syncAnswer(server)
    const registration = path.match(/^\/teams\/.+\/registrations\/(.+)$/)
    if (registration) {
      if (!server.playsIn.includes(registration[1]!)) return problem(404, 'TEAM_NOT_REGISTERED')
      return Response.json({
        team: server.team,
        seasonId: registration[1],
        competitions: server.competitions.map((c) => ({ competitionId: c.id, federationTeamId: server.linked ? '824' : null })),
        rosterSyncedAt: server.rosterSyncedAt,
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
    const removing = path.match(/^\/players\/([^/]+)$/)
    if (removing && request.method === 'DELETE') {
      if (server.removeFails) return problem(503, 'DATABASE_UNAVAILABLE')
      server.players = server.players.filter((p) => (p as { id: string }).id !== removing[1])
      return new Response(null, { status: 204 })
    }
    if (path === '/players' && request.method === 'POST') {
      const body = await request.json()
      const created = player('nuevo', body.fullName, body.shirtNumber)
      server.players = [...server.players, created]
      return Response.json(created, { status: 201 })
    }
    if (path === '/players') {
      if (server.playersFail) return problem(503, 'DATABASE_UNAVAILABLE')
      return Response.json(server.players)
    }
    if (path === '/player-profiles') return Response.json([])
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
  players: [player('a', 'MARCOS DÍAZ', 1), player('b', 'JUAN CARLOS GARCÍA DE LA FUENTE', null)] as unknown[],
  playersFail: false,
  removeFails: false,
  // La sincronización de la plantilla (R6.16): la fecha de la inscripción, si el equipo está enganchado, y qué
  // contesta el servidor al sincronizar (por omisión, todos federados y un resumen).
  rosterSyncedAt: null as string | null,
  linked: true,
  syncAnswer: (server: { players: unknown[] }): Response | Promise<Response> => {
    server.players = server.players.map((p) => ({ ...(p as object), federated: true, lastListedAt: SYNCED_AT }))
    return Response.json({
      syncedAt: SYNCED_AT,
      added: 0,
      alreadyInRoster: 2,
      withoutBirthYear: 0,
      deletedInClub: 0,
      duplicateName: [],
      inOtherTeam: [],
      invalidName: ['TORRES, IÑAKI/'],
      namesDictionary: { found: true, skippedLines: [] },
    })
  },
}

const SYNCED_AT = '2026-11-17T17:30:00Z'

// Un jugador de la plantilla, con su dorsal o sin él; sin foto, salvo que se le dé.
function player(id: string, fullName: string, shirtNumber: number | null, photoUrl: string | null = null) {
  return {
    id,
    profileId: `perfil-${id}`,
    teamId: TEAM,
    seasonId: 'id-2026',
    fullName,
    birthYear: 2011,
    shirtNumber,
    position: shirtNumber === 1 ? 'portero' : null,
    federated: null,
    lastListedAt: null,
    photoUrl,
    createdAt: '2026-11-16T00:00:00Z',
    updatedAt: '2026-11-16T00:00:00Z',
  }
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
      { path: '/temporadas/:temporada/equipos/:id/plantilla', component: TeamScreen, meta: { title: 'Plantilla', tab: 'plantilla' } },
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
    // Sin marca de dónde sale: es siempre la última clasificación, y esa siempre es de la Federación (R6.19c).
    expect(within(box('Posición')).queryByText('Federación')).not.toBeInTheDocument()
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

  // Sin la etiqueta «Federación» junto a las pestañas: toda la web es de la Federación (R6.19c).
  test('la pestaña, sin la etiqueta «Federación», y la tabla con un partido por fila', async () => {
    fakeServer()
    await openTeam()

    const table = await matchesTable()
    expect(screen.getByRole('link', { name: 'Resultados' })).toHaveAttribute('aria-current', 'page')
    expect(within(screen.getByRole('navigation', { name: 'Secciones del equipo' }).parentElement!).queryByText('Federación'))
      .not.toBeInTheDocument()
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

describe('la pestaña Plantilla (plan R6, §3)', () => {
  const rosterTable = (season = '2026/27') => screen.findByRole('table', { name: `Plantilla de Cadete A en la temporada ${season}` })
  const plantilla = `/temporadas/2026-27/equipos/${TEAM}/plantilla`

  test('la pestaña, sin la etiqueta «Federación», y un jugador por fila, como llegan', async () => {
    fakeServer()
    await openTeam(plantilla)

    const table = await rosterTable()
    expect(screen.getByRole('link', { name: 'Plantilla' })).toHaveAttribute('aria-current', 'page')
    expect(screen.getByRole('link', { name: 'Resultados' })).not.toHaveAttribute('aria-current')
    expect(within(screen.getByRole('navigation', { name: 'Secciones del equipo' }).parentElement!).queryByText('Federación'))
      .not.toBeInTheDocument()
    const rows = within(table).getAllByRole('row').slice(1)
    expect(rows).toHaveLength(2)
    expect(rows[0]).toHaveTextContent('1')
    expect(rows[0]).toHaveTextContent('Marcos Díaz')
    expect(rows[0]).toHaveTextContent('Portero')
    expect(rows[0]).toHaveTextContent('2011')
    expect(rows[1]).toHaveTextContent('Juan Carlos García de la Fuente')
    expect(rows[1]).toHaveTextContent('—')
  })

  test('el nombre lleva a su ficha, en la misma temporada', async () => {
    fakeServer()
    await openTeam(plantilla)

    expect(within(await rosterTable()).getByRole('link', { name: 'Marcos Díaz' })).toHaveAttribute('href', '/temporadas/2026-27/jugadores/a')
  })

  test('la foto, con el nombre del jugador; sin foto, sus iniciales', async () => {
    fakeServer({ players: [player('a', 'MARCOS DÍAZ', 1, '/api/v1/player-photos/a.jpg'), player('b', 'ANA RUIZ', 2)] })
    await openTeam(plantilla)

    const rows = within(await rosterTable()).getAllByRole('row').slice(1)
    expect(within(rows[0]!).getByRole('img', { name: 'Marcos Díaz' })).toHaveAttribute('src', '/api/v1/player-photos/a.jpg')
    expect(within(rows[1]!).getByText('AR')).toBeInTheDocument()
  })

  test('pide la plantilla de ese equipo y esa temporada, y no los partidos', async () => {
    const server = fakeServer()
    await openTeam(plantilla)
    await rosterTable()

    expect(server.asked).toContain(`GET /players?teamId=${TEAM}&seasonId=id-2026`)
    expect(server.asked.some((a) => a.startsWith('GET /matches'))).toBe(false)
  })

  test('la pestaña Resultados no pide la plantilla', async () => {
    const server = fakeServer()
    await openTeam()
    await screen.findByRole('table', { name: 'Partidos de Cadete A en la temporada 2026/27' })

    expect(server.asked.some((a) => a.startsWith('GET /players'))).toBe(false)
  })

  test('de Resultados a Plantilla, la cabecera no se vuelve a pedir', async () => {
    const server = fakeServer()
    const router = await openTeam()
    await positionShown()

    await fireEvent.click(screen.getByRole('link', { name: 'Plantilla' }))

    await rosterTable()
    expect(router.currentRoute.value.path).toBe(plantilla)
    expect(server.asked.filter((a) => a === `GET /teams/${TEAM}`)).toHaveLength(1)
    expect(screen.queryByText('Cargando equipo…')).not.toBeInTheDocument()
  })

  test('al cambiar de temporada, se sigue en Plantilla', async () => {
    fakeServer({ playsIn: ['id-2026', 'id-2025'] })
    const router = await openTeam(plantilla)
    await rosterTable()

    await fireEvent.click(screen.getByRole('combobox', { name: 'Temporada' }))
    await fireEvent.mouseDown(await screen.findByRole('option', { name: '2025/26' }))

    await waitFor(() => expect(router.currentRoute.value.path).toBe(`/temporadas/2025-26/equipos/${TEAM}/plantilla`))
    expect(await rosterTable('2025/26')).toBeInTheDocument()
  })

  test('sin jugadores, lo dice con la temporada', async () => {
    fakeServer({ players: [] })
    await openTeam(plantilla)

    expect(await screen.findByText('Este equipo aún no tiene jugadores en 2026/27.')).toBeInTheDocument()
    expect(screen.queryByRole('table')).not.toBeInTheDocument()
  })

  test('mientras llegan, «Cargando jugadores…»; la cabecera ya está', async () => {
    fakeServer()
    const real = globalThis.fetch
    vi.stubGlobal('fetch', (request: Request) =>
      new URL(request.url).pathname === '/api/v1/players' ? new Promise(() => {}) : real(request),
    )
    await openTeam(plantilla)

    expect(await screen.findByText('Cargando jugadores…')).toBeInTheDocument()
    expect(box('Posición')).toHaveTextContent('13º')
  })

  test('si fallan, el error con «Reintentar», y la cabecera se queda', async () => {
    const server = fakeServer({ playersFail: true })
    await openTeam(plantilla)

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha podido conectar con el servidor')
    expect(box('Posición')).toHaveTextContent('13º')

    server.playersFail = false
    await fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))
    expect(await rosterTable()).toBeInTheDocument()
  })

  describe('dar de alta un jugador (R6.12)', () => {
    test('«Dar de alta un jugador» abre el diálogo encima de la plantilla', async () => {
      fakeServer()
      await openTeam(plantilla)
      await rosterTable()

      await fireEvent.click(screen.getByRole('button', { name: 'Dar de alta un jugador' }))

      expect(await screen.findByRole('dialog', { name: 'Dar de alta un jugador en Cadete A, 2026/27' })).toBeInTheDocument()
    })

    test('sin jugadores, también se ofrece', async () => {
      fakeServer({ players: [] })
      await openTeam(plantilla)

      await screen.findByText('Este equipo aún no tiene jugadores en 2026/27.')
      expect(screen.getByRole('button', { name: 'Dar de alta un jugador' })).toBeInTheDocument()
    })

    test('en una temporada archivada, no', async () => {
      fakeServer({ seasons: [season('2026/27', true), { ...season('2025/26'), archivedAt: '2026-08-01T00:00:00Z' }], playsIn: ['id-2025'] })
      await openTeam(`/temporadas/2025-26/equipos/${TEAM}/plantilla`)

      await rosterTable('2025/26')
      expect(screen.queryByRole('button', { name: 'Dar de alta un jugador' })).not.toBeInTheDocument()
    })

    test('en una temporada pasada sin archivar, tampoco (decisión 4 de R6.14)', async () => {
      fakeServer({ seasons: [season('2026/27', true), season('2025/26')], playsIn: ['id-2025'] })
      await openTeam(`/temporadas/2025-26/equipos/${TEAM}/plantilla`)

      await rosterTable('2025/26')
      expect(screen.queryByRole('button', { name: 'Dar de alta un jugador' })).not.toBeInTheDocument()
    })

    test('al guardar, el diálogo se cierra, la plantilla trae al nuevo y el aviso dice «Guardado»', async () => {
      fakeServer()
      await openTeam(plantilla)
      await rosterTable()
      await fireEvent.click(screen.getByRole('button', { name: 'Dar de alta un jugador' }))
      const box = await screen.findByRole('combobox', { name: /Nombre y apellidos/ })
      await fireEvent.update(box, 'Ana Ruiz')
      await fireEvent.input(box)
      await fireEvent.click(await screen.findByRole('option', { name: /como jugador nuevo/ }, { timeout: 2000 }))
      await fireEvent.update(screen.getByRole('textbox', { name: /Año de nacimiento/ }), '2012')
      await fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))

      await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
      await waitFor(async () => expect(within(await rosterTable()).getAllByRole('row').slice(1)).toHaveLength(3))
      expect(notice.value).toBe('Guardado')
    })
  })

  describe('corregir un jugador (R6.12)', () => {
    test('✎ de una fila abre el diálogo de corregir con sus datos', async () => {
      fakeServer()
      await openTeam(plantilla)
      await rosterTable()

      await fireEvent.click(screen.getByRole('button', { name: 'Corregir, Marcos Díaz' }))

      const dialog = await screen.findByRole('dialog', { name: 'Corregir a Marcos Díaz' })
      expect(within(dialog).getByRole('textbox', { name: 'Dorsal' })).toHaveValue('1')
    })

    test('en una temporada archivada, las filas no tienen acciones', async () => {
      fakeServer({ seasons: [season('2026/27', true), { ...season('2025/26'), archivedAt: '2026-08-01T00:00:00Z' }], playsIn: ['id-2025'] })
      await openTeam(`/temporadas/2025-26/equipos/${TEAM}/plantilla`)

      await rosterTable('2025/26')
      expect(screen.queryByRole('button', { name: /^Corregir/ })).not.toBeInTheDocument()
      expect(screen.queryByRole('columnheader', { name: 'Acciones' })).not.toBeInTheDocument()
    })

    test('en una temporada pasada sin archivar, tampoco', async () => {
      fakeServer({ seasons: [season('2026/27', true), season('2025/26')], playsIn: ['id-2025'] })
      await openTeam(`/temporadas/2025-26/equipos/${TEAM}/plantilla`)

      await rosterTable('2025/26')
      expect(screen.queryByRole('button', { name: /^Corregir/ })).not.toBeInTheDocument()
    })
  })

  describe('dar de baja a un jugador (R6.12)', () => {
    const confirmation = () => screen.findByRole('dialog', { name: 'Dar de baja' })

    test('🗑 pide confirmación, con su nombre y su equipo, y dice qué pasa', async () => {
      fakeServer()
      await openTeam(plantilla)
      await rosterTable()

      await fireEvent.click(screen.getByRole('button', { name: 'Dar de baja, Marcos Díaz' }))

      const dialog = await confirmation()
      expect(dialog).toHaveTextContent('¿Dar de baja a Marcos Díaz del Cadete A?')
      expect(dialog).toHaveTextContent('Sus goles y tarjetas siguen contando para el equipo.')
      expect(dialog).toHaveTextContent('Sincronizar con la Federación no lo volverá a añadir.')
      await waitFor(() => expect(within(dialog).getByRole('button', { name: 'Cancelar' })).toHaveFocus())
    })

    test('confirmar lo quita de la plantilla, con el aviso «Dado de baja»', async () => {
      const server = fakeServer()
      await openTeam(plantilla)
      await rosterTable()
      await fireEvent.click(screen.getByRole('button', { name: 'Dar de baja, Marcos Díaz' }))
      await fireEvent.click(within(await confirmation()).getByRole('button', { name: 'Dar de baja' }))

      await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
      expect(server.asked).toContain('DELETE /players/a')
      await waitFor(async () => expect(within(await rosterTable()).queryByText('Marcos Díaz')).not.toBeInTheDocument())
      expect(notice.value).toBe('Dado de baja')
    })

    test('cancelar no la hace', async () => {
      const server = fakeServer()
      await openTeam(plantilla)
      await rosterTable()
      await fireEvent.click(screen.getByRole('button', { name: 'Dar de baja, Marcos Díaz' }))
      await fireEvent.click(within(await confirmation()).getByRole('button', { name: 'Cancelar' }))

      await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
      expect(server.asked.some((a) => a.startsWith('DELETE'))).toBe(false)
      expect(within(await rosterTable()).getByText('Marcos Díaz')).toBeInTheDocument()
    })

    test('si falla, lo dice en la confirmación, que sigue abierta', async () => {
      fakeServer({ removeFails: true })
      await openTeam(plantilla)
      await rosterTable()
      await fireEvent.click(screen.getByRole('button', { name: 'Dar de baja, Marcos Díaz' }))
      await fireEvent.click(within(await confirmation()).getByRole('button', { name: 'Dar de baja' }))

      expect(await within(await confirmation()).findByRole('alert')).toHaveTextContent('No se ha podido conectar con el servidor')
    })

    test('en una temporada archivada, sin 🗑', async () => {
      fakeServer({ seasons: [season('2026/27', true), { ...season('2025/26'), archivedAt: '2026-08-01T00:00:00Z' }], playsIn: ['id-2025'] })
      await openTeam(`/temporadas/2025-26/equipos/${TEAM}/plantilla`)

      await rosterTable('2025/26')
      expect(screen.queryByRole('button', { name: /^Dar de baja/ })).not.toBeInTheDocument()
    })
  })
})

describe('sincronizar la plantilla con la Federación (R6.16)', () => {
  const rosterTable = () => screen.findByRole('table', { name: 'Plantilla de Cadete A en la temporada 2026/27' })
  const plantilla = `/temporadas/2026-27/equipos/${TEAM}/plantilla`
  const syncButton = () => screen.queryByRole('button', { name: 'Sincronizar con la Federación' })
  const withRoster = (provides = true) => (club.value = { federationProvidesTeamRoster: provides } as typeof club.value)

  afterEach(() => (club.value = undefined))

  test('en la temporada en curso, con el equipo enganchado, se ofrece, y dice que todavía no se ha hecho', async () => {
    withRoster()
    fakeServer()
    await openTeam(plantilla)

    await rosterTable()
    expect(syncButton()).toBeInTheDocument()
    expect(screen.getByText('Todavía no se ha sincronizado con la Federación')).toBeInTheDocument()
  })

  test('con una federación que no publica plantillas, no se ofrece', async () => {
    withRoster(false)
    fakeServer()
    await openTeam(plantilla)

    await rosterTable()
    expect(syncButton()).not.toBeInTheDocument()
  })

  test('con el equipo sin enganchar esa temporada, no se ofrece', async () => {
    withRoster()
    fakeServer({ linked: false })
    await openTeam(plantilla)

    await rosterTable()
    expect(syncButton()).not.toBeInTheDocument()
  })

  test('en una temporada pasada, no se ofrece', async () => {
    withRoster()
    fakeServer({ playsIn: ['id-2025'] })
    await openTeam(`/temporadas/2025-26/equipos/${TEAM}/plantilla`)

    await screen.findByRole('table', { name: 'Plantilla de Cadete A en la temporada 2025/26' })
    expect(syncButton()).not.toBeInTheDocument()
  })

  test('sin jugadores, también se ofrece', async () => {
    withRoster()
    fakeServer({ players: [] })
    await openTeam(plantilla)

    await screen.findByText('Este equipo aún no tiene jugadores en 2026/27.')
    expect(syncButton()).toBeInTheDocument()
  })

  test('junto al botón, la última sincronización', async () => {
    withRoster()
    fakeServer({ rosterSyncedAt: '2026-11-10T09:05:00Z' })
    await openTeam(plantilla)

    await rosterTable()
    expect(screen.getByText(/^Última sincronización: 10\/11\/2026 \d\d:05$/)).toBeInTheDocument()
  })

  test('mientras sincroniza, el botón dice «Sincronizando…» y no se puede pulsar', async () => {
    withRoster()
    let answer!: (response: Response) => void
    fakeServer({ syncAnswer: () => new Promise<Response>((resolve) => (answer = resolve)) })
    await openTeam(plantilla)
    await rosterTable()

    await fireEvent.click(syncButton()!)

    expect(await screen.findByRole('button', { name: 'Sincronizando…' })).toBeDisabled()
    answer(problem(504, 'FEDERATION_UNREACHABLE'))
    expect(await screen.findByRole('button', { name: 'Sincronizar con la Federación' })).toBeEnabled()
  })

  test('al acabar, el resumen encima de la tabla, la fecha nueva y cada fila «Federado»', async () => {
    withRoster()
    fakeServer()
    await openTeam(plantilla)
    await rosterTable()

    await fireEvent.click(syncButton()!)

    const status = await screen.findByText('Sincronizada con la Federación')
    const summary = status.closest('[role="status"]')!
    expect(summary).toHaveTextContent('0 añadidos y 2 que ya estaban.')
    expect(summary).toHaveTextContent('para darlo de alta a mano: «TORRES, IÑAKI/».')
    expect(screen.getByText(/^Última sincronización: 17\/11\/2026/)).toBeInTheDocument()
    await waitFor(async () => expect(within(await rosterTable()).getAllByText('Federado')).toHaveLength(2))
  })

  test('el resumen se cierra con ✕', async () => {
    withRoster()
    fakeServer()
    await openTeam(plantilla)
    await rosterTable()
    await fireEvent.click(syncButton()!)
    await screen.findByText('Sincronizada con la Federación')

    await fireEvent.click(screen.getByRole('button', { name: 'Cerrar el resumen' }))

    expect(screen.queryByText('Sincronizada con la Federación')).not.toBeInTheDocument()
  })

  test('si la Federación falla, el aviso en la caja, como alerta, y la plantilla como estaba', async () => {
    withRoster()
    fakeServer({ syncAnswer: () => problem(502, 'FEDERATION_UNEXPECTED_STATUS') })
    await openTeam(plantilla)
    await rosterTable()

    await fireEvent.click(syncButton()!)

    const alert = await screen.findByText('La Federación ha respondido con un error. Prueba otra vez en un rato.')
    expect(alert.closest('[role="alert"]')).toHaveTextContent('Código: FEDERATION_UNEXPECTED_STATUS')
    expect(within(await rosterTable()).getAllByRole('row').slice(1)).toHaveLength(2)
    expect(within(await rosterTable()).queryByText('Federado')).not.toBeInTheDocument()
    expect(syncButton()).toBeEnabled()
  })

  test('la fecha nueva se queda al ir a Resultados y volver', async () => {
    withRoster()
    fakeServer()
    const router = await openTeam(plantilla)
    await rosterTable()
    await fireEvent.click(syncButton()!)
    await screen.findByText('Sincronizada con la Federación')

    await router.push(`/temporadas/2026-27/equipos/${TEAM}/resultados`)
    await router.push(plantilla)

    await rosterTable()
    expect(screen.getByText(/^Última sincronización: 17\/11\/2026/)).toBeInTheDocument()
    expect(screen.queryByText('Sincronizada con la Federación')).not.toBeInTheDocument()
  })
})
