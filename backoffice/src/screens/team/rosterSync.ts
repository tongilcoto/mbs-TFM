// Sincronizar la plantilla con la Federación (plan R6, decisión 9 y parte D; D-120), sin pintar nada: cuándo se
// ofrece el botón, qué dice la fecha y qué dice el resumen al acabar.
import type { components } from '../../api/schema'
import { shownName } from '../../components/playerName'
import { formatInstant } from '../../theme/format'
import { namesOf } from '../../theme/names'
import { type Season, seasonPhase } from '../home/seasons'

type RosterSync = components['schemas']['RosterSyncResponse']
type SkipReason = components['schemas']['NamesDictionarySkipReason']

const skipReasons = namesOf('NamesDictionarySkipReason')

export interface SyncConditions {
  season: Season
  today: string
  // Si la federación del club publica las plantillas (`federationProvidesTeamRoster`, DW-24).
  providesRoster: boolean
  // Si el equipo está enganchado a la federación esa temporada: alguna competición de su inscripción con código.
  linked: boolean
}

// Solo en la temporada en curso (decisión 1 de R6.14: la ficha de la federación es la de hoy), si su federación
// publica plantillas y el equipo está enganchado. En los demás casos el servidor diría que no, así que ni se ofrece.
export function canSyncRoster({ season, today, providesRoster, linked }: SyncConditions): boolean {
  return providesRoster && linked && season.archivedAt == null && seasonPhase(season, today) === 'current'
}

// Junto al botón: cuándo se sincronizó por última vez, o que todavía no.
export function lastSyncText(syncedAt: string | null | undefined): string {
  return syncedAt ? `Última sincronización: ${formatInstant(syncedAt)}` : 'Todavía no se ha sincronizado con la Federación'
}

// El resumen (decisión 1 de R6.16): la primera línea, siempre; cada una de las demás, solo si hay algo que contar.
// Los nombres, como en la tabla («Nombre Apellidos»); los que no valen, tal cual los escribe la federación.
export function summaryLines(summary: RosterSync): string[] {
  const n = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`
  const names = (list: { fullName: string }[]) => list.map((player) => shownName(player.fullName)).join(', ')
  const lines = [`${n(summary.added, 'añadido', 'añadidos')} y ${n(summary.alreadyInRoster, 'que ya estaba', 'que ya estaban')}.`]
  if (summary.withoutBirthYear > 0) {
    lines.push(`${n(summary.withoutBirthYear, 'añadido', 'añadidos')} sin año de nacimiento: se pone desde su ficha.`)
  }
  if (summary.deletedInClub > 0) {
    const again = summary.deletedInClub === 1 ? 'no se vuelve' : 'no se vuelven'
    lines.push(`${n(summary.deletedInClub, 'dado de baja en el club', 'dados de baja en el club')}: ${again} a añadir.`)
  }
  if (summary.duplicateName.length > 0) {
    const one = summary.duplicateName.length === 1
    const what = one ? 'dado de alta como jugador nuevo; para revisarlo' : 'dados de alta como jugadores nuevos; para revisarlos'
    lines.push(`Con nombre repetido en el club, ${what}: ${names(summary.duplicateName)}.`)
  }
  if (summary.inOtherTeam.length > 0) {
    const list = summary.inOtherTeam.map((player) => `${shownName(player.fullName)} (${player.team.displayName})`).join(', ')
    lines.push(`En otro equipo del club esta temporada, ${summary.inOtherTeam.length === 1 ? 'no añadido' : 'no añadidos'}: ${list}.`)
  }
  if (summary.invalidName.length > 0) {
    const list = summary.invalidName.map((name) => `«${name}»`).join(', ')
    const what = summary.invalidName.length === 1 ? 'no añadido; para darlo' : 'no añadidos; para darlos'
    lines.push(`Con un nombre que no vale, ${what} de alta a mano: ${list}.`)
  }
  // El diccionario de nombres (R6.19): nunca para la sincronización, así que el resumen dice si faltaba o qué líneas no
  // se han usado, para arreglarlas en el fichero.
  const dictionary = summary.namesDictionary
  if (!dictionary.found) {
    lines.push('No se ha encontrado el diccionario de nombres: los nombres se han guardado como llegan de la Federación.')
  } else if (dictionary.skippedLines.length > 0) {
    const skipped = dictionary.skippedLines
    const one = skipped.length === 1
    const list = skipped
      .map((line) => {
        const why = skipReasons[line.reason as SkipReason]
        const where = line.reason === 'repeated' && line.repeatedLine != null ? `: ya está en la línea ${line.repeatedLine}` : ''
        return `línea ${line.line}, «${line.text}» (${why}${where})`
      })
      .join('; ')
    const what = one ? 'línea con error, que no se ha usado' : 'líneas con error, que no se han usado'
    lines.push(`El diccionario de nombres tiene ${skipped.length} ${what}: ${list}.`)
  }
  return lines
}
