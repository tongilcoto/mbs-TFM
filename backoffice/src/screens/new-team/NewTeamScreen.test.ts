import { fireEvent, render, screen, waitFor, within } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { primeVueOptions } from '../../theme/primevue'
import type { Season } from '../home/seasons'
import NewTeamScreen from './NewTeamScreen.vue'

function season(label: string, isCurrent = false): Season {
  const year = Number(label.slice(0, 4))
  return {
    id: `0b7e7a52-4c1d-4f7e-9a51-${year}0c2b8d11`,
    label,
    startDate: `${year}-07-01`,
    endDate: `${year + 1}-06-30`,
    isCurrent,
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
  }
}
const seasons = [season('2026/27', true), season('2025/26')]

// Un servidor de mentira: contesta la lista de temporadas y el alta como diga cada prueba, y apunta lo que se
// envió al dar de alta.
function fakeServer(answers: {
  seasons?: () => Response
  createTeam?: () => Response
  createSeason?: (body: { label: string }) => Response
}) {
  const sent: unknown[] = []
  vi.stubGlobal('fetch', async (request: Request) => {
    const path = new URL(request.url).pathname
    if (request.method === 'GET' && path === '/api/v1/seasons') return (answers.seasons ?? (() => Response.json(seasons)))()
    if (request.method === 'POST' && path === '/api/v1/teams') {
      sent.push(await request.json())
      return (answers.createTeam ?? (() => Response.json({}, { status: 201 })))()
    }
    if (request.method === 'POST' && path === '/api/v1/seasons') {
      const body = (await request.json()) as { label: string }
      sent.push(body)
      return (answers.createSeason ?? ((b) => Response.json(season(b.label), { status: 201 })))(body)
    }
    throw new Error(`Petición no esperada: ${request.method} ${path}`)
  })
  return sent
}

function problem(status: number, code: string, detail = 'No se enseña') {
  return Response.json({ type: 'https://example.com/x', title: 'x', status, code, detail }, { status })
}

// Abre el formulario desde la portada, como lo hará su botón: con la temporada que enseñaba en el estado de la
// navegación. Sin `fromHome`, como al recargar.
// `realTransitions`: con la animación de verdad de las ventanas, para las pruebas del foco. La de mentira de las
// pruebas no avisa de que una ventana se ha abierto o cerrado.
async function openForm(fromHome?: string, realTransitions = false) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: defineComponent({ render: () => h('h1', 'Portada') }) },
      { path: '/equipos/nuevo', component: NewTeamScreen },
    ],
  })
  await router.push('/?temporada=2025-26')
  await router.push({ path: '/equipos/nuevo', state: fromHome ? { seasonLabel: fromHome } : {} })
  render(RouterView, {
    global: { plugins: [router, [PrimeVue, primeVueOptions]], stubs: realTransitions ? { transition: false } : {} },
  })
  return router
}

function field(name: string) {
  return screen.getByRole('combobox', { name: new RegExp(`^${name}`) })
}

// PrimeVue elige la opción al apretar el botón del ratón, no al soltarlo.
async function choose(name: string, option: string) {
  await fireEvent.click(field(name))
  await fireEvent.mouseDown(await screen.findByRole('option', { name: option }))
}

async function fillTeam() {
  await choose('Categoría', 'Alevín')
  await choose('Género', 'Femenino')
  await choose('Modalidad', 'Fútbol 7')
}

afterEach(() => vi.unstubAllGlobals())

