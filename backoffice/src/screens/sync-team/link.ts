// Lo que decide la pantalla de sincronizar sin pintar nada (plan R3, §3.2 y decisión 6).
import type { components } from '../../api/schema'
import type { ShownError } from '../../api/errors'
import { namesOf, teamName } from '../../theme/names'

type Team = components['schemas']['TeamResponse']

// Los códigos son UUID (LLD-B §6.3): lo que no lo es no existe, y la web lo sabe sin preguntar (LLD-B §6.7).
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function isTeamCode(id: string): boolean {
  return uuid.test(id)
}

// «No se ha encontrado el equipo» sin que lo diga el servidor: el código no es un UUID, o el equipo es un rival
// (decisión 6). Sin código en pequeño: no hubo error del servidor que contar.
export const teamNotFound: ShownError = { message: 'No se ha encontrado el equipo', retry: false }

const genderNames = namesOf('Gender')
const modalityNames = namesOf('Modality')

// El equipo debajo del título, siempre con su género y su modalidad: «Alevín B · Masculino · Fútbol 7», como en la
// maqueta (pantalla D). La pantalla solo tiene este equipo y no sabe si en la portada hay otro que se llame igual,
// así que no puede dar el nombre corto solo cuando basta. Nunca el `displayName` del servidor (D-109).
export function teamTitle(team: Team): string {
  return [teamName(team.category, team.letter), genderNames[team.gender], modalityNames[team.modality]].join(' · ')
}

// Dónde sale un error al comprobar la dirección (decisión 6): junto al campo, los que dicen que la dirección está
// mal; la página entera, si el equipo ya no está; y arriba del paso 1, el resto, con *Reintentar* si es pasajero.
export type CheckErrorPlace = 'field' | 'page' | 'banner'

const fieldCodes: (string | undefined)[] = ['UNREADABLE_FEDERATION_URL', 'FEDERATION_COORDINATE_NOT_FOUND']

export function placeCheckError(error: ShownError): CheckErrorPlace {
  if (fieldCodes.includes(error.code)) return 'field'
  if (error.code === 'TEAM_NOT_FOUND') return 'page'
  return 'banner'
}
