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
