<!-- La portada: los equipos del club en una temporada (plan R1, §3.2). Pide la lista de temporadas una vez, y
     con la elegida, sus equipos y sus competiciones a la vez: tres peticiones al abrir y dos al cambiar de
     temporada, tenga el club los equipos que tenga. -->
<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Button from 'primevue/button'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import LoadError from '../../components/LoadError.vue'
import SeasonPicker from '../../components/SeasonPicker.vue'
import TeamsTable from '../../components/TeamsTable.vue'
import { nextOrder, orderFromAddress, orderToAddress, sortRows } from '../../sorting'
import { type Column, columns, rules } from './order'
import { type HomeRow, teamRows } from './rows'
import { chooseSeason, newestFirst, type Season, type SeasonChoice, todayHere, toAddress } from './seasons'

// Los cuatro estados de toda pantalla (LLD-B §3.1). `unknownSeason` es el error de la temporada de la dirección
// que no existe: lo decide la web, sin preguntar al servidor.
type State =
  | { kind: 'loading' }
  | { kind: 'error'; error: ShownError }
  | { kind: 'unknownSeason'; asked: string }
  | { kind: 'noSeasons' }
  | { kind: 'noTeams' }
  | { kind: 'teams'; rows: HomeRow[] }

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

// «Dar de alta un equipo» lleva al formulario con la temporada que se está viendo, en el estado de la navegación y
// no en la dirección (plan R2, decisión 5): `/equipos/nuevo` es siempre el mismo camino.
const newTeam = computed(() => ({
  path: '/equipos/nuevo',
  state: chosen.value ? { seasonLabel: chosen.value.season.label } : {},
}))

// El selector cambia la dirección, así que «Atrás» vuelve a la anterior y el enlace se puede compartir. El orden
// de la tabla se conserva.
function pickSeason(label: string) {
  router.push({ query: { ...route.query, temporada: toAddress(label) } })
}

// El orden de la tabla va en la dirección, como la temporada (bloque T del plan R2): `?orden=ingesta`. Sin él, el
// del servidor. Cambiarlo no vuelve a pedir nada: las filas ya están, solo se colocan de otra manera.
const order = computed(() => orderFromAddress(route.query.orden, columns))
const sortedRows = computed(() => {
  if (state.value.kind !== 'teams') return []
  const current = order.value
  return current ? sortRows(state.value.rows, rules[current.column], current.reversed) : state.value.rows
})

function sortBy(column: string) {
  const next = nextOrder(order.value, column as Column)
  // Vuelto al orden de siempre, `orden` queda sin valor y Vue Router lo quita de la dirección.
  router.push({ query: { ...route.query, orden: orderToAddress(next) } })
}
</script>

<template>
  <div class="heading">
    <h1>Equipos</h1>
    <div
      v-if="seasons && seasons.length > 0"
      class="tools"
    >
      <SeasonPicker
        :labels="pickerLabels"
        :model-value="chosen?.season.label ?? ''"
        @update:model-value="pickSeason"
      />
      <!-- Con texto, no solo un «+» (LLD-B §10.1). Va a otra pantalla: es un enlace con aspecto de botón. -->
      <Button
        as="router-link"
        :to="newTeam"
        label="Dar de alta un equipo"
      />
    </div>
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
  <!-- La portada vacía tiene salida (plan R2, §3.1): el mismo botón, debajo del mensaje. -->
  <div
    v-else-if="state.kind === 'noSeasons'"
    class="empty"
  >
    <p>Todavía no hay ninguna temporada.</p>
    <p>Para empezar, da de alta el primer equipo. La temporada se crea desde el mismo formulario.</p>
    <Button
      as="router-link"
      :to="newTeam"
      label="Dar de alta un equipo"
    />
  </div>
  <div
    v-else-if="state.kind === 'noTeams'"
    class="empty"
  >
    <p>No hay equipos en la temporada {{ chosen?.season.label }}.</p>
    <Button
      as="router-link"
      :to="newTeam"
      label="Dar de alta un equipo"
    />
  </div>
  <TeamsTable
    v-else
    :rows="sortedRows"
    :caption="`Equipos de la temporada ${chosen?.season.label}`"
    :order="order"
    @sort="sortBy"
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
.tools {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 1rem;
}
.empty {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
}
.empty p:first-child {
  margin-bottom: 0;
}
.note {
  margin-top: 0;
  color: var(--p-text-muted-color);
}
</style>
