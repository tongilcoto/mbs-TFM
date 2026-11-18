<!-- El diálogo de un jugador, encima de la plantilla (plan R6, decisiones 7 a 10): el alta y la corrección, con los
     mismos campos en dos bloques, lo del jugador en todas sus temporadas (su perfil, D-119) y lo de esta plantilla.

     El alta: los cinco campos a la vista desde el principio (decisión 2 de R6.12). El del nombre es también el
     buscador: ofrece a los jugadores del club que ya existen y, al final, dar de alta lo escrito como jugador nuevo.
     Elegir uno que existe trae su nombre y su año, bloqueados, y de su perfil el último dorsal, la última demarcación
     y la última foto (D-122), que se pueden cambiar. Sin elegir a nadie, es un jugador nuevo: pide nombre y año.

     Corregir (`player`): el nombre se corrige; el año, solo si está vacío, con una confirmación al guardar; y los dos
     a la vez, no, para que un perfil no pase a ser otra persona (decisión 1 de R6.12).

     Guardar son hasta dos peticiones tras un solo clic: el jugador, y después la foto (D-35). Si la foto falla, el
     jugador queda guardado sin ella, y el aviso lo dice. -->
<script setup lang="ts">
import AutoComplete, { type AutoCompleteOptionSelectEvent } from 'primevue/autocomplete'
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { api } from '../../api/client'
import { placeSaveError, type ShownError } from '../../api/errors'
import { asResult, type Result } from '../../api/result'
import type { components } from '../../api/schema'
import FormErrorList, { type FormError } from '../../components/FormErrorList.vue'
import FormField from '../../components/FormField.vue'
import LoadError from '../../components/LoadError.vue'
import PhotoPicker from '../../components/PhotoPicker.vue'
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
  // «Cadete A», para el título y el bloque de esta plantilla.
  teamTitle: string
  season: Season
  // La plantilla que se ve detrás: de ahí sale quién tiene un dorsal cogido (decisión 5).
  players: Player[]
  // El jugador que se corrige; sin él, es un alta.
  player?: Player
}>()
const emit = defineEmits<{
  close: []
  // Se ha guardado: la plantilla se vuelve a pedir. `notice`, lo que dice el aviso; `again`, si el diálogo sigue
  // abierto para dar de alta a otro.
  saved: [notice: string, again: boolean]
}>()

// Quién: uno nuevo (lo escrito en el buscador), uno del club elegido en él, o, al corregir, el de la fila.
type Choice = { kind: 'new' } | { kind: 'profile'; profile: Profile } | { kind: 'edit'; player: Player }
// La foto: la que ya tenía (la de la fila, o la del perfil en el alta), una elegida en el ordenador, o ninguna.
type Photo = { kind: 'current'; url: string } | { kind: 'file'; file: File; preview: string } | { kind: 'none' }

const choice = ref<Choice>({ kind: 'new' })
const query = ref<string | ProfileOption>('')
const suggestions = ref<ProfileOption[]>([])
const name = ref('')
const year = ref('')
const shirt = ref('')
const position = ref<Position | null>(null)
const photo = ref<Photo>({ kind: 'none' })
const errors = ref<Partial<Record<'name' | 'year' | 'shirt', string>>>({})
const banner = ref<ShownError>()
const savedNow = ref<string>()
const saving = ref(false)
const confirmingYear = ref(false)
const errorList = ref<InstanceType<typeof FormErrorList>>()

