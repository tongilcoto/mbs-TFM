// Lo que dice cada fila de la pestaña Plantilla, sin pintar nada (plan R6, §3 y decisión 7). El dorsal, la
// demarcación y la foto son de la fila de esa temporada; el nombre y el año, de su perfil (D-119).
import type { components } from '../../api/schema'
import { initialsOf, shownName } from '../../components/playerName'
import { formatInstant } from '../../theme/format'
import { namesOf } from '../../theme/names'

type Player = components['schemas']['PlayerResponse']
type PlayerPosition = components['schemas']['PlayerPosition']

const positionNames = namesOf('PlayerPosition')

export interface RosterRow {
  id: string
  // «Nombre Apellidos» (decisión 9): también es el texto alternativo de la foto.
  name: string
  initials: string
  // Sin foto, nada: se pintan las iniciales.
  photoUrl?: string
  // Sin dorsal ni demarcación, una raya; sin año, «Sin año».
  shirtNumber: string
  position: string
  birthYear: string
  // «Federado» si la última sincronización lo listó, «No federado» si no; nada si la plantilla nunca se ha
  // sincronizado o la federación no publica plantillas (`federated` nulo, D-120).
  federation?: 'Federado' | 'No federado'
}

// En el orden en que llegan. Un nulo puede llegar como clave ausente (DW-21): `??` trata igual los dos.
export function rosterRows(players: Player[]): RosterRow[] {
  return players.map((player) => ({
    id: player.id,
    name: shownName(player.fullName),
    initials: initialsOf(player.fullName),
    photoUrl: player.photoUrl ?? undefined,
    shirtNumber: player.shirtNumber == null ? '—' : String(player.shirtNumber),
    // El generador ensancha la demarcación «o nula» a cualquier texto (`type` con `'null'` y `anyOf`, R6.6); el
    // catálogo solo admite las cuatro.
    position: player.position == null ? '—' : positionNames[player.position as PlayerPosition],
    birthYear: player.birthYear == null ? 'Sin año' : String(player.birthYear),
    federation: player.federated == null ? undefined : player.federated ? 'Federado' : 'No federado',
  }))
}

// En la ficha del jugador (decisión 5 de R6.16): «Federado» o «No federado», con la última vez que lo publicó la
// Federación si lo ha publicado alguna vez; nada si la plantilla nunca se ha sincronizado.
export function federationText(player: Pick<Player, 'federated' | 'lastListedAt'>): string | undefined {
  if (player.federated == null) return undefined
  if (player.lastListedAt == null) return player.federated ? 'Federado' : 'No federado'
  const when = formatInstant(player.lastListedAt)
  return player.federated ? `Federado · publicado el ${when}` : `No federado · publicado por última vez el ${when}`
}
