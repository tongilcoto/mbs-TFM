import { describe, expect, test } from 'vitest'
import { errorFromResponse, noConnection, placeSaveError } from './errors'

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

  test('la base de datos caída y la Federación que no responde se pueden reintentar', () => {
    expect(errorFromResponse(503, problem(503, 'DATABASE_UNAVAILABLE'))).toEqual({
      message: 'No se ha podido conectar con el servidor',
      code: 'DATABASE_UNAVAILABLE',
      retry: true,
    })
    expect(errorFromResponse(504, problem(504, 'FEDERATION_UNREACHABLE'))).toEqual({
      message: 'La Federación no responde. Prueba otra vez en un rato.',
      code: 'FEDERATION_UNREACHABLE',
      retry: true,
    })
  })

  // Plan R3, decisión 6: la RFFM contesta a veces `null` unos minutos (H-61).
  test.each(['FEDERATION_UNEXPECTED_STATUS', 'FEDERATION_MALFORMED_RESPONSE'])(
    'la Federación que contesta mal (%s) también se reintenta, con el mismo mensaje',
    (code) => {
      expect(errorFromResponse(502, problem(502, code))).toEqual({
        message: 'La Federación ha respondido con un error. Prueba otra vez en un rato.',
        code,
        retry: true,
      })
    },
  )

  test('una dirección donde la Federación no tiene calendario es un 502, pero no se reintenta', () => {
    expect(errorFromResponse(502, problem(502, 'FEDERATION_COORDINATE_NOT_FOUND')).retry).toBe(false)
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

describe('el campo de un error de valor, leído del detail (LLD-B §4.5 a)', () => {
  // Como lo escribe el servidor en un error de valor: `<campo>: <motivo>`.
  function valueError(code: string, detail: string) {
    return { ...problem(422, code), detail }
  }
  const seasonForm = ['label']

  test('un INVALID_VALUE con la forma «campo: motivo» va junto a su campo, con el motivo del servidor', () => {
    const body = valueError('INVALID_VALUE', 'label: debe ser AAAA/AB con AB el año siguiente, como "2025/26"')
    expect(placeSaveError(errorFromResponse(422, body), seasonForm)).toEqual({
      field: 'label',
      reason: 'debe ser AAAA/AB con AB el año siguiente, como "2025/26"',
    })
  })

  test('se separa por el primer «: »: el motivo puede llevar otros', () => {
    const body = valueError('NOT_EDITABLE_AFTER_SYNC', 'label: no se cambia: ya se ha sincronizado')
    expect(placeSaveError(errorFromResponse(409, body), seasonForm)).toEqual({
      field: 'label',
      reason: 'no se cambia: ya se ha sincronizado',
    })
  })

  test.each([
    ['sin la forma «campo: motivo»', 'la etiqueta no vale'],
    ['sin campo delante', ': no vale'],
    ['sin motivo detrás', 'label: '],
  ])('un detail %s va al aviso de arriba, con el mensaje del código', (_, detail) => {
    const error = errorFromResponse(422, valueError('INVALID_VALUE', detail))
    expect(placeSaveError(error, seasonForm)).toEqual({
      banner: { message: 'Hay un dato que no es válido', code: 'INVALID_VALUE', retry: false },
    })
  })

  test('un campo que el formulario no tiene va al aviso de arriba', () => {
    const error = errorFromResponse(422, valueError('INVALID_VALUE', 'federationSeasonId: no puede estar vacío'))
    expect(placeSaveError(error, seasonForm)).toEqual({ banner: error })
  })

  test('solo en los errores de valor: el detail de un 409 «ya existe» no se lee, aunque tenga la forma', () => {
    const error = errorFromResponse(409, valueError('SEASON_ALREADY_EXISTS', "label: ya hay una temporada con '2026/27'"))
    expect(placeSaveError(error, seasonForm)).toEqual({
      banner: {
        message: 'Ya existe una temporada con esa etiqueta. Si no la ves en el selector, está archivada: se recupera desde Temporadas',
        code: 'SEASON_ALREADY_EXISTS',
        retry: false,
      },
    })
  })

  test('un error sin respuesta del servidor va al aviso de arriba', () => {
    expect(placeSaveError(noConnection, seasonForm)).toEqual({ banner: noConnection })
  })
})
