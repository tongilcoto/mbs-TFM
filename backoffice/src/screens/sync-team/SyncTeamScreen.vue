<!-- Sincronizar un equipo con la Federación (plan R3, §3.2 y decisión 2): un asistente de dos pasos en la misma
     dirección, `/equipos/:id/federacion`. Al abrir pide el equipo (`getTeam`), para decir cuál se sincroniza: hace
     falta aunque se venga de la portada, porque al recargar o al escribir la dirección no hay de dónde sacarlo.
     El paso 1 comprueba la dirección del calendario en la Federación (`previewFederationLink`); el paso 2, elegir
     el equipo y sincronizar, llega en R3.11. -->
<script setup lang="ts">
import Button from 'primevue/button'
import InputText from 'primevue/inputtext'
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import { checkForm, exampleOf, requiredFields } from '../../api/rules'
import type { components } from '../../api/schema'
import FormErrorList, { type FormError } from '../../components/FormErrorList.vue'
import FormField from '../../components/FormField.vue'
import LoadError from '../../components/LoadError.vue'
import StepLine from '../../components/StepLine.vue'
import { toAddress } from '../home/seasons'
import type { FromHome } from '../new-team/form'
import { isTeamCode, placeCheckError, teamNotFound, teamTitle } from './link'

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

// Lo comprobado: con ello se pasa al paso 2.
const preview = ref<Preview>()
const step = computed(() => (preview.value ? 1 : 0))

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

// «Comprobar en la Federación»: primero el formato, con el catálogo y sin llegar al servidor; después, el
// `/preview`. Mientras tanto el botón se bloquea, porque la Federación puede tardar (LLD §5.4).
async function check() {
  banner.value = undefined
  const written = url.value.trim()
  // Vacío no es «formato no válido»: es que falta.
  fieldError.value = checkForm('FederationLinkPreviewRequest', { federationCalendarUrl: written || undefined }).federationCalendarUrl
  if (fieldError.value !== undefined) return showErrorList()

  checking.value = true
  const signal = startRequest()
  let result
  try {
    result = await asResult(
      api.POST('/teams/{teamId}/federation-link/preview', {
        params: { path: { teamId } },
        body: { federationCalendarUrl: written },
        signal,
      }),
    )
  } catch (error) {
    if (signal.aborted) return
    throw error
  } finally {
    checking.value = false
  }

  if (result.ok) {
    preview.value = result.data
    return
  }
  const place = placeCheckError(result.error)
  if (place === 'page') state.value = { kind: 'error', error: result.error, notFound: true }
  else if (place === 'banner') banner.value = result.error
  else {
    fieldError.value = result.error.message
    return showErrorList()
  }
}

async function showErrorList() {
  await nextTick()
  errorList.value?.focus()
}

// «Cancelar» vuelve a la portada de la que se vino, sustituyendo a esta pantalla en el historial (§3.3).
function cancel() {
  const seasonLabel = fromHome.seasonLabel
  return router.replace(seasonLabel ? { path: '/', query: { temporada: toAddress(seasonLabel) } } : '/')
}

onBeforeUnmount(() => pending?.abort())
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
      v-if="step === 0"
      class="address"
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
    <!-- El paso 2: la dirección comprobada, lo que hay en ella y elegir el equipo, en R3.11. -->
    <div
      v-else
      class="actions"
    >
      <Button
        type="button"
        label="Cancelar"
        severity="secondary"
        @click="cancel"
      />
    </div>
  </template>
</template>

<style scoped>
h1 {
  margin-bottom: 0.25rem;
}
.team {
  margin-top: 0;
  color: var(--p-text-muted-color);
}
.address {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  max-width: 48rem;
  margin-top: 1.5rem;
}
/* La dirección de ejemplo es larga y sin espacios: se parte donde haga falta para no salirse en el móvil. */
.address :deep(.help) {
  overflow-wrap: anywhere;
}
.actions {
  display: flex;
  gap: 0.75rem;
}
</style>
