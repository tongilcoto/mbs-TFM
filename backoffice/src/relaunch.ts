// Volver a traer los datos de una competición con su ↻ (plan R4, decisión 7), en la portada y en la ficha del
// equipo. Con una sola competición el servidor responde cuando la pasada ha terminado, así que mientras tanto la
// competición sale «En marcha» y su botón está bloqueado; al acabar, bien o mal, la pantalla vuelve a pedir lo que
// enseña (`afterwards`). Si falla, el aviso arriba con el texto de su código, y con «Reintentar» si es pasajero.
//
// Lo usa una pantalla al montarse. La pasada no se cancela al salir: ya está pedida, y sigue en el servidor; solo
// se deja de esperar (LLD-B §3.2).
import { onScopeDispose, reactive, ref } from 'vue'
import { api } from './api/client'
import type { ShownError } from './api/errors'
import { asResult } from './api/result'
import type { components } from './api/schema'
import { healthNames, type IngestionHealth } from './theme/names'

type Competition = components['schemas']['CompetitionResponse']

export interface RelaunchFailure {
  error: ShownError
  competitionId: string
  // Para el aviso: «Al volver a traer los datos de PREFERENTE CADETE · Grupo 2».
  competitionName: string
}

export function useRelaunch(afterwards: () => Promise<void>) {
  // Las competiciones cuyos datos se están trayendo. Reactiva: la pantalla rehace lo que pinta al cambiar.
  const running = reactive(new Set<string>())
  // El error de la última que falló; se va al pulsar otra vez.
  const failure = ref<RelaunchFailure>()
  const leaving = new AbortController()
  onScopeDispose(() => leaving.abort())

  async function relaunch(competitionId: string, competitionName: string) {
    failure.value = undefined
    running.add(competitionId)
    try {
      const result = await asResult(
        api.POST('/ingestion-runs', { body: { competitionIds: [competitionId] }, signal: leaving.signal }),
      )
      if (!result.ok) failure.value = { error: result.error, competitionId, competitionName }
    } catch (error) {
      if (leaving.signal.aborted) return
      throw error
    } finally {
      running.delete(competitionId)
    }
    await afterwards()
  }

  return { running, failure, relaunch }
}

// Cómo se enseña la ingesta de una competición: la del servidor, o «En marcha» si se están trayendo sus datos con ↻,
// aunque el servidor aún no lo diga. `previousFailed`, «La anterior tuvo fallos», como cuando lo dice el servidor
// (plan R1, decisión 2): al volver a traerla, la anterior es la que se veía.
export function shownHealth(
  competition: Competition,
  relaunched: boolean,
): { health?: IngestionHealth; healthName?: string; previousFailed: boolean } {
  const health = relaunched ? 'pending' : competition.ingestionHealth
  const previous =
    relaunched && competition.ingestionHealth !== 'pending' ? competition.ingestionHealth : competition.previousIngestionHealth
  return {
    health,
    healthName: health && healthNames[health],
    previousFailed: health === 'pending' && previous === 'failing',
  }
}
