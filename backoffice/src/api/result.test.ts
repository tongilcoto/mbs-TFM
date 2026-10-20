import { afterEach, describe, expect, test, vi } from 'vitest'
import { api } from './client'
import { noConnection } from './errors'
import { asResult } from './result'

// Un fetch de mentira que contesta lo que diga cada prueba, como en client.test.ts.
function serverAnswers(answer: () => Promise<Response>) {
  vi.stubGlobal('fetch', answer)
}

afterEach(() => vi.unstubAllGlobals())

describe('lo que recibe la pantalla de una petición', () => {
  test('si va bien, los datos', async () => {
    serverAnswers(async () => Response.json({ shortName: 'Celtic Castilla' }))

    expect(await asResult(api.GET('/club'))).toEqual({ ok: true, data: { shortName: 'Celtic Castilla' } })
  })

  test('si el servidor responde con un error, el error ya traducido', async () => {
    serverAnswers(async () => Response.json({ status: 404, code: 'UNKNOWN_TENANT', title: 'Club desconocido' }, { status: 404 }))

    expect(await asResult(api.GET('/club'))).toEqual({
      ok: false,
      error: { message: 'Este club no existe. Revisa la dirección', code: 'UNKNOWN_TENANT', retry: false },
    })
  })

  test('si el recepcionista contesta 502 sin cuerpo, «no se ha podido conectar»', async () => {
    serverAnswers(async () => new Response(null, { status: 502, headers: { 'Content-Length': '0' } }))

    expect(await asResult(api.GET('/club'))).toEqual({ ok: false, error: noConnection })
  })

  test('si no se puede ni conectar, «no se ha podido conectar»', async () => {
    serverAnswers(async () => {
      throw new TypeError('fetch failed')
    })

    expect(await asResult(api.GET('/club'))).toEqual({ ok: false, error: noConnection })
  })

  test('si quien pidió la cancela, no hay nada que enseñar: la cancelación sigue su camino', async () => {
    serverAnswers(async () => {
      throw new DOMException('cancelada', 'AbortError')
    })

    await expect(asResult(api.GET('/club'))).rejects.toMatchObject({ name: 'AbortError' })
  })
})
