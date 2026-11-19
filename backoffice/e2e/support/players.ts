// Los jugadores de los escenarios (plan R6): se inventan al azar y se dan de alta por la API, como lo haría el club
// (`createPlayer`, y la foto con `PUT /players/{id}/photo`), salvo en los escenarios que prueban el alta. Lo que se
// compara en los `Then` se lee de aquí, no de la web.
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { expectApi } from './club-api.ts'
import { seasonIdOf } from './club-data.ts'
import type { ScenarioClub } from './clubs.ts'
import { currentSeason, fullName, inventedPerson, type InventedPerson, type Season, type Team } from './invented.ts'
import type { Random } from './random.ts'

export type Position = 'portero' | 'defensa' | 'centrocampista' | 'delantero'
export const positions: Position[] = ['portero', 'defensa', 'centrocampista', 'delantero']
/** Como la escribe la web (el catálogo, `x-enum-names`). */
export const positionNames: Record<Position, string> = {
  portero: 'Portero',
  defensa: 'Defensa',
  centrocampista: 'Centrocampista',
  delantero: 'Delantero',
}

/** Las dos fotos de las pruebas: un cuadrado de un color cada una, sin la cara de nadie ni datos dentro. */
export type PhotoName = 'foto-a.jpg' | 'foto-b.jpg'
export const photoFile = (name: PhotoName) => fileURLToPath(new URL(`../fixtures/${name}`, import.meta.url))
const photoBytes = (name: PhotoName) => readFileSync(photoFile(name))

/** Un jugador del escenario: su fila en una plantilla, con lo de su perfil que enseña la pantalla. */
export interface ScenarioPlayer {
  /** Su fila de esa temporada. */
  id: string
  profileId: string
  /** Del perfil, en mayúsculas, como lo guarda el servidor. */
  fullName: string
  birthYear: number | null
  /** De la fila. */
  shirtNumber: number | null
  position: Position | null
  /** El camino de su foto en el almacén, sin la firma: cada lectura firma de nuevo, pero el fichero es el mismo. */
  photoPath?: string
  team: Team
  season: Season
}

/** Cómo es la fila: lo que no se diga, al azar (el dorsal y la demarcación, a veces sin). */
export interface PlayerShape {
  person?: InventedPerson
  shirtNumber?: number | null
  position?: Position | null
  photo?: PhotoName
}

/** El camino de una dirección, sin la firma: `/api/player-photos/<club>/<código>.jpg`. */
export const pathOf = (url: string) => new URL(url, 'http://x').pathname

/** Un dorsal de 1 a 99 que no lleva nadie de `taken` en esa plantilla. */
export function freeShirtNumber(random: Random, taken: ScenarioPlayer[]): number {
  for (;;) {
    const number = random.int(1, 99)
    if (!taken.some((player) => player.shirtNumber === number)) return number
  }
}

/** Una persona que no se llama como ninguno de los jugadores ya inventados. */
export function newPerson(random: Random, taken: ScenarioPlayer[]): InventedPerson {
  return inventedPerson(random, taken.map((player) => ({ given: player.fullName, surnames: '' })))
}

/** Un año de nacimiento de chaval de fútbol base: de 5 a 18 años en la temporada en curso. */
export function birthYearFor(random: Random): number {
  const start = currentSeason().start
  return random.int(start - 18, start - 5)
}

interface PlayerAnswer {
  id: string
  profileId: string
  fullName: string
  birthYear: number | null
  shirtNumber: number | null
  position: Position | null
  photoUrl?: string | null
}

/**
 * Da de alta a un jugador nuevo para el club en la plantilla de un equipo, con su foto si la lleva. `taken` son los
 * que ya hay, para no repetir nombre ni dorsal.
 */
export async function addPlayer(
  club: ScenarioClub,
  random: Random,
  team: Team,
  season: Season,
  taken: ScenarioPlayer[],
  shape: PlayerShape = {},
): Promise<ScenarioPlayer> {
  const inSameRoster = taken.filter((player) => player.team.id === team.id && player.season.label === season.label)
  const person = shape.person ?? newPerson(random, taken)
  const shirtNumber = shape.shirtNumber !== undefined ? shape.shirtNumber : random.chance(0.8) ? freeShirtNumber(random, inSameRoster) : null
  const position = shape.position !== undefined ? shape.position : random.chance(0.8) ? random.pick(positions) : null
  const created = await expectApi<PlayerAnswer>(
    club,
    'POST',
    '/players',
    {
      teamId: team.id,
      seasonId: await seasonIdOf(club, season),
      fullName: fullName(person),
      birthYear: birthYearFor(random),
      shirtNumber,
      position,
    },
    201,
  )
  return withPhoto(club, rowOf(created, team, season), shape.photo)
}

