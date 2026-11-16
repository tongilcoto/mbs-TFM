<!-- La pestaña Resultados de la ficha del equipo (plan R4, §3.3): los partidos del equipo en la temporada, de la
     competición que se ve en la cabecera. Los pide ella: la ficha le dice de qué equipo, temporada y competición, y
     le pasa la clasificación que ya encontró para la posición, de donde sale el puesto de hoy de los partidos sin
     jugar. Si fallan, el error va aquí y la cabecera se queda. Sus datos son de la Federación: no se crean, ni se
     editan, ni se borran (LLD-B §7.5). -->
<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult, type Result } from '../../api/result'
import type { components } from '../../api/schema'
import LoadError from '../../components/LoadError.vue'
import type { Season } from '../home/seasons'
import MatchesTable from './MatchesTable.vue'
import { matchRows } from './matches'

type Match = components['schemas']['MatchResponse']
type Standing = components['schemas']['StandingResponse']

const props = defineProps<{
  teamId: string
  // El nombre del equipo, «Cadete A», para el título de la tabla.
  teamTitle: string
  season: Season
  // La competición que se ve. Sin ella, el equipo está inscrito sin sincronizar: no hay partidos que pedir.
  competitionId?: string
  // La clasificación de la cabecera y su jornada; sin ella mientras se busca, o si aún no hay ninguna.
  standing?: { round: number; table: Standing[] }
  // La ingesta de la competición está «En marcha»: si no hay partidos, es que están llegando.
  ingesting: boolean
  // A dónde lleva «Sincronizar con la Federación».
  syncTarget: RouteLocationRaw
  // La ficha lo sube cada vez que se refresca sola o tras ↻: se vuelven a pedir los partidos, sin «Cargando…».
  refreshCount: number
}>()

type Matches = { kind: 'loading' } | { kind: 'error'; error: ShownError } | { kind: 'list'; matches: Match[] }

const matches = ref<Matches>({ kind: 'loading' })

// Cada petición cancela la anterior, y salir cancela la que quede (LLD-B §3.2).
let pending: AbortController | undefined

// Las filas de la tabla: los partidos de la competición que se ve (§3.2).
const rows = computed(() =>
  matches.value.kind === 'list'
    ? matchRows(
        matches.value.matches.filter((match) => match.competitionId === props.competitionId),
        props.teamId,
        props.standing,
      )
    : [],
)

// Todos los partidos del equipo en la temporada, de todas sus competiciones: unos 30, y la página llega a 100. Por
// si un día son más, página a página hasta el total.
async function fetchMatches(signal: AbortSignal): Promise<Result<Match[]>> {
  const all: Match[] = []
  for (let page = 1; ; page++) {
    const answer = await asResult(
      api.GET('/matches', { params: { query: { teamId: props.teamId, seasonId: props.season.id, page, perPage: 100 } }, signal }),
    )
    if (!answer.ok) return answer
    all.push(...answer.data.data)
    if (all.length >= answer.data.total || answer.data.data.length === 0) return { ok: true, data: all }
  }
}

// Al abrir y con *Reintentar*, con «Cargando partidos…»; en el refresco (`quiet`), sin él, y si falla se deja como
// estaba.
async function load(quiet = false) {
  pending?.abort()
  if (props.competitionId === undefined) {
    matches.value = { kind: 'list', matches: [] }
    return
  }
  const leaving = new AbortController()
  pending = leaving
  if (!quiet) matches.value = { kind: 'loading' }
  try {
    const listed = await fetchMatches(leaving.signal)
    if (listed.ok) matches.value = { kind: 'list', matches: listed.data }
    else if (!quiet) matches.value = { kind: 'error', error: listed.error }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

// Al abrir, y si cambia el equipo o la temporada. Con otra competición del mismo equipo no hace falta: ya están
// los de todas.
watch(() => [props.teamId, props.season.id, props.competitionId === undefined], () => load(), { immediate: true })
watch(() => props.refreshCount, () => load(true))
onBeforeUnmount(() => pending?.abort())
</script>

<template>
  <!-- Lo de la pestaña, como una zona con su nombre: el lector puede saltar a ella. -->
  <section aria-label="Resultados">
    <p
      v-if="matches.kind === 'loading'"
      role="status"
    >
      Cargando partidos…
    </p>
    <LoadError
      v-else-if="matches.kind === 'error'"
      :message="matches.error.message"
      :code="matches.error.code"
      :retry="matches.error.retry"
      @retry="load()"
    />
    <div
      v-else-if="competitionId === undefined"
      class="empty"
    >
      <p>Este equipo aún no tiene partidos.</p>
      <p>
        <RouterLink :to="syncTarget">
          Sincronizar con la Federación
        </RouterLink>
      </p>
    </div>
    <p
      v-else-if="rows.length === 0"
      class="empty"
    >
      {{ ingesting ? 'Trayendo el calendario de la Federación…' : 'La Federación aún no ha publicado partidos de este equipo.' }}
    </p>
    <MatchesTable
      v-else
      :rows="rows"
      :caption="`Partidos de ${teamTitle} en la temporada ${season.label}`"
      :season-label="season.label"
    />
  </section>
</template>

<style scoped>
.empty p {
  margin: 0 0 0.375rem;
}
</style>
