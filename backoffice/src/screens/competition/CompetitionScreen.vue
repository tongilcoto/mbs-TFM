<!-- Jornada y clasificación de una competición (plan R4, §3.4): `/temporadas/:temporada/competiciones/:id`, con la
     jornada detrás de `?` (`?jornada=5`, decisión 3). Arriba, la competición; debajo, «‹ Anterior», el selector de
     jornada y «Siguiente ›»; y la jornada: sus partidos y, debajo, la clasificación tras ella.
     Al abrir pide las temporadas, las competiciones de la del camino (el servidor no da una competición suelta) y
     sus jornadas; con la jornada, sus partidos y su clasificación a la vez. Al cambiar de jornada, solo esas dos. -->
<script setup lang="ts">
import Button from 'primevue/button'
import Select from 'primevue/select'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult, type Result } from '../../api/result'
import type { components } from '../../api/schema'
import LoadError from '../../components/LoadError.vue'
import { competitionLabel } from '../../theme/names'
import { isTeamCode } from '../sync-team/link'
import { type Season, toAddress } from '../home/seasons'
import { roundsToLookIn } from '../team/header'
import RoundMatchesTable from './RoundMatchesTable.vue'
import StandingTable from './StandingTable.vue'
import { askedRound, competitionDetails, roundMatchRows, roundOptions, standingLines } from './round'

type Competition = components['schemas']['CompetitionResponse']
type Round = components['schemas']['RoundResponse']
type Match = components['schemas']['MatchResponse']
type Standing = components['schemas']['StandingResponse']

// La competición que no existe, o un código que no es un UUID (LLD-B §6.7): sin código en pequeño, porque no hubo
// error del servidor que contar.
const competitionNotFound: ShownError = { message: 'No se ha encontrado la competición', retry: false }

// Lo de la competición, que no cambia al moverse entre jornadas. «Sin jornadas»: la Federación aún no ha publicado
// el calendario.
type State =
  | { kind: 'loading' }
  | { kind: 'error'; error: ShownError; notFound: boolean }
  | { kind: 'ready'; competition: Competition; season: Season; rounds: Round[] }

// Lo de la jornada que se ve.
type Shown =
  | { kind: 'loading' }
  | { kind: 'error'; error: ShownError }
  | { kind: 'unknown'; asked: string }
  | { kind: 'none' }
  | { kind: 'round'; round: Round; matches: Match[]; table: Standing[] }

const route = useRoute()
const router = useRouter()

const state = ref<State>({ kind: 'loading' })
const shown = ref<Shown>({ kind: 'loading' })

let pending: AbortController | undefined
function startRequest(): AbortSignal {
  pending?.abort()
  pending = new AbortController()
  return pending.signal
}
onBeforeUnmount(() => pending?.abort())

const ready = computed(() => (state.value.kind === 'ready' ? state.value : undefined))
const options = computed(() => roundOptions(ready.value?.rounds ?? []))
const round = computed(() => (shown.value.kind === 'round' ? shown.value.round : undefined))
const first = computed(() => options.value[0]?.value)
const last = computed(() => options.value.at(-1)?.value)
const matchRows = computed(() => (shown.value.kind === 'round' ? roundMatchRows(shown.value.matches) : []))
const lines = computed(() => (shown.value.kind === 'round' ? standingLines(shown.value.table) : []))

// «← Volver», a donde se estaba (la ficha del equipo, si se vino de ella); entrando por la dirección, a la portada
// de esa temporada.
const back = computed(() => {
  const previous = router.options.history.state.back
  if (typeof previous === 'string') return previous
  return { path: '/', query: { temporada: String(route.params.temporada) } }
})