/** Otra fila del mismo perfil, en otro equipo o temporada: el alta con un perfil que ya existe (D-119). */
export async function addRowOfProfile(
  club: ScenarioClub,
  of: ScenarioPlayer,
  team: Team,
  season: Season,
  shape: Omit<PlayerShape, 'person'>,
): Promise<ScenarioPlayer> {
  const created = await expectApi<PlayerAnswer>(
    club,
    'POST',
    '/players',
    {
      teamId: team.id,
      seasonId: await seasonIdOf(club, season),
      profileId: of.profileId,
      shirtNumber: shape.shirtNumber ?? null,
      position: shape.position ?? null,
    },
    201,
  )
  return withPhoto(club, rowOf(created, team, season), shape.photo)
}

async function withPhoto(club: ScenarioClub, player: ScenarioPlayer, photo?: PhotoName): Promise<ScenarioPlayer> {
  if (!photo) return player
  const answer = await expectApi<PlayerAnswer>(
    club,
    'PUT',
    `/players/${player.id}/photo`,
    { raw: photoBytes(photo), type: 'image/jpeg' },
    200,
  )
  if (!answer.photoUrl) throw new Error(`La foto de ${player.fullName} se subió, pero el servidor no da su enlace`)
  return { ...player, photoPath: pathOf(answer.photoUrl) }
}

function rowOf(answer: PlayerAnswer, team: Team, season: Season): ScenarioPlayer {
  return {
    id: answer.id,
    profileId: answer.profileId,
    fullName: answer.fullName,
    // Un nulo puede llegar como clave ausente (DW-21): aquí, siempre `null`.
    birthYear: answer.birthYear ?? null,
    shirtNumber: answer.shirtNumber ?? null,
    position: answer.position ?? null,
    team,
    season,
  }
}

/** Sincroniza la plantilla del equipo con la Federación por la API, como el botón (`syncTeamRoster`). */
export async function syncRoster(club: ScenarioClub, team: Team, season: Season): Promise<void> {
  await expectApi(club, 'POST', `/teams/${team.id}/registrations/${await seasonIdOf(club, season)}/roster-sync`, undefined, 200)
}

/** Los jugadores de la plantilla de un equipo en una temporada, como los da la API, para leer lo que se sabe de ellos. */
export function rosterOf(club: ScenarioClub, team: Team, seasonId: string): Promise<PlayerAnswer[]> {
  return expectApi<PlayerAnswer[]>(club, 'GET', `/players?teamId=${team.id}&seasonId=${seasonId}`, undefined, 200)
}

// ── Cómo lo enseña la web ────────────────────────────────────────────────────────────────────────────────────

// Las palabras que van en minúscula salvo al principio (plan R6, decisión 9).
const particles = new Set(['de', 'del', 'la', 'las', 'los', 'y'])

/** El nombre como «Nombre Apellidos»: «JUAN GARCÍA DE LA FUENTE» → «Juan García de la Fuente». */
export function shownName(name: string): string {
  return name
    .toLocaleLowerCase('es-ES')
    .split(' ')
    .map((word, index) =>
      index > 0 && particles.has(word)
        ? word
        : word
            .split('-')
            .map((part) => part.charAt(0).toLocaleUpperCase('es-ES') + part.slice(1))
            .join('-'),
    )
    .join(' ')
}

/** Las iniciales: las de las dos primeras palabras que no son partícula. */
export function initialsOf(name: string): string {
  return name
    .toLocaleLowerCase('es-ES')
    .split(' ')
    .filter((word) => word !== '' && !particles.has(word))
    .slice(0, 2)
    .map((word) => word.charAt(0).toLocaleUpperCase('es-ES'))
    .join('')
}

// ── El perfil, por la API ────────────────────────────────────────────────────────────────────────────────────

/** Un perfil como lo da el buscador del alta (`searchPlayerProfiles`): lo que el perfil guarda como ayuda (D-122). */
export interface ProfileAnswer {
  profileId: string
  fullName: string
  birthYear?: number | null
  lastShirtNumber?: number | null
  lastPosition?: Position | null
  lastPhotoUrl?: string | null
  lastRoster?: { team: { displayName: string }; seasonLabel: string } | null
  otherTeamThisSeason?: { displayName: string } | null
}

/**
 * Los perfiles del club que encuentra el buscador con ese texto, preguntando desde una plantilla (`teamId` y
 * `seasonId`): el buscador quita a los de esa plantilla, así que para leer el de alguien hay que preguntar desde otra.
 */