describe('el selector de temporada', () => {
  test('mientras carga, lo dice en su sitio, y el resto ya se puede rellenar', async () => {
    fakeServer({ seasons: () => new Promise<Response>(() => {}) as never })
    await openForm()

    expect(screen.getByRole('status')).toHaveTextContent('Cargando temporadas…')
    await choose('Categoría', 'Cadete')
    expect(field('Categoría')).toHaveTextContent('Cadete')
  })

  test('viene elegida la que enseñaba la portada', async () => {
    fakeServer({})
    await openForm('2025/26')

    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2025/26'))
  })

  test('al recargar, sin temporada de la portada, la en curso', async () => {
    fakeServer({})
    await openForm()

    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2026/27'))
  })

  test('si falla al cargar, el error en su sitio, con Reintentar si puede ser pasajero', async () => {
    fakeServer({ seasons: () => problem(503, 'DATABASE_UNAVAILABLE') })
    await openForm()

    expect(await screen.findByRole('alert')).toHaveTextContent('No se ha podido conectar con el servidor')
    expect(screen.getByRole('button', { name: 'Reintentar' })).toBeInTheDocument()
  })

  test('el club sin temporadas: el selector vacío', async () => {
    fakeServer({ seasons: () => Response.json([]) })
    await openForm()

    await fireEvent.click(await screen.findByRole('combobox', { name: /^Temporada/ }))
    // PrimeVue lo escribe dos veces: el que se ve y el que se lee.
    expect((await screen.findAllByText('Todavía no hay ninguna temporada')).length).toBeGreaterThan(0)
  })
})

describe('al guardar', () => {
  test('vacío: no envía nada, marca los cuatro obligatorios a la vez y el foco va a la lista', async () => {
    const sent = fakeServer({ seasons: () => Response.json([]) })
    await openForm()
    await screen.findByRole('combobox', { name: /^Temporada/ })

    await fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))

    const list = await screen.findByRole('group', { name: 'Revisa estos campos:' })
    expect(list).toHaveFocus()
    expect([...list.querySelectorAll('a')].map((a) => a.textContent)).toEqual([
      'Categoría: Este campo es obligatorio',
      'Género: Este campo es obligatorio',
      'Modalidad: Este campo es obligatorio',
      'Temporada: Este campo es obligatorio',
    ])
    expect(field('Categoría')).toHaveAttribute('aria-invalid', 'true')
    expect(field('Categoría')).toHaveAccessibleDescription('Este campo es obligatorio')
    expect(sent).toEqual([])
  })

  test('bien: envía el equipo y vuelve a la portada en la temporada del equipo, sin el formulario detrás', async () => {
    const sent = fakeServer({})
    const router = await openForm('2025/26')
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2025/26'))
    await fillTeam()
    await choose('Temporada', '2026/27')

    await fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))

    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/?temporada=2026-27'))
    expect(sent).toEqual([{ category: 'alevin', gender: 'femenino', modality: 'futbol_7', seasonId: seasons[0]!.id }])
    // El formulario se ha sustituido: «Atrás» lleva a la portada de partida.
    router.back()
    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/?temporada=2025-26'))
  })

  test('el equipo ya está en esa temporada: el aviso arriba, y lo escrito sigue ahí', async () => {
    fakeServer({ createTeam: () => problem(409, 'TEAM_ALREADY_REGISTERED') })
    await openForm('2026/27')
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2026/27'))
    await fillTeam()
    await fireEvent.update(screen.getByRole('textbox', { name: 'Letra' }), 'A')

    await fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))

    expect(await screen.findByRole('alert')).toHaveTextContent('Ese equipo ya está dado de alta en esta temporada')
    expect(screen.getByRole('alert')).toHaveTextContent('Código: TEAM_ALREADY_REGISTERED')
    expect(field('Categoría')).toHaveTextContent('Alevín')
    expect(screen.getByRole('textbox', { name: 'Letra' })).toHaveValue('A')
  })

  test('un error de valor del servidor sale junto a su campo, con su motivo', async () => {
    fakeServer({ createTeam: () => problem(422, 'INVALID_VALUE', 'letter: no puede estar vacía') })
    await openForm('2026/27')
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2026/27'))
    await fillTeam()
    await fireEvent.update(screen.getByRole('textbox', { name: 'Letra' }), ' ')

    await fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))

    await waitFor(() =>
      expect(screen.getByRole('textbox', { name: 'Letra' })).toHaveAccessibleDescription(
        'Si el club tiene varios equipos de la misma categoría: A, B… no puede estar vacía',
      ),
    )
    expect(screen.getByRole('group', { name: 'Revisa este campo:' })).toHaveFocus()
  })

  test('mientras se guarda, el botón está bloqueado', async () => {
    fakeServer({ createTeam: () => new Promise<Response>(() => {}) as never })
    await openForm('2026/27')
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2026/27'))
    await fillTeam()

    await fireEvent.click(screen.getByRole('button', { name: 'Guardar' }))

    await waitFor(() => expect(screen.getByRole('button', { name: /Guardar/ })).toBeDisabled())
  })
})

