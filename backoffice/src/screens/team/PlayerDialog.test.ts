import { fireEvent, render, screen, waitFor, within } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test, vi } from 'vitest'
import { primeVueOptions } from '../../theme/primevue'
import PlayerDialog from './PlayerDialog.vue'

// El diálogo del alta de un jugador (plan R6, decisiones 7 a 10). Los escenarios miran lo que queda guardado; aquí,
// lo que hace el diálogo con cada respuesta del servidor.

const TEAM = '11111111-1111-4111-8111-111111111111'
const season = {
  id: 'id-2026',
  label: '2026/27',
  startDate: '2026-07-01',
  endDate: '2027-06-30',
  isCurrent: true,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
}

function player(id: string, fullName: string, shirtNumber: number | null) {
  return { id, profileId: `perfil-${id}`, teamId: TEAM, seasonId: 'id-2026', fullName, birthYear: 2011, shirtNumber, position: null, federated: null, lastListedAt: null, photoUrl: null, createdAt: 'x', updatedAt: 'x' }
}

function profile(fields: Record<string, unknown> = {}) {
  return {
    profileId: 'perfil-juan',
    fullName: 'JUAN GARCÍA FUENTE',
    birthYear: 2010,
    lastShirtNumber: 7,
    lastPosition: 'defensa',
    lastPhotoUrl: null,
    lastRoster: { team: { teamId: 'infantil', displayName: 'Celtic Infantil A' }, seasonId: 'id-2025', seasonLabel: '2025/26' },
    otherTeamThisSeason: null,
    ...fields,
  }
}

const problem = (status: number, code: string) => Response.json({ type: 'about:blank', title: 'x', status, code }, { status })

// El servidor de mentira: lo que encuentra el buscador, cómo responde el alta y la foto. Apunta lo que se le pidió.
function fakeServer(fields: { profiles?: unknown[]; create?: () => Response; photo?: () => Response } = {}) {
  const server = { asked: [] as string[], bodies: [] as unknown[], photoTypes: [] as string[] }
  vi.stubGlobal('fetch', async (request: Request) => {
    const url = new URL(request.url)
    const path = url.pathname.replace('/api/v1', '')
    server.asked.push(`${request.method} ${path}${url.search}`)
    if (path === '/player-profiles') return Response.json(fields.profiles ?? [])
    if (path === '/players' && request.method === 'POST') {
      const body = await request.json()
      server.bodies.push(body)
      if (fields.create) return fields.create()
      return Response.json({ ...player('nuevo', body.fullName ?? 'JUAN GARCÍA FUENTE', body.shirtNumber) }, { status: 201 })
    }
    if (path.endsWith('/photo')) {
      server.photoTypes.push(request.headers.get('Content-Type') ?? '')
      return fields.photo ? fields.photo() : new Response(null, { status: 204 })
    }
    throw new Error(`Petición no esperada: ${request.method} ${path}`)
  })
  return server
}

function openDialog(players = [player('a', 'MARCOS DÍAZ', 9)]) {
  return render(PlayerDialog, {
    props: { teamId: TEAM, teamTitle: 'Cadete A', season, players },
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })
}

const dialog = () => screen.findByRole('dialog', { name: 'Dar de alta un jugador en Cadete A, 2026/27' })
const searchBox = () => screen.findByRole('combobox', { name: /Nombre y apellidos/ })

async function typeInSearch(text: string) {
  const box = await searchBox()
  await fireEvent.update(box, text)
  await fireEvent.input(box)
}

async function chooseOption(name: RegExp) {
  await fireEvent.click(await screen.findByRole('option', { name }, { timeout: 2000 }))
}

const press = async (label: string) => fireEvent.click(within(await dialog()).getByRole('button', { name: label }))

afterEach(() => vi.unstubAllGlobals())

describe('abrir el diálogo', () => {
  test('el título dice el equipo y la temporada, y el buscador está vacío y tiene el foco', async () => {
    fakeServer()
    openDialog()

    await dialog()
    const box = await searchBox()
    expect(box).toHaveValue('')
    await waitFor(() => expect(box).toHaveFocus())
  })
})

