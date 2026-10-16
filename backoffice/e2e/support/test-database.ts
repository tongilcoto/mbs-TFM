// La base de las pruebas, `tfm_test`. No existe hasta que alguien la crea: si no están, se crea igual que
// hacen las pruebas del backend (`TestEnvironment.swift`), y se le pasan las migraciones comunes.
import pg from 'pg'
import { config } from './config.ts'
import { run } from './processes.ts'

function client(database: string): pg.Client {
  const { host, port, user, password } = config.database
  return new pg.Client({ host, port, user, password, database })
}

/** Abre una conexión a la base, hace lo que se le pida y la cierra siempre. */
export async function withDatabase<T>(database: string, work: (db: pg.Client) => Promise<T>): Promise<T> {
  const db = client(database)
  try {
    await db.connect()
  } catch (error) {
    const { host, port } = config.database
    throw new Error(`La base de datos no contesta en ${host}:${port} (¿está Docker en marcha?): ${String(error)}`, {
      cause: error,
    })
  }
  try {
    return await work(db)
  } finally {
    await db.end()
  }
}

/** Crea `tfm_test` si no existe y le pasa las migraciones comunes (`public.tenants`). */
export async function prepareTestDatabase(): Promise<void> {
  const name = config.database.name
  await withDatabase('postgres', async (db) => {
    const found = await db.query('SELECT 1 FROM pg_database WHERE datname = $1', [name])
    if (found.rowCount === 0) {
      try {
        await db.query(`CREATE DATABASE "${name}"`)
      } catch (error) {
        // Otro proceso (una pasada del backend) se nos adelantó: que exista es lo que queríamos.
        const now = await db.query('SELECT 1 FROM pg_database WHERE datname = $1', [name])
        if (now.rowCount === 0) throw error
      }
    }
  })
  // Lo mismo que `swift run Run migrate --yes`, con el binario ya compilado. Si no hay nada nuevo, no hace nada.
  await run(config.serverBinary, ['migrate', '--yes'], { DB_NAME: name })
}
