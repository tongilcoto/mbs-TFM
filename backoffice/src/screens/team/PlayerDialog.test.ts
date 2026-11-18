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

type TestPlayer = Record<string, unknown> & { id: string; fullName: string }

function player(id: string, fullName: string, shirtNumber: number | null): TestPlayer {
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
    if (path.startsWith('/players/') && request.method === 'PUT' && !path.endsWith('/photo')) {
      const body = await request.json()
      server.bodies.push(body)
      if (fields.create) return fields.create()
      return Response.json({ ...player(path.split('/')[2]!, body.fullName, body.shirtNumber), birthYear: body.birthYear })
    }
    if (path.endsWith('/photo')) {
      server.photoTypes.push(request.headers.get('Content-Type') ?? '')
      return fields.photo ? fields.photo() : new Response(null, { status: 204 })
    }
    throw new Error(`Petición no esperada: ${request.method} ${path}`)
  })
  return server
}

function openDialog(players: TestPlayer[] = [player('a', 'MARCOS DÍAZ', 9)], edited?: TestPlayer) {
  return render(PlayerDialog, {
    props: { teamId: TEAM, teamTitle: 'Cadete A', season, players: players as never, player: edited as never },
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

  test('los cinco campos, a la vista desde el principio (decisión 2 de R6.12)', async () => {
    fakeServer()
    openDialog()

    expect(await searchBox()).toHaveAccessibleDescription('Desde 3 letras, busca entre los jugadores del club')
    expect(screen.getByRole('textbox', { name: /Año de nacimiento \(obligatorio\)/ })).toBeEnabled()
    expect(screen.getByRole('textbox', { name: 'Dorsal' })).toHaveAccessibleDescription('Del 1 al 99')
    expect(screen.getByRole('combobox', { name: /Demarcación/ })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Elegir foto' })).toHaveAccessibleDescription('JPEG o PNG, hasta 5 MB')
    expect(screen.queryByRole('button', { name: 'Elegir otro jugador' })).not.toBeInTheDocument()
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

  // Lo que se ve tiene que estar en lo que lee el lector, con sus espacios: axe lo pide (R6.18).
  test('el nombre y el detalle de cada opción, separados por un espacio, como en lo que lee el lector', async () => {
    fakeServer({ profiles: [profile()] })
    openDialog()
    await typeInSearch('juan')

    const option = await screen.findByRole('option', { name: /Juan García Fuente/ }, { timeout: 2000 })
    expect(option.textContent?.replace(/\s+/g, ' ')).toContain('Juan García Fuente 2010 · Celtic Infantil A 2025/26')
  })

  // Sin el aviso de PrimeVue de «sin resultados» (R6.18): con menos de tres letras no se busca, y no sale nada.
  test('con menos de tres letras no sale ninguna lista', async () => {
    const server = fakeServer({ profiles: [profile()] })
    openDialog()
    await typeInSearch('ju')
    await new Promise((resolve) => setTimeout(resolve, 400))

    expect(screen.queryAllByRole('option')).toHaveLength(0)
    expect(server.asked.some((asked) => asked.startsWith('GET /player-profiles'))).toBe(false)
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

  test('elegirlo deja lo escrito en el nombre, y el foco pasa al año', async () => {
    fakeServer()
    openDialog()
    await chooseNew()

    expect(screen.getByRole('combobox', { name: /Nombre y apellidos \(obligatorio\)/ })).toHaveValue('Ana Ruiz')
    await waitFor(() => expect(screen.getByRole('textbox', { name: /Año de nacimiento \(obligatorio\)/ })).toHaveFocus())
  })

  test('sin elegir nada en la lista, también es un jugador nuevo', async () => {
    const server = fakeServer()
    const { emitted } = openDialog()
    await fireEvent.update(await searchBox(), 'Ana Ruiz')
    await fireEvent.update(screen.getByRole('textbox', { name: /Año de nacimiento/ }), '2012')
    await press('Guardar')

    await waitFor(() => expect(emitted().saved).toEqual([['Guardado', false]]))
    expect(server.bodies).toEqual([{ teamId: TEAM, seasonId: 'id-2026', fullName: 'Ana Ruiz', birthYear: 2012, shirtNumber: null, position: null }])
  })

  test('sin nombre ni año, dice qué falta, sin enviar nada', async () => {
    const server = fakeServer()
    openDialog()
    await chooseNew()
    await fireEvent.update(screen.getByRole('combobox', { name: /Nombre y apellidos/ }), '')
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

describe('corregir (R6.12, decisión 1)', () => {
  const ana = { ...player('b', 'ANA RUIZ', 4), position: 'portero', photoUrl: '/api/v1/player-photos/ana.jpg' }
  const editDialog = () => screen.findByRole('dialog', { name: 'Corregir a Ana Ruiz' })
  const pressIn = async (label: string) => fireEvent.click(within(await editDialog()).getByRole('button', { name: label }))

  test('trae sus datos, en dos bloques: lo del jugador y lo de esta plantilla', async () => {
    fakeServer()
    openDialog([player('a', 'MARCOS DÍAZ', 9), ana], ana)

    const ofPlayer = await screen.findByRole('group', { name: 'Del jugador, en todas sus temporadas' })
    expect(within(ofPlayer).getByRole('textbox', { name: /Nombre y apellidos/ })).toHaveValue('Ana Ruiz')
    const ofRoster = screen.getByRole('group', { name: 'En Cadete A, 2026/27' })
    expect(within(ofRoster).getByRole('textbox', { name: 'Dorsal' })).toHaveValue('4')
    expect(within(ofRoster).getByRole('combobox', { name: /Demarcación/ })).toHaveTextContent('Portero')
    expect(within(ofRoster).getByRole('img', { name: 'Ana Ruiz' })).toBeInTheDocument()
    expect(within(await editDialog()).queryByRole('button', { name: 'Guardar y dar de alta otro' })).not.toBeInTheDocument()
  })

  test('el año que ya tiene está bloqueado', async () => {
    fakeServer()
    openDialog([ana], ana)

    const year = await screen.findByRole('textbox', { name: /Año de nacimiento/ })
    expect(year).toHaveValue('2011')
    expect(year).toBeDisabled()
  })

  test('corregir el nombre lo envía con lo demás como estaba, y cierra con «Guardado»', async () => {
    const server = fakeServer()
    const { emitted } = openDialog([ana], ana)
    await fireEvent.update(await screen.findByRole('textbox', { name: /Nombre y apellidos/ }), 'Ana Ruíz')
    await pressIn('Guardar')

    await waitFor(() => expect(emitted().saved).toEqual([['Guardado', false]]))
    expect(server.bodies).toEqual([{ fullName: 'Ana Ruíz', birthYear: 2011, shirtNumber: 4, position: 'portero' }])
    expect(server.asked.some((a) => a.includes('/photo'))).toBe(false)
  })

  test('el dorsal de otro dice quién lo tiene; el suyo no cuenta', async () => {
    fakeServer({ create: () => problem(409, 'SHIRT_NUMBER_TAKEN') })
    openDialog([player('a', 'MARCOS DÍAZ', 9), ana], ana)
    await fireEvent.update(await screen.findByRole('textbox', { name: 'Dorsal' }), '9')
    await pressIn('Guardar')

    expect(await screen.findAllByText('Ese dorsal ya lo tiene Marcos Díaz')).not.toHaveLength(0)
  })

  test('quitar la foto la quita de su fila', async () => {
    const server = fakeServer()
    const { emitted } = openDialog([ana], ana)
    await pressIn('Quitar foto')
    await pressIn('Guardar')

    await waitFor(() => expect(emitted().saved).toBeDefined())
    expect(server.asked).toContain('DELETE /players/b/photo')
  })

  describe('un jugador sin año', () => {
    const sinAño = { ...ana, birthYear: null }

    test('el año se puede poner, y avisa de que no se podrá cambiar', async () => {
      fakeServer()
      openDialog([sinAño], sinAño)

      const year = await screen.findByRole('textbox', { name: /Año de nacimiento/ })
      expect(year).toBeEnabled()
      expect(year).toHaveAccessibleDescription('Una vez puesto, no se puede cambiar')
    })

    test('al guardar con el año, pregunta antes; confirmar lo envía', async () => {
      const server = fakeServer()
      const { emitted } = openDialog([sinAño], sinAño)
      await fireEvent.update(await screen.findByRole('textbox', { name: /Año de nacimiento/ }), '2012')
      await pressIn('Guardar')

      const confirm = await screen.findByRole('dialog', { name: 'Poner el año de nacimiento' })
      expect(confirm).toHaveTextContent('El año no se podrá cambiar después.')
      expect(confirm).toHaveTextContent('Si te equivocas, tendrás que dar de baja al jugador y darlo de alta como nuevo.')
      expect(server.bodies).toEqual([])

      await fireEvent.click(within(confirm).getByRole('button', { name: 'Guardar el año' }))
      await waitFor(() => expect(emitted().saved).toEqual([['Guardado', false]]))
      expect(server.bodies).toEqual([{ fullName: 'Ana Ruiz', birthYear: 2012, shirtNumber: 4, position: 'portero' }])
    })

    test('volver de la pregunta no envía nada, y el diálogo sigue abierto', async () => {
      const server = fakeServer()
      const { emitted } = openDialog([sinAño], sinAño)
      await fireEvent.update(await screen.findByRole('textbox', { name: /Año de nacimiento/ }), '2012')
      await pressIn('Guardar')
      await fireEvent.click(within(await screen.findByRole('dialog', { name: 'Poner el año de nacimiento' })).getByRole('button', { name: 'Volver' }))

      await waitFor(() => expect(screen.queryByRole('dialog', { name: 'Poner el año de nacimiento' })).not.toBeInTheDocument())
      expect(await editDialog()).toBeInTheDocument()
      expect(server.bodies).toEqual([])
      expect(emitted().saved).toBeUndefined()
    })

    test('el nombre y el año a la vez no se guardan, y dice qué hacer', async () => {
      const server = fakeServer()
      openDialog([sinAño], sinAño)
      await fireEvent.update(await screen.findByRole('textbox', { name: /Nombre y apellidos/ }), 'Lucía Gómez')
      await fireEvent.update(screen.getByRole('textbox', { name: /Año de nacimiento/ }), '2012')
      await pressIn('Guardar')

      expect(await screen.findByRole('alert')).toHaveTextContent(
        'No se pueden cambiar a la vez el nombre y el año. Si es otra persona, da de baja a este jugador y da de alta al otro como nuevo.',
      )
      expect(screen.queryByRole('dialog', { name: 'Poner el año de nacimiento' })).not.toBeInTheDocument()
      expect(server.bodies).toEqual([])
    })

    test('sin poner el año, se guarda sin preguntar', async () => {
      const server = fakeServer()
      const { emitted } = openDialog([sinAño], sinAño)
      await fireEvent.update(await screen.findByRole('textbox', { name: 'Dorsal' }), '5')
      await pressIn('Guardar')

      await waitFor(() => expect(emitted().saved).toBeDefined())
      expect(server.bodies).toEqual([{ fullName: 'Ana Ruiz', birthYear: null, shirtNumber: 5, position: 'portero' }])
    })
  })
})
