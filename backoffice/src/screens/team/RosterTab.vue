<!-- La pestaña Plantilla de la ficha del equipo (plan R6, §3 y decisión 7): los jugadores del equipo en la temporada,
     uno por fila, con su foto o sus iniciales, su dorsal, su nombre, su demarcación y su año. Los pide ella, al
     abrirse: la pestaña Resultados no los necesita. Si fallan, el error va aquí y la cabecera se queda.
     Dar de alta y corregir (✎ en cada fila), en un diálogo encima (`PlayerDialog`, R6.12), y dar de baja (🗑), con su
     confirmación (`RemovePlayerDialog`). El nombre lleva a su ficha (R6.13). «Sincronizar con la Federación» (R6.16,
     D-120), con la fecha de la última vez, solo en la temporada en curso; al acabar, su resumen o su error en una
     caja encima de la tabla, que se queda hasta cerrarla (decisiones 1 y 4 de R6.16). Cada fila dice si está
     «Federado» o «No federado». Una temporada pasada o archivada se ve,
     pero no se cambia: sin botones (R6.3; decisión 4 de R6.14). -->
<script setup lang="ts">
import Button from 'primevue/button'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import type { components } from '../../api/schema'
import IconAction from '../../components/IconAction.vue'
import LoadError from '../../components/LoadError.vue'
import PlayerPhoto from '../../components/PlayerPhoto.vue'
import ScrollBox from '../../components/ScrollBox.vue'
import { club } from '../../club'
import { announce } from '../../notice'
import { canChange, type Season, todayHere } from '../home/seasons'
import PlayerDialog from './PlayerDialog.vue'
import RemovePlayerDialog from './RemovePlayerDialog.vue'
import { playerPath } from './header'
import { rosterRows } from './roster'
import { canSyncRoster, lastSyncText, summaryLines } from './rosterSync'

type Player = components['schemas']['PlayerResponse']

const props = defineProps<{
  teamId: string
  // El nombre del equipo, «Cadete A», para el título de la tabla.
  teamTitle: string
  season: Season
  // De la inscripción (R6.16): la última sincronización de la plantilla, y si el equipo está enganchado.
  rosterSyncedAt: string | null
  linked: boolean
}>()
const emit = defineEmits<{ synced: [at: string] }>()

type Players = { kind: 'loading' } | { kind: 'error'; error: ShownError } | { kind: 'list'; players: Player[] }

const players = ref<Players>({ kind: 'loading' })
const rows = computed(() => (players.value.kind === 'list' ? rosterRows(players.value.players) : []))
const caption = computed(() => `Plantilla de ${props.teamTitle} en la temporada ${props.season.label}`)
const listed = computed(() => (players.value.kind === 'list' ? players.value.players : []))
// Ni en una temporada pasada ni en una archivada (decisión 4 de R6.14).
const editable = computed(() => canChange(props.season, todayHere()))
// El diálogo abierto: el alta, corregir a un jugador, o su baja.
const dialog = ref<{ kind: 'add' } | { kind: 'edit'; player: Player } | { kind: 'remove'; id: string; name: string }>()
const playerOf = (id: string) => listed.value.find((player) => player.id === id)

// Cada petición cancela la anterior, y salir cancela la que quede (LLD-B §3.2).
let pending: AbortController | undefined

// Sincronizar con la Federación (R6.16). Mientras, el botón dice «Sincronizando…»; al acabar, el resumen o el error.
const syncable = computed(() =>
  canSyncRoster({
    season: props.season,
    today: todayHere(),
    providesRoster: club.value?.federationProvidesTeamRoster ?? false,
    linked: props.linked,
  }),
)
const lastSync = computed(() => lastSyncText(props.rosterSyncedAt))
const syncing = ref(false)
const outcome = ref<{ kind: 'summary'; lines: string[] } | { kind: 'error'; error: ShownError }>()
let syncPending: AbortController | undefined

async function sync() {
  syncPending?.abort()
  const leaving = new AbortController()
  syncPending = leaving
  syncing.value = true
  outcome.value = undefined
  try {
    const synced = await asResult(
      api.POST('/teams/{teamId}/registrations/{seasonId}/roster-sync', {
        params: { path: { teamId: props.teamId, seasonId: props.season.id } },
        signal: leaving.signal,
      }),
    )
    if (synced.ok) {
      outcome.value = { kind: 'summary', lines: summaryLines(synced.data) }
      emit('synced', synced.data.syncedAt)
      load(true)
    } else {
      outcome.value = { kind: 'error', error: synced.error }
    }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  } finally {
    if (syncPending === leaving) syncing.value = false
  }
}

