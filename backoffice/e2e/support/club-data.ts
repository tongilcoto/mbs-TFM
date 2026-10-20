// Los datos que necesita cada escenario, escritos directamente en el *schema* de su club (`bo_…`). El servidor
// todavía no tiene activas las operaciones de escritura (llegan con la rebanada 2), así que se escriben las
// filas a mano, con las mismas columnas que dejan las migraciones. Lo que el servidor calcula al leer —el nombre
// de la competición, el estado de su ingesta— sale de estas filas como saldría de las de verdad.
import { config } from './config.ts'
import type { ScenarioClub } from './clubs.ts'
import { withDatabase } from './test-database.ts'

type Category = 'prebenjamin' | 'benjamin' | 'alevin' | 'infantil' | 'cadete' | 'juvenil' | 'senior'

const categories: Record<string, Category> = {
  Prebenjamín: 'prebenjamin',
  Benjamín: 'benjamin',
  Alevín: 'alevin',
  Infantil: 'infantil',
  Cadete: 'cadete',
  Juvenil: 'juvenil',
  Senior: 'senior',
}

/** Cómo va la ingesta de una competición: las palabras de la pantalla (plan R1, decisión 2). */
export type HealthWords = 'Al día' | 'Con fallos' | 'En marcha' | 'Sin datos todavía' | 'Desactualizada'

// Una consulta en el *schema* del club: `$schema` se cambia por su nombre. Devuelve las filas.
type Query = (text: string, values?: unknown[]) => Promise<Record<string, string>[]>

function sql<T>(club: ScenarioClub, work: (query: Query) => Promise<T>): Promise<T> {
  return withDatabase(config.database.name, (db) =>
    work(async (text, values) => (await db.query(text.replaceAll('$schema', `"${club.schema}"`), values)).rows),
  )
}

/** La temporada que contiene hoy, en Madrid (`D-103`): de julio a junio. */
export function currentSeasonLabel(today = new Date()): string {
  const madrid = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Madrid', year: 'numeric', month: 'numeric' })
  const parts = Object.fromEntries(madrid.formatToParts(today).map((p) => [p.type, Number(p.value)]))
  const start = parts.month! >= 7 ? parts.year! : parts.year! - 1
  return `${start}/${String((start + 1) % 100).padStart(2, '0')}`
}

/** Crea la temporada `2025/26`: del 1 de julio de 2025 al 30 de junio de 2026. Devuelve su `id`. */
export async function addSeason(club: ScenarioClub, label: string): Promise<string> {
  const start = Number(label.slice(0, 4))
  return sql(club, async (query) => {
    const [row] = await query(
      `INSERT INTO $schema.seasons (id, label, federation_season_id, start_date, end_date, created_at, updated_at)
       VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now()) RETURNING id`,
      // El código de la federación no se repite: el año en que empieza vale.
      [label, String(start), `${start}-07-01`, `${start + 1}-06-30`],
    )
    return row!.id!
  })
}

/** El `id` de una temporada del club, por su etiqueta; si no la tiene, la crea. */
async function seasonId(club: ScenarioClub, label: string): Promise<string> {
  const [row] = await sql(club, (query) => query('SELECT id FROM $schema.seasons WHERE label = $1', [label]))
  return row ? row.id! : addSeason(club, label)
}

/**
 * Inscribe el equipo «Cadete B» en la temporada, en la competición `PRIMERA CADETE · Grupo 4` (división y
 * grupo), o sin competición si no se dice. Crea la temporada y el equipo si no existen.
 */
export async function addTeam(club: ScenarioClub, team: string, season: string, competition?: string): Promise<void> {
  const [categoryName, letter] = team.split(' ')
  const category = categories[categoryName!]
  if (!category) throw new Error(`«${team}»: la categoría tiene que ser una de ${Object.keys(categories).join(', ')}`)
  const season_id = await seasonId(club, season)

  await sql(club, async (query) => {
    const [found] = await query('SELECT id FROM $schema.teams WHERE category = $1 AND letter = $2', [category, letter])
    const [created] = found
      ? [found]
      : await query(
          `INSERT INTO $schema.teams (id, category, letter, gender, modality, created_at, updated_at)
           VALUES (gen_random_uuid(), $1, $2, 'masculino', 'futbol_11', now(), now()) RETURNING id`,
          [category, letter],
        )
    const teamId = created!.id

    let competitionId: string | null = null
    if (competition) {
      const [division, group] = competition.split(' · ')
      const [row] = await query(
        `INSERT INTO $schema.competitions (id, season_id, modality, gender, age_category, federation_competition_id,
           federation_group_id, division_label, group_label, created_at, updated_at)
         VALUES (gen_random_uuid(), $1, 'futbol_11', 'masculino', $2, '1', gen_random_uuid()::text, $3, $4, now(), now())
         RETURNING id`,
        [season_id, category, division, group],
      )
      competitionId = row!.id!
    }
    await query(
      `INSERT INTO $schema.team_registrations (id, team_id, season_id, competition_id, federation_team_id, created_at, updated_at)
       VALUES (gen_random_uuid(), $1, $2, $3, $4, now(), now())`,
      [teamId, season_id, competitionId, competitionId ? '820' : null],
    )
  })
}