describe('al salir', () => {
  test('«Cancelar» sin cambios vuelve a la portada de partida sin preguntar, y sin el formulario detrás', async () => {
    fakeServer({})
    const router = await openForm('2025/26')
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2025/26'))

    await fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))

    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/?temporada=2025-26'))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  test('llegado sin temporada, «Cancelar» vuelve a /', async () => {
    fakeServer({})
    const router = await openForm()
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2026/27'))

    await fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))

    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/'))
  })

  test('con cambios, pregunta; «Seguir editando» se queda, y «Salir sin guardar» sale', async () => {
    fakeServer({})
    const router = await openForm('2025/26')
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2025/26'))
    await choose('Categoría', 'Cadete')

    await fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    const dialog = await screen.findByRole('dialog', { name: 'Cambios sin guardar' })
    expect(dialog).toHaveTextContent('Tienes cambios sin guardar. ¿Salir sin guardar?')
    await fireEvent.click(screen.getByRole('button', { name: 'Seguir editando' }))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(router.currentRoute.value.path).toBe('/equipos/nuevo')
    expect(field('Categoría')).toHaveTextContent('Cadete')

    await fireEvent.click(screen.getByRole('button', { name: 'Cancelar' }))
    await fireEvent.click(await screen.findByRole('button', { name: 'Salir sin guardar' }))
    await waitFor(() => expect(router.currentRoute.value.fullPath).toBe('/?temporada=2025-26'))
  })
})

