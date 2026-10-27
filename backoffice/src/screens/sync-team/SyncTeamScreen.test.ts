import { fireEvent, render, screen, waitFor, within } from '@testing-library/vue'
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
// Un `/preview` que cuadra con el equipo: Primera Alevín, fútbol 7, masculino; con tres equipos en el grupo, en el
// orden del calendario, y uno sin código.
function team(rawName: string, federationTeamId: string | null, takenBy: unknown = null) {
  return { rawName, federationTeamId, takenBy }
}
const aPreview = {
  season: { federationSeasonId: '22', label: '2026/27', exists: true },
  identityMatches: true,
  ageCategoryChecked: true,
  competition: {
    modality: 'futbol_7',
    gender: 'masculino',
    ageCategory: 'alevin',
    divisionLabel: 'PRIMERA ALEVIN',
    groupLabel: 'Grupo 4',
    federationCompetitionId: '26737859',
    federationGroupId: '27325582',
    roundCount: 26,
    alreadyRegistered: false,
    teams: [
      team("U.D. SAN ROQUE 'B'", '101'),
      team("CELTIC CASTILLA C.F. 'B'", '102'),
      team("ESCUELA RIOSECO 'A'", null),
      team("A.D. LOS OLIVOS 'A'", '104'),
    ],
  },
}

