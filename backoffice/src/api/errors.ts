import type { components } from './schema'

// La lista cerrada de códigos que emite el servidor, sacada del catálogo (ProblemCode).
export type ProblemCode = components['schemas']['ProblemCode']

// Lo que la pantalla necesita para enseñar un error (LLD-B §4.2 y §4.4).
export interface ShownError {
  message: string
  // El código que mandó el servidor, para enseñarlo en pequeño («Código: TEAM_NOT_FOUND»). Sin código, no hay.
  code?: string
  // Solo si el fallo puede ser pasajero.
  retry: boolean
}

// Un mensaje para cada código de la lista (LLD-B §4.1). Si falta uno, o sobra uno que la lista no tiene,
// la web no compila: así, al añadir un código al catálogo, esta tabla avisa sola.
const messages: Record<ProblemCode, string> = {
  // El club
  UNKNOWN_TENANT: 'Este club no existe. Revisa la dirección',
  TENANT_NOT_RESOLVED: 'Falta el club en la dirección',
  TENANT_NOT_PROVISIONED: 'Este club aún no está preparado. Avisa a quien lo administra',
  TENANT_MISMATCH: 'Tu sesión es de otro club',

  // Lo que no se encuentra
  NOT_FOUND: 'No se ha encontrado lo que se buscaba',
  SEASON_NOT_FOUND: 'No se ha encontrado la temporada',
  TEAM_NOT_FOUND: 'No se ha encontrado el equipo',
  COMPETITION_NOT_FOUND: 'No se ha encontrado la competición',

  // Lo que la web manda mal
  BAD_REQUEST: 'La web ha enviado algo que el servidor no entiende',
  EMPTY_PATCH: 'No hay ningún cambio que guardar',
  EMPTY_SELECTION: 'Elige al menos una competición',
  INVALID_LIMIT: 'El número de resultados pedido no es válido',
  INVALID_UUID: 'Uno de los datos de la dirección no es válido',
  INVALID_VALUE: 'Hay un dato que no es válido',
  NOT_EDITABLE_AFTER_SYNC: 'Este dato ya no se puede cambiar: la competición ya se ha sincronizado',

  // El enganche con la federación
  ALREADY_LINKED_TO_FEDERATION: 'Este equipo ya está enganchado a la federación',
  FEDERATION_TEAM_ID_TAKEN: 'Ese código de la federación ya es de otro equipo del club',
  OWN_TEAM_NOT_IN_CALENDAR: 'Ese código no es de ningún equipo del calendario',
  COMPETITION_IDENTITY_MISMATCH: 'El equipo y la competición no cuadran: no son de la misma categoría o temporada',
  UNREADABLE_FEDERATION_URL: 'La dirección del calendario no se puede leer',

  // Lo que responde la federación
  FEDERATION_UNREACHABLE: 'La federación no responde',
  FEDERATION_UNEXPECTED_STATUS: 'La federación ha respondido con un error',
  FEDERATION_MALFORMED_RESPONSE: 'La federación ha respondido algo que no se entiende',
  FEDERATION_COORDINATE_NOT_FOUND: 'La federación no tiene ningún calendario en esa dirección',
  FEDERATION_SOURCE_MISMATCH: 'Esa dirección de la federación es de otra competición',
  FEDERATION_SEASON_MISMATCH: 'Ese calendario de la federación es de otra temporada',
  SEASON_LABEL_UNAVAILABLE: 'La federación no dice de qué temporada es el calendario',
  FEDERATION_ADAPTER_MISSING: 'La web todavía no sabe leer la federación de este club',

  // La sincronización
  INGESTION_FAILED: 'La sincronización con la federación no ha terminado',
  RUN_NOT_RECORDED: 'Los datos se han guardado, pero no se ha podido apuntar la sincronización',

  // El servidor
  DATABASE_UNAVAILABLE: 'No se ha podido conectar con el servidor',
  INTERNAL: 'Error del servidor',
}

// Los únicos códigos que pueden ser pasajeros (LLD-B §4.4). Con el resto, reintentar daría lo mismo.
const transientCodes: ProblemCode[] = ['DATABASE_UNAVAILABLE', 'FEDERATION_UNREACHABLE']

// Sin respuesta: pasaron los 30 s (LLD-B §3.4), no se pudo ni conectar, o el recepcionista dice que el servidor
// no está. Las tres cosas, el mismo mensaje y con Reintentar (la ficha del marco, plan R1 §3.1).
export const noConnection: ShownError = { message: 'No se ha podido conectar con el servidor', retry: true }

// El servidor respondió con un error: `status` es el número y `body`, lo que traía (puede no traer nada).
export function errorFromResponse(status: number, body: unknown): ShownError {
  const code = codeIn(body)

  // Sin código, un 502, 503 o 504 es el recepcionista: el servidor no está detrás (DW-18).
  if (code === undefined) {
    return [502, 503, 504].includes(status) ? noConnection : { message: familyMessage(status), retry: false }
  }

  if (isKnown(code)) {
    return { message: messages[code], code, retry: transientCodes.includes(code) }
  }

  // Un código que la tabla no tiene (un servidor más nuevo que la web): el mensaje de su familia.
  return { message: familyMessage(status), code, retry: false }
}

// El mensaje genérico de cada familia de errores (LLD-B §4.1).
function familyMessage(status: number): string {
  if (status === 404) return 'No se ha encontrado'
  if (status === 409 || status === 422) return 'No se ha podido guardar'
  if (status >= 500) return 'Error del servidor'
  return 'Algo ha fallado'
}

// La web decide por el `code` y nunca por el texto (LLD-B §4.1).
function codeIn(body: unknown): string | undefined {
  if (typeof body !== 'object' || body === null || !('code' in body)) return undefined
  return typeof body.code === 'string' ? body.code : undefined
}

function isKnown(code: string): code is ProblemCode {
  return Object.hasOwn(messages, code)
}
