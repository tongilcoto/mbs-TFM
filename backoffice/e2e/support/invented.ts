// Los datos que se inventan los escenarios: temporadas, competiciones de la federación y equipos del club. Se
// eligen al azar (random.ts) entre lo que el sistema acepta; ninguno decide por sí solo qué rama se prueba.
//
// La competición inventada la sirve la federación falsa (fake-federation.ts), y el servidor la da de alta por su
// camino de siempre: el enganche (club-data.ts).
import type { Random } from './random.ts'

export type Category = 'prebenjamin' | 'benjamin' | 'alevin' | 'infantil' | 'cadete' | 'juvenil' | 'senior'
export type Gender = 'masculino' | 'femenino'
// Sin `futbol_playa`: la RFFM no tiene `tipojuego` para él.
export type Modality = 'futbol_11' | 'futbol_7' | 'futbol_sala' | 'futbol_5'

/** De menor a mayor edad: el orden del catálogo, y el de la portada. */
export const categories: Category[] = ['prebenjamin', 'benjamin', 'alevin', 'infantil', 'cadete', 'juvenil', 'senior']
const genders: Gender[] = ['masculino', 'femenino']
const modalities: Modality[] = ['futbol_11', 'futbol_7', 'futbol_sala', 'futbol_5']

/** Cómo la escribe la web (theme/names.ts): es lo que se busca en la pantalla. */
export const categoryLabels: Record<Category, string> = {
  prebenjamin: 'Prebenjamín',
  benjamin: 'Benjamín',
  alevin: 'Alevín',
  infantil: 'Infantil',
  cadete: 'Cadete',
  juvenil: 'Juvenil',
  senior: 'Senior',
}

/** Cómo la escribe la RFFM en el nombre de la competición: de ahí saca el servidor la edad. */
const categoryInFederationNames: Record<Category, string> = {
  prebenjamin: 'PREBENJAMÍN',
  benjamin: 'BENJAMÍN',
  alevin: 'ALEVÍN',
  infantil: 'INFANTIL',
  cadete: 'CADETE',
  juvenil: 'JUVENIL',
  senior: 'AFICIONADO',
}

/** El `tipojuego` de la RFFM de cada modalidad (backend, RFFMGameType). */
export const gameTypes: Record<Modality, string> = { futbol_11: '1', futbol_7: '2', futbol_sala: '3', futbol_5: '4' }

const divisions = ['PRIMERA', 'SEGUNDA', 'PREFERENTE', 'DIVISIÓN DE HONOR', 'SUPERLIGA']
// Competiciones de verdad de la RFFM cuyo nombre no dice la edad (A-12·H-75).
const ageless = ['COPA RFEF FASE AUTONÓMICA', 'TERCERA FEDERACIÓN RFEF', 'COPA DE LA COMUNIDAD']
const rivalNames = ['C.D. LAS ROZAS', 'A.D. ALCORCÓN', 'C.F. POZUELO', 'E.F. TRES CANTOS', 'C.D. LEGANÉS NORTE',
  'U.D. SAN SEBASTIÁN', 'C.D. MÓSTOLES URJC', 'A.D. VILLAVERDE', 'C.F. ARGANDA', 'R.S.D. ALCALÁ']
const clubNames = ['Atlético Ribera', 'Racing Arroyo', 'Unión Valdebebas', 'Deportivo Sierra', 'Sporting Henares',
  'Real Jarama', 'Olímpico Tajo', 'Juventud Manzanares', 'Estrella Guadarrama', 'Fortuna Alberche']

// ── Temporadas ──────────────────────────────────────────────────────────────────────────────────────────────

export interface Season {
  /** El año en que empieza. */
  start: number
  /** `2025/26`: como la escribe la web. */
  label: string
  /** El código de la RFFM: la 21 es la 2025/26. */
  federationId: string
}

export function season(start: number): Season {
  return { start, label: `${start}/${String((start + 1) % 100).padStart(2, '0')}`, federationId: String(start - 2004) }
}

/** La temporada que contiene hoy, en Madrid (`D-103`): de julio a junio. */
export function currentSeason(today = new Date()): Season {
  const madrid = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Madrid', year: 'numeric', month: 'numeric' })
  const parts = Object.fromEntries(madrid.formatToParts(today).map((p) => [p.type, Number(p.value)]))
  return season(parts.month! >= 7 ? parts.year! : parts.year! - 1)
}

/** Una temporada que ya terminó, distinta de las de `taken`. Desde la 2005/06, la primera con código de la RFFM. */
export function pastSeason(random: Random, taken: Season[] = []): Season {
  return seasonBetween(random, 2005, currentSeason().start - 1, taken)
}

/** Una temporada que todavía no ha empezado, distinta de las de `taken`. */
export function futureSeason(random: Random, taken: Season[] = []): Season {
  const now = currentSeason().start
  return seasonBetween(random, now + 1, now + 30, taken)
}

/** La temporada que viene después de la en curso: la que un club crea en julio. */
export function nextSeason(): Season {
  return season(currentSeason().start + 1)
}

function seasonBetween(random: Random, from: number, to: number, taken: Season[]): Season {
  for (;;) {
    const start = random.int(from, to)
    if (!taken.some((s) => s.start === start)) return season(start)
  }
}

