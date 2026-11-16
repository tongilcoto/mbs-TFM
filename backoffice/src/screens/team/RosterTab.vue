<!-- La pestaña Plantilla de la ficha del equipo (plan R6, §3 y decisión 7): los jugadores del equipo en la temporada,
     uno por fila, con su foto o sus iniciales, su dorsal, su nombre, su demarcación y su año. Los pide ella, al
     abrirse: la pestaña Resultados no los necesita. Si fallan, el error va aquí y la cabecera se queda.
     Por ahora solo se ve: dar de alta, corregir, dar de baja, la ficha del jugador y sincronizar llegan con el paso
     que los hace funcionar (decisión 1 de R6.11). -->
<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import type { components } from '../../api/schema'
import LoadError from '../../components/LoadError.vue'
import PlayerPhoto from '../../components/PlayerPhoto.vue'
import ScrollBox from '../../components/ScrollBox.vue'
import type { Season } from '../home/seasons'
import { rosterRows } from './roster'

type Player = components['schemas']['PlayerResponse']

const props = defineProps<{
  teamId: string
  // El nombre del equipo, «Cadete A», para el título de la tabla.
  teamTitle: string
  season: Season
}>()

type Players = { kind: 'loading' } | { kind: 'error'; error: ShownError } | { kind: 'list'; players: Player[] }

const players = ref<Players>({ kind: 'loading' })
const rows = computed(() => (players.value.kind === 'list' ? rosterRows(players.value.players) : []))
const caption = computed(() => `Plantilla de ${props.teamTitle} en la temporada ${props.season.label}`)

// Cada petición cancela la anterior, y salir cancela la que quede (LLD-B §3.2).
let pending: AbortController | undefined

async function load() {
  pending?.abort()
  const leaving = new AbortController()
  pending = leaving
  players.value = { kind: 'loading' }
  try {
    const listed = await asResult(
      api.GET('/players', { params: { query: { teamId: props.teamId, seasonId: props.season.id } }, signal: leaving.signal }),
    )
    players.value = listed.ok ? { kind: 'list', players: listed.data } : { kind: 'error', error: listed.error }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

// Al abrir, y si cambia el equipo o la temporada.
watch([() => props.teamId, () => props.season.id], load, { immediate: true })
onBeforeUnmount(() => pending?.abort())
</script>

<template>
  <!-- Lo de la pestaña, como una zona con su nombre: el lector puede saltar a ella. -->
  <section aria-label="Plantilla">
    <p
      v-if="players.kind === 'loading'"
      role="status"
    >
      Cargando jugadores…
    </p>
    <LoadError
      v-else-if="players.kind === 'error'"
      :message="players.error.message"
      :code="players.error.code"
      :retry="players.error.retry"
      @retry="load"
    />
    <p
      v-else-if="rows.length === 0"
      class="empty"
    >
      Este equipo aún no tiene jugadores en {{ season.label }}.
    </p>
    <ScrollBox
      v-else
      :label="caption"
    >
      <table class="roster">
        <caption class="visually-hidden">
          {{ caption }}
        </caption>
        <thead>
          <tr>
            <th scope="col">
              <span class="visually-hidden">Foto</span>
            </th>
            <th
              scope="col"
              class="number"
            >
              Dorsal
            </th>
            <th scope="col">
              Nombre
            </th>
            <th scope="col">
              Demarcación
            </th>
            <th
              scope="col"
              class="number"
            >
              Año de nacimiento
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.id"
          >
            <td class="photo">
              <PlayerPhoto
                :url="row.photoUrl"
                :name="row.name"
                :initials="row.initials"
              />
            </td>
            <td class="number strong">
              {{ row.shirtNumber }}
            </td>
            <td class="name">
              {{ row.name }}
            </td>
            <td>{{ row.position }}</td>
            <td class="number">
              {{ row.birthYear }}
            </td>
          </tr>
        </tbody>
      </table>
    </ScrollBox>
  </section>
</template>

<style scoped>
.empty {
  margin: 0 0 0.375rem;
}
.roster {
  width: 100%;
  border-collapse: collapse;
  background: var(--p-content-background);
  font-size: 0.9375rem;
}
th,
td {
  padding: 0.375rem 0.5rem;
  text-align: left;
  vertical-align: middle;
  border-bottom: 1px solid var(--p-content-border-color);
}
thead th {
  font-size: 0.8125rem;
  color: var(--p-text-muted-color);
  white-space: nowrap;
}
.number {
  width: 1px;
  text-align: right;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.strong,
.name {
  font-weight: 700;
}
/* La foto, de 40 px, ocupa casi toda la altura de la fila. */
.photo {
  width: 1px;
  padding: 0.25rem 0.5rem;
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
