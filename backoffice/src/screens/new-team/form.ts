// Lo que decide el alta de equipo sin pintar nada (plan R2, §3.2 y decisión 5).
import type { components } from '../../api/schema'
import type { Gender, Modality, TeamCategory } from '../../theme/names'
import { chooseSeason, type Season } from '../home/seasons'

export type CreateTeamRequest = components['schemas']['CreateTeamRequest']

// Lo que va rellenando el usuario. Un campo sin elegir es `undefined`, como pide `checkForm` (rules.ts).
export interface TeamForm {
  category?: TeamCategory
  letter: string
  gender?: Gender
  modality?: Modality
  seasonId?: string
}

// Lo que la portada le pasa al formulario al abrirlo, en el estado de la navegación de Vue Router, no en la
// dirección: `/equipos/nuevo` es siempre el mismo camino (decisión 5). Al recargar, o al escribir la dirección
// a mano, no hay.
export interface FromHome {
  // La temporada que enseñaba la portada, por su etiqueta: `2026/27`.
  seasonLabel?: string
}

// Qué temporada viene elegida en el selector (decisión 5), en este orden: sin temporadas, ninguna; la de la
// portada, si sigue en la lista; y si no, la regla de la portada, sin error.
export function initialSeason(seasons: Season[], fromHome: string | undefined, today: string): Season | undefined {
  if (seasons.length === 0) return undefined
  const fromList = seasons.find((s) => s.label === fromHome)
  if (fromList) return fromList
  const choice = chooseSeason(seasons, undefined, today)
  return choice.kind === 'chosen' ? choice.season : undefined
}

// Lo que se envía a `createTeam`. La letra en blanco no se manda: es opcional, y sin ella es otro equipo.
// Con espacios sí se manda, y la rechaza el servidor (LLD-B §5.1), que dice que es de ese campo.
export function toRequest(form: TeamForm): Partial<CreateTeamRequest> {
  const request: Partial<CreateTeamRequest> = {
    category: form.category,
    gender: form.gender,
    modality: form.modality,
    seasonId: form.seasonId,
  }
  if (form.letter !== '') request.letter = form.letter
  return request
}

// Hay cambios sin guardar si el usuario ha tocado algo. La temporada que viene elegida no cuenta: la puso la web.
export function hasChanges(form: TeamForm, initialSeasonId: string | undefined): boolean {
  return (
    form.category !== undefined ||
    form.letter !== '' ||
    form.gender !== undefined ||
    form.modality !== undefined ||
    form.seasonId !== initialSeasonId
  )
}
