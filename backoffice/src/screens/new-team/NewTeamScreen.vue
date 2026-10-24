<!-- El alta de equipo (plan R2, §3.2). Pide solo la lista de temporadas al abrir: categoría, género y modalidad
     son listas cerradas del catálogo. Al guardar, comprueba todo contra CreateTeamRequest antes de enviar. -->
<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { onBeforeRouteLeave, useRouter } from 'vue-router'
import { api } from '../../api/client'
import { placeSaveError, type ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import { checkForm, requiredFields } from '../../api/rules'
import FormErrorList, { type FormError } from '../../components/FormErrorList.vue'
import FormField from '../../components/FormField.vue'
import LeaveDialog from '../../components/LeaveDialog.vue'
import LoadError from '../../components/LoadError.vue'
import { optionsOf } from '../../theme/names'
import { newestFirst, type Season, todayHere, toAddress } from '../home/seasons'
import { type CreateTeamRequest, type FromHome, hasChanges, initialSeason, type TeamForm, toRequest } from './form'

type Field = keyof CreateTeamRequest

// Cada campo: su `id` en la página y su nombre, que es también el de la lista de errores.
const fields: Record<Field, { id: string; label: string }> = {
  category: { id: 'team-category', label: 'Categoría' },
  letter: { id: 'team-letter', label: 'Letra' },
  gender: { id: 'team-gender', label: 'Género' },
  modality: { id: 'team-modality', label: 'Modalidad' },
  seasonId: { id: 'team-season', label: 'Temporada' },
}
const required = new Set<Field>(requiredFields('CreateTeamRequest'))

const categoryOptions = optionsOf('TeamCategory')
const genderOptions = optionsOf('Gender')
const modalityOptions = optionsOf('Modality')

// Los cuatro estados del selector de temporada (§3.2): el resto del formulario se puede rellenar mientras tanto.
type SeasonsState = { kind: 'loading' } | { kind: 'error'; error: ShownError } | { kind: 'ready'; seasons: Season[] }

const router = useRouter()
// En el navegador es `history.state`; leído del historial de Vue Router, sirve también el de las pruebas.
const fromHome = (router.options.history.state ?? {}) as FromHome

const form = reactive<TeamForm>({ letter: '' })
const seasonsState = ref<SeasonsState>({ kind: 'loading' })
let initialSeasonId: string | undefined

const fieldErrors = ref<Partial<Record<Field, string>>>({})
const banner = ref<ShownError>()
const saving = ref(false)
const errorList = ref<InstanceType<typeof FormErrorList>>()

const seasonOptions = computed(() =>
  seasonsState.value.kind === 'ready' ? seasonsState.value.seasons.map((s) => ({ value: s.id, label: s.label })) : [],
)
const listedErrors = computed<FormError[]>(() =>
  (Object.keys(fields) as Field[])
    .filter((field) => fieldErrors.value[field] !== undefined)
    .map((field) => ({ fieldId: fields[field].id, label: fields[field].label, message: fieldErrors.value[field]! })),
)

// Si se sale antes de la respuesta, la petición se cancela (LLD-B §3.2).
let pending: AbortController | undefined

async function loadSeasons() {
  pending?.abort()
  const leaving = new AbortController()
  pending = leaving
  seasonsState.value = { kind: 'loading' }
  try {
    const result = await asResult(api.GET('/seasons', { signal: leaving.signal }))
    if (!result.ok) {
      seasonsState.value = { kind: 'error', error: result.error }
      return
    }
    // El servidor no manda las archivadas, así que todas valen para inscribir un equipo.
    const seasons = newestFirst(result.data)
    seasonsState.value = { kind: 'ready', seasons }
    initialSeasonId = initialSeason(seasons, fromHome.seasonLabel, todayHere())?.id
    // Si el usuario ya eligió una mientras cargaba (al reintentar), se respeta.
    form.seasonId ??= initialSeasonId
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

onMounted(loadSeasons)

async function save() {
  banner.value = undefined
  const request = toRequest(form)
  fieldErrors.value = checkForm('CreateTeamRequest', request)
  if (listedErrors.value.length > 0) return showErrorList()

  saving.value = true
  const result = await asResult(api.POST('/teams', { body: request as CreateTeamRequest }))
  saving.value = false

  if (result.ok) {
    // Da igual si el equipo era nuevo o ya existía en otra temporada (decisión 6): se vuelve a la portada en la
    // temporada en la que queda inscrito, y el formulario sale del historial (decisión 5).
    const season = seasonOptions.value.find((s) => s.value === request.seasonId)
    return leave(season?.label)
  }

  const placed = placeSaveError(result.error, Object.keys(fields))
  if ('banner' in placed) {
    banner.value = placed.banner
    return
  }
  fieldErrors.value = { [placed.field]: placed.reason }
  return showErrorList()
}

async function showErrorList() {
  await nextTick()
  errorList.value?.focus()
}

// Al guardar bien no se pregunta nada: ya no hay nada sin guardar.
let leavingOnPurpose = false

// La portada en esa temporada, o `/` si no hay ninguna; sustituyendo al formulario en el historial (decisión 5).
function leave(seasonLabel: string | undefined, onPurpose = true) {
  leavingOnPurpose = onPurpose
  return router.replace(seasonLabel ? { path: '/', query: { temporada: toAddress(seasonLabel) } } : '/')
}

// «Cancelar» vuelve a la temporada de la que se vino, y pregunta si hay cambios.
function cancel() {
  return leave(fromHome.seasonLabel, false)
}

// Salir con cambios sin guardar (LLD-B §5.5): dentro de la web, pregunta la web.
const asking = ref(false)
let answer: ((leave: boolean) => void) | undefined

onBeforeRouteLeave(() => {
  if (leavingOnPurpose || !hasChanges(form, initialSeasonId)) return true
  asking.value = true
  return new Promise<boolean>((resolve) => (answer = resolve))
})

function answerLeave(leave: boolean) {
  asking.value = false
  answer?.(leave)
}

// Al cerrar la pestaña o recargar, pregunta el navegador, con su propio texto.
function warnBeforeUnload(event: BeforeUnloadEvent) {
  if (hasChanges(form, initialSeasonId)) event.preventDefault()
}
window.addEventListener('beforeunload', warnBeforeUnload)
onBeforeUnmount(() => {
  pending?.abort()
  window.removeEventListener('beforeunload', warnBeforeUnload)
})
</script>

<template>
  <h1>Dar de alta un equipo</h1>

  <form
    class="team-form"
    novalidate
    @submit.prevent="save"
  >
    <FormErrorList
      v-if="listedErrors.length > 0"
      ref="errorList"
      :errors="listedErrors"
    />
    <!-- Lo que no es de un campo, arriba, sin borrar lo escrito (LLD-B §4.3). -->
    <LoadError
      v-if="banner"
      :message="banner.message"
      :code="banner.code"
      :retry="banner.retry"
      @retry="save"
    />

    <FormField
      :id="fields.category.id"
      v-slot="{ describedBy, invalid }"
      :label="fields.category.label"
      :required="required.has('category')"
      :error="fieldErrors.category"
    >
      <Select
        v-model="form.category"
        :label-id="fields.category.id"
        :aria-labelledby="`${fields.category.id}-label`"
        :options="categoryOptions"
        option-label="label"
        option-value="value"
        :invalid="invalid"
        :pt="{ label: { 'aria-describedby': describedBy } }"
      />
    </FormField>

    <FormField
      :id="fields.letter.id"
      v-slot="{ describedBy, invalid }"
      :label="fields.letter.label"
      :required="required.has('letter')"
      help="Si el club tiene varios equipos de la misma categoría: A, B…"
      :error="fieldErrors.letter"
    >
      <InputText
        :id="fields.letter.id"
        v-model="form.letter"
        class="letter"
        :invalid="invalid"
        :aria-describedby="describedBy"
      />
    </FormField>

    <FormField
      :id="fields.gender.id"
      v-slot="{ describedBy, invalid }"
      :label="fields.gender.label"
      :required="required.has('gender')"
      :error="fieldErrors.gender"
    >
      <Select
        v-model="form.gender"
        :label-id="fields.gender.id"
        :aria-labelledby="`${fields.gender.id}-label`"
        :options="genderOptions"
        option-label="label"
        option-value="value"
        :invalid="invalid"
        :pt="{ label: { 'aria-describedby': describedBy } }"
      />
    </FormField>

    <FormField
      :id="fields.modality.id"
      v-slot="{ describedBy, invalid }"
      :label="fields.modality.label"
      :required="required.has('modality')"
      :error="fieldErrors.modality"
    >
      <Select
        v-model="form.modality"
        :label-id="fields.modality.id"
        :aria-labelledby="`${fields.modality.id}-label`"
        :options="modalityOptions"
        option-label="label"
        option-value="value"
        :invalid="invalid"
        :pt="{ label: { 'aria-describedby': describedBy } }"
      />
    </FormField>

    <FormField
      :id="fields.seasonId.id"
      v-slot="{ describedBy, invalid }"
      :label="fields.seasonId.label"
      :required="required.has('seasonId')"
      :error="fieldErrors.seasonId"
    >
      <!-- Se lee en voz alta sin mover el foco (LLD-B §10.3). -->
      <p
        v-if="seasonsState.kind === 'loading'"
        role="status"
      >
        Cargando temporadas…
      </p>
      <LoadError
        v-else-if="seasonsState.kind === 'error'"
        :message="seasonsState.error.message"
        :code="seasonsState.error.code"
        :retry="seasonsState.error.retry"
        @retry="loadSeasons"
      />
      <!-- Sin temporadas, el selector sale vacío; la temporada nueva se crea al lado (rebanada 2, R2.13). -->
      <Select
        v-else
        v-model="form.seasonId"
        :label-id="fields.seasonId.id"
        :aria-labelledby="`${fields.seasonId.id}-label`"
        :options="seasonOptions"
        option-label="label"
        option-value="value"
        empty-message="Todavía no hay ninguna temporada"
        :invalid="invalid"
        :pt="{ label: { 'aria-describedby': describedBy } }"
      />
    </FormField>

    <div class="actions">
      <Button
        type="submit"
        label="Guardar"
        :loading="saving"
      />
      <Button
        type="button"
        label="Cancelar"
        severity="secondary"
        @click="cancel"
      />
    </div>
  </form>

  <LeaveDialog
    :visible="asking"
    @stay="answerLeave(false)"
    @leave="answerLeave(true)"
  />
</template>

<style scoped>
.team-form {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  max-width: 28rem;
}
.letter {
  max-width: 6rem;
}
.actions {
  display: flex;
  gap: 0.75rem;
}
</style>
