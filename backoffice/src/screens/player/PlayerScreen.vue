<!-- La ficha de un jugador en una temporada (plan R6, §3 y decisión 6): `/temporadas/:temporada/jugadores/:id`, con
     `:id` su fila de esa temporada. Una página, no un diálogo, con el enlace de vuelta a la plantilla de su equipo.
     Enseña el nombre y el año de su perfil, y el dorsal, la demarcación y la foto de su fila; nunca lo que el perfil
     guarda como ayuda (D-122). Desde aquí: corregir y dar de baja (los mismos diálogos que en la fila), y poner,
     cambiar o quitar la foto, que se guarda en cuanto se elige (decisión 7). Una temporada pasada o archivada se ve,
     pero no se cambia (R6.3; decisión 4 de R6.14). Si la temporada del camino no es la del jugador, «No se ha encontrado el jugador». -->
<script setup lang="ts">
import Button from 'primevue/button'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import type { components } from '../../api/schema'
import LoadError from '../../components/LoadError.vue'
import PhotoPicker from '../../components/PhotoPicker.vue'
import PlayerPhoto from '../../components/PlayerPhoto.vue'
import { initialsOf, shownName } from '../../components/playerName'
import { announce } from '../../notice'
import { namesOf, teamName } from '../../theme/names'
import { canChange, type Season, toAddress, todayHere } from '../home/seasons'
import { isTeamCode } from '../sync-team/link'
import { tabPath } from '../team/header'
import { federationText } from '../team/roster'
import { PHOTO_TYPES, photoProblem, removePhoto, uploadPhoto } from '../team/photoUpload'
import PlayerDialog from '../team/PlayerDialog.vue'
import RemovePlayerDialog from '../team/RemovePlayerDialog.vue'

type Player = components['schemas']['PlayerResponse']
type Team = components['schemas']['TeamResponse']
type PlayerPosition = components['schemas']['PlayerPosition']

type State =
  | { kind: 'loading' }
  | { kind: 'error'; error: ShownError; notFound: boolean }
  | { kind: 'ready'; player: Player; team: Team; season: Season; roster: Player[] }

const playerNotFound: ShownError = { message: 'No se ha encontrado el jugador', code: 'PLAYER_NOT_FOUND', retry: false }
const positionNames = namesOf('PlayerPosition')

const route = useRoute()
const router = useRouter()
const state = ref<State>({ kind: 'loading' })
const dialog = ref<'edit' | 'remove'>()
const photoBusy = ref(false)
const photoFailure = ref<string>()

let pending: AbortController | undefined
onBeforeUnmount(() => pending?.abort())

const ready = computed(() => (state.value.kind === 'ready' ? state.value : undefined))
const name = computed(() => (ready.value ? shownName(ready.value.player.fullName) : 'Jugador'))
const teamTitle = computed(() => (ready.value ? teamName(ready.value.team.category, ready.value.team.letter) : ''))
// Ni en una temporada pasada ni en una archivada (decisión 4 de R6.14).
const editable = computed(() => ready.value !== undefined && canChange(ready.value.season, todayHere()))
const rosterLink = computed(() => (ready.value ? tabPath('plantilla', ready.value.season.label, ready.value.team.id) : '/'))
// Lo de su fila, como en la plantilla: una raya si no hay; el año, de su perfil, o «Sin año».
const facts = computed(() => {
  const player = ready.value?.player
  if (!player) return []
  const federation = federationText(player)
  return [
    { label: 'Dorsal', value: player.shirtNumber == null ? '—' : String(player.shirtNumber) },
    // El generador ensancha la demarcación «o nula» a cualquier texto (R6.6); el catálogo solo admite las cuatro.
    { label: 'Demarcación', value: player.position == null ? '—' : positionNames[player.position as PlayerPosition] },
    { label: 'Año de nacimiento', value: player.birthYear == null ? 'Sin año' : String(player.birthYear) },
    // «Federado» o «No federado», con su fecha; sin el dato si la plantilla nunca se ha sincronizado (R6.16).
    ...(federation === undefined ? [] : [{ label: 'Federación', value: federation }]),
  ]
})

