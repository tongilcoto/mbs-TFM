<!-- Sincronizar un equipo con la Federación (plan R3, §3.2 y decisión 2): un asistente de dos pasos en la misma
     dirección, `/equipos/:id/federacion`. Al abrir pide el equipo (`getTeam`), para decir cuál se sincroniza: hace
     falta aunque se venga de la portada, porque al recargar o al escribir la dirección no hay de dónde sacarlo.
     El paso 1 comprueba la dirección del calendario en la Federación (`previewFederationLink`); el paso 2 enseña lo
     que hay en ella, pide elegir el equipo y sincroniza (`linkTeamToFederation`, §3.3). -->
<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import Select from 'primevue/select'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { onBeforeRouteLeave, useRoute, useRouter } from 'vue-router'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import { checkForm, exampleOf, requiredFields } from '../../api/rules'
import type { components } from '../../api/schema'
import CheckedAddress from '../../components/CheckedAddress.vue'
import FormErrorList, { type FormError } from '../../components/FormErrorList.vue'
import FormField from '../../components/FormField.vue'
import LeaveDialog from '../../components/LeaveDialog.vue'
import LoadError from '../../components/LoadError.vue'
import NoticeBox from '../../components/NoticeBox.vue'
import StepLine from '../../components/StepLine.vue'
import TeamChoiceList from '../../components/TeamChoiceList.vue'
import { announce } from '../../notice'
import { categoryNames, type Gender, namesOf, optionsOf, teamName } from '../../theme/names'
import { toAddress } from '../home/seasons'
import type { FromHome } from '../new-team/form'
import {
  choicesOf,
  competitionName,
  isTeamCode,
  mismatchesOf,
  placeCheckError,
  placeSyncError,
  syncLabel,
  teamNotFound,
  teamTitle,
} from './link'

type Team = components['schemas']['TeamResponse']
type Preview = components['schemas']['FederationLinkPreviewResponse']

// Los cuatro estados de lo que se pide al abrir (LLD-B §3.1). No hay «vacío»: un equipo existe o no. «No se ha
// encontrado» es un error más, sin *Reintentar* y con el enlace a la portada (LLD-B §6.7).
type State =
  | { kind: 'loading' }
  | { kind: 'error'; error: ShownError; notFound: boolean }
  | { kind: 'ready'; team: Team }

const steps = ['La dirección', 'Tu equipo']

const route = useRoute()
const router = useRouter()
// La temporada de la portada de la que se vino, para volver a ella al cancelar (como el alta, plan R2, decisión 5).
const fromHome = (router.options.history.state ?? {}) as FromHome
const teamId = String(route.params.id)

const state = ref<State>({ kind: 'loading' })
const team = computed(() => (state.value.kind === 'ready' ? state.value.team : undefined))

// ── Paso 1: la dirección ──

// El campo de la dirección, con la ayuda y el ejemplo del catálogo (§3.2), como la etiqueta de temporada del alta.
const field = { id: 'calendar-url', label: 'Dirección del calendario' }
const urlRequired = requiredFields('FederationLinkPreviewRequest').includes('federationCalendarUrl')
const urlExample = exampleOf('FederationLinkPreviewRequest', 'federationCalendarUrl')
const urlHelp = ['Cópiala de la web de la Federación, en la página del calendario del grupo.', urlExample && `Por ejemplo: ${urlExample}`]
  .filter(Boolean)
  .join(' ')

const url = ref('')
const fieldError = ref<string>()
const banner = ref<ShownError>()
const checking = ref(false)
const errorList = ref<InstanceType<typeof FormErrorList>>()
const listedErrors = computed<FormError[]>(() =>
  fieldError.value === undefined ? [] : [{ fieldId: field.id, label: field.label, message: fieldError.value }],
)

// ── Paso 2: tu equipo ──

// Lo comprobado, y la dirección con la que se comprobó: es la que se envía al sincronizar, no la del campo. Al
// editarla, lo comprobado se borra: lo que se sincroniza es siempre lo que se ha visto (decisión 2).
const preview = ref<Preview>()
const checkedUrl = ref('')
const step = computed(() => (preview.value ? 1 : 0))