/** La competición del equipo en la temporada (la primera, si tiene más de una). */
async function competitionOf(club: ScenarioClub, team: string): Promise<string> {
  const [categoryName, letter] = team.split(' ')
  return sql(club, async (query) => {
    const [row] = await query(
      `SELECT r.competition_id AS id FROM $schema.team_registrations r JOIN $schema.teams t ON t.id = r.team_id
       WHERE t.category = $1 AND t.letter = $2 AND r.competition_id IS NOT NULL LIMIT 1`,
      [categories[categoryName!], letter],
    )
    if (!row) throw new Error(`El ${team} del club del escenario no juega ninguna competición`)
    return row.id!
  })
}

/** Apunta cuándo se sincronizó por última vez la competición del equipo (un instante en UTC). */
export async function setLastSynced(club: ScenarioClub, team: string, instant: string): Promise<void> {
  const id = await competitionOf(club, team)
  await sql(club, (query) => query('UPDATE $schema.competitions SET last_synced_at = $1 WHERE id = $2', [instant, id]))
}

// Una pasada de ingesta: su clase, cómo acabó y cuántos minutos hace que empezó. Las que acabaron, lo hicieron un
// minuto después de empezar; la que está en marcha (`accepted`), no ha acabado.
interface Run {
  kind: 'calendar' | 'standings' | 'scorers'
  outcome: 'succeeded' | 'failed' | 'accepted'
  minutesAgo: number
}

const hour = 60
const day = 24 * hour

// Las pasadas que dejan la competición en cada estado, con la regla de `D-89` (IngestionHealth.swift).
const runsFor: Record<HealthWords | 'En marcha, y la anterior falló', { runs: Run[]; syncedMinutesAgo?: number }> = {
  'Al día': { runs: [{ kind: 'calendar', outcome: 'succeeded', minutesAgo: hour }], syncedMinutesAgo: hour },
  'Con fallos': {
    runs: [
      { kind: 'calendar', outcome: 'succeeded', minutesAgo: 2 * hour },
      { kind: 'calendar', outcome: 'failed', minutesAgo: hour },
    ],
    syncedMinutesAgo: 2 * hour,
  },
  'En marcha': {
    runs: [
      { kind: 'calendar', outcome: 'succeeded', minutesAgo: hour },
      { kind: 'calendar', outcome: 'accepted', minutesAgo: 1 },
    ],
    syncedMinutesAgo: hour,
  },
  'En marcha, y la anterior falló': {
    runs: [
      { kind: 'calendar', outcome: 'failed', minutesAgo: hour },
      { kind: 'calendar', outcome: 'accepted', minutesAgo: 1 },
    ],
  },
  'Sin datos todavía': { runs: [] },
  Desactualizada: { runs: [{ kind: 'calendar', outcome: 'succeeded', minutesAgo: 10 * day }], syncedMinutesAgo: 10 * day },
}

/** Deja la ingesta de la competición del equipo en un estado, escribiendo las pasadas que llevan a él. */
export async function setIngestion(club: ScenarioClub, team: string, state: keyof typeof runsFor): Promise<void> {
  const preset = runsFor[state]
  if (!preset) throw new Error(`«${state}» no es un estado de la ingesta: ${Object.keys(runsFor).join(', ')}`)
  const id = await competitionOf(club, team)

  await sql(club, async (query) => {
    await query('DELETE FROM $schema.ingestion_runs WHERE competition_id = $1', [id])
    for (const run of preset.runs) {
      await query(
        // Una pasada que falló lleva su motivo: la base lo exige.
        `INSERT INTO $schema.ingestion_runs (id, competition_id, kind, outcome, started_at, finished_at, error,
           opponent_clubs_created, opponent_clubs_updated, teams_created, teams_updated, rounds_created,
           rounds_updated, matches_created, matches_updated, skipped, created_at)
         VALUES (gen_random_uuid(), $1, $2, $3, now() - make_interval(mins => $4),
           CASE WHEN $3 = 'accepted' THEN NULL ELSE now() - make_interval(mins => $4 - 1) END,
           CASE WHEN $3 = 'failed' THEN 'La federación no respondió (escenario)' END,
           0, 0, 0, 0, 0, 0, 0, 0, '{"rows": []}', now())`,
        [id, run.kind, run.outcome, run.minutesAgo],
      )
    }
    await query(
      `UPDATE $schema.competitions SET last_synced_at =
         CASE WHEN $2::int IS NULL THEN NULL ELSE now() - make_interval(mins => $2::int) END WHERE id = $1`,
      [id, preset.syncedMinutesAgo ?? null],
    )
  })
}

/** Pone el nombre corto del club, el de la cabecera. */
export async function setShortName(club: ScenarioClub, shortName: string): Promise<void> {
  await sql(club, (query) => query('UPDATE $schema.clubs SET short_name = $1', [shortName]))
}

/**
 * Deja el club a medias: existe y tiene sus tablas, pero no su fila en `clubs`. Es lo que el servidor llama
 * «sin aprovisionar» (`TENANT_NOT_PROVISIONED`, GetClub.swift). Sin el *schema* entero, el servidor da un 500
 * genérico, no este código (hallazgo de R1.17).
 */
export async function leaveClubHalfProvisioned(club: ScenarioClub): Promise<void> {
  await sql(club, (query) => query('DELETE FROM $schema.clubs'))
}
