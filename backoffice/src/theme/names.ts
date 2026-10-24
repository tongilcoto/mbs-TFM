// Los nombres en español de los valores que manda el servidor. Ninguna pantalla los escribe por su cuenta.
import type { components } from '../api/schema'

export type TeamCategory = components['schemas']['TeamCategory']
export type Gender = components['schemas']['Gender']
export type Modality = components['schemas']['Modality']
export type IngestionHealth = components['schemas']['IngestionHealth']

// Como `errors.ts`: si el catálogo añade un valor y aquí falta su nombre, la web no compila.
// En el orden del catálogo, que es el de edad, de menor a mayor: así los enseña el selector del alta.
export const categoryNames: Record<TeamCategory, string> = {
  prebenjamin: 'Prebenjamín',
  benjamin: 'Benjamín',
  alevin: 'Alevín',
  infantil: 'Infantil',
  cadete: 'Cadete',
  juvenil: 'Juvenil',
  senior: 'Senior',
}

export const genderNames: Record<Gender, string> = {
  masculino: 'Masculino',
  femenino: 'Femenino',
  mixto: 'Mixto',
}

export const modalityNames: Record<Modality, string> = {
  futbol_11: 'Fútbol 11',
  futbol_7: 'Fútbol 7',
  futbol_5: 'Fútbol 5',
  futbol_sala: 'Fútbol sala',
  futbol_playa: 'Fútbol playa',
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
