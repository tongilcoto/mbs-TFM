// Los datos que necesita cada escenario, dados de alta en su club por los caminos de la aplicación (la skill de
// escenarios, principio 9), en este orden de preferencia:
//
//   1. Los endpoints de la API, como lo haría un usuario: la temporada (`POST /seasons`), el equipo
//      (`POST /teams`), el enganche (`POST /teams/{id}/federation-link`), la ingesta (`POST /ingestion-runs`) y
//      el nombre del club (`PATCH /club`). Nunca el que prueba el escenario.
//   2. Los comandos del servidor, donde la API todavía no llega. Desde la rebanada 2 (R2.15), ninguno: `seed-team`
//      y `seed-competition` los sustituyen `POST /teams` y `POST /seasons`.
//   3. La base de datos, solo para lo que ninguno de los dos produce. Cada caso dice por qué.
//
// Las competiciones las inventa el escenario (invented.ts) y las sirve la federación falsa, así que el servidor
// las da de alta y las sincroniza como haría con las de la RFFM.
import { expectApi } from './club-api.ts'
import type { ScenarioClub } from './clubs.ts'
import { config } from './config.ts'
import { fakeFederation } from './fake-federation.ts'
import { competition, team, type Competition, type Season, type Team } from './invented.ts'
import type { Random } from './random.ts'
import { withDatabase } from './test-database.ts'

/** Un equipo del club que juega una competición en una temporada. */
export interface PlayingTeam {
  team: Team
  competition: Competition
}

/** Cómo va la ingesta de una competición: las palabras de la pantalla (plan R1, decisión 2). */
export type HealthWords = 'Al día' | 'Con fallos' | 'En marcha' | 'Sin datos todavía' | 'Desactualizada'

// ── 1 y 2: por la aplicación ────────────────────────────────────────────────────────────────────────────────

/** Le pone al club su nombre corto, el de la cabecera. */
export async function setShortName(club: ScenarioClub, shortName: string): Promise<void> {
  await expectApi(club, 'PATCH', '/club', { shortName }, 200)
}

/**
 * Da de alta la temporada, sin equipos y sin código de la federación, como «Crear nueva temporada» (`D-106`).
 * Devuelve su `id`.
 */
export async function addSeason(club: ScenarioClub, season: Season): Promise<string> {
  const created = await expectApi<{ id: string }>(club, 'POST', '/seasons', { label: season.label }, 201)
  return created.id
}

/** El `id` de la temporada; si el club no la tiene, la da de alta. */
async function seasonIdOf(club: ScenarioClub, season: Season): Promise<string> {
  const seasons = await expectApi<{ id: string; label: string }[]>(club, 'GET', '/seasons?includeArchived=true', undefined, 200)
  return seasons.find((s) => s.label === season.label)?.id ?? (await addSeason(club, season))
}

/**
 * Da de alta un equipo del club en la temporada, que no choque con los de `taken`, como el formulario: queda
 * inscrito sin competición, la fila de junio (`D-68`). Devuelve el equipo con su `id`.
 */
async function createTeam(club: ScenarioClub, random: Random, season: Season, taken: Team[]): Promise<Team> {
  const created = team(random, taken)
  const seasonId = await seasonIdOf(club, season)
  const { category, letter, gender, modality } = created
  const body = { category, gender, modality, seasonId, ...(letter ? { letter } : {}) }
  const { id } = await expectApi<{ id: string }>(club, 'POST', '/teams', body, 201)
  return { ...created, id }
}

/**
 * Un equipo nuevo del club, enganchado a una competición de la temporada. Como lo haría el club: da de alta el
 * equipo en la temporada (y la temporada, si no estaba), y después lo engancha. El enganche encuentra la temporada
 * por su etiqueta y le pone el código de la federación (`D-106`), crea la competición, llena la inscripción y
 * lanza la primera ingesta. Vuelve cuando la ingesta ha acabado: la competición queda «Al día».
 */
export async function addPlayingTeam(
  club: ScenarioClub,
  random: Random,
  season: Season,
  taken: Team[] = [],
): Promise<PlayingTeam> {
  const created = await createTeam(club, random, season, taken)
  const plays = competition(random, season, created)
  fakeFederation().invent(plays)
  const linked = await expectApi<{ competitionId: string }>(
    club,
    'POST',
    `/teams/${created.id}/federation-link`,
    { federationCalendarUrl: plays.calendarUrl, ownTeamFederationId: plays.teams[0]!.code, gender: created.gender },
    202,
  )
  plays.id = linked.competitionId
  await ingestionFinished(club, plays.id)
  return { team: created, competition: plays }
}

/** Un equipo nuevo del club, inscrito en la temporada sin competición (el estado de junio), por el alta. */
export function addTeamWithoutCompetition(club: ScenarioClub, random: Random, season: Season, taken: Team[] = []): Promise<Team> {
  return createTeam(club, random, season, taken)
}

interface IngestionRun {
  kind: 'calendar' | 'standings' | 'scorers'
  outcome: 'accepted' | 'succeeded' | 'failed'
  startedAt: string
}

const runsOf = (club: ScenarioClub, competitionId: string) =>
  expectApi<IngestionRun[]>(club, 'GET', `/ingestion-runs?competitionId=${competitionId}`, undefined, 200)

/** Espera a que la competición no tenga ninguna pasada en marcha. */
export async function ingestionFinished(club: ScenarioClub, competitionId: string, timeoutMs = 10_000): Promise<void> {
  const until = Date.now() + timeoutMs
  for (;;) {
    const runs = await runsOf(club, competitionId)
    if (!runs.some((r) => r.outcome === 'accepted')) return
    if (Date.now() > until) throw new Error(`La ingesta de la competición ${competitionId} no acabó en ${timeoutMs} ms`)
    await new Promise((resolve) => setTimeout(resolve, 100))
  }
}