// El jugador y las temporadas a la vez; con ellos, su equipo y su plantilla (la de los dorsales cogidos al corregir).
// `quiet`, tras guardar: lo que se ve se queda mientras llega lo nuevo.
async function load(quiet = false) {
  pending?.abort()
  const leaving = new AbortController()
  pending = leaving
  if (!quiet) state.value = { kind: 'loading' }
  const id = String(route.params.id)
  const asked = String(route.params.temporada)
  if (!isTeamCode(id)) {
    state.value = { kind: 'error', error: playerNotFound, notFound: true }
    return
  }
  try {
    const [found, seasons] = await Promise.all([
      asResult(api.GET('/players/{playerId}', { params: { path: { playerId: id } }, signal: leaving.signal })),
      asResult(api.GET('/seasons', { signal: leaving.signal })),
    ])
    if (!found.ok) {
      state.value = { kind: 'error', error: found.error, notFound: found.error.code === 'PLAYER_NOT_FOUND' }
      return
    }
    if (!seasons.ok) {
      state.value = { kind: 'error', error: seasons.error, notFound: false }
      return
    }
    // La temporada del camino tiene que ser la suya (decisión 6), como una competición de otra temporada.
    const season = seasons.data.find((s) => toAddress(s.label) === asked)
    const player = found.data
    if (!season || season.id !== player.seasonId) {
      state.value = { kind: 'error', error: playerNotFound, notFound: true }
      return
    }
    const [team, roster] = await Promise.all([
      asResult(api.GET('/teams/{teamId}', { params: { path: { teamId: player.teamId } }, signal: leaving.signal })),
      asResult(api.GET('/players', { params: { query: { teamId: player.teamId, seasonId: season.id } }, signal: leaving.signal })),
    ])
    if (!team.ok) {
      state.value = { kind: 'error', error: team.error, notFound: false }
      return
    }
    state.value = { kind: 'ready', player, team: team.data, season, roster: roster.ok ? roster.data : [] }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

watch([() => route.params.id, () => route.params.temporada], () => load(), { immediate: true })

// Corregido: la ficha otra vez, y el aviso.
function saved(notice: string) {
  dialog.value = undefined
  announce(notice)
  load(true)
}

// Dado de baja: de vuelta a la plantilla de su equipo, que ya no lo tiene, con el aviso.
async function removed() {
  const link = rosterLink.value
  dialog.value = undefined
  announce('Dado de baja')
  await router.push(link)
}

// La foto, al elegirla o al quitarla: se guarda ya, y la ficha se vuelve a pedir para traer su enlace.
async function changePhoto(file?: File) {
  if (!ready.value) return
  photoBusy.value = true
  photoFailure.value = undefined
  try {
    const id = ready.value.player.id
    const done = file ? await uploadPhoto(id, file) : await removePhoto(id)
    if (!done.ok) {
      photoFailure.value = `${file ? 'No se ha podido poner la foto' : 'No se ha podido quitar la foto'}: ${photoProblem(done.error)}.`
      return
    }
    announce(file ? 'Foto guardada' : 'Foto quitada')
    await load(true)
  } finally {
    photoBusy.value = false
  }
}
</script>

<template>
  <p
    v-if="ready"
    class="back"
  >
    <RouterLink :to="rosterLink">
      ← Plantilla del {{ teamTitle }}
    </RouterLink>
  </p>
  <h1>{{ name }}</h1>

  <p
    v-if="state.kind === 'loading'"
    role="status"
  >
    Cargando jugador…
  </p>
  <LoadError
    v-else-if="state.kind === 'error'"
    :message="state.error.message"
    :code="state.error.code"
    :retry="state.error.retry"
    @retry="load()"
  >
    <p v-if="state.notFound">
      <RouterLink to="/">
        Ir a la portada
      </RouterLink>
    </p>
  </LoadError>

  <template v-else>
    <p class="subtitle">
      {{ teamTitle }} · {{ state.season.label }}
    </p>

    <div class="sheet">
      <section
        class="photo-box"
        aria-label="Foto"
      >
        <PlayerPhoto
          class="big"
          :url="state.player.photoUrl ?? undefined"
          :name="name"
          :initials="initialsOf(state.player.fullName)"
        />
        <p
          v-if="photoFailure"
          role="alert"
          class="failure"
        >
          {{ photoFailure }}
        </p>
        <div
          v-if="editable"
          class="photo-actions"
        >
          <PhotoPicker
            input-id="sheet-photo"
            name="Foto"
            :label="state.player.photoUrl ? 'Cambiar foto' : 'Poner foto'"
            :accept="PHOTO_TYPES"
            :disabled="photoBusy"
            described-by="sheet-photo-help"
            @pick="changePhoto"
          />
          <Button
            v-if="state.player.photoUrl"
            type="button"
            label="Quitar foto"
            severity="secondary"
            size="small"
            :disabled="photoBusy"
            @click="changePhoto()"
          />
          <small
            id="sheet-photo-help"
            class="help"
          >JPEG o PNG, hasta 5 MB</small>
        </div>
      </section>

      <dl class="facts">
        <template
          v-for="fact in facts"
          :key="fact.label"
        >
          <dt>{{ fact.label }}</dt>
          <dd>{{ fact.value }}</dd>
        </template>
      </dl>
    </div>

    <p
      v-if="editable"
      class="actions"
    >
      <Button
        label="Corregir"
        @click="dialog = 'edit'"
      />
      <Button
        label="Dar de baja"
        severity="danger"
        outlined
        @click="dialog = 'remove'"
      />
    </p>

    <PlayerDialog
      v-if="dialog === 'edit'"
      :team-id="state.team.id"
      :team-title="teamTitle"
      :season="state.season"
      :players="state.roster"
      :player="state.player"
      @close="dialog = undefined"
      @saved="saved"
    />
    <RemovePlayerDialog
      v-if="dialog === 'remove'"
      :player-id="state.player.id"
      :player-name="name"
      :team-title="teamTitle"
      @close="dialog = undefined"
      @removed="removed"
    />
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
.sheet {
  display: flex;
  flex-wrap: wrap;
  gap: 1.5rem;
  align-items: flex-start;
  margin: 1rem 0;
}
.photo-box {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  align-items: flex-start;
}
/* La foto, grande: la de la fila mide 40 px. Con la caja delante, para pasar por encima del tamaño de la pieza. */
.photo-box .big {
  width: 8rem;
  height: 8rem;
  font-size: 2rem;
}
.photo-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
  max-width: 16rem;
}
.help {
  flex-basis: 100%;
  color: var(--p-text-muted-color);
}
.failure {
  margin: 0;
  color: var(--p-estado-fallo);
  font-weight: 600;
}
.facts {
  display: grid;
  grid-template-columns: auto auto;
  gap: 0.5rem 1.5rem;
  margin: 0;
}
.facts dt {
  font-weight: 600;
  color: var(--p-text-muted-color);
}
.facts dd {
  margin: 0;
  font-weight: 700;
}
.actions {
  display: flex;
  gap: 0.5rem;
}
</style>
