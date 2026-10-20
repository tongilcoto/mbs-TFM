<!-- La portada: los equipos del club en una temporada (plan R1, §3.2). Pide la lista de temporadas una vez, y
     con la elegida, sus equipos y sus competiciones a la vez: tres peticiones al abrir y dos al cambiar de
     temporada, tenga el club los equipos que tenga. -->
<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import LoadError from '../../components/LoadError.vue'
import SeasonPicker from '../../components/SeasonPicker.vue'
import type { TeamRow } from '../../components/teamRow'
import TeamsTable from '../../components/TeamsTable.vue'
import { teamRows } from './rows'
import { chooseSeason, newestFirst, type Season, type SeasonChoice, todayHere, toAddress } from './seasons'

// Los cuatro estados de toda pantalla (LLD-B §3.1). `unknownSeason` es el error de la temporada de la dirección
// que no existe: lo decide la web, sin preguntar al servidor.
type State =
  | { kind: 'loading' }
  | { kind: 'error'; error: ShownError }
  | { kind: 'unknownSeason'; asked: string }
  | { kind: 'noSeasons' }
  | { kind: 'noTeams' }
  | { kind: 'teams'; rows: TeamRow[] }

const route = useRoute()
const router = useRouter()

const state = ref<State>({ kind: 'loading' })
// `undefined` mientras no se han pedido, o si su petición falló.
const seasons = ref<Season[]>()
const choice = ref<SeasonChoice>()

// Cada carga cancela la anterior: al cambiar de temporada deprisa, una respuesta vieja no se pinta encima de
// la nueva; y al salir de la pantalla, se cancela la que quede (LLD-B §3.2).
let pending: AbortController | undefined

const chosen = computed(() => (choice.value?.kind === 'chosen' ? choice.value : undefined))
const pickerLabels = computed(() => newestFirst(seasons.value ?? []).map((s) => s.label))

async function load() {
  pending?.abort()
  const leaving = new AbortController()
  pending = leaving
  state.value = { kind: 'loading' }

  try {
    if (!seasons.value) {
      const result = await asResult(api.GET('/seasons', { signal: leaving.signal }))
      if (!result.ok) {
        state.value = { kind: 'error', error: result.error }
        return
      }
      seasons.value = result.data
    }

    const asked = typeof route.query.temporada === 'string' ? route.query.temporada : undefined
    choice.value = chooseSeason(seasons.value, asked, todayHere())
    if (choice.value.kind === 'none') {
      state.value = { kind: 'noSeasons' }
      return
    }
    if (choice.value.kind === 'unknown') {
      state.value = { kind: 'unknownSeason', asked: choice.value.asked }
      return
    }

    const seasonId = choice.value.season.id
    const [registrations, competitions] = await Promise.all([
      asResult(api.GET('/seasons/{seasonId}/registrations', { params: { path: { seasonId } }, signal: leaving.signal })),
      asResult(api.GET('/competitions', { params: { query: { seasonId } }, signal: leaving.signal })),
    ])
    if (!registrations.ok) {
      state.value = { kind: 'error', error: registrations.error }
      return
    }
    if (!competitions.ok) {
      state.value = { kind: 'error', error: competitions.error }
      return
    }

    const rows = teamRows(registrations.data, competitions.data)
    state.value = rows.length === 0 ? { kind: 'noTeams' } : { kind: 'teams', rows }
  } catch (error) {
    // Cancelada por otra carga o por salir de la pantalla: no hay nada que enseñar.
    if (leaving.signal.aborted) return
    throw error
  }
}

// Al abrir, y cada vez que cambia la temporada de la dirección (el selector, o «Atrás»).
watch(() => route.query.temporada, load, { immediate: true })
onBeforeUnmount(() => pending?.abort())

// El selector cambia la dirección, así que «Atrás» vuelve a la anterior y el enlace se puede compartir.
function pickSeason(label: string) {
  router.push({ query: { temporada: toAddress(label) } })
}
</script>

<template>
  <div class="heading">
    <h1>Equipos</h1>
    <SeasonPicker
      v-if="seasons && seasons.length > 0"
      :labels="pickerLabels"
      :model-value="chosen?.season.label ?? ''"
      @update:model-value="pickSeason"
    />
  </div>
  <p
    v-if="chosen?.note"
    class="note"
  >
    Temporada {{ chosen.season.label }} · {{ chosen.note }}
  </p>

  <!-- Se lee en voz alta sin mover el foco (LLD-B §10.3). -->
  <p
    v-if="state.kind === 'loading'"
    role="status"
  >
    Cargando equipos…
  </p>
  <LoadError
    v-else-if="state.kind === 'error'"
    :message="state.error.message"
    :code="state.error.code"
    :retry="state.error.retry"
    @retry="load"
  />
  <LoadError
    v-else-if="state.kind === 'unknownSeason'"
    :message="`No hay ninguna temporada ${state.asked}`"
    :retry="false"
  >
    <p>
      <RouterLink to="/">
        Ir a la temporada en curso
      </RouterLink>
    </p>
  </LoadError>
  <p v-else-if="state.kind === 'noSeasons'">
    Todavía no hay ninguna temporada.
  </p>
  <p v-else-if="state.kind === 'noTeams'">
    No hay equipos en la temporada {{ chosen?.season.label }}.
  </p>
  <TeamsTable
    v-else
    :rows="state.rows"
    :caption="`Equipos de la temporada ${chosen?.season.label}`"
  />
</template>

<style scoped>
.heading {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
}
.note {
  margin-top: 0;
  color: var(--p-text-muted-color);
}
</style>
