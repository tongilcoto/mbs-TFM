// Cómo se ordena la tabla de la portada por cada columna (bloque T del plan R2). Cada regla da el orden del primer
// clic; el segundo es el mismo al revés (sorting.ts). Los equipos sin competición van siempre al final en las tres
// columnas de las competiciones. Una columna nueva es una regla más aquí y una cabecera más en la tabla.
import type { SortRule } from '../../sorting'
import type { IngestionHealth } from '../../theme/names'
import type { HomeRow } from './rows'

// Los nombres de las columnas en la dirección: `?orden=ingesta`.
export const columns = ['equipo', 'competicion', 'ingesta', 'sincronizacion'] as const
export type Column = (typeof columns)[number]

// De peor a mejor: lo que hay que mirar, primero. Sin estado, detrás de todos.
const severity: IngestionHealth[] = ['failing', 'stale', 'pending', 'never', 'ok']

const withoutCompetition = (row: HomeRow) => row.keys.competitionNames.length === 0
const text = new Intl.Collator('es', { sensitivity: 'base' })

export const rules: Record<Column, SortRule<HomeRow>> = {
  // Por edad, de menor a mayor (Benjamín antes que Alevín, aunque el alfabeto diga lo contrario), y por letra. Los
  // empates —dos «Alevín A» de distinto género o modalidad— se quedan en el orden del servidor.
  equipo: {
    compare: (a, b) => a.keys.age - b.keys.age || text.compare(a.keys.letter, b.keys.letter),
  },

  // Por orden alfabético, sin que las tildes descoloquen. Un equipo con varias, por la primera de las suyas.
  competicion: {
    compare: (a, b) => text.compare(first(a.keys.competitionNames), first(b.keys.competitionNames)),
    isEmpty: withoutCompetition,
  },

  // De peor a mejor. Un equipo con varias, por la peor de las suyas.
  ingesta: {
    compare: (a, b) => worst(a) - worst(b),
    isEmpty: withoutCompetition,
  },

  // De la más antigua a la más reciente, con «Nunca» arriba. Un equipo con varias, por la más antigua de las suyas.
  // Las fechas llegan en UTC y con el mismo formato (`2026-10-20T10:00:00Z`): ordenarlas como texto es ordenarlas
  // por fecha.
  sincronizacion: {
    compare: (a, b) => oldest(a).localeCompare(oldest(b)),
    isEmpty: withoutCompetition,
  },
}

function first(names: string[]): string {
  return [...names].sort(text.compare)[0] ?? ''
}

function worst(row: HomeRow): number {
  return Math.min(...row.keys.healths.map((health) => (health ? severity.indexOf(health) : severity.length)))
}

// «Nunca» es la cadena vacía, que va antes que cualquier fecha.
function oldest(row: HomeRow): string {
  return [...row.keys.lastSynced.map((instant) => instant ?? '')].sort()[0] ?? ''
}
