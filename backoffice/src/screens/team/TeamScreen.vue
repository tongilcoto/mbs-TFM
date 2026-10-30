<!-- La ficha del equipo en una temporada (plan R4, §3.2): `/temporadas/:temporada/equipos/:id/resultados`. Arriba,
     el equipo y tres cajas: la temporada, la competición con su ingesta y ↻, y la posición (decisión 4). Al abrir
     pide el equipo y las temporadas a la vez; con la temporada, la inscripción del equipo en ella; con su
     competición, el estado de su ingesta (las competiciones de la temporada), sus jornadas y la clasificación de la
     jornada en curso, o de la anterior si esa aún no tiene tabla; y a la vez, sus partidos de la temporada, para la
     pestaña Resultados (§3.3). `/equipos/:id`, sin temporada, lleva a la en curso (LLD-B §6.4). Mientras la ingesta
     está «En marcha», se refresca sola, como la portada. -->
<script setup lang="ts">
import Select from 'primevue/select'
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult, type Result } from '../../api/result'
import type { components } from '../../api/schema'
import HealthStatus from '../../components/HealthStatus.vue'
import IconAction from '../../components/IconAction.vue'
import LoadError from '../../components/LoadError.vue'
import NoticeBox from '../../components/NoticeBox.vue'
import SeasonPicker from '../../components/SeasonPicker.vue'
import MatchesTable from './MatchesTable.vue'
import { refreshWhile } from '../../refresh'
import { shownHealth, useRelaunch } from '../../relaunch'
import { competitionLabel } from '../../theme/names'
import { chooseSeason, newestFirst, type Season, todayHere, toAddress } from '../home/seasons'
import { isTeamCode, teamNotFound } from '../sync-team/link'
import { competitionPath, notPlayingText, positionIn, resultsPath, roundsToLookIn, teamHeading } from './header'
import { matchRows } from './matches'

type Team = components['schemas']['TeamResponse']
type Competition = components['schemas']['CompetitionResponse']
type Match = components['schemas']['MatchResponse']
type Standing = components['schemas']['StandingResponse']

// Los estados de la ficha (§3.2). Los que tienen el equipo enseñan su título; los que tienen la temporada, el
// selector. «No se ha encontrado» es un error más, con el enlace a la portada (LLD-B §6.7).
type State =
  | { kind: 'loading' }
  | { kind: 'error'; error: ShownError; notFound: boolean }
  | { kind: 'noSeasons'; team: Team }
  | { kind: 'unknownSeason'; team: Team; asked: string }
  | { kind: 'notPlaying'; team: Team; season: Season }
  | { kind: 'ready'; team: Team; season: Season; competitions: Competition[] }

// La posición, por separado: se vuelve a buscar al elegir otra competición, sin rehacer la ficha. Con ella, la
// clasificación de la que sale (`table`): da el puesto de hoy de los partidos sin jugar (§3.3).
type Position =
  | { kind: 'loading' }
  | { kind: 'none'; table: Standing[] }
  | { kind: 'found'; position: number; of: number; round: number; table: Standing[] }

// Los partidos de la temporada, también por separado: si fallan, la cabecera se queda (§3.3).
type Matches = { kind: 'loading' } | { kind: 'error'; error: ShownError } | { kind: 'list'; matches: Match[] }

const route = useRoute()
const router = useRouter()

const state = ref<State>({ kind: 'loading' })
const position = ref<Position>({ kind: 'loading' })
const matches = ref<Matches>({ kind: 'loading' })
// Las temporadas, una vez: no cambian al cambiar de temporada. `undefined` mientras no han llegado.
const seasons = ref<Season[]>()
// La competición que se ve, si el equipo tiene más de una (liga y copa, D-12).
const chosenId = ref<string>()

// Cada carga cancela la anterior, y salir cancela la que quede (LLD-B §3.2). El refresco, igual.
let pending: AbortController | undefined
let refreshing: AbortController | undefined

const { running: relaunched, failure: relaunchFailure, relaunch } = useRelaunch(refresh)

