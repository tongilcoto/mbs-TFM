import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import { enoughLetters, latestSearch, profileOptions } from './profileSearch'

// El buscador del alta (plan R6, decisión 9): desde 3 letras, al dejar de teclear unos 300 ms, y quedándose solo con
// la respuesta de lo último escrito (R6.7).

describe('cuándo busca', () => {
  test('desde 3 letras, contando todas las palabras y sin espacios, guiones ni apóstrofos', () => {
    expect(enoughLetters('ju')).toBe(false)
    expect(enoughLetters("j o'")).toBe(false)
    expect(enoughLetters('ju a')).toBe(true)
    expect(enoughLetters('ñuñ')).toBe(true)
  })
})

describe('se queda con lo último escrito', () => {
  beforeEach(() => vi.useFakeTimers())
  afterEach(() => vi.useRealTimers())

  // Un servidor que contesta cuando la prueba quiere, a cada búsqueda por separado.
  function fakeServer() {
    const asked: { q: string; signal: AbortSignal; answer: (names: string[]) => void }[] = []
    const fetch = (q: string, signal: AbortSignal) =>
      new Promise<{ ok: true; data: string[] }>((resolve) => asked.push({ q, signal, answer: (data) => resolve({ ok: true, data }) }))
    return { asked, fetch }
  }

  test('busca al dejar de teclear 300 ms, no a cada letra', async () => {
    const server = fakeServer()
    const search = latestSearch(server.fetch, () => {})

    search.type('jua')
    await vi.advanceTimersByTimeAsync(200)
    search.type('juan')
    await vi.advanceTimersByTimeAsync(299)
    expect(server.asked).toHaveLength(0)

    await vi.advanceTimersByTimeAsync(1)
    expect(server.asked.map((a) => a.q)).toEqual(['juan'])
  })

  test('con menos de 3 letras no pregunta, y lo que había se quita', async () => {
    const server = fakeServer()
    const shown: (string[] | undefined)[] = []
    const search = latestSearch(server.fetch, (result) => shown.push(result))

    search.type('ju')
    await vi.advanceTimersByTimeAsync(300)

    expect(server.asked).toHaveLength(0)
    expect(shown).toEqual([undefined])
  })

  test('si la respuesta de «jua» llega después que la de «juan g», no se pinta', async () => {
    const server = fakeServer()
    const shown: (string[] | undefined)[] = []
    const search = latestSearch(server.fetch, (result) => shown.push(result))

    search.type('jua')
    await vi.advanceTimersByTimeAsync(300)
    search.type('juan g')
    await vi.advanceTimersByTimeAsync(300)

    server.asked[1]!.answer(['JUAN GARCÍA'])
    server.asked[0]!.answer(['JUAN GARCÍA', 'JUANA RUIZ'])
    await vi.runAllTimersAsync()

    expect(shown).toEqual([['JUAN GARCÍA']])
    expect(server.asked[0]!.signal.aborted).toBe(true)
  })

  test('al cerrar, lo que esté en marcha se cancela y no se pinta', async () => {
    const server = fakeServer()
    const shown: unknown[] = []
    const search = latestSearch(server.fetch, (result) => shown.push(result))

    search.type('juan')
    await vi.advanceTimersByTimeAsync(300)
    search.stop()
    server.asked[0]!.answer(['JUAN GARCÍA'])
    await vi.runAllTimersAsync()

    expect(shown).toEqual([])
    expect(server.asked[0]!.signal.aborted).toBe(true)
  })
})

describe('lo que ofrece', () => {
  function profile(fields: Record<string, unknown> = {}) {
    return {
      profileId: 'p1',
      fullName: 'JUAN GARCÍA FUENTE',
      birthYear: 2010,
      lastShirtNumber: 7,
      lastPosition: 'defensa',
      lastPhotoUrl: null,
      lastRoster: { team: { teamId: 'infantil-a', displayName: 'Celtic Infantil A' }, seasonId: 's', seasonLabel: '2024/25' },
      otherTeamThisSeason: null,
      ...fields,
    } as Parameters<typeof profileOptions>[0][number]
  }

  test('cada jugador con su nombre, su año y su último equipo y temporada; al final, el jugador nuevo', () => {
    expect(profileOptions([profile()], 'juan  garc')).toEqual([
      {
        kind: 'profile',
        key: 'p1',
        name: 'Juan García Fuente',
        detail: '2010 · Celtic Infantil A 2024/25',
        label: 'Juan García Fuente, 2010 · Celtic Infantil A 2024/25',
        disabled: false,
        profile: profile(),
      },
      {
        kind: 'new',
        key: 'nuevo',
        name: 'juan garc',
        detail: 'Dar de alta a «juan garc» como jugador nuevo',
        label: 'Dar de alta a «juan garc» como jugador nuevo',
        disabled: false,
      },
    ])
  })

  test('sin año, sin equipo de antes', () => {
    const [option] = profileOptions([profile({ birthYear: null, lastRoster: null })], 'juan')
    expect(option!.detail).toBe('Sin año')
  })

  test('el que ya está en otro equipo esta temporada, desactivado, y dice dónde', () => {
    const [option] = profileOptions(
      [profile({ otherTeamThisSeason: { teamId: 'cadete-b', displayName: 'Celtic Cadete B' } })],
      'juan',
    )
    expect(option).toMatchObject({ disabled: true, detail: '2010 · Ya está en Celtic Cadete B' })
  })
})