// Un servidor de mentira: el equipo, el `/preview` y el enganche, como diga cada prueba; apunta lo que se envió a
// comprobar (`sent`) y a sincronizar (`linked`).
type Answer = () => Response | Promise<Response>
function fakeServer(answers: { team?: Answer; preview?: Answer; link?: Answer }) {
  const sent: unknown[] = []
  const linked: unknown[] = []
  const asked: string[] = []
  vi.stubGlobal('fetch', async (request: Request) => {
    const path = new URL(request.url).pathname
    asked.push(`${request.method} ${path}`)
    if (request.method === 'GET' && path.startsWith('/api/v1/teams/')) return (answers.team ?? (() => Response.json(aTeam)))()
    if (request.method === 'POST' && path === `/api/v1/teams/${teamId}/federation-link/preview`) {
      sent.push(await request.json())
      return (answers.preview ?? (() => Response.json(aPreview)))()
    }
    if (request.method === 'POST' && path === `/api/v1/teams/${teamId}/federation-link`) {
      linked.push(await request.json())
      return (answers.link ?? (() => Response.json({ jobId: 'j', status: 'encolado', teamId, competitionId: 'c', seasonId: 's' }, { status: 202 })))()
    }
    throw new Error(`Petición no esperada: ${request.method} ${path}`)
  })
  return { sent, linked, asked }
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

// ── El paso 2 ──

// Un `/preview` como `aPreview`, con lo que cambie cada prueba en la competición, la temporada o lo demás.
function previewWith(changes: { competition?: object; season?: object; ageCategoryChecked?: boolean }) {
  return {
    ...aPreview,
    ...(changes.ageCategoryChecked === undefined ? {} : { ageCategoryChecked: changes.ageCategoryChecked }),
    season: { ...aPreview.season, ...changes.season },
    competition: { ...aPreview.competition, ...changes.competition },
  }
}

// Abre la pantalla y comprueba la dirección: llega al paso 2.
async function openStepTwo(answers: Parameters<typeof fakeServer>[0] = {}, fromHome?: string) {
  const server = fakeServer(answers)
  const router = await openScreen(teamId, fromHome)
  await checkAddress(calendar)
  await screen.findByRole('heading', { name: 'Lo que hay en esa dirección' })
  return { ...server, router }
}

const teamChoice = () => screen.getByRole('group', { name: /¿Cuál es tu equipo\?/ })
const radios = () => within(teamChoice()).getAllByRole('radio')
const syncButton = () => screen.getByRole('button', { name: /^Sincronizar/ })
const summary = () =>
  [...document.querySelectorAll('.summary div')].map((pair) => [pair.querySelector('dt')!.textContent, pair.querySelector('dd')!.textContent!.trim()])

describe('el paso 2: lo que hay en la dirección (§3.3)', () => {
  test('el resumen de la competición, y el foco en su título', async () => {
    await openStepTwo()

    expect(summary()).toEqual([
      ['Competición', 'PRIMERA ALEVIN · Grupo 4'],
      ['Edad', 'Alevín'],
      ['Modalidad', 'Fútbol 7'],
      ['Temporada', '2026/27'],
      ['Jornadas', '26'],
    ])
    await waitFor(() => expect(screen.getByRole('heading', { name: 'Lo que hay en esa dirección' })).toHaveFocus())
  })

  test('la dirección comprobada, en su línea, sin el https://', async () => {
    await openStepTwo()

    expect(screen.getByText(calendar.replace('https://', ''))).toBeInTheDocument()
  })

  test('una temporada que el club no tiene: «nueva», y el aviso de que se creará', async () => {
    await openStepTwo({ preview: () => Response.json(previewWith({ season: { label: '2027/28', exists: false } })) })

    expect(summary()).toContainEqual(['Temporada', '2027/28 · nueva'])
    expect(screen.getByText(/no existe todavía en el club: se creará al sincronizar/)).toHaveTextContent('La temporada 2027/28')
  })

  test('una competición que ya está en el club: el aviso, y su género a la vista, sin elegirlo', async () => {
    await openStepTwo({ preview: () => Response.json(previewWith({ competition: { alreadyRegistered: true } })) })

    expect(screen.getByText('Esta competición ya está en el club; se reutiliza.')).toBeInTheDocument()
    expect(summary()).toContainEqual(['Género', 'Masculino'])
    expect(screen.queryByRole('combobox', { name: /Género/ })).not.toBeInTheDocument()
  })

  test('una competición de otra edad: qué no cuadra, y no deja sincronizar', async () => {
    await openStepTwo({ preview: () => Response.json(previewWith({ competition: { ageCategory: 'infantil' } })) })

    expect(screen.getByText('Edad: el equipo es Alevín y la competición, Infantil.')).toBeInTheDocument()
    expect(syncButton()).toBeDisabled()
  })

  test('el género propuesto no cuadra: al corregirlo, deja sincronizar, y se envía el elegido', async () => {
    const { linked } = await openStepTwo({ preview: () => Response.json(previewWith({ competition: { gender: 'femenino' } })) })
    expect(screen.getByText('Género: el equipo es Masculino y la competición, Femenino.')).toBeInTheDocument()
    expect(syncButton()).toBeDisabled()

    await fireEvent.click(screen.getByRole('combobox', { name: /Género de la competición/ }))
    await fireEvent.mouseDown(await screen.findByRole('option', { name: 'Masculino' }))
    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))
    await fireEvent.click(syncButton())

    await waitFor(() => expect(linked).toEqual([expect.objectContaining({ gender: 'masculino' })]))
  })

  test('una competición cuyo nombre no dice la edad: el aviso, y deja sincronizar', async () => {
    await openStepTwo({ preview: () => Response.json(previewWith({ ageCategoryChecked: false })) })

    expect(screen.getByText(/La Federación no dice la edad de esta competición: se usará la del equipo, Alevín\./)).toBeInTheDocument()
    expect(syncButton()).toBeEnabled()
  })
})