describe('el buscador', () => {
  test('ofrece a los del club con su año y su último equipo, y al final el jugador nuevo', async () => {
    const server = fakeServer({ profiles: [profile()] })
    openDialog()
    await typeInSearch('juan')

    expect(await screen.findByRole('option', { name: /Juan García Fuente/ }, { timeout: 2000 })).toHaveTextContent(
      '2010 · Celtic Infantil A 2025/26',
    )
    const options = screen.getAllByRole('option')
    expect(options.at(-1)).toHaveTextContent('Dar de alta a «juan» como jugador nuevo')
    expect(server.asked).toContain(`GET /player-profiles?q=juan&teamId=${TEAM}&seasonId=id-2026`)
  })

  test('el que está en otro equipo esta temporada sale desactivado, diciendo dónde', async () => {
    fakeServer({ profiles: [profile({ otherTeamThisSeason: { teamId: 'infantil', displayName: 'Celtic Infantil A' } })] })
    openDialog()
    await typeInSearch('juan')

    const option = await screen.findByRole('option', { name: /Juan García Fuente/ }, { timeout: 2000 })
    expect(option).toHaveAttribute('aria-disabled', 'true')
    expect(option).toHaveTextContent('Ya está en Celtic Infantil A')
  })
})

describe('elegir uno del club', () => {
  test('trae su nombre y su año, bloqueados, y de su perfil el dorsal, la demarcación y la foto', async () => {
    fakeServer({ profiles: [profile({ lastPhotoUrl: '/api/v1/player-photos/juan.jpg' })] })
    openDialog()
    await typeInSearch('juan')
    await chooseOption(/Juan García Fuente/)

    expect(screen.getByRole('textbox', { name: /Nombre y apellidos/ })).toHaveValue('Juan García Fuente')
    expect(screen.getByRole('textbox', { name: /Nombre y apellidos/ })).toBeDisabled()
    expect(screen.getByRole('textbox', { name: /Año de nacimiento/ })).toHaveValue('2010')
    expect(screen.getByRole('textbox', { name: /Año de nacimiento/ })).toBeDisabled()
    expect(screen.getByRole('textbox', { name: /Dorsal/ })).toHaveValue('7')
    expect(screen.getByRole('combobox', { name: /Demarcación/ })).toHaveTextContent('Defensa')
    expect(screen.getByRole('img', { name: 'Juan García Fuente' })).toHaveAttribute('src', '/api/v1/player-photos/juan.jpg')
  })

  test('guardar envía su perfil, el dorsal y la demarcación, y cierra con «Guardado»', async () => {
    const server = fakeServer({ profiles: [profile()] })
    const { emitted } = openDialog()
    await typeInSearch('juan')
    await chooseOption(/Juan García Fuente/)
    await press('Guardar')

    await waitFor(() => expect(emitted().saved).toEqual([['Guardado', false]]))
    expect(server.bodies).toEqual([{ teamId: TEAM, seasonId: 'id-2026', profileId: 'perfil-juan', shirtNumber: 7, position: 'defensa' }])
    expect(server.asked.some((a) => a.includes('/photo'))).toBe(false)
  })

  test('si se quita la foto que traía el perfil, se quita también de su fila', async () => {
    const server = fakeServer({ profiles: [profile({ lastPhotoUrl: '/api/v1/player-photos/juan.jpg' })] })
    const { emitted } = openDialog()
    await typeInSearch('juan')
    await chooseOption(/Juan García Fuente/)
    await press('Quitar foto')
    await press('Guardar')

    await waitFor(() => expect(emitted().saved).toBeDefined())
    expect(server.asked).toContain('DELETE /players/nuevo/photo')
  })
})