export function searchProfiles(club: ScenarioClub, text: string, teamId: string, seasonId: string): Promise<ProfileAnswer[]> {
  // Con `encodeURIComponent`: el espacio, `%20`. `URLSearchParams` lo escribe `+`, y el servidor no lo lee como espacio.
  const q = encodeURIComponent(text)
  return expectApi<ProfileAnswer[]>(club, 'GET', `/player-profiles?q=${q}&teamId=${teamId}&seasonId=${seasonId}`, undefined, 200)
}

/** El nombre de un equipo del club como lo manda el servidor (`displayName`: el club, la categoría y la letra). */
export async function teamDisplayName(club: ScenarioClub, team: Team): Promise<string> {
  return (await expectApi<{ displayName: string }>(club, 'GET', `/teams/${team.id}`, undefined, 200)).displayName
}

// ── Las fotos que no valen ───────────────────────────────────────────────────────────────────────────────────

/** Un fichero para el campo de la foto, como lo elegiría alguien en su ordenador. */
export interface PickedFile {
  name: string
  mimeType: string
  buffer: Buffer
}

export type BadPhoto = 'que no es una imagen' | 'de más de 5 MB' | 'en un formato que no es JPEG ni PNG'

// Un GIF de un punto: una imagen de verdad, pero ni JPEG ni PNG.
const tinyGif = Buffer.from('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==', 'base64')

export function badPhoto(how: BadPhoto): PickedFile {
  switch (how) {
    case 'que no es una imagen':
      return { name: 'foto.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('Esto no es una foto.\n') }
    case 'de más de 5 MB': {
      // Una foto que vale, con relleno hasta pasar de 5 MB: lo que falla es solo el peso.
      const photo = photoBytes('foto-a.jpg')
      return { name: 'foto.jpg', mimeType: 'image/jpeg', buffer: Buffer.concat([photo, Buffer.alloc(5 * 1024 * 1024 + 1)]) }
    }
    case 'en un formato que no es JPEG ni PNG':
      return { name: 'foto.gif', mimeType: 'image/gif', buffer: tinyGif }
  }
}

/** Lo que lleva dentro la foto con ubicación, para buscarlo en la que sirve el servidor. */
export const LOCATION_MARK = 'UBICACION-DE-PRUEBA-40.4168N-3.7038W'

/**
 * Una foto con la ubicación dentro, como las del móvil: un bloque Exif con su apartado GPS (la latitud «N» y, como
 * método, un texto reconocible). Fabricada aquí, sobre una de las fotos de las pruebas.
 */
export function photoWithLocation(): PickedFile {
  const mark = Buffer.concat([Buffer.from('ASCII\0\0\0'), Buffer.from(LOCATION_MARK)])
  const tiff = Buffer.alloc(56 + mark.length)
  tiff.write('MM', 0, 'latin1')
  tiff.writeUInt16BE(42, 2)
  tiff.writeUInt32BE(8, 4)
  // IFD0: una entrada, la que apunta al apartado GPS (0x8825), en el 26.
  tiff.writeUInt16BE(1, 8)
  tiff.writeUInt16BE(0x8825, 10)
  tiff.writeUInt16BE(4, 12)
  tiff.writeUInt32BE(1, 14)
  tiff.writeUInt32BE(26, 18)
  tiff.writeUInt32BE(0, 22)
  // El apartado GPS: la referencia de latitud («N») y el método, con el texto reconocible en el 56.
  tiff.writeUInt16BE(2, 26)
  tiff.writeUInt16BE(0x0001, 28)
  tiff.writeUInt16BE(2, 30)
  tiff.writeUInt32BE(2, 32)
  tiff.write('N\0', 36, 'latin1')
  tiff.writeUInt16BE(0x001b, 40)
  tiff.writeUInt16BE(7, 42)
  tiff.writeUInt32BE(mark.length, 44)
  tiff.writeUInt32BE(56, 48)
  tiff.writeUInt32BE(0, 52)
  mark.copy(tiff, 56)
  const body = Buffer.concat([Buffer.from('Exif\0\0', 'latin1'), tiff])
  const header = Buffer.from([0xff, 0xe1, 0, 0])
  header.writeUInt16BE(body.length + 2, 2)
  const photo = photoBytes('foto-a.jpg')
  // Justo detrás del comienzo del JPEG (FFD8), donde la pone una cámara.
  return { name: 'foto-movil.jpg', mimeType: 'image/jpeg', buffer: Buffer.concat([photo.subarray(0, 2), header, body, photo.subarray(2)]) }
}

