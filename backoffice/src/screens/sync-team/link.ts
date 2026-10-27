// Lo que decide la pantalla de sincronizar sin pintar nada (plan R3, §3.2 y decisión 6).
import type { components } from '../../api/schema'
import type { ShownError } from '../../api/errors'
import type { TeamOption } from '../../components/TeamChoiceList.vue'
import { categoryNames, type Gender, namesOf, teamName } from '../../theme/names'

type Team = components['schemas']['TeamResponse']
type Competition = components['schemas']['CompetitionPreviewResponse']
type PreviewTeam = components['schemas']['PreviewTeam']

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

// ── El paso 2: tu equipo (§3.3, decisión 4) ──

// Un equipo de la lista, como lo pinta TeamChoiceList: `code`, el de la Federación (lo que se envía); y `reason`,
// por qué no se puede elegir.
export type Choice = TeamOption

// Por orden alfabético del nombre de la Federación, con las reglas del español: así «CELTIC CASTILLA C.F. 'A'» y
// «'B'» salen juntos. Se ven todos; los que no se pueden elegir, con el motivo.
const spanish = new Intl.Collator('es')

export function choicesOf(teams: PreviewTeam[], teamId: string): Choice[] {
  return teams
    .map((team) => ({ code: team.federationTeamId ?? null, name: team.rawName, reason: reasonOf(team, teamId) }))
    .sort((a, b) => spanish.compare(a.name, b.name))
}

// `takenBy` puede no venir: un nulo falta (LLD-B §3.8).
function reasonOf(team: PreviewTeam, teamId: string): string | undefined {
  if (team.federationTeamId == null) return 'La Federación no publica su código: no se puede elegir'
  const taken = team.takenBy ?? null
  if (taken === null) return undefined
  if (!taken.isOwn) return 'Ya está en el club como rival: la Federación lo trajo antes de sincronizarlo'
  return taken.teamId === teamId ? 'Ya está sincronizado con este equipo' : `Ya está sincronizado con ${taken.displayName}`
}

// Lo que no cuadra entre el equipo y la competición, pieza a pieza (§3.3): la edad, el género y la modalidad. El
// género es el elegido en la pantalla, porque una competición nueva se crea con él; la que ya está en el club tiene
// el suyo, y el que se envíe no lo cambia. Vacío: cuadra.
export interface Mismatch {
  piece: 'Edad' | 'Género' | 'Modalidad'
  team: string
  competition: string
}

export function mismatchesOf(team: Team, competition: Competition, chosenGender: Gender): Mismatch[] {
  const gender = competition.alreadyRegistered ? competition.gender : chosenGender
  const pairs: [Mismatch['piece'], string, string][] = [
    ['Edad', categoryNames[team.category], categoryNames[competition.ageCategory]],
    ['Género', genderNames[team.gender], genderNames[gender]],
    ['Modalidad', modalityNames[team.modality], modalityNames[competition.modality]],
  ]
  return pairs.filter(([, mine, theirs]) => mine !== theirs).map(([piece, mine, theirs]) => ({ piece, team: mine, competition: theirs }))
}

// El botón dice lo que va a sincronizar (§3.3): «Sincronizar CELTIC CASTILLA C.F. 'B'», o solo «Sincronizar».
export function syncLabel(chosen: Choice | undefined): string {
  return chosen ? `Sincronizar ${chosen.name}` : 'Sincronizar'
}

// Lo que se enseña de la competición: su división y su grupo, como en la portada; sin división, solo el grupo.
export function competitionName(competition: Competition): string {
  return [competition.divisionLabel, competition.groupLabel].filter(Boolean).join(' · ')
}

// Dónde sale un error al sincronizar (decisión 6): la página entera si el equipo ya no está; el resto, arriba del
// paso 2 y **sin Reintentar**, porque el botón de sincronizar sigue a mano y es lo que se reintenta.
export function placeSyncError(error: ShownError): { page: ShownError } | { banner: ShownError } {
  if (error.code === 'TEAM_NOT_FOUND') return { page: error }
  return { banner: { ...error, retry: false } }
}
