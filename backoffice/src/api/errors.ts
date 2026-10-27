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
  // En un error de valor, el campo al que pertenece y el motivo, leídos del `detail` (LLD-B §4.5 a).
  field?: { name: string; reason: string }
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

  // Lo que ya está (Plan R2, decisión 6)
  TEAM_ALREADY_REGISTERED: 'Ese equipo ya está dado de alta en esta temporada',
  SEASON_ALREADY_EXISTS: 'Ya existe una temporada con esa etiqueta. Si no la ves en el selector, está archivada: se recupera desde Temporadas',

  // Sincronizar con la Federación (plan R3, decisión 6): con las palabras de la pantalla, y diciendo qué hacer.
  ALREADY_LINKED_TO_FEDERATION: 'Este equipo ya está sincronizado con otro equipo de la Federación en esa competición.',
  FEDERATION_TEAM_ID_TAKEN: 'Ese equipo de la Federación ya es de otro equipo del club.',
  SEASON_ALREADY_LINKED: 'Esa temporada ya está sincronizada con otro código de la Federación. Revisa que el calendario sea de la temporada correcta.',
  OWN_TEAM_NOT_IN_CALENDAR: 'Ese equipo ya no está en el calendario de la Federación. Vuelve a comprobar con el botón ↻ de la dirección.',
  COMPETITION_IDENTITY_MISMATCH: 'El equipo y la competición no cuadran: no son de la misma edad, género o modalidad.',
  UNREADABLE_FEDERATION_URL: 'Esa dirección no es la de un calendario de la Federación. Cópiala de la página del calendario del grupo.',

  // Lo que responde la Federación
  FEDERATION_UNREACHABLE: 'La Federación no responde. Prueba otra vez en un rato.',
  FEDERATION_UNEXPECTED_STATUS: 'La Federación ha respondido con un error. Prueba otra vez en un rato.',
  FEDERATION_MALFORMED_RESPONSE: 'La Federación ha respondido con un error. Prueba otra vez en un rato.',
  FEDERATION_COORDINATE_NOT_FOUND: 'La Federación no tiene ningún calendario en esa dirección. Revisa que esté completa.',
  FEDERATION_SOURCE_MISMATCH: 'En esa dirección la Federación tiene ahora otra competición.',
  FEDERATION_SEASON_MISMATCH: 'Las fechas de ese calendario son de otra temporada. Revisa que la dirección sea la de esta temporada.',
  SEASON_LABEL_UNAVAILABLE: 'La Federación no dice de qué temporada es ese calendario.',
  FEDERATION_ADAPTER_MISSING: 'Todavía no se puede sincronizar con la federación de este club.',

  // La sincronización
  INGESTION_FAILED: 'La sincronización con la federación no ha terminado',
  RUN_NOT_RECORDED: 'Los datos se han guardado, pero no se ha podido apuntar la sincronización',

  // El servidor
  DATABASE_UNAVAILABLE: 'No se ha podido conectar con el servidor',
  INTERNAL: 'Error del servidor',
}

// Los únicos códigos que pueden ser pasajeros (LLD-B §4.4). Con el resto, reintentar daría lo mismo. Los dos de la
// Federación que contesta mal también: la RFFM devuelve a veces `null` unos minutos (H-61, plan R3, decisión 6).
const transientCodes: ProblemCode[] = [
  'DATABASE_UNAVAILABLE',
  'FEDERATION_UNREACHABLE',
  'FEDERATION_UNEXPECTED_STATUS',
  'FEDERATION_MALFORMED_RESPONSE',
]

// Los errores de valor, los únicos cuyo `detail` dice de qué campo son, con la forma `<campo>: <motivo>`.
const valueErrorCodes: ProblemCode[] = ['INVALID_VALUE', 'NOT_EDITABLE_AFTER_SYNC']

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
    const shown: ShownError = { message: messages[code], code, retry: transientCodes.includes(code) }
    const field = valueErrorCodes.includes(code) ? fieldIn(body) : undefined
    return field === undefined ? shown : { ...shown, field }
  }

  // Un código que la tabla no tiene (un servidor más nuevo que la web): el mensaje de su familia.
  return { message: familyMessage(status), code, retry: false }
}

// Dónde enseña un formulario el error de guardar (LLD-B §4.3): junto a su campo, si el servidor dijo cuál es y
// el formulario lo tiene; si no, en el aviso de arriba.
export type SavePlacement = { field: string; reason: string } | { banner: ShownError }

export function placeSaveError(error: ShownError, formFields: readonly string[]): SavePlacement {
  const field = error.field
  if (field !== undefined && formFields.includes(field.name)) return { field: field.name, reason: field.reason }
  return { banner: error }
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

// La única vez que la web lee el `detail` (LLD-B §4.5 a): se separa por el primer «: », y lo de delante es el
// campo. Si no sigue esa forma, no hay campo.
function fieldIn(body: unknown): ShownError['field'] {
  if (typeof body !== 'object' || body === null || !('detail' in body) || typeof body.detail !== 'string') return undefined
  const cut = body.detail.indexOf(': ')
  if (cut <= 0) return undefined
  const reason = body.detail.slice(cut + 2)
  return reason === '' ? undefined : { name: body.detail.slice(0, cut), reason }
}

function isKnown(code: string): code is ProblemCode {
  return Object.hasOwn(messages, code)
}
