import { fireEvent, render, screen, waitFor, within } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { notice } from '../../notice'
import { primeVueOptions } from '../../theme/primevue'
import PlayerScreen from './PlayerScreen.vue'

// La ficha de un jugador en una temporada (plan R6, §3 y decisiones 6 y 7).

const PLAYER = '33333333-3333-4333-8333-333333333333'
const TEAM = '11111111-1111-4111-8111-111111111111'

function season(label: string, fields: Record<string, unknown> = {}) {
  const year = Number(label.slice(0, 4))
  return { id: `id-${year}`, label, startDate: `${year}-07-01`, endDate: `${year + 1}-06-30`, isCurrent: year === 2026, createdAt: 'x', updatedAt: 'x', ...fields }
}

function player(fields: Record<string, unknown> = {}) {
  return {
    id: PLAYER,
    profileId: 'perfil',
    teamId: TEAM,
    seasonId: 'id-2026',
    fullName: 'JUAN CARLOS GARCÍA DE LA FUENTE',
    birthYear: 2011,
    shirtNumber: 7,
    position: 'delantero',
    federated: null,
    lastListedAt: null,
    photoUrl: null,
    createdAt: 'x',
    updatedAt: 'x',
    ...fields,
  }
}

const team = { id: TEAM, category: 'cadete', letter: 'A', gender: 'masculino', modality: 'futbol_11', isOwn: true, clubName: 'Celtic', displayName: 'Celtic Cadete A', createdAt: 'x', updatedAt: 'x' }
const problem = (status: number, code: string) => Response.json({ type: 'about:blank', title: 'x', status, code }, { status })

function fakeServer(fields: { player?: Record<string, unknown>; seasons?: unknown[]; photo?: () => Response } = {}) {
  const server = { asked: [] as string[], player: player(fields.player) as Record<string, unknown> }
  vi.stubGlobal('fetch', async (request: Request) => {
    const url = new URL(request.url)
    const path = url.pathname.replace('/api/v1', '')
    server.asked.push(`${request.method} ${path}`)
    if (path === '/seasons') return Response.json(fields.seasons ?? [season('2026/27'), season('2025/26')])
    if (path === `/players/${PLAYER}/photo`) {
      if (fields.photo) return fields.photo()
      server.player = { ...server.player, photoUrl: request.method === 'PUT' ? '/api/v1/player-photos/nueva.jpg' : null }
      return new Response(null, { status: 204 })
    }
    if (path === `/players/${PLAYER}` && request.method === 'DELETE') return new Response(null, { status: 204 })
    if (path === `/players/${PLAYER}`) return Response.json(server.player)
    if (path.startsWith('/players/')) return problem(404, 'PLAYER_NOT_FOUND')
    if (path === '/players') return Response.json([server.player])
    if (path === `/teams/${TEAM}`) return Response.json(team)
    throw new Error(`Petición no esperada: ${request.method} ${path}`)
  })
  return server
}

// Las pantallas a las que se va, solo con su título.
const landing = (title: string) => defineComponent({ setup: () => () => h('h1', title) })

let router: ReturnType<typeof createRouter>
async function openSheet(address = `/temporadas/2026-27/jugadores/${PLAYER}`) {
  router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: landing('Equipos') },
      { path: '/temporadas/:temporada/equipos/:id/plantilla', component: landing('Plantilla') },
      { path: '/temporadas/:temporada/jugadores/:id', component: PlayerScreen },
    ],
  })
  await router.push(address)
  render(RouterView, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
}

const title = () => screen.findByRole('heading', { level: 1, name: 'Juan Carlos García de la Fuente' })

afterEach(() => vi.unstubAllGlobals())

describe('la ficha', () => {
  test('el nombre de su perfil, su equipo y la temporada, y el dorsal, la demarcación y el año', async () => {
    fakeServer()
    await openSheet()

    await title()
    expect(screen.getByText('Cadete A · 2026/27')).toBeInTheDocument()
    expect(screen.getAllByRole('term').map((t) => t.textContent)).toEqual(['Dorsal', 'Demarcación', 'Año de nacimiento'])
    const facts = screen.getAllByRole('definition').map((d) => d.textContent)
    expect(facts).toEqual(['7', 'Delantero', '2011'])
  })

  test('sin dorsal, sin demarcación y sin año: la raya y «Sin año»', async () => {
    fakeServer({ player: { shirtNumber: null, position: null, birthYear: null } })
    await openSheet()
    await title()

    expect(screen.getAllByRole('definition').map((d) => d.textContent)).toEqual(['—', '—', 'Sin año'])
  })

  test('un jugador federado dice «Federación» con la última vez que lo publicó (R6.16)', async () => {
    fakeServer({ player: { federated: true, lastListedAt: '2026-11-17T17:30:00Z' } })
    await openSheet()
    await title()

    expect(screen.getAllByRole('term').map((t) => t.textContent)).toContain('Federación')
    expect(screen.getAllByRole('definition').at(-1)).toHaveTextContent(/^Federado · publicado el 17\/11\/2026 \d\d:30$/)
  })

  test('un jugador de una plantilla que nunca se ha sincronizado no tiene «Federación»', async () => {
    fakeServer()
    await openSheet()
    await title()

    expect(screen.getAllByRole('term').map((t) => t.textContent)).not.toContain('Federación')
  })

  test('encima, el enlace de vuelta a la plantilla de su equipo', async () => {
    fakeServer()
    await openSheet()

    expect(await screen.findByRole('link', { name: '← Plantilla del Cadete A' })).toHaveAttribute(
      'href',
      `/temporadas/2026-27/equipos/${TEAM}/plantilla`,
    )
  })

  test('con otra temporada en el camino, «No se ha encontrado el jugador» y el enlace a la portada', async () => {
    fakeServer()
    await openSheet(`/temporadas/2025-26/jugadores/${PLAYER}`)

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado el jugador')
    expect(screen.getByRole('link', { name: 'Ir a la portada' })).toHaveAttribute('href', '/')
  })

  test('un jugador que no existe, igual', async () => {
    fakeServer()
    await openSheet('/temporadas/2026-27/jugadores/44444444-4444-4444-8444-444444444444')

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado el jugador')
  })
})

