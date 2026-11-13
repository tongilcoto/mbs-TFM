import { fireEvent, render, screen, waitFor, within } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createRouter, createWebHistory, RouterView } from 'vue-router'
import { primeVueOptions } from '../../theme/primevue'
import CompetitionScreen from './CompetitionScreen.vue'

// La pantalla de jornada y clasificación (plan R4, §3.4). Lo demás lo prueban sus escenarios.

const LIGA = '33333333-3333-4333-8333-333333333333'

const season = {
  id: 'id-2026',
  label: '2026/27',
  startDate: '2026-07-01',
  endDate: '2027-06-30',
  isCurrent: true,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
}

const competition = {
  id: LIGA,
  seasonId: 'id-2026',
  modality: 'futbol_11',
  gender: 'masculino',
  ageCategory: 'cadete',
  divisionLabel: 'PREFERENTE CADETE',
  groupLabel: 'Grupo 2',
  federationCompetitionId: '1',
  federationGroupId: '2',
  displayName: 'x',
  ingestionHealth: 'ok',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
}

// Tres jornadas; la 2, en curso.
const rounds = [1, 2, 3].map((number) => ({
  id: `j${number}`,
  competitionId: LIGA,
  number,
  startDate: `2026-10-0${number}`,
  endDate: `2026-10-0${number + 1}`,
  isCurrent: number === 2,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
}))

const side = (name: string, isOwn = false, score?: number) => ({ teamId: name, nameWithLetter: name, isOwn, score })

// Un partido por jornada, el del club; jugado en la 1.
function matchOf(roundId: string) {
  const played = roundId === 'j1'
  return {
    id: `p-${roundId}`,
    competitionId: LIGA,
    roundId,
    roundNumber: Number(roundId.slice(1)),
    matchDate: '2026-10-03',
    kickoffTime: '12:00',
    status: played ? 'finalizado' : 'programado',
    home: side('Celtic Castilla A', true, played ? 2 : undefined),
    away: side('COLEGIO EL PRADO A', false, played ? 1 : undefined),
  }
}

const standingRow = (position: number, name: string, isOwn = false) => ({
  position,
  previousPosition: null,
  team: side(name, isOwn),
  played: 1,
  won: 1,
  drawn: 0,
  lost: 0,
  goalsFor: 2,
  goalsAgainst: 1,
  points: 3,
  form: [{ roundNumber: 1, outcome: 'victoria' }],
})

// El servidor de mentira. Solo la jornada 1 tiene clasificación. Apunta lo que se le pidió.
function fakeServer(fields: { rounds?: unknown[]; failStandings?: boolean; noTables?: boolean } = {}) {
  const asked: string[] = []
  vi.stubGlobal('fetch', async (request: Request) => {
    const url = new URL(request.url)
    const path = url.pathname.replace('/api/v1', '')
    asked.push(`${path}${url.search}`)
    if (path === '/seasons') return Response.json([season])
    if (path === '/competitions') return Response.json([competition])
    if (path === '/rounds') {
      return url.searchParams.get('competitionId') === LIGA
        ? Response.json(fields.rounds ?? rounds)
        : Response.json({ code: 'COMPETITION_NOT_FOUND', status: 404 }, { status: 404 })
    }
    if (path === '/matches') {
      const data = [matchOf(url.searchParams.get('roundId')!)]
      return Response.json({ page: 1, perPage: 100, total: 1, data })
    }
    if (path === '/standings') {
      if (fields.failStandings) return Response.json({ code: 'DATABASE_UNAVAILABLE', status: 503 }, { status: 503 })
      return Response.json(
        url.searchParams.get('roundId') === 'j1' && !fields.noTables ? [standingRow(2, 'COLEGIO EL PRADO A'), standingRow(1, 'Celtic Castilla A', true)] : [],
      )
    }
    throw new Error(`Petición no esperada: ${path}`)
  })
  return asked
}

let router: ReturnType<typeof createRouter>

// Una pantalla de mentira, para tener de dónde venir.
function elsewhere(title: string) {
  return defineComponent({ setup: () => () => h('h1', title) })
}

