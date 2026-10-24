import { fireEvent, render, screen, waitFor } from '@testing-library/vue'
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
function fakeServer(answers: { seasons?: () => Response; createTeam?: () => Response }) {
  const sent: unknown[] = []
  vi.stubGlobal('fetch', async (request: Request) => {
    const path = new URL(request.url).pathname
    if (request.method === 'GET' && path === '/api/v1/seasons') return (answers.seasons ?? (() => Response.json(seasons)))()
    if (request.method === 'POST' && path === '/api/v1/teams') {
      sent.push(await request.json())
      return (answers.createTeam ?? (() => Response.json({}, { status: 201 })))()
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
async function openForm(fromHome?: string) {
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      { path: '/', component: defineComponent({ render: () => h('h1', 'Portada') }) },
      { path: '/equipos/nuevo', component: NewTeamScreen },
    ],
  })
  await router.push('/?temporada=2025-26')
  await router.push({ path: '/equipos/nuevo', state: fromHome ? { seasonLabel: fromHome } : {} })
  render(RouterView, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
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