describe('el paso 2: la lista de equipos (decisión 4)', () => {
  test('por orden alfabético, ninguno elegido, y el botón dice solo «Sincronizar»', async () => {
    await openStepTwo()

    expect(radios()).toHaveLength(4)
    expect([...teamChoice().querySelectorAll('.option label')].map((label) => label.textContent!.trim())).toEqual([
      "A.D. LOS OLIVOS 'A'",
      "CELTIC CASTILLA C.F. 'B'",
      "ESCUELA RIOSECO 'A'",
      "U.D. SAN ROQUE 'B'",
    ])
    expect(radios().filter((radio) => (radio as HTMLInputElement).checked)).toEqual([])
    expect(syncButton()).toHaveTextContent(/^Sincronizar$/)
  })

  test('el que no tiene código: desactivado, y el motivo se lee con él', async () => {
    await openStepTwo()

    const noCode = screen.getByRole('radio', { name: /ESCUELA RIOSECO/ })
    expect(noCode).toBeDisabled()
    expect(noCode).toHaveAccessibleDescription('La Federación no publica su código: no se puede elegir')
  })

  test('el que ya es de otro equipo del club, o de este: desactivado, diciendo de quién', async () => {
    const taken = (teamRef: string, displayName: string) => ({ teamId: teamRef, displayName, shortDisplayName: 'x', isOwn: true })
    await openStepTwo({
      preview: () =>
        Response.json(
          previewWith({
            competition: {
              teams: [team("CELTIC CASTILLA C.F. 'A'", '201', taken('otro', 'Celtic Alevín A')), team("CELTIC CASTILLA C.F. 'B'", '202', taken(teamId, 'Celtic Alevín B'))],
            },
          }),
        ),
    })

    expect(screen.getByRole('radio', { name: /'A'/ })).toHaveAccessibleDescription('Ya está sincronizado con Celtic Alevín A')
    expect(screen.getByRole('radio', { name: /'B'/ })).toHaveAccessibleDescription('Ya está sincronizado con este equipo')
  })

  test('al elegir uno, el botón dice su nombre', async () => {
    await openStepTwo()

    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    expect(syncButton()).toHaveTextContent("Sincronizar CELTIC CASTILLA C.F. 'B'")
  })
})

describe('el paso 2: sincronizar', () => {
  test('sin elegir: «Elige tu equipo» en la lista de errores, con el foco, y en la lista; sin enviar nada', async () => {
    const { linked } = await openStepTwo()

    await fireEvent.click(syncButton())

    await waitFor(() => expect(screen.getByRole('group', { name: 'Revisa este campo:' })).toHaveFocus())
    expect(screen.getByRole('link', { name: /Elige tu equipo/ })).toBeInTheDocument()
    expect(teamChoice()).toHaveAccessibleDescription(expect.stringContaining('Elige tu equipo'))
    expect(linked).toEqual([])
  })

  test('el enlace de la lista de errores lleva al primer equipo que se puede elegir', async () => {
    await openStepTwo()
    await fireEvent.click(syncButton())

    await fireEvent.click(await screen.findByRole('link', { name: /Elige tu equipo/ }))

    expect(screen.getByRole('radio', { name: /LOS OLIVOS/ })).toHaveFocus()
  })

  test('al elegir después, lo que faltaba se va', async () => {
    await openStepTwo()
    await fireEvent.click(syncButton())

    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    expect(screen.queryByRole('group', { name: 'Revisa este campo:' })).not.toBeInTheDocument()
  })

  test('con uno elegido: la dirección comprobada, su código y el género; sin la temporada (decisión 3)', async () => {
    const { linked } = await openStepTwo()

    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))
    await fireEvent.click(syncButton())

    await waitFor(() =>
      expect(linked).toEqual([{ federationCalendarUrl: calendar, ownTeamFederationId: '102', gender: 'masculino' }]),
    )
  })

  test('bien: de momento, vuelve a la portada de la que se vino (la vuelta de verdad es de R3.12)', async () => {
    const { router } = await openStepTwo({}, '2025/26')

    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))
    await fireEvent.click(syncButton())

    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/?temporada=2025-26'))
  })

  test.each([
    [409, 'OWN_TEAM_NOT_IN_CALENDAR', 'Ese equipo ya no está en el calendario de la Federación. Vuelve a comprobar con el botón ↻ de la dirección.'],
    [502, 'FEDERATION_SEASON_MISMATCH', 'Las fechas de ese calendario son de otra temporada.'],
    [504, 'FEDERATION_UNREACHABLE', 'La Federación no responde. Prueba otra vez en un rato.'],
  ])('un %i %s: arriba, sin Reintentar, y lo elegido sigue', async (status, code, message) => {
    await openStepTwo({ link: () => problem(status, code) })
    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    await fireEvent.click(syncButton())

    expect(await screen.findByRole('alert')).toHaveTextContent(message)
    expect(screen.queryByRole('button', { name: 'Reintentar' })).not.toBeInTheDocument()
    expect(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'")).toBeChecked()
  })

  test('el equipo ya no está: la página entera', async () => {
    await openStepTwo({ link: () => problem(404, 'TEAM_NOT_FOUND') })
    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    await fireEvent.click(syncButton())

    expect(await screen.findByRole('link', { name: 'Ir a la portada' })).toBeInTheDocument()
    expect(screen.queryByRole('group', { name: /¿Cuál es tu equipo/ })).not.toBeInTheDocument()
  })
})