// ── Equipos del club ────────────────────────────────────────────────────────────────────────────────────────

export interface Team {
  category: Category
  /** `null` si es el único de su edad, género y modalidad. */
  letter: string | null
  gender: Gender
  modality: Modality
  /** Como lo escribe la web en su fila: «Cadete B», o «Cadete» sin letra. */
  name: string
  /** El que le da el servidor al crearlo. */
  id?: string
}

/** Un equipo del club que no choca con ninguno de `taken` (la edad, el género, la modalidad y la letra). */
export function team(random: Random, taken: Team[] = []): Team {
  for (;;) {
    const category = random.pick(categories)
    const letter = random.chance(0.2) ? null : random.pick(['A', 'B', 'C', 'D', 'E'])
    const candidate: Team = {
      category,
      letter,
      gender: random.pick(genders),
      modality: random.pick(modalities),
      name: letter ? `${categoryLabels[category]} ${letter}` : categoryLabels[category],
    }
    const same = (t: Team) =>
      t.category === candidate.category && t.letter === candidate.letter && t.gender === candidate.gender &&
      t.modality === candidate.modality
    // Dos filas con el mismo nombre no se distinguen en la pantalla: tampoco se repite el nombre.
    if (!taken.some((t) => same(t) || t.name === candidate.name)) return candidate
  }
}

/**
 * El equipo que se llamaría igual que `of`, con el otro género: mismas edad, letra y modalidad. Es lo que el
 * club puede tener («Alevín A» masculino y femenino), y lo que la portada tiene que distinguir (bloque T del plan R2).
 */
export function twinOf(of: Team): Team {
  return { ...of, id: undefined, gender: of.gender === 'masculino' ? 'femenino' : 'masculino' }
}

/** Un nombre corto de club. */
export function clubName(random: Random): string {
  return random.pick(clubNames)
}

// ── Competiciones de la federación ──────────────────────────────────────────────────────────────────────────

export interface FederationTeam {
  code: string
  /** Como lo publica la RFFM: `C.D. LAS ROZAS 'A'`. */
  rawName: string
}

export interface Competition {
  season: Season
  category: Category
  gender: Gender
  modality: Modality
  /** `PRIMERA CADETE`: el nombre que publica la RFFM, que el servidor guarda como división. */
  division: string
  /** `Grupo 4`. */
  group: string
  federationCompetitionId: string
  federationGroupId: string
  /** Los equipos del grupo; el primero es el del club. */
  teams: FederationTeam[]
  /** Como la escribe el servidor: «Cadete · PRIMERA CADETE · Grupo 4». */
  displayName: string
  /** Como la enseña la portada, sin la categoría que ya dice el equipo: «PRIMERA CADETE · Grupo 4». */
  rowName: string
  /** La dirección de su calendario en la web de la RFFM: la que se pega para engancharla. */
  calendarUrl: string
  /**
   * Lo que dice su calendario en `temporada`, si no es la de la temporada («2026-2027»): «2027-2029» no se puede
   * leer como etiqueta, y el servidor se queda sin saber de qué temporada es (H-10).
   */
  calendarSeason?: string
  /** El `id` que le da el servidor. */
  id?: string
}

/**
 * Una competición de la temporada, de la edad, el género y la modalidad del equipo. Con `withoutAge`, su nombre no
 * dice la edad, como «COPA RFEF FASE AUTONÓMICA»: el servidor no la puede comprobar y usa la del equipo.
 */
export function competition(
  random: Random,
  of: Season,
  forTeam: Pick<Team, 'category' | 'gender' | 'modality'>,
  withoutAge = false,
): Competition {
  const words = withoutAge ? [random.pick(ageless)] : [random.pick(divisions), categoryInFederationNames[forTeam.category]]
  if (forTeam.gender === 'femenino') words.push('FEMENINO')
  const division = words.join(' ')
  const group = `Grupo ${random.int(1, 12)}`
  const federationCompetitionId = String(random.int(10_000_000, 99_999_999))
  const federationGroupId = String(Number(federationCompetitionId) + random.int(1, 50))

  const codes = new Set<string>()
  while (codes.size < 4) codes.add(String(random.int(100, 9_999_999)))
  const [own, ...rivals] = [...codes]
  const rivalPool = [...rivalNames]
  const teams: FederationTeam[] = [
    { code: own!, rawName: `CLUB DEL ESCENARIO '${random.pick(['A', 'B', 'C'])}'` },
    ...rivals.map((code) => {
      const name = rivalPool.splice(random.int(0, rivalPool.length - 1), 1)[0]!
      return { code, rawName: `${name} '${random.pick(['A', 'B', 'C'])}'` }
    }),
  ]

  const query = new URLSearchParams({
    temporada: of.federationId,
    tipojuego: gameTypes[forTeam.modality],
    competicion: federationCompetitionId,
    grupo: federationGroupId,
  })
  return {
    season: of,
    ...forTeam,
    division,
    group,
    federationCompetitionId,
    federationGroupId,
    teams,
    displayName: `${categoryLabels[forTeam.category]} · ${division} · ${group}`,
    rowName: `${division} · ${group}`,
    calendarUrl: `https://www.rffm.es/competicion/calendario?${query}`,
  }
}
