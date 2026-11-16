// El buscador del diálogo del alta (plan R6, decisión 9): los jugadores que el club ya tiene, por su nombre. Lo que
// decide sin pintar nada: cuándo pregunta, con qué respuesta se queda y qué ofrece.
import type { Result } from '../../api/result'
import type { components } from '../../api/schema'
import { shownName } from '../../components/playerName'

type Profile = components['schemas']['PlayerProfileSearchResult']

// Cuánto se espera a que se deje de teclear.
export const SEARCH_DELAY_MS = 300

// Desde 3 letras, contando todas las palabras (como el servidor, `PlayerSearch`; con menos responde 400).
export function enoughLetters(text: string): boolean {
  return (text.match(/\p{L}/gu) ?? []).length >= 3
}

// Busca al dejar de teclear y **se queda solo con la respuesta de lo último escrito** (R6.7): si salen dos búsquedas
// seguidas, la primera puede llegar después, y no debe pintar lo de «jua» cuando ya pone «juan g». Cada búsqueda
// cancela la anterior, y además se comprueba que la que llega es la última. `show` recibe lo encontrado, o nada si
// no se busca.
export function latestSearch<T>(
  fetch: (text: string, signal: AbortSignal) => Promise<Result<T[]>>,
  show: (result: T[] | undefined, failure?: Result<T[]>) => void,
) {
  let timer: ReturnType<typeof setTimeout> | undefined
  let current: AbortController | undefined

  function stop() {
    clearTimeout(timer)
    current?.abort()
    current = undefined
  }

  function type(text: string) {
    stop()
    if (!enoughLetters(text)) {
      show(undefined)
      return
    }
    timer = setTimeout(async () => {
      const mine = new AbortController()
      current = mine
      try {
        const answer = await fetch(text, mine.signal)
        if (current !== mine) return
        if (answer.ok) show(answer.data)
        else show(undefined, answer)
      } catch (error) {
        if (mine.signal.aborted) return
        throw error
      }
    }, SEARCH_DELAY_MS)
  }

  return { type, stop }
}

// Una opción del buscador: un jugador del club, o la última, dar de alta lo escrito como jugador nuevo. `label` es
// lo que lee el lector de pantalla, entero: la lista lo pone de nombre a la opción, y lo de dentro no se lee.
export type ProfileOption =
  | { kind: 'profile'; key: string; name: string; detail: string; label: string; disabled: boolean; profile: Profile }
  | { kind: 'new'; key: 'nuevo'; name: string; detail: string; label: string; disabled: false }

// Cada jugador, «Juan García Fuente», y debajo su año y su último equipo y temporada: «2010 · Infantil A 2024/25».
// El que ya está en otro equipo esta temporada no se puede elegir (D-121), y dice dónde: «Ya está en Celtic Cadete
// B». El equipo, con el nombre que manda el servidor (club, categoría y letra): la web no tiene la lista de los
// equipos del club, porque el servidor no sirve `listTeams`.
export function profileOptions(profiles: Profile[], typed: string): ProfileOption[] {
  const teamName = (team: { displayName: string }) => team.displayName
  const options: ProfileOption[] = profiles.map((profile) => {
    const parts = [profile.birthYear == null ? 'Sin año' : String(profile.birthYear)]
    const other = profile.otherTeamThisSeason
    if (other) parts.push(`Ya está en ${teamName(other)}`)
    else if (profile.lastRoster) parts.push(`${teamName(profile.lastRoster.team)} ${profile.lastRoster.seasonLabel}`)
    const name = shownName(profile.fullName)
    const detail = parts.join(' · ')
    return { kind: 'profile', key: profile.profileId, name, detail, label: `${name}, ${detail}`, disabled: other != null, profile }
  })
  const text = typed.trim().replace(/\s+/g, ' ')
  const detail = `Dar de alta a «${text}» como jugador nuevo`
  options.push({ kind: 'new', key: 'nuevo', name: text, detail, label: detail, disabled: false })
  return options
}
