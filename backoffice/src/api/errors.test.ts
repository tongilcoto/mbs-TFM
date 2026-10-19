import { describe, expect, test } from 'vitest'
import { errorFromResponse, noConnection } from './errors'

// Un error como los que manda el servidor (LLD-B §4): aquí solo cuentan el número y el código.
function problem(status: number, code: string) {
  return { status, code, title: 'Lo escribe el servidor', detail: 'No se enseña', type: 'https://example.com/x' }
}

describe('los errores con un código de la lista', () => {
  test('cada código sale con su mensaje y con el código para enseñarlo en pequeño', () => {
    expect(errorFromResponse(404, problem(404, 'UNKNOWN_TENANT'))).toEqual({
      message: 'Este club no existe. Revisa la dirección',
      code: 'UNKNOWN_TENANT',
      retry: false,
    })
  })

  test('el mensaje lo elige el código, no el número: un 500 puede ser «club sin preparar»', () => {
    expect(errorFromResponse(500, problem(500, 'TENANT_NOT_PROVISIONED')).message).toBe(
      'Este club aún no está preparado. Avisa a quien lo administra',
    )
  })

  test('la base de datos caída y la federación que no responde se pueden reintentar', () => {
    expect(errorFromResponse(503, problem(503, 'DATABASE_UNAVAILABLE'))).toEqual({
      message: 'No se ha podido conectar con el servidor',
      code: 'DATABASE_UNAVAILABLE',
      retry: true,
    })
    expect(errorFromResponse(504, problem(504, 'FEDERATION_UNREACHABLE'))).toEqual({
      message: 'La federación no responde',
      code: 'FEDERATION_UNREACHABLE',
      retry: true,
    })
  })

  test('el resto no se reintenta, aunque sea un 5xx: daría lo mismo', () => {
    expect(errorFromResponse(500, problem(500, 'INTERNAL')).retry).toBe(false)
    expect(errorFromResponse(409, problem(409, 'ALREADY_LINKED_TO_FEDERATION')).retry).toBe(false)
  })

  test('un 502 con código es del propio servidor, no del recepcionista', () => {
    expect(errorFromResponse(502, problem(502, 'INGESTION_FAILED'))).toEqual({
      message: 'La sincronización con la federación no ha terminado',
      code: 'INGESTION_FAILED',
      retry: false,
    })
  })
})

describe('un código que la web no conoce (un servidor más nuevo que ella)', () => {
  test.each([
    [404, 'No se ha encontrado'],
    [409, 'No se ha podido guardar'],
    [422, 'No se ha podido guardar'],
    [500, 'Error del servidor'],
    [502, 'Error del servidor'],
    [400, 'Algo ha fallado'],
  ])('un %i sale con el mensaje de su familia, y con su código', (status, message) => {
    expect(errorFromResponse(status, problem(status, 'CODIGO_NUEVO'))).toEqual({
      message,
      code: 'CODIGO_NUEVO',
      retry: false,
    })
  })

  test('un código que coincide con algo de JavaScript no cuenta como conocido', () => {
    expect(errorFromResponse(500, problem(500, 'toString')).message).toBe('Error del servidor')
  })
})

describe('una respuesta sin código', () => {
  // Así contesta el recepcionista cuando el servidor no está detrás (DW-18): 502 y el cuerpo vacío.
  test.each([502, 503, 504])('un %i es «no se ha podido conectar», con Reintentar', (status) => {
    expect(errorFromResponse(status, undefined)).toEqual(noConnection)
    expect(noConnection).toEqual({ message: 'No se ha podido conectar con el servidor', retry: true })
  })

  test('el cuerpo puede llegar como texto, y tampoco trae código', () => {
    expect(errorFromResponse(502, 'Bad Gateway')).toEqual(noConnection)
  })

  test('un 500 sin código es «error del servidor», sin Reintentar ni código', () => {
    expect(errorFromResponse(500, '')).toEqual({ message: 'Error del servidor', retry: false })
  })

  test('un 404 sin código es «no se ha encontrado»', () => {
    expect(errorFromResponse(404, { status: 404 })).toEqual({ message: 'No se ha encontrado', retry: false })
  })
})
