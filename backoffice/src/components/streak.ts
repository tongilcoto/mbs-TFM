// Lo que recibe la racha (StreakBoxes.vue): ya en español. Lo prepara la pantalla (screens/competition/round.ts,
// `streakBoxes`), que es la que lee al servidor (DW-01).

// Los resultados de la racha, los del catálogo (`MatchOutcome`), con el descanso como una jornada más (D-114).
export type StreakOutcome = 'victoria' | 'empate' | 'derrota' | 'descanso'

export interface StreakBox {
  round: number
  outcome: StreakOutcome
  // Para el lector y al pasar el ratón: «Victoria en la jornada 5». El color es lo único que lo dice a la vista.
  label: string
}