async function openCompetition(address = `/temporadas/2026-27/competiciones/${LIGA}`, from?: string) {
  // Cada prueba, como una visita nueva que entra por `from` o, sin él, por la dirección de la competición. Antes de
  // crear el router, que lee el historial al nacer.
  window.history.replaceState(null, '', from ?? address)
  // El historial del navegador (el de jsdom), no el de memoria: solo ese apunta de dónde se viene, que es lo que usa
  // «← Volver».
  router = createRouter({
    history: createWebHistory(),
    routes: [
      { path: '/', component: elsewhere('Equipos') },
      { path: '/ficha', component: elsewhere('Ficha') },
      { path: '/temporadas/:temporada/competiciones/:id', component: CompetitionScreen },
    ],
  })
  await router.replace(from ?? address)
  if (from) await router.push(address)
  render(RouterView, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
  return router
}

const roundPicker = () => screen.getByRole('combobox', { name: 'Jornada' })
const previous = () => screen.getByRole('button', { name: '‹ Anterior' })
const next = () => screen.getByRole('button', { name: 'Siguiente ›' })

afterEach(() => vi.unstubAllGlobals())

describe('la jornada que se enseña', () => {
  test('sin jornada en la dirección, la de la última clasificación; con la competición arriba, su edad, género, modalidad y temporada', async () => {
    const asked = fakeServer()
    await openCompetition()

    expect(await screen.findByRole('heading', { level: 1, name: 'PREFERENTE CADETE · Grupo 2' })).toBeInTheDocument()
    expect(screen.getByText('Cadete · Masculino · Fútbol 11 · 2026/27')).toBeInTheDocument()
    await waitFor(() => expect(roundPicker()).toHaveTextContent('Jornada 1 · 1 – 2 oct'))
    expect(screen.getByRole('table', { name: 'Clasificación tras la jornada 1' })).toBeInTheDocument()
    expect(screen.getByText('Federación')).toBeInTheDocument()
    // Desde la en curso hacia atrás, y los partidos solo de la que se enseña.
    expect(asked.filter((a) => a.startsWith('/standings') || a.startsWith('/matches'))).toEqual([
      '/standings?roundId=j2',
      '/standings?roundId=j1',
      '/matches?roundId=j1&perPage=100',
    ])
  })

  test('sin jornada en la dirección y sin ninguna clasificación todavía, la en curso', async () => {
    fakeServer({ noTables: true })
    await openCompetition()

    await waitFor(() => expect(roundPicker()).toHaveTextContent('Jornada 2 · 2 – 3 oct'))
    expect(await screen.findByText('Esta jornada aún no tiene clasificación.')).toBeInTheDocument()
  })

  test('sin jornada en la dirección y con la competición terminada, desde la última hacia atrás', async () => {
    const asked = fakeServer({ rounds: rounds.map((r) => ({ ...r, isCurrent: false })) })
    await openCompetition()

    await waitFor(() => expect(roundPicker()).toHaveTextContent('Jornada 1 · 1 – 2 oct'))
    expect(asked.filter((a) => a.startsWith('/standings'))).toEqual([
      '/standings?roundId=j3',
      '/standings?roundId=j2',
      '/standings?roundId=j1',
    ])
  })

  test('con ?jornada=, esa; sus partidos, el del club señalado, y su clasificación por puesto', async () => {
    const asked = fakeServer()
    await openCompetition(`/temporadas/2026-27/competiciones/${LIGA}?jornada=1`)

    const matches = await screen.findByRole('table', { name: 'Partidos de la jornada 1' })
    const row = within(matches).getAllByRole('row')[1]!
    expect(row).toHaveTextContent('Celtic Castilla A')
    expect(row).toHaveTextContent('2 - 1')
    expect(row).toHaveClass('own')
    const table = screen.getByRole('table', { name: 'Clasificación tras la jornada 1' })
    expect(within(table).getAllByRole('rowheader').map((cell) => cell.textContent?.trim())).toEqual([
      'Celtic Castilla A',
      'COLEGIO EL PRADO A',
    ])
    expect(within(table).getAllByText('Victoria en la jornada 1')).toHaveLength(2)
    expect(asked).toContain('/matches?roundId=j1&perPage=100')
    expect(asked).toContain('/standings?roundId=j1')
  })

  test('una jornada sin clasificación todavía: los partidos y el aviso', async () => {
    fakeServer()
    await openCompetition(`/temporadas/2026-27/competiciones/${LIGA}?jornada=2`)

    expect(await screen.findByText('Esta jornada aún no tiene clasificación.')).toBeInTheDocument()
    expect(screen.getByRole('table', { name: 'Partidos de la jornada 2' })).toBeInTheDocument()
  })

  test('una jornada que la competición no tiene: el error y el enlace a la última jugada', async () => {
    fakeServer()
    await openCompetition(`/temporadas/2026-27/competiciones/${LIGA}?jornada=40`)

    expect(await screen.findByRole('alert')).toHaveTextContent('No hay ninguna jornada 40 en esta competición')
    expect(screen.getByRole('link', { name: 'Ir a la última jornada jugada' })).toBeInTheDocument()
  })

  test('sin jornadas: la Federación aún no ha publicado el calendario', async () => {
    fakeServer({ rounds: [] })
    await openCompetition()

    expect(await screen.findByText('La Federación aún no ha publicado el calendario.')).toBeInTheDocument()
  })
})

describe('moverse entre jornadas', () => {
  test('«Siguiente» y «Anterior» cambian la dirección, y solo se piden los partidos y la clasificación', async () => {
    const asked = fakeServer()
    const router = await openCompetition(`/temporadas/2026-27/competiciones/${LIGA}?jornada=2`)
    await waitFor(() => expect(roundPicker()).toHaveTextContent('Jornada 2'))

    await fireEvent.click(next())
    await waitFor(() => expect(router.currentRoute.value.query).toEqual({ jornada: '3' }))
    await screen.findByRole('table', { name: 'Partidos de la jornada 3' })

    await fireEvent.click(previous())
    await waitFor(() => expect(router.currentRoute.value.query).toEqual({ jornada: '2' }))
    await screen.findByRole('table', { name: 'Partidos de la jornada 2' })

    expect(asked.filter((a) => a.startsWith('/rounds'))).toHaveLength(1)
  })

  test('el selector abre la jornada elegida', async () => {
    fakeServer()
    const router = await openCompetition(`/temporadas/2026-27/competiciones/${LIGA}?jornada=2`)
    await waitFor(() => expect(roundPicker()).toHaveTextContent('Jornada 2'))

    await fireEvent.click(roundPicker())
    await fireEvent.mouseDown(await screen.findByRole('option', { name: 'Jornada 1 · 1 – 2 oct' }))

    await waitFor(() => expect(router.currentRoute.value.query).toEqual({ jornada: '1' }))
    expect(await screen.findByRole('table', { name: 'Clasificación tras la jornada 1' })).toBeInTheDocument()
  })

  test('en la primera, «Anterior» bloqueado; en la última, «Siguiente»', async () => {
    fakeServer()
    const router = await openCompetition(`/temporadas/2026-27/competiciones/${LIGA}?jornada=1`)
    await screen.findByRole('table', { name: 'Partidos de la jornada 1' })
    expect(previous()).toBeDisabled()
    expect(next()).toBeEnabled()

    await router.push({ query: { jornada: '3' } })
    await screen.findByRole('table', { name: 'Partidos de la jornada 3' })
    expect(previous()).toBeEnabled()
    expect(next()).toBeDisabled()
  })
})

describe('«← Volver»', () => {
  test('a donde se estaba', async () => {
    fakeServer()
    await openCompetition(undefined, '/ficha')

    expect(await screen.findByRole('link', { name: '← Volver' })).toHaveAttribute('href', '/ficha')
  })

  test('entrando por la dirección, a la portada de esa temporada', async () => {
    fakeServer()
    await openCompetition()

    expect(await screen.findByRole('link', { name: '← Volver' })).toHaveAttribute('href', '/?temporada=2026-27')
  })
})

describe('lo que no se puede enseñar', () => {
  test('mientras llegan los datos, «Cargando jornada…»', async () => {
    vi.stubGlobal('fetch', () => new Promise(() => {}))
    await openCompetition()

    expect(await screen.findByRole('status')).toHaveTextContent('Cargando jornada…')
  })

  test.each([
    ['una competición que el club no tiene', `/temporadas/2026-27/competiciones/44444444-4444-4444-8444-444444444444`],
    ['un código que no es un UUID', '/temporadas/2026-27/competiciones/abc'],
    ['una temporada que el club no tiene', `/temporadas/2019-20/competiciones/${LIGA}`],
  ])('%s: «No se ha encontrado la competición» y el enlace a la portada', async (_, address) => {
    fakeServer()
    await openCompetition(address)

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado la competición')
    expect(screen.getByRole('link', { name: 'Ir a la portada' })).toHaveAttribute('href', '/')
  })

  test('un error que puede ser pasajero, con «Reintentar»; la competición se queda', async () => {
    fakeServer({ failStandings: true })
    await openCompetition()

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha podido conectar con el servidor')
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
    expect(screen.getByRole('heading', { level: 1, name: 'PREFERENTE CADETE · Grupo 2' })).toBeInTheDocument()
  })
})
