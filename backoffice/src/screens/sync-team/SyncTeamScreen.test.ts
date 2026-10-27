import { fireEvent, render, screen, waitFor } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { primeVueOptions } from '../../theme/primevue'
import SyncTeamScreen from './SyncTeamScreen.vue'

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
}
const calendar = 'https://www.rffm.es/competicion/calendario?temporada=22&tipojuego=2&competicion=26737859&grupo=27325582'
// Lo justo para pasar al paso 2: su contenido lo pinta R3.11.
const aPreview = { season: { label: '2026/27', exists: true }, identityMatches: true, ageCategoryChecked: true }

// Un servidor de mentira: el equipo y el `/preview`, como diga cada prueba; apunta lo que se envió a comprobar.
function fakeServer(answers: { team?: () => Response | Promise<Response>; preview?: () => Response | Promise<Response> }) {
  const sent: unknown[] = []
  const asked: string[] = []
  vi.stubGlobal('fetch', async (request: Request) => {
    const path = new URL(request.url).pathname
    asked.push(`${request.method} ${path}`)
    if (request.method === 'GET' && path.startsWith('/api/v1/teams/')) return (answers.team ?? (() => Response.json(aTeam)))()
    if (request.method === 'POST' && path === `/api/v1/teams/${teamId}/federation-link/preview`) {
      sent.push(await request.json())
      return (answers.preview ?? (() => Response.json(aPreview)))()
    }
    throw new Error(`Petición no esperada: ${request.method} ${path}`)
  })
  return { sent, asked }
}

function problem(status: number, code: string) {
  return Response.json({ type: 'https://example.com/x', title: 'x', status, code, detail: 'No se enseña' }, { status })
}

// Abre la pantalla desde la portada, como sus enlaces: con la temporada que enseñaba en el estado de la navegación.
// Sin `fromHome`, como al escribir la dirección a mano.
async function openScreen(id = teamId, fromHome?: string) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: defineComponent({ render: () => h('h1', 'Portada') }) },
      { path: '/equipos/:id/federacion', component: SyncTeamScreen },
    ],
  })
  await router.push('/?temporada=2025-26')
  await router.push({ path: `/equipos/${id}/federacion`, state: fromHome ? { seasonLabel: fromHome } : {} })
  render(RouterView, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
  return router
}

const urlField = () => screen.findByRole('textbox', { name: /^Dirección del calendario/ })
const checkButton = () => screen.getByRole('button', { name: /Compro/ })

async function checkAddress(address: string) {
  await fireEvent.update(await urlField(), address)
  await fireEvent.click(checkButton())
}

afterEach(() => vi.unstubAllGlobals())

