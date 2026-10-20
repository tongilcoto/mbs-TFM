// Los nombres en español de los valores que manda el servidor. Ninguna pantalla los escribe por su cuenta.
import type { components } from '../api/schema'

type TeamCategory = components['schemas']['TeamCategory']
export type IngestionHealth = components['schemas']['IngestionHealth']

// Como `errors.ts`: si el catálogo añade un valor y aquí falta su nombre, la web no compila.
const categoryNames: Record<TeamCategory, string> = {
  prebenjamin: 'Prebenjamín',
  benjamin: 'Benjamín',
  alevin: 'Alevín',
  infantil: 'Infantil',
  cadete: 'Cadete',
  juvenil: 'Juvenil',
  senior: 'Senior',
}

// Cómo va la ingesta de una competición (plan R1, decisión 2).
export const healthNames: Record<IngestionHealth, string> = {
  ok: 'Al día',
  failing: 'Con fallos',
  pending: 'En marcha',
  never: 'Sin datos todavía',
  stale: 'Desactualizada',
}

// Un equipo por su categoría y su letra: «Cadete B», o «Cadete» si no tiene letra.
export function teamName(category: TeamCategory, letter?: string | null): string {
  return letter ? `${categoryNames[category]} ${letter}` : categoryNames[category]
}