describe('«Crear nueva temporada» (§3.3)', () => {
  const newSeasonButton = () => screen.getByRole('button', { name: 'Crear nueva temporada' })
  const labelField = () => screen.getByRole('textbox', { name: /^Temporada/ })

  async function openDialog() {
    await fireEvent.click(await screen.findByRole('button', { name: 'Crear nueva temporada' }))
    return screen.findByRole('dialog', { name: 'Crear nueva temporada' })
  }

  test('mientras cargan las temporadas no está: no se sabe todavía cuáles hay', async () => {
    fakeServer({ seasons: () => new Promise<Response>(() => {}) as never })
    await openForm()

    expect(screen.queryByRole('button', { name: 'Crear nueva temporada' })).not.toBeInTheDocument()
  })

  test('el club sin temporadas: crea la primera, que entra en el selector elegida, y lo rellenado sigue ahí', async () => {
    const sent = fakeServer({ seasons: () => Response.json([]) })
    await openForm()
    await choose('Categoría', 'Cadete')

    await openDialog()
    await fireEvent.update(labelField(), '2027/28')
    await fireEvent.click(screen.getByRole('button', { name: 'Crear' }))

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(sent).toEqual([{ label: '2027/28' }])
    expect(field('Temporada')).toHaveTextContent('2027/28')
    expect(field('Categoría')).toHaveTextContent('Cadete')
  })

  test('con temporadas, la nueva entra en su sitio por fecha, la primera', async () => {
    fakeServer({})
    await openForm('2025/26')
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2025/26'))

    await openDialog()
    await fireEvent.update(labelField(), '2027/28')
    await fireEvent.click(screen.getByRole('button', { name: 'Crear' }))
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2027/28'))

    await fireEvent.click(field('Temporada'))
    expect((await screen.findAllByRole('option')).map((o) => o.textContent)).toEqual(['2027/28', '2026/27', '2025/26'])
  })

  test('con mal formato, el error del catálogo junto al campo, con su ejemplo, y sin llegar al servidor', async () => {
    const sent = fakeServer({})
    await openForm()
    await openDialog()

    await fireEvent.update(labelField(), '2026-27')
    await fireEvent.click(screen.getByRole('button', { name: 'Crear' }))

    await waitFor(() => expect(labelField()).toHaveAccessibleDescription('El formato no es válido. Por ejemplo: 2024/25'))
    expect(labelField()).toHaveAttribute('aria-invalid', 'true')
    // El foco vuelve al campo, para que el lector lea el motivo.
    expect(labelField()).toHaveFocus()
    expect(sent).toEqual([])
  })

  test('al volver a abrirlo, el campo está vacío y sin el error de antes', async () => {
    fakeServer({})
    await openForm()
    const dialog = await openDialog()
    await fireEvent.update(labelField(), '2026-27')
    await fireEvent.click(screen.getByRole('button', { name: 'Crear' }))
    await waitFor(() => expect(labelField()).toHaveAttribute('aria-invalid', 'true'))
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Cancelar' }))
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())

    await openDialog()

    expect(labelField()).toHaveValue('')
    expect(labelField()).not.toHaveAttribute('aria-invalid')
  })

  test('con años que no siguen, el motivo del servidor junto al campo', async () => {
    fakeServer({
      createSeason: () =>
        problem(422, 'INVALID_VALUE', 'label: debe ser AAAA/AB con AB el año siguiente, como "2025/26"'),
    })
    await openForm()
    await openDialog()

    await fireEvent.update(labelField(), '2026/28')
    await fireEvent.click(screen.getByRole('button', { name: 'Crear' }))

    await waitFor(() =>
      expect(labelField()).toHaveAccessibleDescription('debe ser AAAA/AB con AB el año siguiente, como "2025/26"'),
    )
    expect(screen.getByRole('dialog')).toBeInTheDocument()
  })

  test('una que ya existe (archivada, por ejemplo): el aviso arriba del diálogo, que sigue abierto', async () => {
    fakeServer({ createSeason: () => problem(409, 'SEASON_ALREADY_EXISTS', "label: ya hay una temporada con '2024/25'") })
    await openForm('2026/27')
    const dialog = await openDialog()

    await fireEvent.update(labelField(), '2024/25')
    await fireEvent.click(screen.getByRole('button', { name: 'Crear' }))

    await waitFor(() =>
      expect(within(dialog).getByRole('alert')).toHaveTextContent(
        'Ya existe una temporada con esa etiqueta. Si no la ves en el selector, está archivada: se recupera desde Temporadas',
      ),
    )
    expect(labelField()).toHaveValue('2024/25')
    expect(labelField()).not.toHaveAttribute('aria-invalid')
  })

  test('«Cancelar» no crea nada, deja el selector como estaba y el foco vuelve al botón', async () => {
    const sent = fakeServer({})
    await openForm('2025/26', true)
    await waitFor(() => expect(field('Temporada')).toHaveTextContent('2025/26'))
    newSeasonButton().focus()

    const dialog = await openDialog()
    await waitFor(() => expect(labelField()).toHaveFocus())
    await fireEvent.update(labelField(), '2027/28')
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Cancelar' }))

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(sent).toEqual([])
    expect(field('Temporada')).toHaveTextContent('2025/26')
    await waitFor(() => expect(newSeasonButton()).toHaveFocus())
  })

  test('Escape la cierra como «Cancelar»', async () => {
    const sent = fakeServer({})
    await openForm('2025/26', true)
    const dialog = await openDialog()

    await fireEvent.keyDown(dialog, { key: 'Escape', code: 'Escape' })

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument())
    expect(sent).toEqual([])
    expect(field('Temporada')).toHaveTextContent('2025/26')
  })

  test('al crearla, el foco va al selector, donde está elegida', async () => {
    fakeServer({ seasons: () => Response.json([]) })
    await openForm(undefined, true)

    await openDialog()
    await fireEvent.update(labelField(), '2027/28')
    await fireEvent.click(screen.getByRole('button', { name: 'Crear' }))

    await waitFor(() => expect(field('Temporada')).toHaveFocus())
  })
})
