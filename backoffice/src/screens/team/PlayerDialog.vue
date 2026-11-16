<!-- El diálogo del alta de un jugador, encima de la plantilla (plan R6, decisiones 7 a 10). Primero se elige quién:
     el buscador ofrece a los jugadores del club que ya existen (su perfil, D-119) y, al final, dar de alta lo escrito
     como jugador nuevo. Elegir uno que existe trae su nombre y su año, bloqueados, y de su perfil el último dorsal,
     la última demarcación y la última foto (D-122), que se pueden cambiar. Un jugador nuevo pide nombre y año.
     Guardar son hasta dos peticiones tras un solo clic: el alta, y después la foto (D-35). Si la foto falla, el
     jugador queda dado de alta sin ella, y el aviso lo dice. -->
<script setup lang="ts">
import AutoComplete, { type AutoCompleteOptionSelectEvent } from 'primevue/autocomplete'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { api } from '../../api/client'
import { placeSaveError, type ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import type { components } from '../../api/schema'
import FormErrorList, { type FormError } from '../../components/FormErrorList.vue'
import FormField from '../../components/FormField.vue'
import LoadError from '../../components/LoadError.vue'
import PlayerPhoto from '../../components/PlayerPhoto.vue'
import { initialsOf, shownName } from '../../components/playerName'
import { optionsOf } from '../../theme/names'
import type { Season } from '../home/seasons'
import { PHOTO_TYPES, photoProblem, removePhoto, uploadPhoto } from './photoUpload'
import { cleanName, nameProblem, shirtNumberOf, shirtProblem, yearProblem } from './playerForm'
import { latestSearch, type ProfileOption, profileOptions } from './profileSearch'

type Player = components['schemas']['PlayerResponse']
type Profile = components['schemas']['PlayerProfileSearchResult']
type Position = components['schemas']['PlayerPosition']

const props = defineProps<{
  teamId: string
  // «Cadete A», para el título.
  teamTitle: string
  season: Season
  // La plantilla que se ve detrás: de ahí sale quién tiene un dorsal cogido (decisión 5).
  players: Player[]
}>()
const emit = defineEmits<{
  close: []
  // Se ha dado de alta a alguien: la plantilla se vuelve a pedir. `notice`, lo que dice el aviso; `again`, si el
  // diálogo sigue abierto para dar de alta a otro.
  saved: [notice: string, again: boolean]
}>()

// Quién se da de alta: todavía nadie, uno del club o uno nuevo.
type Choice = { kind: 'none' } | { kind: 'profile'; profile: Profile } | { kind: 'new' }
// La foto: la que trae el perfil (o ninguna), una elegida en el ordenador, o quitada.
type Photo = { kind: 'profile'; url?: string } | { kind: 'file'; file: File; preview: string } | { kind: 'none' }

const choice = ref<Choice>({ kind: 'none' })
const query = ref<string | ProfileOption>('')
const suggestions = ref<ProfileOption[]>([])
const name = ref('')
const year = ref('')
const shirt = ref('')
const position = ref<Position | null>(null)
const photo = ref<Photo>({ kind: 'none' })
const errors = ref<Partial<Record<'query' | 'name' | 'year' | 'shirt', string>>>({})
const banner = ref<ShownError>()
const savedNow = ref<string>()
const saving = ref(false)
const errorList = ref<InstanceType<typeof FormErrorList>>()

const title = computed(() => `Dar de alta un jugador en ${props.teamTitle}, ${props.season.label}`)
const positionOptions = optionsOf('PlayerPosition')
const photoShown = computed(() => {
  const current = photo.value
  if (current.kind === 'file') return current.preview
  return current.kind === 'profile' ? current.url : undefined
})
const shownChosenName = computed(() => (choice.value.kind === 'profile' ? shownName(choice.value.profile.fullName) : name.value))

const labels = { query: 'Nombre y apellidos', name: 'Nombre y apellidos', year: 'Año de nacimiento', shirt: 'Dorsal' }
const ids = { query: 'player-search', name: 'player-name', year: 'player-year', shirt: 'player-shirt' }
const listedErrors = computed<FormError[]>(() =>
  (Object.keys(errors.value) as (keyof typeof labels)[])
    .filter((field) => errors.value[field] !== undefined)
    .map((field) => ({ fieldId: ids[field], label: labels[field], message: errors.value[field]! })),
)

// El buscador se queda con la respuesta de lo último escrito (R6.7).
const search = latestSearch<Profile>(
  (text, signal) =>
    asResult(api.GET('/player-profiles', { params: { query: { q: text, teamId: props.teamId, seasonId: props.season.id } }, signal })),
  (found) => {
    // Una lista nueva cada vez, también vacía: así el campo deja de decir que está buscando.
    suggestions.value = found === undefined ? [] : profileOptions(found, typedText())
  },
)
onBeforeUnmount(() => {
  search.stop()
  dropPreview()
})

function typedText(): string {
  return typeof query.value === 'string' ? query.value : query.value.name
}

// Al abrirse (la pestaña lo monta al pulsar el botón), el foco en el buscador.
onMounted(focusSearch)

function reset() {
  search.stop()
  dropPreview()
  choice.value = { kind: 'none' }
  query.value = ''
  suggestions.value = []
  name.value = ''
  year.value = ''
  shirt.value = ''
  position.value = null
  photo.value = { kind: 'none' }
  errors.value = {}
  banner.value = undefined
}

async function focusSearch() {
  await nextTick()
  document.getElementById(ids.query)?.focus()
}

function choose(event: AutoCompleteOptionSelectEvent) {
  const option = event.value as ProfileOption
  search.stop()
  errors.value = {}
  if (option.kind === 'new') {
    choice.value = { kind: 'new' }
    name.value = option.name
    photo.value = { kind: 'none' }
    shirt.value = ''
    position.value = null
    return
  }
  // Lo que el perfil guarda como ayuda (D-122): se puede cambiar.
  const profile = option.profile
  choice.value = { kind: 'profile', profile }
  shirt.value = profile.lastShirtNumber == null ? '' : String(profile.lastShirtNumber)
  position.value = (profile.lastPosition ?? null) as Position | null
  photo.value = { kind: 'profile', url: profile.lastPhotoUrl ?? undefined }
}

async function chooseAgain() {
  const typed = choice.value.kind === 'new' ? name.value : ''
  reset()
  query.value = typed
  await focusSearch()
}

function pickPhoto(event: Event) {
  const input = event.target as HTMLInputElement
  const file = input.files?.[0]
  input.value = ''
  if (!file) return
  dropPreview()
  photo.value = { kind: 'file', file, preview: URL.createObjectURL(file) }
}

function clearPhoto() {
  dropPreview()
  photo.value = { kind: 'none' }
}

function dropPreview() {
  if (photo.value.kind === 'file') URL.revokeObjectURL(photo.value.preview)
}

// Lo que la web mira antes de enviar (decisión 9). Sin elegir a nadie, el buscador lo dice.
function check(): boolean {
  const found: typeof errors.value = {}
  if (choice.value.kind === 'none') found.query = 'Elige un jugador de la lista, o da de alta uno nuevo'
  if (choice.value.kind === 'new') {
    found.name = nameProblem(name.value)
    found.year = yearProblem(year.value, new Date().getFullYear())
  }
  if (choice.value.kind !== 'none') found.shirt = shirtProblem(shirt.value)
  errors.value = Object.fromEntries(Object.entries(found).filter(([, message]) => message !== undefined))
  return listedErrors.value.length === 0
}

// Quién tiene ya un dorsal en esta plantilla, para decirlo junto al campo (decisión 5).
function shirtTakenMessage(): string {
  const number = shirtNumberOf(shirt.value)
  const holder = props.players.find((player) => player.shirtNumber === number)
  return holder ? `Ese dorsal ya lo tiene ${shownName(holder.fullName)}` : 'Ese dorsal ya está cogido'
}

async function save(again: boolean) {
  banner.value = undefined
  savedNow.value = undefined
  if (!check()) {
    await nextTick()
    errorList.value?.focus()
    return
  }
  const chosen = choice.value
  if (chosen.kind === 'none') return
  saving.value = true
  try {
    const common = { teamId: props.teamId, seasonId: props.season.id, shirtNumber: shirtNumberOf(shirt.value), position: position.value }
    const body =
      chosen.kind === 'profile'
        ? { ...common, profileId: chosen.profile.profileId }
        : { ...common, fullName: cleanName(name.value), birthYear: Number(year.value.trim()) }
    const created = await asResult(api.POST('/players', { body }))
    if (!created.ok) {
      showSaveError(created.error)
      return
    }

    // La foto, aparte. El alta con un perfil ya empieza con la foto del perfil: si se ha quitado, se quita.
    let problem: string | undefined
    const current = photo.value
    if (current.kind === 'file') {
      const uploaded = await uploadPhoto(created.data.id, current.file)
      if (!uploaded.ok) problem = photoProblem(uploaded.error)
    } else if (current.kind === 'none' && chosen.kind === 'profile' && chosen.profile.lastPhotoUrl != null) {
      const removed = await removePhoto(created.data.id)
      if (!removed.ok) problem = photoProblem(removed.error)
    }

    const who = shownName(created.data.fullName)
    const notice = problem ? `Guardado, sin la foto: ${problem}.` : 'Guardado'
    emit('saved', notice, again)
    if (again) {
      reset()
      savedNow.value = problem ? `${who}: guardado, sin la foto: ${problem}.` : `${who}: guardado.`
      await focusSearch()
    }
  } finally {
    saving.value = false
  }
}

// El dorsal cogido, junto al dorsal; lo que el servidor diga de un campo, junto a él; lo demás, arriba.
async function showSaveError(error: ShownError) {
  if (error.code === 'SHIRT_NUMBER_TAKEN') {
    errors.value = { shirt: shirtTakenMessage() }
  } else {
    const placed = placeSaveError(error, ['fullName', 'birthYear', 'shirtNumber'])
    if ('banner' in placed) {
      banner.value = placed.banner
      return
    }
    const field = ({ fullName: 'name', birthYear: 'year', shirtNumber: 'shirt' } as const)[placed.field as 'fullName']
    errors.value = { [field]: placed.reason }
  }
  await nextTick()
  errorList.value?.focus()
}
</script>

<template>
  <Dialog
    visible
    modal
    :header="title"
    :style="{ width: '34rem' }"
    :breakpoints="{ '640px': '95vw' }"
    @update:visible="emit('close')"
  >
    <form
      class="player-form"
      novalidate
      @submit.prevent="save(false)"
    >
      <p
        v-if="savedNow"
        role="status"
        class="saved"
      >
        {{ savedNow }}
      </p>
      <FormErrorList
        v-if="listedErrors.length > 0"
        ref="errorList"
        :errors="listedErrors"
      />
      <LoadError
        v-if="banner"
        :message="banner.message"
        :code="banner.code"
        :retry="false"
      />

      <!-- Quién: el buscador, hasta que se elige. -->
      <FormField
        v-if="choice.kind === 'none'"
        :id="ids.query"
        :label="labels.query"
        :required="true"
        help="Escribe al menos 3 letras para buscar entre los jugadores del club"
        :error="errors.query"
      >
        <template #default="{ describedBy, invalid }">
          <AutoComplete
            v-model="query"
            :input-id="ids.query"
            :suggestions="suggestions"
            option-label="label"
            option-disabled="disabled"
            :delay="0"
            :min-length="1"
            :invalid="invalid"
            :aria-describedby="describedBy"
            fluid
            @complete="search.type($event.query)"
            @option-select="choose"
          >
            <template #option="{ option }">
              <span class="option">
                <span :class="option.kind === 'new' ? 'detail' : 'name'">{{ option.kind === 'new' ? option.detail : option.name }}</span>
                <span
                  v-if="option.kind === 'profile'"
                  class="detail"
                >{{ option.detail }}</span>
              </span>
            </template>
          </AutoComplete>
        </template>
      </FormField>

      <template v-else>
        <!-- Del jugador, en todas sus temporadas (su perfil): bloqueado si ya existía. -->
        <FormField
          :id="ids.name"
          :label="labels.name"
          :required="true"
          :error="errors.name"
        >
          <template #default="{ describedBy, invalid }">
            <InputText
              v-if="choice.kind === 'profile'"
              :id="ids.name"
              :model-value="shownChosenName"
              disabled
              fluid
            />
            <InputText
              v-else
              :id="ids.name"
              v-model="name"
              :invalid="invalid"
              :aria-describedby="describedBy"
              autocomplete="off"
              fluid
            />
          </template>
        </FormField>
        <FormField
          :id="ids.year"
          :label="labels.year"
          :required="choice.kind === 'new'"
          :error="errors.year"
        >
          <template #default="{ describedBy, invalid }">
            <InputText
              v-if="choice.kind === 'profile'"
              :id="ids.year"
              :model-value="choice.profile.birthYear == null ? 'Sin año' : String(choice.profile.birthYear)"
              disabled
            />
            <InputText
              v-else
              :id="ids.year"
              v-model="year"
              :invalid="invalid"
              :aria-describedby="describedBy"
              inputmode="numeric"
              autocomplete="off"
            />
          </template>
        </FormField>
        <p>
          <Button
            type="button"
            label="Elegir otro jugador"
            link
            @click="chooseAgain"
          />
        </p>

        <!-- En esta plantilla: el dorsal, la demarcación y la foto. -->
        <FormField
          :id="ids.shirt"
          :label="labels.shirt"
          :required="false"
          help="Del 1 al 99"
          :error="errors.shirt"
        >
          <template #default="{ describedBy, invalid }">
            <InputText
              :id="ids.shirt"
              v-model="shirt"
              :invalid="invalid"
              :aria-describedby="describedBy"
              inputmode="numeric"
              autocomplete="off"
            />
          </template>
        </FormField>
        <FormField
          id="player-position"
          label="Demarcación"
          :required="false"
        >
          <template #default="{ describedBy }">
            <Select
              v-model="position"
              label-id="player-position"
              :options="positionOptions"
              option-label="label"
              option-value="value"
              placeholder="Sin demarcación"
              show-clear
              :aria-describedby="describedBy"
              aria-labelledby="player-position-label"
            />
          </template>
        </FormField>
        <FormField
          id="player-photo"
          label="Foto"
          :required="false"
          help="JPEG o PNG, hasta 5 MB"
        >
          <template #default="{ describedBy }">
            <div class="photo-field">
              <PlayerPhoto
                :url="photoShown"
                :name="shownChosenName || 'Jugador'"
                :initials="initialsOf(shownChosenName)"
              />
              <input
                id="player-photo"
                type="file"
                :accept="PHOTO_TYPES"
                :aria-describedby="describedBy"
                @change="pickPhoto"
              >
              <Button
                v-if="photoShown"
                type="button"
                label="Quitar foto"
                severity="secondary"
                size="small"
                @click="clearPhoto"
              />
            </div>
          </template>
        </FormField>
      </template>
    </form>

    <template #footer>
      <Button
        label="Guardar"
        :loading="saving"
        @click="save(false)"
      />
      <Button
        label="Guardar y dar de alta otro"
        severity="secondary"
        :disabled="saving"
        @click="save(true)"
      />
      <Button
        label="Cancelar"
        severity="secondary"
        text
        @click="emit('close')"
      />
    </template>
  </Dialog>
</template>

<style scoped>
.player-form {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.player-form p {
  margin: 0;
}
.saved {
  font-weight: 600;
  color: var(--p-estado-bien);
}
.option {
  display: flex;
  flex-direction: column;
}
.name {
  font-weight: 600;
}
.detail {
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
.photo-field {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  align-items: center;
}
</style>