const choiceList = { id: 'team-choice', legend: '¿Cuál es tu equipo?' }
const chosenCode = ref<string>()
const gender = ref<Gender>()
const choiceError = ref<string>()
const stepTwoBanner = ref<ShownError>()
const rechecking = ref(false)
const syncing = ref(false)
const stepTwoHeading = ref<HTMLElement>()
const choices = ref<InstanceType<typeof TeamChoiceList>>()
const stepTwoErrors = ref<InstanceType<typeof FormErrorList>>()

const genderNames = namesOf('Gender')
const modalityNames = namesOf('Modality')
const genderOptions = optionsOf('Gender')
// La temporada, con «· nueva» si el club no la tiene: se creará al sincronizar (decisión 3).
const seasonText = computed(() => (preview.value ? `${preview.value.season.label}${preview.value.season.exists ? '' : ' · nueva'}` : ''))
const options = computed(() => (preview.value ? choicesOf(preview.value.competition.teams, teamId) : []))
const chosen = computed(() => options.value.find((option) => option.code !== null && option.code === chosenCode.value))
const mismatches = computed(() =>
  preview.value && team.value && gender.value ? mismatchesOf(team.value, preview.value.competition, gender.value) : [],
)
const listedChoiceErrors = computed<FormError[]>(() =>
  choiceError.value === undefined
    ? []
    : [{ fieldId: choices.value?.firstId ?? choiceList.id, label: choiceList.legend, message: choiceError.value }],
)

// Si se sale antes de la respuesta, la petición se cancela (LLD-B §3.2).
let pending: AbortController | undefined

function startRequest(): AbortSignal {
  pending?.abort()
  pending = new AbortController()
  return pending.signal
}

async function loadTeam() {
  if (!isTeamCode(teamId)) {
    state.value = { kind: 'error', error: teamNotFound, notFound: true }
    return
  }
  state.value = { kind: 'loading' }
  const signal = startRequest()
  try {
    const result = await asResult(api.GET('/teams/{teamId}', { params: { path: { teamId } }, signal }))
    if (result.ok) {
      // Un rival no se sincroniza: para esta pantalla, no existe (decisión 6).
      state.value = result.data.isOwn ? { kind: 'ready', team: result.data } : { kind: 'error', error: teamNotFound, notFound: true }
      return
    }
    state.value = { kind: 'error', error: result.error, notFound: result.error.code === 'TEAM_NOT_FOUND' }
  } catch (error) {
    if (signal.aborted) return
    throw error
  }
}

onMounted(loadTeam)

// El `/preview`, para el paso 1 y para volver a comprobar desde el paso 2. Sin resultado si se canceló.
async function askPreview(address: string) {
  const signal = startRequest()
  try {
    return await asResult(
      api.POST('/teams/{teamId}/federation-link/preview', {
        params: { path: { teamId } },
        body: { federationCalendarUrl: address },
        signal,
      }),
    )
  } catch (error) {
    if (signal.aborted) return undefined
    throw error
  }
}

// Lo comprobado pasa al paso 2. El equipo elegido se conserva si sigue en la lista y se puede elegir (al volver a
// comprobar); el género, el que propone la Federación.
function showPreview(address: string, data: Preview) {
  checkedUrl.value = address
  preview.value = data
  gender.value = data.competition.gender
  if (!options.value.some((option) => option.reason === undefined && option.code === chosenCode.value)) chosenCode.value = undefined
}

// «Comprobar en la Federación»: primero el formato, con el catálogo y sin llegar al servidor; después, el
// `/preview`. Mientras tanto el botón se bloquea, porque la Federación puede tardar (LLD §5.4).
async function check() {
  banner.value = undefined
  const written = url.value.trim()
  // Vacío no es «formato no válido»: es que falta.
  fieldError.value = checkForm('FederationLinkPreviewRequest', { federationCalendarUrl: written || undefined }).federationCalendarUrl
  if (fieldError.value !== undefined) return focusLater(() => errorList.value?.focus())

  checking.value = true
  const result = await askPreview(written).finally(() => (checking.value = false))
  if (result === undefined) return

  if (result.ok) {
    showPreview(written, result.data)
    // El foco, al principio del paso 2: si no, se queda en un botón que ya no está.
    return focusLater(() => stepTwoHeading.value?.focus())
  }
  const place = placeCheckError(result.error)
  if (place === 'page') state.value = { kind: 'error', error: result.error, notFound: true }
  else if (place === 'banner') banner.value = result.error
  else {
    fieldError.value = result.error.message
    return focusLater(() => errorList.value?.focus())
  }
}

