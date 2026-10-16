// Un club por escenario (LLD-B §11.2, DW-13): así ninguno ve lo que dejó otro.
// Se crea con `provision-tenant` del servidor ya compilado, el mismo camino que en producción, en la base
// de pruebas. El *schema* empieza por `bo_`, que es lo único que barre `sweep.ts`.
import { randomBytes } from 'node:crypto'
import { config } from './config.ts'
import { run } from './processes.ts'
import { withDatabase } from './test-database.ts'

export interface ScenarioClub {
  /** Lo que va en la dirección: `bo-3f9a1c.localhost`. */
  slug: string
  /** Donde viven sus tablas: `bo_3f9a1c`. */
  schema: string
}

export async function createScenarioClub(): Promise<ScenarioClub> {
  const id = randomBytes(3).toString('hex')
  const club = { slug: `bo-${id}`, schema: `bo_${id}` }
  await run(
    config.serverBinary,
    ['provision-tenant', club.slug, '-f', 'rffm', '-s', club.schema, '--name', 'Club de pruebas'],
    { DB_NAME: config.database.name },
  )
  return club
}

/** Borra las dos cosas: su *schema* y su fila en `public.tenants`. */
export async function dropScenarioClub(club: ScenarioClub): Promise<void> {
  await withDatabase(config.database.name, async (db) => {
    await db.query(`DROP SCHEMA IF EXISTS "${club.schema}" CASCADE`)
    await db.query('DELETE FROM public.tenants WHERE slug = $1', [club.slug])
  })
}
