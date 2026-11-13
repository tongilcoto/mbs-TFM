// Lo que recibe la tabla de equipos (TeamsTable.vue): ya en español y con las fechas escritas. Lo prepara la
// portada (screens/home/rows.ts).
import type { StreakBox } from './streak'

export type HealthState = 'ok' | 'failing' | 'stale' | 'never' | 'pending'

export interface CompetitionCell {
  id: string
  name: string
  health?: HealthState
  healthName?: string
  // «La anterior tuvo fallos»: la pasada está en marcha y la anterior falló (plan R1, decisión 2).
  previousFailed: boolean
  lastSynced: string
  // Cómo le va al equipo en ella (plan R5, §3): lo prepara screens/home/summary.ts.
  summary: SummaryCell
}

// Cada parte, vacía si no hay dato: sin clasificación, ni posición ni racha; sin jugar, sin último; acabada, sin
// próximo.
export interface SummaryCell {
  position?: number
  streak: StreakBox[]
  last?: LastMatchCell
  next?: NextMatchCell
}

// El último partido (decisión 5): la letra del resultado, casa o fuera, el marcador con el local primero y el rival,
// con el puesto con el que llegó (ninguno en la primera jornada).
export interface LastMatchCell {
  outcome: 'V' | 'E' | 'D'
  atHome: boolean
  score: string
  opponent: string
  opponentPosition?: number
}

// El próximo partido, con su jornada para llevar a ella (decisión 6); o el descanso, que solo dice su jornada.
export type NextMatchCell =
  | {
      kind: 'match'
      round: number
      // «Sáb 14 nov», como en la pestaña Resultados.
      date: string
      // Sin ella, «hora por fijar».
      time?: string
      atHome: boolean
      opponent: string
      opponentPosition?: number
    }
  | { kind: 'rest'; round: number }

export interface TeamRow {
  id: string
  team: string
  // Vacía si el equipo aún no tiene competición (el estado de junio, D-68).
  competitions: CompetitionCell[]
}