const teamId = computed(() => String(route.params.id))
const team = computed(() => (state.value.kind === 'loading' || state.value.kind === 'error' ? undefined : state.value.team))
const season = computed(() => (state.value.kind === 'ready' || state.value.kind === 'notPlaying' ? state.value.season : undefined))
const heading = computed(() => team.value && teamHeading(team.value))
const pickerLabels = computed(() => newestFirst(seasons.value ?? []).map((s) => s.label))
const competitions = computed(() => (state.value.kind === 'ready' ? state.value.competitions : []))
const competition = computed(() => competitions.value.find((c) => c.id === chosenId.value))
const health = computed(() => competition.value && shownHealth(competition.value, relaunched.has(competition.value.id)))
const competitionOptions = computed(() => competitions.value.map((c) => ({ value: c.id, label: competitionLabel(c) })))
// Las filas de la tabla: los partidos de la competición que se ve (§3.2).
const rows = computed(() =>
  matches.value.kind === 'list'
    ? matchRows(
        matches.value.matches.filter((match) => match.competitionId === chosenId.value),
        teamId.value,
        position.value.kind === 'loading' ? [] : position.value.table,
      )
    : [],
)

// «← Equipos», a la portada en la misma temporada.
const homeLink = computed(() => (season.value ? { path: '/', query: { temporada: toAddress(season.value.label) } } : '/'))
// Sincronizar, con la temporada en el estado de la navegación, como desde la portada (plan R3, decisión 1).
const syncTarget = computed(() => ({
  path: `/equipos/${teamId.value}/federacion`,
  state: season.value ? { seasonLabel: season.value.label } : {},
}))

