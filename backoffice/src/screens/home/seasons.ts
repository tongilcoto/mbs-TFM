// Qué temporada enseña la portada (plan R1, decisión 5). Lo decide la web con la lista de temporadas, sin
// preguntar más al servidor.
import type { components } from '../../api/schema'

export type Season = components['schemas']['SeasonResponse']

export type SeasonChoice =
  // El club no tiene ninguna temporada: la portada vacía, sin selector (decisión 6).
  | { kind: 'none' }
  // La de la dirección no existe, o no se entiende: el error de la tabla.
  | { kind: 'unknown'; asked: string }
  // `note`, solo si no hay ninguna en curso y se enseña la más reciente: «terminada» o «todavía no ha empezado».
  | { kind: 'chosen'; season: Season; note?: string }

// En la dirección, con guion (`2025-26`); en la etiqueta, con barra (`2025/26`). LLD-B §6.5.
export function toAddress(label: string): string {
  return label.replace('/', '-')
}

// De la más reciente a la más antigua, como las enseña el selector.
export function newestFirst(seasons: Season[]): Season[] {
  return [...seasons].sort((a, b) => b.startDate.localeCompare(a.startDate))
}

// `asked` es lo que trae `?temporada=` (o nada); `today`, la fecha de hoy como `2026-10-20`.
export function chooseSeason(seasons: Season[], asked: string | undefined, today: string): SeasonChoice {
  if (seasons.length === 0) return { kind: 'none' }

  if (asked !== undefined) {
    const season = seasons.find((s) => toAddress(s.label) === asked)
    return season ? { kind: 'chosen', season } : { kind: 'unknown', asked: asked.replace('-', '/') }
  }

  const current = seasons.find((s) => s.isCurrent)
  if (current) return { kind: 'chosen', season: current }

  // Sin ninguna en curso, la más reciente. Las fechas son texto (`2026-07-01`) y se comparan como texto, sin
  // pasar por la zona horaria (LLD-B §9.7).
  const newest = newestFirst(seasons)[0]!
  const note = newest.endDate < today ? 'terminada' : newest.startDate > today ? 'todavía no ha empezado' : undefined
  return { kind: 'chosen', season: newest, note }
}

// La fecha de hoy en el navegador, como `2026-10-20`.
export function todayHere(): string {
  const now = new Date()
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
}