const editing = computed(() => props.player !== undefined)
const title = computed(() =>
  props.player ? `Corregir a ${shownName(props.player.fullName)}` : `Dar de alta un jugador en ${props.teamTitle}, ${props.season.label}`,
)
const rosterBlock = computed(() => `En ${props.teamTitle}, ${props.season.label}`)
const positionOptions = optionsOf('PlayerPosition')
const photoShown = computed(() => {
  const current = photo.value
  if (current.kind === 'file') return current.preview
  return current.kind === 'current' ? current.url : undefined
})
// El nombre y el año que se ven bloqueados: los del perfil elegido en el alta.
const lockedName = computed(() => (choice.value.kind === 'profile' ? shownName(choice.value.profile.fullName) : undefined))
const lockedYear = computed(() => {
  const chosen = choice.value
  const known = chosen.kind === 'profile' ? chosen.profile.birthYear : chosen.kind === 'edit' ? chosen.player.birthYear : null
  if (chosen.kind === 'profile') return known == null ? 'Sin año' : String(known)
  return known == null ? undefined : String(known)
})
// El nombre que se está dando de alta o corrigiendo: el elegido, o lo escrito (en el buscador, en el alta).
const typedName = computed(() => (editing.value ? name.value : typedText()))
const shownChosenName = computed(() => lockedName.value ?? typedName.value)

const labels = { name: 'Nombre y apellidos', year: 'Año de nacimiento', shirt: 'Dorsal' }
const ids = { name: 'player-name', year: 'player-year', shirt: 'player-shirt' }
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

// Al abrirse (la pestaña lo monta al pulsar el botón): al corregir, con los datos del jugador. El foco, en el nombre
// (en el alta, el buscador), al montarse y otra vez al acabar de aparecer: la ventana lo lleva a la ✕ al terminar
// de mostrarse, y lo pone la web, como en LeaveDialog.
onMounted(async () => {
  const player = props.player
  if (player) {
    choice.value = { kind: 'edit', player }
    name.value = shownName(player.fullName)
    shirt.value = player.shirtNumber == null ? '' : String(player.shirtNumber)
    position.value = (player.position ?? null) as Position | null
    photo.value = player.photoUrl ? { kind: 'current', url: player.photoUrl } : { kind: 'none' }
  }
  await focusName()
})