// `quiet`, tras un alta: la tabla se queda mientras llega la nueva, sin «Cargando…».
async function load(quiet = false) {
  pending?.abort()
  const leaving = new AbortController()
  pending = leaving
  if (!quiet) players.value = { kind: 'loading' }
  try {
    const listed = await asResult(
      api.GET('/players', { params: { query: { teamId: props.teamId, seasonId: props.season.id } }, signal: leaving.signal }),
    )
    if (listed.ok) players.value = { kind: 'list', players: listed.data }
    else if (!quiet) players.value = { kind: 'error', error: listed.error }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

// Al abrir, y si cambia el equipo o la temporada: el resumen de otra plantilla no vale aquí.
watch(
  [() => props.teamId, () => props.season.id],
  () => {
    syncPending?.abort()
    syncing.value = false
    outcome.value = undefined
    load()
  },
  { immediate: true },
)

// Tras guardar: la plantilla otra vez y el aviso, que se ve también con el diálogo cerrado (LLD-B §5.4).
function saved(notice: string, again: boolean) {
  if (!again) {
    dialog.value = undefined
    announce(notice)
  }
  load(true)
}

// Tras la baja: la plantilla sin él, y el aviso.
function removed() {
  dialog.value = undefined
  announce('Dado de baja')
  load(true)
}
onBeforeUnmount(() => {
  pending?.abort()
  syncPending?.abort()
})
</script>

<template>
  <!-- Lo de la pestaña, como una zona con su nombre: el lector puede saltar a ella. -->
  <section aria-label="Plantilla">
    <!-- El resumen de la sincronización, en una zona que está siempre en la página, para que el lector la lea al
         llenarse sin mover el foco (LLD-B §10.3); el error, una alerta, que se lee al aparecer. Se quedan hasta
         cerrarlos o sincronizar otra vez. -->
    <div role="status">
      <div
        v-if="outcome?.kind === 'summary'"
        class="outcome summary"
      >
        <p class="outcome-title">
          Sincronizada con la Federación
        </p>
        <p
          v-for="line in outcome.lines"
          :key="line"
        >
          {{ line }}
        </p>
        <IconAction
          class="close"
          label="Cerrar el resumen"
          icon="x"
          @press="outcome = undefined"
        />
      </div>
    </div>
    <div
      v-if="outcome?.kind === 'error'"
      role="alert"
      class="outcome error"
    >
      <p class="outcome-title">
        {{ outcome.error.message }}
      </p>
      <p
        v-if="outcome.error.code"
        class="code"
      >
        Código: {{ outcome.error.code }}
      </p>
      <IconAction
        class="close"
        label="Cerrar el aviso"
        icon="x"
        @press="outcome = undefined"
      />
    </div>
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
      @retry="load()"
    />
    <template v-else>
      <div
        v-if="editable || syncable"
        class="actions"
      >
        <p
          v-if="syncable"
          class="last-sync"
        >
          {{ lastSync }}
        </p>
        <Button
          v-if="syncable"
          :label="syncing ? 'Sincronizando…' : 'Sincronizar con la Federación'"
          :disabled="syncing"
          severity="secondary"
          @click="sync"
        />
        <Button
          v-if="editable"
          label="Dar de alta un jugador"
          @click="dialog = { kind: 'add' }"
        />
      </div>
      <p
        v-if="rows.length === 0"
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
              <th
                v-if="editable"
                scope="col"
              >
                <span class="visually-hidden">Acciones</span>
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
                <RouterLink :to="playerPath(season.label, row.id)">
                  {{ row.name }}
                </RouterLink>
                <span
                  v-if="row.federation"
                  class="federation"
                >{{ row.federation }}</span>
              </td>
              <td>{{ row.position }}</td>
              <td class="number">
                {{ row.birthYear }}
              </td>
              <!-- Las acciones de la fila, iconos con su texto (DW-19): sin ellas en una temporada archivada. -->
              <td
                v-if="editable"
                class="row-actions"
              >
                <IconAction
                  label="Corregir"
                  :subject="row.name"
                  icon="pencil"
                  @press="dialog = { kind: 'edit', player: playerOf(row.id)! }"
                />
                <IconAction
                  label="Dar de baja"
                  :subject="row.name"
                  icon="trash-2"
                  @press="dialog = { kind: 'remove', id: row.id, name: row.name }"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </ScrollBox>
    </template>
    <RemovePlayerDialog
      v-if="dialog?.kind === 'remove'"
      :player-id="dialog.id"
      :player-name="dialog.name"
      :team-title="teamTitle"
      @close="dialog = undefined"
      @removed="removed"
    />
    <PlayerDialog
      v-else-if="dialog"
      :key="dialog.kind === 'edit' ? dialog.player.id : 'alta'"
      :team-id="teamId"
      :team-title="teamTitle"
      :season="season"
      :players="listed"
      :player="dialog.kind === 'edit' ? dialog.player : undefined"
      @close="dialog = undefined"
      @saved="saved"
    />
  </section>
</template>

<style scoped>
.empty {
  margin: 0 0 0.375rem;
}
.actions {
  margin: 0 0 0.75rem;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 0.5rem;
}
.last-sync {
  margin: 0 auto 0 0;
  color: var(--p-text-muted-color);
  font-size: 0.875rem;
}
/* La caja del resumen o del error, como la de un error al cargar (LoadError): el borde de la izquierda, del color de
   lo que dice. */
.outcome {
  position: relative;
  margin: 0 0 0.75rem;
  padding: 0.75rem 3rem 0.75rem 1rem;
  border: 1px solid var(--p-content-border-color);
  background: var(--p-content-background);
}
.outcome p {
  margin: 0.25rem 0 0;
}
.outcome .outcome-title {
  margin-top: 0;
  font-weight: 600;
}
.summary {
  border-left: 4px solid var(--p-estado-bien);
}
.error {
  border-left: 4px solid var(--p-estado-fallo);
}
.code {
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
.close {
  position: absolute;
  top: 0.25rem;
  right: 0.25rem;
}
/* Junto al nombre, en texto normal y más pequeño: un dato de la fila, no parte del nombre. */
.federation {
  margin-left: 0.5rem;
  padding: 0.0625rem 0.375rem;
  border: 1px solid var(--p-content-border-color);
  border-radius: 0.25rem;
  font-size: 0.8125rem;
  font-weight: 400;
  white-space: nowrap;
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
/* El icono, de 40 px, ocupa casi toda la altura de la fila. */
.row-actions {
  width: 1px;
  padding: 0.125rem 0.375rem;
  white-space: nowrap;
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