// Editar (el lápiz): vuelve al paso 1 con la dirección comprobada en el campo, y lo comprobado se borra.
function edit() {
  url.value = checkedUrl.value
  preview.value = undefined
  chosenCode.value = undefined
  choiceError.value = undefined
  stepTwoBanner.value = undefined
  return focusLater(() => document.getElementById(field.id)?.focus())
}

// Volver a comprobar (la flecha): el `/preview` con la misma dirección, sin salir del paso 2. Un fallo sale arriba
// del paso 2 y lo de antes sigue a la vista; se reintenta con la misma flecha.
async function recheck() {
  stepTwoBanner.value = undefined
  rechecking.value = true
  const result = await askPreview(checkedUrl.value).finally(() => (rechecking.value = false))
  if (result === undefined) return
  if (result.ok) return showPreview(checkedUrl.value, result.data)
  if (placeCheckError(result.error) === 'page') state.value = { kind: 'error', error: result.error, notFound: true }
  else stepTwoBanner.value = { ...result.error, retry: false }
}

// «Sincronizar…»: sin equipo elegido se puede pulsar, y dice qué falta (§3.3). Con él, el enganche con la dirección
// comprobada, el código elegido y el género, sin `seasonLabel`: el servidor usa la de la Federación (decisión 3).
async function sync() {
  stepTwoBanner.value = undefined
  if (!chosen.value) {
    choiceError.value = 'Elige tu equipo'
    return focusLater(() => stepTwoErrors.value?.focus())
  }
  choiceError.value = undefined

  syncing.value = true
  const signal = startRequest()
  let result
  try {
    result = await asResult(
      api.POST('/teams/{teamId}/federation-link', {
        params: { path: { teamId } },
        body: { federationCalendarUrl: checkedUrl.value, ownTeamFederationId: chosen.value.code!, gender: gender.value! },
        signal,
      }),
    )
  } catch (error) {
    if (signal.aborted) return
    throw error
  } finally {
    syncing.value = false
  }

  // Bien: el enganche está escrito y la primera ingesta, en cola (202). A la portada en la temporada **del
  // calendario**, que puede no ser la de partida, porque es donde está ahora el equipo con su competición; sin
  // esta pantalla en el historial (decisión 5). El aviso lo pone el marco, como «Guardado» (§3.4).
  if (result.ok) {
    announce('Sincronizado. La primera ingesta está en marcha.')
    return leave(preview.value!.season.label)
  }
  const placed = placeSyncError(result.error)
  if ('page' in placed) state.value = { kind: 'error', error: placed.page, notFound: true }
  else stepTwoBanner.value = placed.banner
}

// Al elegir un equipo, lo que faltaba deja de faltar.
function choose(code: string | undefined) {
  chosenCode.value = code
  if (code) choiceError.value = undefined
}

async function focusLater(move: () => void) {
  await nextTick()
  move()
}

// Al sincronizar bien no se pregunta nada: ya no hay nada sin guardar.
let leavingOnPurpose = false

// La portada en esa temporada, o `/` si no hay ninguna; sustituyendo a esta pantalla en el historial (§3.3).
function leave(seasonLabel: string | undefined, onPurpose = true) {
  leavingOnPurpose = onPurpose
  return router.replace(seasonLabel ? { path: '/', query: { temporada: toAddress(seasonLabel) } } : '/')
}

// «Cancelar» vuelve a la temporada de la que se vino, y pregunta si hay algo escrito o comprobado.
function cancel() {
  return leave(fromHome.seasonLabel, false)
}

// Algo que se perdería al salir (§3.3): una dirección escrita, o lo comprobado, que la lleva siempre: el campo la
// conserva durante el paso 2. Sin el equipo cargado no hay nada. (Los espacios de los lados ya los quita el
// navegador en un campo `type="url"`; el `trim`, por si el campo deja de serlo.)
const hasChanges = computed(() => state.value.kind === 'ready' && url.value.trim() !== '')