// La competición: se pide al abrir y al cambiar de competición o de temporada en el camino.
async function loadCompetition() {
  const signal = startRequest()
  state.value = { kind: 'loading' }
  shown.value = { kind: 'loading' }
  const id = String(route.params.id)
  if (!isTeamCode(id)) {
    state.value = { kind: 'error', error: competitionNotFound, notFound: true }
    return
  }
  try {
    const seasons = await asResult(api.GET('/seasons', { signal }))
    if (!seasons.ok) {
      state.value = { kind: 'error', error: seasons.error, notFound: false }
      return
    }
    // Una temporada que el club no tiene: tampoco tiene esa competición.
    const season = seasons.data.find((s) => toAddress(s.label) === route.params.temporada)
    if (!season) {
      state.value = { kind: 'error', error: competitionNotFound, notFound: true }
      return
    }
    const [competitions, rounds] = await Promise.all([
      asResult(api.GET('/competitions', { params: { query: { seasonId: season.id } }, signal })),
      asResult(api.GET('/rounds', { params: { query: { competitionId: id } }, signal })),
    ])
    const competition = competitions.ok ? competitions.data.find((c) => c.id === id) : undefined
    if (!competitions.ok) state.value = { kind: 'error', error: competitions.error, notFound: false }
    else if (!competition || (!rounds.ok && rounds.error.code === 'COMPETITION_NOT_FOUND'))
      state.value = { kind: 'error', error: competitionNotFound, notFound: true }
    else if (!rounds.ok) state.value = { kind: 'error', error: rounds.error, notFound: false }
    else {
      state.value = { kind: 'ready', competition, season, rounds: rounds.data }
      await loadRound(signal)
    }
  } catch (error) {
    if (signal.aborted) return
    throw error
  }
}

// La jornada de la dirección, o la que toca: sus partidos y su clasificación.
async function loadRound(signal = startRequest()) {
  if (state.value.kind !== 'ready') return
  const rounds = state.value.rounds
  if (rounds.length === 0) {
    shown.value = { kind: 'none' }
    return
  }
  const asked = typeof route.query.jornada === 'string' ? route.query.jornada : undefined
  const found = asked === undefined ? undefined : askedRound(rounds, asked)
  if (found === 'unknown') {
    shown.value = { kind: 'unknown', asked: asked! }
    return
  }
  shown.value = { kind: 'loading' }
  try {
    const matchesOf = (round: Round) =>
      asResult(api.GET('/matches', { params: { query: { roundId: round.id, perPage: 100 } }, signal }))
    let chosen: Round
    let table: Result<Standing[]>
    let matches: Result<{ data: Match[] }> | undefined
    if (found) {
      // La pedida: sus partidos y su clasificación, a la vez.
      chosen = found
      ;[table, matches] = await Promise.all([
        asResult(api.GET('/standings', { params: { query: { roundId: chosen.id } }, signal })),
        matchesOf(chosen),
      ])
    } else {
      // Sin jornada en la dirección, la de la última clasificación: desde la en curso hacia atrás, como la caja
      // Posición de la ficha (§3.4). Si ninguna la tiene todavía, la en curso; si la competición terminó, desde la
      // última.
      const candidates = roundsToLookIn(rounds)
      chosen = candidates[0]!
      table = { ok: true, data: [] }
      for (const candidate of candidates) {
        const answer = await asResult(api.GET('/standings', { params: { query: { roundId: candidate.id } }, signal }))
        if (!answer.ok || answer.data.length > 0) {
          chosen = candidate
          table = answer
          break
        }
      }
    }
    if (!table.ok) {
      shown.value = { kind: 'error', error: table.error }
      return
    }
    matches ??= await matchesOf(chosen)
    if (!matches.ok) shown.value = { kind: 'error', error: matches.error }
    else shown.value = { kind: 'round', round: chosen, matches: matches.data.data, table: table.data }
  } catch (error) {
    if (signal.aborted) return
    throw error
  }
}

function retry() {
  if (state.value.kind === 'ready') void loadRound()
  else void loadCompetition()
}

// Con una clave de texto: una lista nueva en cada cambio de la dirección haría saltar también al cambiar de jornada.
watch(() => `${String(route.params.temporada)}/${String(route.params.id)}`, loadCompetition, { immediate: true })
watch(
  () => route.query.jornada,
  () => {
    if (state.value.kind === 'ready') void loadRound()
  },
)

// Moverse entre jornadas cambia la dirección: recargar deja en la misma, y «Atrás» vuelve a la anterior.
function goTo(number: number | undefined) {
  if (number === undefined) return
  router.push({ query: { ...route.query, jornada: String(number) } })
}
</script>