describe('un jugador nuevo', () => {
  async function chooseNew(typed = 'Ana Ruiz') {
    await typeInSearch(typed)
    await chooseOption(/como jugador nuevo/)
  }

  test('pide el nombre, con lo escrito, y el año; el dorsal, la demarcación y la foto, opcionales', async () => {
    fakeServer()
    openDialog()
    await chooseNew()

    expect(screen.getByRole('textbox', { name: /Nombre y apellidos \(obligatorio\)/ })).toHaveValue('Ana Ruiz')
    expect(screen.getByRole('textbox', { name: /Año de nacimiento \(obligatorio\)/ })).toHaveValue('')
    expect(screen.getByRole('textbox', { name: 'Dorsal' })).toHaveAccessibleDescription('Del 1 al 99')
    expect(screen.getByLabelText('Foto')).toHaveAccessibleDescription('JPEG o PNG, hasta 5 MB')
  })

  test('sin nombre ni año, dice qué falta, sin enviar nada', async () => {
    const server = fakeServer()
    openDialog()
    await chooseNew()
    await fireEvent.update(screen.getByRole('textbox', { name: /Nombre y apellidos/ }), '')
    await press('Guardar')

    expect(await screen.findAllByText('Escribe el nombre y al menos un apellido')).not.toHaveLength(0)
    expect(screen.getAllByText('Falta el año de nacimiento')).not.toHaveLength(0)
    expect(server.bodies).toEqual([])
  })

  test('guardar envía el nombre limpio y el año; con una foto, la sube después con su tipo', async () => {
    const server = fakeServer()
    const { emitted } = openDialog()
    await chooseNew('  Ana   Ruiz ')
    await fireEvent.update(screen.getByRole('textbox', { name: /Año de nacimiento/ }), '2012')
    await fireEvent.change(screen.getByLabelText('Foto'), { target: { files: [new File(['x'], 'ana.png', { type: 'image/png' })] } })
    await press('Guardar')

    await waitFor(() => expect(emitted().saved).toEqual([['Guardado', false]]))
    expect(server.bodies).toEqual([{ teamId: TEAM, seasonId: 'id-2026', fullName: 'Ana Ruiz', birthYear: 2012, shirtNumber: null, position: null }])
    expect(server.asked).toContain('PUT /players/nuevo/photo')
    expect(server.photoTypes).toEqual(['image/png'])
  })

  test('si la foto no vale, queda dado de alta y el aviso dice por qué', async () => {
    fakeServer({ photo: () => problem(400, 'NOT_AN_IMAGE') })
    const { emitted } = openDialog()
    await chooseNew()
    await fireEvent.update(screen.getByRole('textbox', { name: /Año de nacimiento/ }), '2012')
    await fireEvent.change(screen.getByLabelText('Foto'), { target: { files: [new File(['x'], 'ana.jpg', { type: 'image/jpeg' })] } })
    await press('Guardar')

    await waitFor(() => expect(emitted().saved).toEqual([['Guardado, sin la foto: el fichero no es una imagen.', false]]))
  })

  test('un dorsal cogido dice quién lo tiene en la plantilla', async () => {
    fakeServer({ create: () => problem(409, 'SHIRT_NUMBER_TAKEN') })
    const { emitted } = openDialog()
    await chooseNew()
    await fireEvent.update(screen.getByRole('textbox', { name: /Año de nacimiento/ }), '2012')
    await fireEvent.update(screen.getByRole('textbox', { name: 'Dorsal' }), '9')
    await press('Guardar')

    expect(await screen.findAllByText('Ese dorsal ya lo tiene Marcos Díaz')).not.toHaveLength(0)
    expect(emitted().saved).toBeUndefined()
  })

  test('«Guardar y dar de alta otro» guarda, deja el diálogo vacío con el foco en el buscador, y dice a quién', async () => {
    fakeServer()
    const { emitted } = openDialog()
    await chooseNew()
    await fireEvent.update(screen.getByRole('textbox', { name: /Año de nacimiento/ }), '2012')
    await press('Guardar y dar de alta otro')

    await waitFor(() => expect(emitted().saved).toEqual([['Guardado', true]]))
    expect(await screen.findByText('Ana Ruiz: guardado.')).toHaveAttribute('role', 'status')
    const box = await searchBox()
    expect(box).toHaveValue('')
    await waitFor(() => expect(box).toHaveFocus())
  })
})

describe('sin elegir a nadie', () => {
  test('guardar lo dice en el buscador', async () => {
    const server = fakeServer()
    openDialog()
    await searchBox()
    await press('Guardar')

    expect(await screen.findAllByText('Elige un jugador de la lista, o da de alta uno nuevo')).not.toHaveLength(0)
    expect(server.bodies).toEqual([])
  })
})