async function load() {
  pending?.abort()
  refreshing?.abort()
  const leaving = new AbortController()
  pending = leaving
  relaunchFailure.value = undefined
  state.value = { kind: 'loading' }

  const id = teamId.value
  if (!isTeamCode(id)) {
    state.value = { kind: 'error', error: teamNotFound, notFound: true }
    return
  }
  const asked = typeof route.params.temporada === 'string' ? route.params.temporada : undefined

  try {
    const [found, listed] = await Promise.all([
      asResult(api.GET('/teams/{teamId}', { params: { path: { teamId: id } }, signal: leaving.signal })),
      seasons.value ? undefined : asResult(api.GET('/seasons', { signal: leaving.signal })),
    ])
    if (!found.ok) {
      state.value = { kind: 'error', error: found.error, notFound: found.error.code === 'TEAM_NOT_FOUND' }
      return
    }
    // Un rival no tiene ficha: para el club, no existe (como al sincronizar, plan R3, decisión 6).
    if (!found.data.isOwn) {
      state.value = { kind: 'error', error: teamNotFound, notFound: true }
      return
    }
    if (listed && !listed.ok) {
      state.value = { kind: 'error', error: listed.error, notFound: false }
      return
    }
    if (listed) seasons.value = listed.data
    const team = found.data

    const choice = chooseSeason(seasons.value!, asked, todayHere())
    if (choice.kind === 'none') {
      state.value = { kind: 'noSeasons', team }
      return
    }
    if (choice.kind === 'unknown') {
      state.value = { kind: 'unknownSeason', team, asked: choice.asked }
      return
    }
    // Sin temporada en la dirección, la que toca, en la dirección: así se puede compartir y recargar.
    if (asked === undefined) {
      await router.replace(resultsPath(choice.season.label, id))
      return
    }
    const season = choice.season

    const registration = await asResult(
      api.GET('/teams/{teamId}/registrations/{seasonId}', {
        params: { path: { teamId: id, seasonId: season.id } },
        signal: leaving.signal,
      }),
    )
    if (!registration.ok) {
      state.value =
        registration.error.code === 'TEAM_NOT_REGISTERED'
          ? { kind: 'notPlaying', team, season }
          : { kind: 'error', error: registration.error, notFound: registration.error.code === 'TEAM_NOT_FOUND' }
      return
    }

    // Su estado de la ingesta y sus nombres vienen con las competiciones de la temporada; en el orden de la
    // inscripción.
    let own: Competition[] = []
    if (registration.data.competitions.length > 0) {
      const all = await asResult(api.GET('/competitions', { params: { query: { seasonId: season.id } }, signal: leaving.signal }))
      if (!all.ok) {
        state.value = { kind: 'error', error: all.error, notFound: false }
        return
      }
      own = registration.data.competitions.flatMap(({ competitionId }) => all.data.find((c) => c.id === competitionId) ?? [])
    }
    if (!own.some((c) => c.id === chosenId.value)) chosenId.value = own[0]?.id

    // La posición y los partidos se piden a la vez; la cabecera sale en cuanto está la posición, y los partidos,
    // debajo, cuando lleguen. Sin competición, no hay ni una cosa ni otra que pedir.
    const listing = own.length > 0 ? fetchMatches(season.id, leaving.signal) : Promise.resolve(ok<Match[]>([]))
    // Si la posición falla, nadie espera a los partidos: que su cancelación no quede como un error suelto.
    listing.catch(() => undefined)
    const located = chosenId.value ? await findPosition(chosenId.value, leaving.signal) : ok<Position>({ kind: 'none', table: [] })
    if (!located.ok) {
      state.value = { kind: 'error', error: located.error, notFound: false }
      return
    }
    position.value = located.data
    matches.value = { kind: 'loading' }
    state.value = { kind: 'ready', team, season, competitions: own }

    const fetched = await listing
    matches.value = fetched.ok ? { kind: 'list', matches: fetched.data } : { kind: 'error', error: fetched.error }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

function ok<T>(data: T): Result<T> {
  return { ok: true, data }
}

// La posición (§3.2): la de la clasificación de la jornada en curso; si esa todavía no tiene tabla, la anterior, y
// así hasta encontrarla. Si ninguna la tiene, «—».
async function findPosition(competitionId: string, signal: AbortSignal): Promise<Result<Position>> {
  const rounds = await asResult(api.GET('/rounds', { params: { query: { competitionId } }, signal }))
  if (!rounds.ok) return rounds
  for (const round of roundsToLookIn(rounds.data)) {
    const table = await asResult(api.GET('/standings', { params: { query: { roundId: round.id } }, signal }))
    if (!table.ok) return table
    if (table.data.length === 0) continue
    const found = positionIn(table.data, teamId.value)
    return ok(found ? { kind: 'found', ...found, round: round.number, table: table.data } : { kind: 'none', table: table.data })
  }
  return ok({ kind: 'none', table: [] })
}

// Todos los partidos del equipo en la temporada, de todas sus competiciones: unos 30, y la página llega a 100. Por
// si un día son más, página a página hasta el total.
async function fetchMatches(seasonId: string, signal: AbortSignal): Promise<Result<Match[]>> {
  const all: Match[] = []
  for (let page = 1; ; page++) {
    const answer = await asResult(
      api.GET('/matches', { params: { query: { teamId: teamId.value, seasonId, page, perPage: 100 } }, signal }),
    )
    if (!answer.ok) return answer
    all.push(...answer.data.data)
    if (all.length >= answer.data.total || answer.data.data.length === 0) return ok(all)
  }
}

// *Reintentar* de la tabla: solo los partidos.
async function reloadMatches() {
  if (state.value.kind !== 'ready') return
  const { season } = state.value
  const leaving = new AbortController()
  pending = leaving
  matches.value = { kind: 'loading' }
  try {
    const listed = await fetchMatches(season.id, leaving.signal)
    matches.value = listed.ok ? { kind: 'list', matches: listed.data } : { kind: 'error', error: listed.error }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

// Al abrir, y cada vez que cambia el equipo o la temporada de la dirección (el selector, o «Atrás»).
watch(() => [route.params.id, route.params.temporada], load, { immediate: true })

// Otra competición del equipo: solo cambia la posición. Si falla, el error de la ficha, con *Reintentar*.
async function chooseCompetition(id: string) {
  chosenId.value = id
  pending?.abort()
  const leaving = new AbortController()
  pending = leaving
  position.value = { kind: 'loading' }
  try {
    const found = await findPosition(id, leaving.signal)
    if (found.ok) position.value = found.data
    else state.value = { kind: 'error', error: found.error, notFound: false }
  } catch (error) {
    if (leaving.signal.aborted) return
    throw error
  }
}

// El refresco (como la portada, plan R3, decisión 5): mientras la ingesta de alguna de sus competiciones esté «En
// marcha», cada 10 s, las competiciones, la posición y los partidos, sin «Cargando…». Si falla, se deja como
// estaba. También después de ↻.
const running = computed(() => competitions.value.some((c) => c.ingestionHealth === 'pending'))

async function refresh() {
  if (state.value.kind !== 'ready') return
  const { season } = state.value
  refreshing?.abort()
  const current = new AbortController()
  refreshing = current
  try {
    const [all, found, listed] = await Promise.all([
      asResult(api.GET('/competitions', { params: { query: { seasonId: season.id } }, signal: current.signal })),
      chosenId.value ? findPosition(chosenId.value, current.signal) : ok<Position>({ kind: 'none', table: [] }),
      state.value.competitions.length > 0 ? fetchMatches(season.id, current.signal) : ok<Match[]>([]),
    ])
    // Una carga nueva (otra temporada) manda sobre un refresco a medias.
    if (!all.ok || !found.ok || !listed.ok || state.value.kind !== 'ready' || state.value.season.id !== season.id) return
    const ids = state.value.competitions.map((c) => c.id)
    state.value = { ...state.value, competitions: ids.flatMap((id) => all.data.find((c) => c.id === id) ?? []) }
    position.value = found.data
    matches.value = { kind: 'list', matches: listed.data }
  } catch (error) {
    if (current.signal.aborted) return
    throw error
  }
}

refreshWhile(() => running.value, refresh)
onBeforeUnmount(() => {
  pending?.abort()
  refreshing?.abort()
})

// El selector cambia la dirección: «Atrás» vuelve a la anterior, y el enlace se puede compartir.
function pickSeason(label: string) {
  router.push(resultsPath(label, teamId.value))
}
</script>

<template>
  <p class="back">
    <RouterLink :to="homeLink">
      ← Equipos
    </RouterLink>
  </p>
  <h1>{{ heading?.title ?? 'Equipo' }}</h1>
  <p
    v-if="heading"
    class="subtitle"
  >
    {{ heading.subtitle }}
  </p>

  <!-- Se lee en voz alta sin mover el foco (LLD-B §10.3). -->
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
    @retry="load"
  >
    <p v-if="state.notFound">
      <RouterLink to="/">
        Ir a la portada
      </RouterLink>
    </p>
  </LoadError>
  <LoadError
    v-else-if="state.kind === 'noSeasons'"
    message="Todavía no hay ninguna temporada."
    :retry="false"
  />
  <template v-else>
    <!-- Volver a traer los datos no ha ido bien: arriba, con las cajas a la vista (LLD-B §4.3). -->
    <LoadError
      v-if="relaunchFailure"
      class="banner"
      :message="relaunchFailure.error.message"
      :code="relaunchFailure.error.code"
      :retry="relaunchFailure.error.retry"
      @retry="relaunch(relaunchFailure.competitionId, relaunchFailure.competitionName)"
    >
      <p>Al volver a traer los datos de {{ relaunchFailure.competitionName }}.</p>
    </LoadError>

    <div class="boxes">
      <!-- Todas las temporadas del club, no solo las que juega (decisión 4): saberlo costaría una petición por
           temporada. -->
      <div class="box season">
        <SeasonPicker
          :labels="pickerLabels"
          :model-value="season?.label ?? ''"
          @update:model-value="pickSeason"
        />
      </div>

      <template v-if="state.kind === 'ready'">
        <section
          class="box"
          aria-labelledby="competition-title"
        >
          <h2
            id="competition-title"
            class="box-title"
          >
            Competición
          </h2>
          <template v-if="competition">
            <!-- Con más de una, se elige; con una, su nombre lleva a su jornada y clasificación (§3.4). -->
            <Select
              v-if="competitions.length > 1"
              :options="competitionOptions"
              option-label="label"
              option-value="value"
              :model-value="chosenId"
              aria-labelledby="competition-title"
              @update:model-value="chooseCompetition"
            />
            <p class="competition">
              <RouterLink :to="competitionPath(state.season.label, competition.id)">
                {{ competitions.length > 1 ? 'Jornada y clasificación' : competitionLabel(competition) }}
              </RouterLink>
            </p>
            <div class="ingestion">
              <div>
                <HealthStatus
                  :health="health?.health"
                  :name="health?.healthName"
                  :previous-failed="health?.previousFailed ?? false"
                />
              </div>
              <IconAction
                class="relaunch"
                label="Volver a traer los datos de la Federación"
                :subject="competitionLabel(competition)"
                icon="rotate-cw"
                :disabled="health?.health === 'pending'"
                @press="relaunch(competition.id, competitionLabel(competition))"
              />
            </div>
          </template>
          <!-- Inscrito sin sincronizar: nada que enseñar ni que traer; lo que hay que hacer. -->
          <template v-else>
            <p class="competition">
              Sin competición
            </p>
            <p>
              <RouterLink :to="syncTarget">
                Sincronizar con la Federación
              </RouterLink>
            </p>
          </template>
        </section>

        <section
          class="box"
          aria-labelledby="position-title"
        >
          <h2
            id="position-title"
            class="box-title"
          >
            Posición
          </h2>
          <p
            v-if="position.kind === 'loading'"
            role="status"
          >
            Cargando…
          </p>
          <template v-else-if="position.kind === 'found'">
            <p class="figure">
              {{ position.position }}º
            </p>
            <p class="detail">
              de {{ position.of }} · tras la jornada {{ position.round }}
            </p>
          </template>
          <template v-else>
            <p class="figure">
              —
            </p>
            <p
              v-if="competition"
              class="detail"
            >
              aún no se ha jugado
            </p>
          </template>
        </section>
      </template>
    </div>

    <!-- La pestaña Resultados (§3.3), la única por ahora: las demás llegan con sus rebanadas (decisión 5). Sus datos
         son de la Federación: no se crean, ni se editan, ni se borran (LLD-B §7.5). -->
    <template v-if="state.kind === 'ready'">
      <div class="tabs">
        <nav aria-label="Secciones del equipo">
          <RouterLink
            :to="resultsPath(state.season.label, teamId)"
            class="tab"
          >
            Resultados
          </RouterLink>
        </nav>
        <span class="source">Federación</span>
      </div>

      <p
        v-if="matches.kind === 'loading'"
        role="status"
      >
        Cargando partidos…
      </p>
      <LoadError
        v-else-if="matches.kind === 'error'"
        :message="matches.error.message"
        :code="matches.error.code"
        :retry="matches.error.retry"
        @retry="reloadMatches"
      />
      <div
        v-else-if="!competition"
        class="empty"
      >
        <p>Este equipo aún no tiene partidos.</p>
        <p>
          <RouterLink :to="syncTarget">
            Sincronizar con la Federación
          </RouterLink>
        </p>
      </div>
      <p
        v-else-if="rows.length === 0"
        class="empty"
      >
        {{
          health?.health === 'pending'
            ? 'Trayendo el calendario de la Federación…'
            : 'La Federación aún no ha publicado partidos de este equipo.'
        }}
      </p>
      <MatchesTable
        v-else
        :rows="rows"
        :caption="`Partidos de ${heading?.title} en la temporada ${state.season.label}`"
        :season-label="state.season.label"
      />
    </template>

    <NoticeBox
      v-if="state.kind === 'notPlaying'"
      kind="info"
    >
      <p>{{ notPlayingText(state.team, state.season.label) }}</p>
    </NoticeBox>
    <LoadError
      v-else-if="state.kind === 'unknownSeason'"
      :message="`No hay ninguna temporada ${state.asked}`"
      :retry="false"
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
.banner {
  margin-bottom: 1rem;
}
/* Las tres cajas en una fila; en una pantalla estrecha, una debajo de otra. */
.boxes {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
  gap: 1rem;
  margin-bottom: 1rem;
}
.box {
  padding: 0.875rem 1rem;
  border: 1px solid var(--p-content-border-color);
  border-radius: var(--p-content-border-radius);
  background: var(--p-content-background);
}
.box p {
  margin: 0;
}
.box p + p,
.box .competition {
  margin-top: 0.375rem;
}
/* El título de cada caja, pequeño: lo que importa es lo que dice. La etiqueta del selector de temporada hace de
   título en la suya. */
.box-title,
.season :deep(label) {
  margin: 0 0 0.5rem;
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--p-text-muted-color);
}
.season :deep(.season-picker) {
  flex-direction: column;
  align-items: flex-start;
}
.competition {
  font-weight: 600;
}
.ingestion {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  margin-top: 0.25rem;
}
.figure {
  font-size: 2rem;
  font-weight: 700;
  line-height: 1.1;
}
.detail {
  color: var(--p-text-muted-color);
}
/* La barra de pestañas, con una sola; y a la derecha, de dónde vienen los datos. */
.tabs {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-bottom: 0.75rem;
  border-bottom: 1px solid var(--p-content-border-color);
}
.tab {
  display: inline-block;
  padding: 0.5rem 0.25rem;
  color: var(--p-text-color);
  font-weight: 600;
  text-decoration: none;
}
/* La pestaña abierta: subrayada con el principal y en negrita, no solo de color (LLD-B §9.4). */
.tab[aria-current='page'] {
  border-bottom: 3px solid var(--p-primary-color);
  margin-bottom: -1px;
}
.source {
  margin-bottom: 0.375rem;
  padding: 0.125rem 0.5rem;
  border: 1px solid var(--p-content-border-color);
  border-radius: 999px;
  font-size: 0.8125rem;
  color: var(--p-text-muted-color);
}
.empty p {
  margin: 0 0 0.375rem;
}
</style>
