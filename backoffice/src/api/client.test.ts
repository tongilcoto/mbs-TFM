import { afterEach, describe, expect, test, vi } from 'vitest'
import { api, REQUEST_TIMEOUT_MS, ServerNotRespondingError } from './client'

// Un fetch de mentira: apunta qué dirección se pidió y contesta lo que le diga cada prueba.
// Así se prueba la pieza de conexión sola, sin servidor (ADR, decisión 6, nivel 1).
function fakeFetch(answer: (request: Request) => Promise<Response>) {
  const requested: string[] = []
  vi.stubGlobal('fetch', (input: Request) => {
    requested.push(new URL(input.url).pathname)
    return answer(input)
  })
  return requested
}

// Un servidor que no contesta nunca; solo se entera si le cancelan la petición, como el fetch de verdad.
function silentServer(request: Request): Promise<Response> {
  return new Promise((_, reject) => {
    request.signal.addEventListener('abort', () => reject(request.signal.reason))
  })
}

// Un servidor que tarda 1 s en contestar con el club; si le cancelan antes, no contesta.
function slowServer(request: Request): Promise<Response> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve(clubResponse()), 1_000)
    request.signal.addEventListener('abort', () => {
      clearTimeout(timer)
      reject(request.signal.reason)
    })
  })
}

// Apunta en qué acaba una petición sin esperarla, para poder mirar mientras el reloj de mentira avanza.
function watch<T>(promise: Promise<T>) {
  const outcome: { state: 'waiting' | 'answered' | 'failed'; value?: unknown } = { state: 'waiting' }
  promise.then(
    (value) => Object.assign(outcome, { state: 'answered', value }),
    (error) => Object.assign(outcome, { state: 'failed', value: error }),
  )
  return outcome
}

function clubResponse(): Response {
  return Response.json({ id: 'celtic-castilla', name: 'Celtic Castilla' })
}

afterEach(() => {
  vi.unstubAllGlobals()
  vi.useRealTimers()
})

describe('la conexión con el servidor', () => {
  test('pedir el club sale a /api/v1/club', async () => {
    const requested = fakeFetch(async () => clubResponse())

    await api.GET('/club')

    expect(requested).toEqual(['/api/v1/club'])
  })

  test('sin respuesta en 30 s, llega el error «el servidor no responde»', async () => {
    vi.useFakeTimers()
    fakeFetch(silentServer)

    const outcome = watch(api.GET('/club'))

    await vi.advanceTimersByTimeAsync(REQUEST_TIMEOUT_MS - 1)
    expect(outcome.state).toBe('waiting')

    await vi.advanceTimersByTimeAsync(1)
    expect(outcome.state).toBe('failed')
    expect(outcome.value).toBeInstanceOf(ServerNotRespondingError)
  })

  test('una petición cancelada no entrega nada', async () => {
    vi.useFakeTimers()
    fakeFetch(slowServer)
    const leaving = new AbortController()

    const outcome = watch(api.GET('/club', { signal: leaving.signal }))
    await vi.advanceTimersByTimeAsync(500)
    leaving.abort()
    await vi.advanceTimersByTimeAsync(1_000)

    expect(outcome.state).toBe('failed')
    expect(outcome.value).toMatchObject({ name: 'AbortError' })
  })
})