<template>
  <p class="back">
    <RouterLink :to="back">
      ← Volver
    </RouterLink>
  </p>
  <h1>{{ ready ? competitionLabel(ready.competition) : 'Competición' }}</h1>
  <p
    v-if="ready"
    class="subtitle"
  >
    {{ competitionDetails(ready.competition, ready.season.label) }}
  </p>

  <!-- Se lee en voz alta sin mover el foco (LLD-B §10.3). -->
  <p
    v-if="state.kind === 'loading'"
    role="status"
  >
    Cargando jornada…
  </p>
  <LoadError
    v-else-if="state.kind === 'error'"
    :message="state.error.message"
    :code="state.error.code"
    :retry="state.error.retry"
    @retry="retry"
  >
    <p v-if="state.notFound">
      <RouterLink to="/">
        Ir a la portada
      </RouterLink>
    </p>
  </LoadError>
  <p
    v-else-if="shown.kind === 'none'"
    class="empty"
  >
    La Federación aún no ha publicado el calendario.
  </p>
  <template v-else>
    <!-- Moverse entre jornadas. Sus datos son de la Federación: no se crean, ni se editan, ni se borran (LLD-B §7.5). -->
    <div class="rounds">
      <Button
        label="‹ Anterior"
        severity="secondary"
        outlined
        :disabled="!round || round.number === first"
        @click="goTo(options[options.findIndex((o) => o.value === round?.number) - 1]?.value)"
      />
      <label
        id="round-picker-label"
        for="round-picker"
        class="visually-hidden"
      >Jornada</label>
      <Select
        label-id="round-picker"
        aria-labelledby="round-picker-label"
        :options="options"
        option-label="label"
        option-value="value"
        :model-value="round?.number"
        @update:model-value="goTo"
      />
      <Button
        label="Siguiente ›"
        severity="secondary"
        outlined
        :disabled="!round || round.number === last"
        @click="goTo(options[options.findIndex((o) => o.value === round?.number) + 1]?.value)"
      />
      <span class="source">Federación</span>
    </div>

    <p
      v-if="shown.kind === 'loading'"
      role="status"
    >
      Cargando jornada…
    </p>
    <LoadError
      v-else-if="shown.kind === 'error'"
      :message="shown.error.message"
      :code="shown.error.code"
      :retry="shown.error.retry"
      @retry="retry"
    />
    <LoadError
      v-else-if="shown.kind === 'unknown'"
      :message="`No hay ninguna jornada ${shown.asked} en esta competición`"
      :retry="false"
    >
      <p>
        <RouterLink :to="{ query: {} }">
          Ir a la última jornada jugada
        </RouterLink>
      </p>
    </LoadError>
    <template v-else-if="shown.kind === 'round'">
      <h2>Partidos de la jornada {{ shown.round.number }}</h2>
      <RoundMatchesTable
        :rows="matchRows"
        :caption="`Partidos de la jornada ${shown.round.number}`"
      />

      <h2>Clasificación tras la jornada {{ shown.round.number }}</h2>
      <StandingTable
        v-if="lines.length > 0"
        :lines="lines"
        :caption="`Clasificación tras la jornada ${shown.round.number}`"
      />
      <p
        v-else
        class="empty"
      >
        Esta jornada aún no tiene clasificación.
      </p>
    </template>
  </template>
</template>

<style scoped>
.back {
  margin: 0 0 0.5rem;
}
h1 {
  margin-bottom: 0;
}
.subtitle {
  margin-top: 0.25rem;
  color: var(--p-text-muted-color);
}
h2 {
  margin: 1.5rem 0 0.5rem;
  font-size: 1.125rem;
}
.rounds {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.5rem;
}
.source {
  margin-left: auto;
  padding: 0.125rem 0.5rem;
  border: 1px solid var(--p-content-border-color);
  border-radius: 999px;
  font-size: 0.8125rem;
  color: var(--p-text-muted-color);
}
.empty {
  color: var(--p-text-muted-color);
}
/* Lo lee el lector de pantalla y no se ve. */
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}
</style>