describe('al abrir: el equipo que se sincroniza (§3.2)', () => {
  test('mientras llega, «Cargando equipo…» en su sitio', async () => {
    fakeServer({ team: () => new Promise<Response>(() => {}) })
    await openScreen()

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Sincronizar con la Federación')
    expect(screen.getByRole('status')).toHaveTextContent('Cargando equipo…')
  })

  test('con el equipo, su nombre con género y modalidad, y el paso 1 en curso', async () => {
    fakeServer({})
    await openScreen()

    expect(await screen.findByText('Alevín B · Masculino · Fútbol 7')).toBeInTheDocument()
    const steps = screen.getByRole('list', { name: 'Pasos' })
    expect(steps.querySelector('[aria-current="step"]')).toHaveTextContent('La dirección')
  })

  test('un equipo que no existe: el mensaje, su código y el enlace a la portada, sin Reintentar', async () => {
    fakeServer({ team: () => problem(404, 'TEAM_NOT_FOUND') })
    await openScreen()

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado el equipo')
    expect(screen.getByText('Código: TEAM_NOT_FOUND')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Ir a la portada' })).toHaveAttribute('href', '/')
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
  })

  test('un código que no es un UUID: no se ha encontrado, sin preguntar al servidor (LLD-B §6.7)', async () => {
    const { asked } = fakeServer({})
    await openScreen('abc')

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado el equipo')
    expect(screen.getByRole('link', { name: 'Ir a la portada' })).toBeInTheDocument()
    expect(asked).toEqual([])
  })

  test('un rival: no se ha encontrado, como si no existiera (decisión 6)', async () => {
    fakeServer({ team: () => Response.json({ ...aTeam, isOwn: false }) })
    await openScreen()

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado el equipo')
    expect(screen.getByRole('link', { name: 'Ir a la portada' })).toBeInTheDocument()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
  })

  test('un fallo pasajero: el mensaje con Reintentar, que vuelve a pedirlo', async () => {
    let calls = 0
    fakeServer({ team: () => (++calls === 1 ? problem(503, 'DATABASE_UNAVAILABLE') : Response.json(aTeam)) })
    await openScreen()

    await fireEvent.click(await screen.findByRole('button', { name: 'Reintentar' }))

    expect(await screen.findByText('Alevín B · Masculino · Fútbol 7')).toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Ir a la portada' })).not.toBeInTheDocument()
  })
})

describe('el paso 1: la dirección', () => {
  test('el campo, obligatorio, con la ayuda y el ejemplo del catálogo', async () => {
    fakeServer({})
    await openScreen()

    const input = await urlField()
    expect(screen.getByText('(obligatorio)')).toBeInTheDocument()
    expect(input).toHaveAccessibleDescription(
      /^Cópiala de la web de la Federación, en la página del calendario del grupo\. Por ejemplo: https:\/\/www\.rffm\.es\//,
    )
    expect(checkButton()).toHaveTextContent('Comprobar en la Federación')
  })

  test('sin dirección: «obligatorio» junto al campo y en la lista, con el foco, sin preguntar a la Federación', async () => {
    const { sent } = fakeServer({})
    await openScreen()

    await checkAddress('   ')

    expect(await urlField()).toHaveAccessibleDescription(expect.stringContaining('Este campo es obligatorio'))
    await waitFor(() => expect(screen.getByRole('group', { name: 'Revisa este campo:' })).toHaveFocus())
    expect(screen.getByRole('link', { name: /Dirección del calendario/ })).toBeInTheDocument()
    expect(sent).toEqual([])
  })

  test('algo que no es una dirección: el formato, con el ejemplo, sin preguntar a la Federación', async () => {
    const { sent } = fakeServer({})
    await openScreen()

    await checkAddress('hola')

    expect(await urlField()).toHaveAccessibleDescription(expect.stringContaining('El formato no es válido. Por ejemplo: https://'))
    expect(sent).toEqual([])
  })

  test('mientras comprueba, «Comprobando…» y bloqueado; envía la dirección sin los espacios de los lados', async () => {
    let answer: (response: Response) => void = () => {}
    const { sent } = fakeServer({ preview: () => new Promise<Response>((resolve) => (answer = resolve)) })
    await openScreen()

    await checkAddress(`  ${calendar} `)

    await waitFor(() => expect(checkButton()).toHaveTextContent('Comprobando…'))
    expect(checkButton()).toBeDisabled()
    await waitFor(() => expect(sent).toEqual([{ federationCalendarUrl: calendar }]))

    answer(Response.json(aPreview))
    await waitFor(() => expect(screen.queryByRole('textbox')).not.toBeInTheDocument())
  })

  test('comprobada bien, pasa al paso 2', async () => {
    fakeServer({})
    await openScreen()

    await checkAddress(calendar)

    const steps = screen.getByRole('list', { name: 'Pasos' })
    await waitFor(() => expect(steps.querySelector('[aria-current="step"]')).toHaveTextContent('Tu equipo'))
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
  })
})

describe('el paso 1: los errores de la Federación, cada uno en su sitio (decisión 6)', () => {
  test.each([
    [400, 'UNREADABLE_FEDERATION_URL', 'Esa dirección no es la de un calendario de la Federación. Cópiala de la página del calendario del grupo.'],
    [502, 'FEDERATION_COORDINATE_NOT_FOUND', 'La Federación no tiene ningún calendario en esa dirección. Revisa que esté completa.'],
  ])('un %i %s, junto al campo y en la lista', async (status, code, message) => {
    fakeServer({ preview: () => problem(status, code) })
    await openScreen()

    await checkAddress(calendar)

    await waitFor(() => expect(screen.getByRole('group', { name: 'Revisa este campo:' })).toHaveFocus())
    expect(await urlField()).toHaveAccessibleDescription(expect.stringContaining(message))
    expect(screen.queryByRole('alert')).not.toBeInTheDocument()
  })

  test('la Federación responde con un error: arriba, con Reintentar, y la dirección sigue escrita', async () => {
    fakeServer({ preview: () => problem(502, 'FEDERATION_UNEXPECTED_STATUS') })
    await openScreen()

    await checkAddress(calendar)

    expect(await screen.findByRole('alert')).toHaveTextContent('La Federación ha respondido con un error. Prueba otra vez en un rato.')
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
    expect(await urlField()).toHaveValue(calendar)
  })

  test('Reintentar vuelve a comprobar la misma dirección, y con la Federación ya bien pasa al paso 2', async () => {
    let calls = 0
    const { sent } = fakeServer({
      preview: () => (++calls === 1 ? problem(504, 'FEDERATION_UNREACHABLE') : Response.json(aPreview)),
    })
    await openScreen()
    await checkAddress(calendar)

    await fireEvent.click(await screen.findByRole('button', { name: 'Reintentar' }))

    const steps = screen.getByRole('list', { name: 'Pasos' })
    await waitFor(() => expect(steps.querySelector('[aria-current="step"]')).toHaveTextContent('Tu equipo'))
    expect(sent).toEqual([{ federationCalendarUrl: calendar }, { federationCalendarUrl: calendar }])
  })

  test.each([
    [400, 'SEASON_LABEL_UNAVAILABLE', 'La Federación no dice de qué temporada es ese calendario.'],
    [409, 'SEASON_ALREADY_LINKED', 'Esa temporada ya está sincronizada con otro código de la Federación.'],
    [501, 'FEDERATION_ADAPTER_MISSING', 'Todavía no se puede sincronizar con la federación de este club.'],
  ])('un %i %s: arriba, sin Reintentar', async (status, code, message) => {
    fakeServer({ preview: () => problem(status, code) })
    await openScreen()

    await checkAddress(calendar)

    expect(await screen.findByRole('alert')).toHaveTextContent(message)
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
  })

  test('el equipo ya no está: la página entera, con el enlace a la portada', async () => {
    fakeServer({ preview: () => problem(404, 'TEAM_NOT_FOUND') })
    await openScreen()

    await checkAddress(calendar)

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha encontrado el equipo')
    expect(screen.getByRole('link', { name: 'Ir a la portada' })).toBeInTheDocument()
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument()
  })

  test('al volver a comprobar, el error de antes se va', async () => {
    let calls = 0
    fakeServer({ preview: () => (++calls === 1 ? problem(400, 'SEASON_LABEL_UNAVAILABLE') : new Promise<Response>(() => {})) })
    await openScreen()
    await checkAddress(calendar)
    await screen.findByRole('alert')

    await fireEvent.click(checkButton())

    await waitFor(() => expect(screen.queryByRole('alert')).not.toBeInTheDocument())
  })
})

describe('Cancelar', () => {
  test('vuelve a la portada de la que se vino, y la pantalla sale del historial', async () => {
    fakeServer({})
    const router = await openScreen(teamId, '2025/26')

    await fireEvent.click(await screen.findByRole('button', { name: 'Cancelar' }))

    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/?temporada=2025-26'))
    router.back()
    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/?temporada=2025-26'))
  })

  test('escrita la dirección a mano, sin temporada de la portada, a la portada sin más', async () => {
    fakeServer({})
    const router = await openScreen()

    await fireEvent.click(await screen.findByRole('button', { name: 'Cancelar' }))

    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/'))
  })
})