describe('el paso 2: la línea de la dirección', () => {
  test('editar vuelve al paso 1 con la dirección comprobada en el campo, y el foco en él; lo comprobado se borra', async () => {
    await openStepTwo()
    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    await fireEvent.click(screen.getByRole('button', { name: 'Editar la dirección' }))

    const input = await urlField()
    expect(input).toHaveValue(calendar)
    await waitFor(() => expect(input).toHaveFocus())
    expect(screen.queryByRole('heading', { name: 'Lo que hay en esa dirección' })).not.toBeInTheDocument()

    // Vuelto a comprobar, ninguno elegido: lo de antes no se arrastra.
    await fireEvent.click(checkButton())
    await screen.findByRole('heading', { name: 'Lo que hay en esa dirección' })
    expect(radios().filter((radio) => (radio as HTMLInputElement).checked)).toEqual([])
  })

  test('volver a comprobar repite el /preview con la misma dirección, y conserva el equipo elegido', async () => {
    // La segunda respuesta, con una jornada más: así se sabe que ya ha llegado.
    let calls = 0
    const { sent } = await openStepTwo({
      preview: () => Response.json(++calls === 1 ? aPreview : previewWith({ competition: { roundCount: 27 } })),
    })
    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    await fireEvent.click(screen.getByRole('button', { name: 'Volver a comprobar en la Federación' }))

    await waitFor(() => expect(summary()).toContainEqual(['Jornadas', '27']))
    expect(sent).toEqual([{ federationCalendarUrl: calendar }, { federationCalendarUrl: calendar }])
    expect(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'")).toBeChecked()
  })

  test('volver a comprobar: si el elegido ya no se puede elegir, se suelta', async () => {
    let calls = 0
    const second = previewWith({
      competition: { teams: [team("CELTIC CASTILLA C.F. 'B'", '102', { teamId: 'otro', displayName: 'Celtic Alevín A', shortDisplayName: 'x', isOwn: true })] },
    })
    await openStepTwo({ preview: () => Response.json(++calls === 1 ? aPreview : second) })
    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    await fireEvent.click(screen.getByRole('button', { name: 'Volver a comprobar en la Federación' }))

    await waitFor(() => expect(screen.getByRole('radio', { name: /'B'/ })).toBeDisabled())
    expect(syncButton()).toHaveTextContent(/^Sincronizar$/)
  })

  test('volver a comprobar con la Federación caída: arriba, y lo de antes sigue', async () => {
    let calls = 0
    await openStepTwo({ preview: () => (++calls === 1 ? Response.json(aPreview) : problem(504, 'FEDERATION_UNREACHABLE')) })
    await fireEvent.click(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'"))

    await fireEvent.click(screen.getByRole('button', { name: 'Volver a comprobar en la Federación' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('La Federación no responde.')
    expect(screen.getByLabelText("CELTIC CASTILLA C.F. 'B'")).toBeChecked()
  })
})

