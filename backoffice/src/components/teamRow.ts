// Lo que recibe la tabla de equipos (TeamsTable.vue): ya en español y con las fechas escritas. Lo prepara la
// portada (screens/home/rows.ts).

export type HealthState = 'ok' | 'failing' | 'stale' | 'never' | 'pending'

export interface CompetitionCell {
  name: string
  health?: HealthState
  healthName?: string
  // «La anterior tuvo fallos»: la pasada está en marcha y la anterior falló (plan R1, decisión 2).
  previousFailed: boolean
  lastSynced: string
}

export interface TeamRow {
  id: string
  team: string
  // Vacía si el equipo aún no tiene competición (el estado de junio, D-68).
  competitions: CompetitionCell[]
}