/**
 * Cuándo se sincronizó bien la competición por última vez: cuando empezó su última pasada buena del calendario.
 * Se pregunta al registro de pasadas, y no a `/competitions`, que es lo que la portada pide y lo que se prueba.
 */
export async function lastSynced(club: ScenarioClub, competitionId: string): Promise<Date> {
  const runs = await runsOf(club, competitionId)
  const good = runs.find((r) => r.kind === 'calendar' && r.outcome === 'succeeded')
  if (!good) throw new Error(`La competición ${competitionId} no tiene ninguna pasada buena del calendario`)
  return new Date(good.startedAt)
}

/**
 * Deja la ingesta de la competición en un estado. Parte de «Al día», que es como la deja el enganche.
 *
 * - «Con fallos»: la federación contesta mal a los goleadores, y se lanza una pasada (falla de verdad).
 * - «En marcha»: se lanza una pasada, y la federación retiene su calendario hasta que acaba el escenario.
 * - «Sin datos todavía» y «Desactualizada»: por la base de datos (abajo).
 */
export async function setIngestion(
  club: ScenarioClub,
  playing: PlayingTeam,
  state: HealthWords | 'En marcha, y la anterior falló',
): Promise<void> {
  const { competition: plays } = playing
  const id = plays.id!
  switch (state) {
    case 'Al día':
      return
    case 'Con fallos':
      fakeFederation().failScorers(plays)
      await expectApi(club, 'POST', '/ingestion-runs', { competitionIds: [id] }, 502)
      return
    case 'En marcha': {
      fakeFederation().hold(plays)
      // Por la temporada, y no por la competición: así contesta 202 y la pasada sigue sola (README del backend §4.2).
      const seasons = await expectApi<{ id: string; label: string }[]>(club, 'GET', '/seasons?includeArchived=true', undefined, 200)
      const seasonId = seasons.find((s) => s.label === plays.season.label)!.id
      await expectApi(club, 'POST', '/ingestion-runs', { seasonId }, 202)
      await fakeFederation().heldArrived(plays)
      return
    }
    case 'En marcha, y la anterior falló':
      await setIngestion(club, playing, 'Con fallos')
      await setIngestion(club, playing, 'En marcha')
      return
    case 'Sin datos todavía':
      return forgetIngestions(club, id)
    case 'Desactualizada':
      return ageIngestions(club, id, 10)
    default:
      throw new Error(`«${String(state)}» no es un estado de la ingesta`)
  }
}

// ── 3: por la base de datos ─────────────────────────────────────────────────────────────────────────────────

// Una consulta en el *schema* del club: `$schema` se cambia por su nombre. Devuelve las filas.
type Query = (text: string, values?: unknown[]) => Promise<Record<string, string>[]>

function sql<T>(club: ScenarioClub, work: (query: Query) => Promise<T>): Promise<T> {
  return withDatabase(config.database.name, (db) =>
    work(async (text, values) => (await db.query(text.replaceAll('$schema', `"${club.schema}"`), values)).rows),
  )
}

/**
 * «Sin datos todavía»: la competición sin ninguna pasada. Por la API no se llega: el enganche siempre lanza la
 * primera. Se borran las pasadas que dejó, y su última sincronización.
 */
async function forgetIngestions(club: ScenarioClub, competitionId: string): Promise<void> {
  await sql(club, async (query) => {
    await query('DELETE FROM $schema.ingestion_runs WHERE competition_id = $1', [competitionId])
    await query('UPDATE $schema.competitions SET last_synced_at = NULL WHERE id = $1', [competitionId])
  })
}

/**
 * «Desactualizada»: la última sincronización buena, de hace más de una semana. Por la API no se llega sin esperar
 * la semana: se echan atrás `days` días las pasadas que dejó el enganche, y su última sincronización.
 */
async function ageIngestions(club: ScenarioClub, competitionId: string, days: number): Promise<void> {
  await sql(club, async (query) => {
    await query(
      `UPDATE $schema.ingestion_runs SET started_at = started_at - make_interval(days => $2),
         finished_at = finished_at - make_interval(days => $2), created_at = created_at - make_interval(days => $2)
       WHERE competition_id = $1`,
      [competitionId, days],
    )
    await query(
      'UPDATE $schema.competitions SET last_synced_at = last_synced_at - make_interval(days => $2) WHERE id = $1',
      [competitionId, days],
    )
  })
}


/**
 * Deja el club a medias: existe y tiene sus tablas, pero no su fila en `clubs`. Es lo que el servidor llama
 * «sin aprovisionar» (`TENANT_NOT_PROVISIONED`, GetClub.swift): un estado roto, que ningún camino de la
 * aplicación produce. Sin el *schema* entero, el servidor da un 500 genérico, no este código (hallazgo de R1.17).
 */
export async function leaveClubHalfProvisioned(club: ScenarioClub): Promise<void> {
  await sql(club, (query) => query('DELETE FROM $schema.clubs'))
}

/** Lo que un escenario puede haber dejado a medias en el servidor: suelta lo retenido y espera a que acabe. */
export async function settleIngestions(club: ScenarioClub, competitionIds: string[]): Promise<void> {
  fakeFederation().releaseAll()
  for (const id of competitionIds) {
    // Si el escenario paró el servidor con una pasada en marcha, esa pasada no acabará nunca: no se espera más.
    await ingestionFinished(club, id, 5_000).catch(() => undefined)
  }
}