function reset() {
  search.stop()
  dropPreview()
  choice.value = { kind: 'new' }
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

async function focusName() {
  await nextTick()
  document.getElementById(ids.name)?.focus()
}

function choose(event: AutoCompleteOptionSelectEvent) {
  const option = event.value as ProfileOption
  search.stop()
  errors.value = {}
  // «Como jugador nuevo» solo cierra la lista: lo escrito se queda, y se sigue por el año.
  // La lista pone en el campo la opción entera; después, lo escrito.
  if (option.kind === 'new') {
    choice.value = { kind: 'new' }
    void nextTick(() => (query.value = option.name))
    // El foco, al año cuando la lista se cierre: al cerrarse, la lista lo devuelve al buscador (R6.18).
    focusYearOnHide = true
    return
  }
  // Lo que el perfil guarda como ayuda (D-122): se puede cambiar.
  const profile = option.profile
  choice.value = { kind: 'profile', profile }
  shirt.value = profile.lastShirtNumber == null ? '' : String(profile.lastShirtNumber)
  position.value = (profile.lastPosition ?? null) as Position | null
  photo.value = profile.lastPhotoUrl ? { kind: 'current', url: profile.lastPhotoUrl } : { kind: 'none' }
}

// Tras «como jugador nuevo», el año. Al cerrarse, la lista devuelve el foco al buscador justo después de avisar
// (`before-hide`): el año, en cuanto acaba.
let focusYearOnHide = false
function listHiding() {
  if (!focusYearOnHide) return
  focusYearOnHide = false
  void nextTick(() => document.getElementById(ids.year)?.focus())
}

// Deshacer la elección: otra vez un jugador nuevo, con todo vacío.
async function chooseAgain() {
  reset()
  await focusName()
}

function pickPhoto(file: File) {
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

// Al corregir: si el nombre es otro (comparado como lo guarda el servidor), y si se pone el año que faltaba.
function nameChanged(player: Player): boolean {
  return cleanName(name.value).toLocaleUpperCase('es-ES') !== player.fullName
}
function yearAdded(player: Player): boolean {
  return player.birthYear == null && year.value.trim() !== ''
}

// Lo que la web mira antes de enviar (decisión 9).
function check(): boolean {
  const chosen = choice.value
  const found: typeof errors.value = {}
  if (chosen.kind !== 'profile') found.name = nameProblem(typedName.value)
  if (chosen.kind === 'new') found.year = yearProblem(year.value, new Date().getFullYear())
  if (chosen.kind === 'edit' && yearAdded(chosen.player)) found.year = yearProblem(year.value, new Date().getFullYear())
  found.shirt = shirtProblem(shirt.value)
  errors.value = Object.fromEntries(Object.entries(found).filter(([, message]) => message !== undefined))
  return listedErrors.value.length === 0
}

// Quién tiene ya un dorsal en esta plantilla, para decirlo junto al campo (decisión 5). Al corregir, él no cuenta.
function shirtTakenMessage(): string {
  const number = shirtNumberOf(shirt.value)
  const holder = props.players.find((player) => player.shirtNumber === number && player.id !== props.player?.id)
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
  if (chosen.kind === 'edit') {
    // Los dos a la vez, no: sería otra persona en el mismo perfil.
    if (nameChanged(chosen.player) && yearAdded(chosen.player)) {
      banner.value = {
        message:
          'No se pueden cambiar a la vez el nombre y el año. Si es otra persona, da de baja a este jugador y da de alta al otro como nuevo.',
        retry: false,
      }
      return
    }
    // Poner el año que faltaba no tiene vuelta atrás: se pregunta antes.
    if (yearAdded(chosen.player) && !confirmingYear.value) {
      confirmingYear.value = true
      return
    }
  }
  confirmingYear.value = false
  await send(again)
}

async function send(again: boolean) {
  const chosen = choice.value
  saving.value = true
  try {
    const common = { shirtNumber: shirtNumberOf(shirt.value), position: position.value }
    let saved: Result<Player>
    if (chosen.kind === 'edit') {
      const birthYear = chosen.player.birthYear ?? (year.value.trim() === '' ? null : Number(year.value.trim()))
      saved = await asResult(
        api.PUT('/players/{playerId}', {
          params: { path: { playerId: chosen.player.id } },
          body: { ...common, fullName: cleanName(name.value), birthYear },
        }),
      )
    } else {
      const placed = { ...common, teamId: props.teamId, seasonId: props.season.id }
      const body =
        chosen.kind === 'profile'
          ? { ...placed, profileId: chosen.profile.profileId }
          : { ...placed, fullName: cleanName(typedName.value), birthYear: Number(year.value.trim()) }
      saved = await asResult(api.POST('/players', { body }))
    }
    if (!saved.ok) {
      await showSaveError(saved.error)
      return
    }

    const problem = await savePhoto(saved.data.id, chosen)
    const notice = problem ? `Guardado, sin la foto: ${problem}.` : 'Guardado'
    emit('saved', notice, again)
    if (again) {
      const who = shownName(saved.data.fullName)
      reset()
      savedNow.value = problem ? `${who}: guardado, sin la foto: ${problem}.` : `${who}: guardado.`
      await focusName()
    }
  } finally {
    saving.value = false
  }
}

// La foto, aparte. Una elegida, se sube. Quitada, se quita si la fila tenía: al corregir, la suya; en el alta con
// un perfil, la del perfil, con la que empieza la fila. Lo que devuelve es el motivo si no se ha podido.
async function savePhoto(playerId: string, chosen: Choice): Promise<string | undefined> {
  const current = photo.value
  if (current.kind === 'file') {
    const uploaded = await uploadPhoto(playerId, current.file)
    return uploaded.ok ? undefined : photoProblem(uploaded.error)
  }
  const had =
    (chosen.kind === 'edit' && chosen.player.photoUrl != null) || (chosen.kind === 'profile' && chosen.profile.lastPhotoUrl != null)
  if (current.kind === 'none' && had) {
    const removed = await removePhoto(playerId)
    return removed.ok ? undefined : photoProblem(removed.error)
  }
  return undefined
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
    @show="focusName"
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

      <fieldset>
        <legend>Del jugador, en todas sus temporadas</legend>
        <!-- En el alta, el nombre es también el buscador; elegido uno del club, su nombre, bloqueado. -->
        <FormField
          :id="ids.name"
          :label="labels.name"
          :required="lockedName === undefined"
          :help="!editing && choice.kind === 'new' ? 'Desde 3 letras, busca entre los jugadores del club' : undefined"
          :error="errors.name"
        >
          <template #default="{ describedBy, invalid }">
            <InputText
              v-if="lockedName !== undefined"
              :id="ids.name"
              :model-value="lockedName"
              disabled
              fluid
            />
            <InputText
              v-else-if="editing"
              :id="ids.name"
              v-model="name"
              :invalid="invalid"
              :aria-describedby="describedBy"
              autocomplete="off"
              fluid
            />
            <AutoComplete
              v-else
              v-model="query"
              :input-id="ids.name"
              :suggestions="suggestions"
              option-label="label"
              option-disabled="disabled"
              :delay="0"
              :min-length="1"
              :invalid="invalid"
              :pt="{ pcInputText: { root: { 'aria-describedby': describedBy } } }"
              fluid
              :show-empty-message="false"
              @complete="search.type($event.query)"
              @option-select="choose"
              @before-hide="listHiding"
            >
              <template #option="{ option }">
                <span class="option">
                  <span :class="option.kind === 'new' ? 'detail' : 'name'">{{ option.kind === 'new' ? option.detail : option.name }}</span>
                  <!-- Un espacio entre el nombre y el detalle: sin él, el texto que se ve («…Fuente2010») no es el que
                       lee el lector («…Fuente, 2010»), y axe lo cuenta como fallo (R6.18). En una columna no se ve. -->
                  {{ ' ' }}
                  <span
                    v-if="option.kind === 'profile'"
                    class="detail"
                  >{{ option.detail }}</span>
                </span>
              </template>
            </AutoComplete>
          </template>
        </FormField>
        <FormField
          :id="ids.year"
          :label="labels.year"
          :required="choice.kind === 'new'"
          :help="choice.kind === 'edit' && lockedYear === undefined ? 'Una vez puesto, no se puede cambiar' : undefined"
          :error="errors.year"
        >
          <template #default="{ describedBy, invalid }">
            <InputText
              v-if="lockedYear !== undefined"
              :id="ids.year"
              :model-value="lockedYear"
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
        <p v-if="choice.kind === 'profile'">
          <Button
            type="button"
            label="Elegir otro jugador"
            link
            @click="chooseAgain"
          />
        </p>
      </fieldset>

      <fieldset>
        <legend>{{ rosterBlock }}</legend>
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
              <PhotoPicker
                input-id="player-photo"
                :label="photoShown ? 'Cambiar foto' : 'Elegir foto'"
                :accept="PHOTO_TYPES"
                :described-by="describedBy"
                @pick="pickPhoto"
              />
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
      </fieldset>
    </form>

    <template #footer>
      <Button
        label="Guardar"
        :loading="saving"
        @click="save(false)"
      />
      <Button
        v-if="!editing"
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

  <!-- Poner el año que faltaba: no se podrá cambiar después (decisión 1 de R6.12). -->
  <Dialog
    :visible="confirmingYear"
    modal
    header="Poner el año de nacimiento"
    :closable="false"
    :style="{ width: '28rem' }"
    @update:visible="confirmingYear = false"
  >
    <p>El año no se podrá cambiar después.</p>
    <p>Si te equivocas, tendrás que dar de baja al jugador y darlo de alta como nuevo.</p>
    <template #footer>
      <Button
        label="Guardar el año"
        :loading="saving"
        @click="save(false)"
      />
      <Button
        label="Volver"
        severity="secondary"
        @click="confirmingYear = false"
      />
    </template>
  </Dialog>
</template>

<style scoped>
.player-form {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}
.player-form p {
  margin: 0;
}
fieldset {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  margin: 0;
  padding: 0.5rem 0.875rem 0.75rem;
  border: 1px solid var(--p-content-border-color);
  border-radius: var(--p-content-border-radius);
}
legend {
  padding: 0 0.375rem;
  font-weight: 700;
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
  /* Con el color del texto: el suave no llega al contraste sobre la opción resaltada (R6.18). Se distingue del nombre,
     que va en negrita, por el tamaño. */
  font-size: 0.875rem;
}
.photo-field {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  align-items: center;
}
</style>