describe('la foto', () => {
  test('sin foto, sus iniciales y «Poner foto»; elegida, se guarda ya y se ve', async () => {
    const server = fakeServer()
    await openSheet()
    await title()
    expect(screen.getByText('JC')).toBeInTheDocument()

    await fireEvent.change(document.getElementById('sheet-photo')!, { target: { files: [new File(['x'], 'j.jpg', { type: 'image/jpeg' })] } })

    expect(await screen.findByRole('img', { name: 'Juan Carlos García de la Fuente' })).toHaveAttribute('src', '/api/v1/player-photos/nueva.jpg')
    expect(server.asked).toContain(`PUT /players/${PLAYER}/photo`)
    expect(screen.getByRole('button', { name: 'Cambiar foto' })).toBeInTheDocument()
  })

  test('«Quitar foto» la quita y deja sus iniciales', async () => {
    fakeServer({ player: { photoUrl: '/api/v1/player-photos/j.jpg' } })
    await openSheet()
    await title()

    await fireEvent.click(screen.getByRole('button', { name: 'Quitar foto' }))

    expect(await screen.findByText('JC')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Quitar foto' })).not.toBeInTheDocument()
  })

  test('una foto que no vale lo dice, y la de antes se queda', async () => {
    fakeServer({ photo: () => problem(415, 'UNSUPPORTED_IMAGE_TYPE') })
    await openSheet()
    await title()

    await fireEvent.change(document.getElementById('sheet-photo')!, { target: { files: [new File(['x'], 'j.gif', { type: 'image/gif' })] } })

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha podido poner la foto: solo JPEG o PNG.')
    expect(screen.getByText('JC')).toBeInTheDocument()
  })
})

describe('corregir y dar de baja desde la ficha', () => {
  test('«Corregir» abre el mismo diálogo, con sus datos', async () => {
    fakeServer()
    await openSheet()
    await title()

    await fireEvent.click(screen.getByRole('button', { name: 'Corregir' }))

    const dialog = await screen.findByRole('dialog', { name: 'Corregir a Juan Carlos García de la Fuente' })
    expect(within(dialog).getByRole('textbox', { name: 'Dorsal' })).toHaveValue('7')
  })

  test('confirmar la baja vuelve a la plantilla de su equipo, con el aviso', async () => {
    const server = fakeServer()
    await openSheet()
    await title()

    await fireEvent.click(screen.getByRole('button', { name: 'Dar de baja' }))
    await fireEvent.click(within(await screen.findByRole('dialog', { name: 'Dar de baja' })).getByRole('button', { name: 'Dar de baja' }))

    await waitFor(() => expect(router.currentRoute.value.path).toBe(`/temporadas/2026-27/equipos/${TEAM}/plantilla`))
    expect(server.asked).toContain(`DELETE /players/${PLAYER}`)
    expect(notice.value).toBe('Dado de baja')
  })

  test('en una temporada archivada, ni corregir, ni dar de baja, ni la foto', async () => {
    fakeServer({ seasons: [season('2026/27', { archivedAt: '2027-08-01T00:00:00Z' })] })
    await openSheet()
    await title()

    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Dar de baja' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Poner foto' })).not.toBeInTheDocument()
  })

  // Pasada, sin archivar: se ve pero no se cambia, como la archivada (decisión 4 de R6.14).
  test('en una temporada pasada sin archivar, ni corregir, ni dar de baja, ni la foto', async () => {
    fakeServer({ player: { seasonId: 'id-2025' } })
    await openSheet(`/temporadas/2025-26/jugadores/${PLAYER}`)
    await title()

    expect(screen.queryByRole('button', { name: 'Corregir' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Dar de baja' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Poner foto' })).not.toBeInTheDocument()
  })

  test('en una temporada futura, sí se corrige', async () => {
    fakeServer({ seasons: [season('2026/27'), season('2040/41')], player: { seasonId: 'id-2040' } })
    await openSheet(`/temporadas/2040-41/jugadores/${PLAYER}`)
    await title()

    expect(screen.getByRole('button', { name: 'Corregir' })).toBeInTheDocument()
  })
})