// Salir con cambios sin guardar (LLD-B §5.5): dentro de la web, pregunta la web, con el aviso del alta.
const asking = ref(false)
let answer: ((leave: boolean) => void) | undefined

onBeforeRouteLeave(() => {
  if (leavingOnPurpose || !hasChanges.value) return true
  asking.value = true
  return new Promise<boolean>((resolve) => (answer = resolve))
})

function answerLeave(leave: boolean) {
  asking.value = false
  answer?.(leave)
}

// Al cerrar la pestaña o recargar, pregunta el navegador, con su propio texto.
function warnBeforeUnload(event: BeforeUnloadEvent) {
  if (hasChanges.value) event.preventDefault()
}
window.addEventListener('beforeunload', warnBeforeUnload)
onBeforeUnmount(() => {
  pending?.abort()
  window.removeEventListener('beforeunload', warnBeforeUnload)
})
</script>

<template>
  <h1>Sincronizar con la Federación</h1>

  <!-- En el sitio del equipo, debajo del título. Se lee en voz alta sin mover el foco (LLD-B §10.3). -->
  <p
    v-if="state.kind === 'loading'"
    role="status"
  >
    Cargando equipo…
  </p>
  <LoadError
    v-else-if="state.kind === 'error'"
    :message="state.error.message"
    :code="state.error.code"
    :retry="state.error.retry"
    @retry="loadTeam"
  >
    <p v-if="state.notFound">
      <RouterLink to="/">
        Ir a la portada
      </RouterLink>
    </p>
  </LoadError>
  <template v-else>
    <p class="team">
      {{ teamTitle(state.team) }}
    </p>
    <StepLine
      :steps="steps"
      :current="step"
    />

    <form
      v-if="!preview"
      class="step"
      novalidate
      @submit.prevent="check"
    >
      <FormErrorList
        v-if="listedErrors.length > 0"
        ref="errorList"
        :errors="listedErrors"
      />
      <!-- La Federación no responde o responde mal: arriba, sin borrar lo escrito (decisión 6). -->
      <LoadError
        v-if="banner"
        :message="banner.message"
        :code="banner.code"
        :retry="banner.retry"
        @retry="check"
      />

      <FormField
        :id="field.id"
        v-slot="{ describedBy, invalid }"
        :label="field.label"
        :required="urlRequired"
        :help="urlHelp"
        :error="fieldError"
      >
        <InputText
          :id="field.id"
          v-model="url"
          type="url"
          :invalid="invalid"
          :aria-describedby="describedBy"
        />
      </FormField>

      <div class="actions">
        <Button
          type="submit"
          :label="checking ? 'Comprobando…' : 'Comprobar en la Federación'"
          :loading="checking"
        />
        <Button
          type="button"
          label="Cancelar"
          severity="secondary"
          @click="cancel"
        />
      </div>
    </form>

    <form
      v-else
      class="step"
      novalidate
      @submit.prevent="sync"
    >
      <FormErrorList
        v-if="listedChoiceErrors.length > 0"
        ref="stepTwoErrors"
        :errors="listedChoiceErrors"
      />
      <!-- Lo que falla al sincronizar o al volver a comprobar: arriba, sin perder lo elegido (decisión 6). -->
      <LoadError
        v-if="stepTwoBanner"
        :message="stepTwoBanner.message"
        :code="stepTwoBanner.code"
        :retry="false"
      />
      <CheckedAddress
        :address="checkedUrl"
        :checking="rechecking"
        @edit="edit"
        @recheck="recheck"
      />

      <h2
        ref="stepTwoHeading"
        tabindex="-1"
      >
        Lo que hay en esa dirección
      </h2>
      <dl class="summary">
        <div>
          <dt>Competición</dt>
          <dd>{{ competitionName(preview.competition) }}</dd>
        </div>
        <div>
          <dt>Edad</dt>
          <dd>{{ categoryNames[preview.competition.ageCategory] }}</dd>
        </div>
        <div>
          <dt>Modalidad</dt>
          <dd>{{ modalityNames[preview.competition.modality] }}</dd>
        </div>
        <!-- La que ya está en el club tiene su género, y el que se envíe no lo cambia: se enseña, no se elige. -->
        <div v-if="preview.competition.alreadyRegistered">
          <dt>Género</dt>
          <dd>{{ genderNames[preview.competition.gender] }}</dd>
        </div>
        <div>
          <dt>Temporada</dt>
          <dd>{{ seasonText }}</dd>
        </div>
        <div>
          <dt>Jornadas</dt>
          <dd>{{ preview.competition.roundCount }}</dd>
        </div>
      </dl>

      <NoticeBox
        v-if="mismatches.length > 0"
        kind="warning"
      >
        <p><strong>No cuadra con el equipo.</strong> Comprueba que la dirección sea la del grupo de este equipo.</p>
        <ul>
          <li
            v-for="mismatch in mismatches"
            :key="mismatch.piece"
          >
            {{ mismatch.piece }}: el equipo es {{ mismatch.team }} y la competición, {{ mismatch.competition }}.
          </li>
        </ul>
      </NoticeBox>
      <NoticeBox
        v-if="!preview.ageCategoryChecked"
        kind="warning"
      >
        <p>
          La Federación no dice la edad de esta competición: se usará la del equipo,
          {{ categoryNames[state.team.category] }}.
        </p>
      </NoticeBox>
      <NoticeBox
        v-if="!preview.season.exists"
        kind="info"
      >
        <p>
          La temporada <strong>{{ preview.season.label }}</strong> no existe todavía en el club: se creará al
          sincronizar, con el nombre que le da la Federación.
        </p>
      </NoticeBox>
      <NoticeBox
        v-if="preview.competition.alreadyRegistered"
        kind="info"
      >
        <p>Esta competición ya está en el club; se reutiliza.</p>
      </NoticeBox>

      <TeamChoiceList
        :id="choiceList.id"
        ref="choices"
        :model-value="chosenCode"
        :legend="choiceList.legend"
        :hint="`Tal como lo escribe la Federación. Elige el que corresponde a ${teamName(state.team.category, state.team.letter)}.`"
        :options="options"
        :error="choiceError"
        @update:model-value="choose"
      />

      <FormField
        v-if="!preview.competition.alreadyRegistered"
        id="competition-gender"
        v-slot="{ describedBy }"
        label="Género de la competición"
        :required="true"
        help="Lo propone la Federación por el nombre de la competición. Cámbialo si no es correcto."
      >
        <Select
          v-model="gender"
          class="gender"
          label-id="competition-gender"
          aria-labelledby="competition-gender-label"
          :options="genderOptions"
          option-label="label"
          option-value="value"
          :pt="{ label: { 'aria-describedby': describedBy } }"
        />
      </FormField>

      <div class="actions">
        <!-- No cuadra: el servidor lo rechazaría (409), así que no se deja; el motivo está a la vista, arriba. -->
        <Button
          type="submit"
          :label="syncLabel(chosen)"
          :loading="syncing"
          :disabled="mismatches.length > 0 || rechecking"
        />
        <Button
          type="button"
          label="Cancelar"
          severity="secondary"
          @click="cancel"
        />
      </div>
    </form>
  </template>

  <LeaveDialog
    :visible="asking"
    @stay="answerLeave(false)"
    @leave="answerLeave(true)"
  />
</template>

<style scoped>
h1 {
  margin-bottom: 0.25rem;
}
h2 {
  margin: 0.5rem 0 0;
  font-size: 1.25rem;
}
.team {
  margin-top: 0;
  color: var(--p-text-muted-color);
}
.step {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  max-width: 48rem;
  margin-top: 1.5rem;
}
/* La dirección de ejemplo es larga y sin espacios: se parte donde haga falta para no salirse en el móvil. */
.step :deep(.help) {
  overflow-wrap: anywhere;
}
.summary {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(8rem, 1fr));
  gap: 0.75rem;
  margin: 0;
  padding: 1rem;
  border: 1px solid var(--p-content-border-color);
  background: var(--p-content-background);
}
dt {
  font-size: 0.8125rem;
  color: var(--p-text-muted-color);
}
dd {
  margin: 0;
  font-weight: 600;
}
.gender {
  max-width: 20rem;
}
.actions {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
}
</style>
