// El barrido de los clubs de los escenarios: solo los que empiezan por `bo_` (DW-13). Las pruebas del
// backend usan `e2e_` y `test_`, y este barrido no las toca, igual que el suyo no toca `bo_`.
import { config } from './config.ts'
import { withDatabase } from './test-database.ts'

/** Borra los *schemas* `bo_…` y sus filas en `public.tenants`. Devuelve cuántos clubs borró. */
export async function sweepScenarioClubs(): Promise<number> {
  return withDatabase(config.database.name, async (db) => {
    const schemas = await db.query<{ nspname: string }>(
      "SELECT nspname FROM pg_namespace WHERE nspname LIKE 'bo\\_%'",
    )
    for (const { nspname } of schemas.rows) {
      await db.query(`DROP SCHEMA "${nspname}" CASCADE`)
    }
    await db.query("DELETE FROM public.tenants WHERE schema_name LIKE 'bo\\_%'")
    return schemas.rowCount ?? 0
  })
}
