<!-- La tabla de la portada: los equipos de una temporada, con su competición y cómo va su ingesta (plan R1, §3.2), y
     cómo le va en ella: su posición, su racha, su último partido y el próximo (plan R5, §3).
     Un equipo con dos competiciones ocupa dos líneas, con su nombre y sus acciones una sola vez (rowspan). -->
<script setup lang="ts">
import HealthStatus from './HealthStatus.vue'
import IconAction from './IconAction.vue'
import OutcomeLetter from './OutcomeLetter.vue'
import PositionBadge from './PositionBadge.vue'
import SortableHeader from './SortableHeader.vue'
import StreakBoxes from './StreakBoxes.vue'
import VenueIcon from './VenueIcon.vue'
import type { CompetitionCell, TeamRow } from './teamRow'

// `order`, por qué columna está ordenada y si al revés; sin él, el orden del servidor. Las filas llegan ya
// ordenadas: la tabla solo dice cómo, y avisa de qué cabecera pinchan (bloque T del plan R2). `seasonLabel`, la
// temporada que se está viendo, para que la pantalla a la que lleva una acción sepa volver a ella; y
// `seasonAddress`, la misma como va en la dirección («2026-27»), para el enlace a la ficha de cada equipo.
const props = defineProps<{
  rows: TeamRow[]
  caption: string
  order?: { column: string; reversed: boolean }
  seasonLabel?: string
  seasonAddress?: string
}>()
// `relaunch`, volver a traer los datos de una competición (plan R4, decisión 7): lo hace la portada.
defineEmits<{ sort: [column: string]; relaunch: [competitionId: string] }>()

// Las columnas, con su nombre en la dirección (`?orden=ingesta`) y el que se ve. Sin nombre en la dirección, no se
// ordena por ella: la racha, el último y el próximo (plan R5, §6).
const columns = [
  { column: 'equipo', label: 'Equipo' },
  { column: 'competicion', label: 'Competición' },
  { column: 'posicion', label: 'Posición' },
  { column: undefined, label: 'Racha' },
  { column: undefined, label: 'Último' },
  { column: undefined, label: 'Próximo' },
  { column: 'ingesta', label: 'Ingesta' },
  { column: 'sincronizacion', label: 'Última sincronización' },
]

function sortOf(column: string): 'ascending' | 'descending' | undefined {
  if (props.order?.column !== column) return undefined
  return props.order.reversed ? 'descending' : 'ascending'
}

// Sincronizar: lo que dice depende de si el equipo ya tiene competición en la temporada (plan R3, decisión 1). La
// temporada va en el estado de la navegación, no en la dirección, como al dar de alta (plan R2, decisión 5).
function syncLabel(row: TeamRow): string {
  return row.competitions.length === 0 ? 'Sincronizar con la Federación' : 'Sincronizar otra competición'
}
function syncTarget(row: TeamRow) {
  return { path: `/equipos/${row.id}/federacion`, state: props.seasonLabel ? { seasonLabel: props.seasonLabel } : {} }
}

// El nombre del equipo lleva a su ficha, en la temporada que se ve (plan R4, §3.1; LLD-B §6.5).
function resultsTarget(row: TeamRow): string | undefined {
  return props.seasonAddress && `/temporadas/${props.seasonAddress}/equipos/${row.id}/resultados`
}

// Cada cuadro de la racha y el próximo partido llevan a su jornada, con su clasificación (plan R5, decisión 6).
function roundTarget(competition: CompetitionCell): ((round: number) => string) | undefined {
  const season = props.seasonAddress
  return season ? (round) => `/temporadas/${season}/competiciones/${competition.id}?jornada=${round}` : undefined
}
</script>

<template>
  <table class="teams">
    <caption class="visually-hidden">
      {{ caption }}
    </caption>
    <thead>
      <tr>
        <template
          v-for="header in columns"
          :key="header.label"
        >
          <SortableHeader
            v-if="header.column"
            :label="header.label"
            :sort="sortOf(header.column)"
            @sort="$emit('sort', header.column)"
          />
          <th
            v-else
            scope="col"
          >
            {{ header.label }}
          </th>
        </template>
        <!-- No se ordena, y no se ve: los iconos dicen lo que hacen. El lector sí la lee (LLD-B §3.7). -->
        <th scope="col">
          <span class="visually-hidden">Acciones</span>
        </th>
      </tr>
    </thead>
    <tbody>
      <template
        v-for="row in rows"
        :key="row.id"
      >
        <tr v-if="row.competitions.length === 0">
          <th scope="row">
            <RouterLink
              v-if="resultsTarget(row)"
              :to="resultsTarget(row)!"
            >
              {{ row.team }}
            </RouterLink>
            <template v-else>
              {{ row.team }}
            </template>
          </th>
          <td colspan="7">
            Sin competición
            <!-- Es el caso que más lo pide: además del icono, el enlace con su texto (LLD-B §3.7). -->
            <span class="note">
              <RouterLink :to="syncTarget(row)">Sincronizar con la Federación</RouterLink>
            </span>
          </td>
          <td class="actions">
            <IconAction
              :label="syncLabel(row)"
              :subject="row.team"
              icon="link"
              :to="syncTarget(row)"
            />
          </td>
        </tr>
        <tr
          v-for="(competition, index) in row.competitions"
          :key="`${row.id}-${index}`"
        >
          <th
            v-if="index === 0"
            scope="row"
            :rowspan="row.competitions.length"
          >
            <RouterLink
              v-if="resultsTarget(row)"
              :to="resultsTarget(row)!"
            >
              {{ row.team }}
            </RouterLink>
            <template v-else>
              {{ row.team }}
            </template>
          </th>
          <td>{{ competition.name }}</td>
          <td>
            <PositionBadge
              v-if="competition.summary.position"
              :position="competition.summary.position"
            />
            <span
              v-else
              class="muted"
            >–</span>
          </td>
          <td>
            <StreakBoxes
              v-if="competition.summary.streak.length > 0"
              :boxes="competition.summary.streak"
              :to="roundTarget(competition)"
            />
            <span
              v-else
              class="muted"
            >–</span>
          </td>
          <td>
            <!-- La letra, casa o fuera, el marcador con el local primero y el rival con el puesto con el que llegó
                 (decisión 5). No lleva a ningún sitio: su jornada es la del cuadro más reciente de la racha. -->
            <div
              v-if="competition.summary.last"
              class="match"
            >
              <OutcomeLetter :outcome="competition.summary.last.outcome" />
              <VenueIcon :at-home="competition.summary.last.atHome" />
              <span class="score">{{ competition.summary.last.score }}</span>
              <PositionBadge
                v-if="competition.summary.last.opponentPosition"
                :position="competition.summary.last.opponentPosition"
              />
              <span>{{ competition.summary.last.opponent }}</span>
            </div>
            <span
              v-else
              class="muted"
            >–</span>
          </td>
          <td>
            <component
              :is="roundTarget(competition) ? 'RouterLink' : 'span'"
              v-if="competition.summary.next"
              :to="roundTarget(competition)?.(competition.summary.next.round)"
              class="next"
            >
              <template v-if="competition.summary.next.kind === 'rest'">
                Descansa · jornada {{ competition.summary.next.round }}
              </template>
              <!-- El nombre del enlace es su texto, con un espacio de verdad entre cada pieza (`{{ ' ' }}`): sin él,
                   el lector lo oiría todo seguido. Uno aparte no valdría: tiene que contener lo que se ve (WCAG 2.5.3). -->
              <template v-else>
                <span class="when">{{ competition.summary.next.date }}{{ competition.summary.next.time ? ` ${competition.summary.next.time}` : ', hora por fijar' }}</span>{{ ' ' }}
                <span class="match">
                  <VenueIcon :at-home="competition.summary.next.atHome" />{{ ' ' }}
                  <PositionBadge
                    v-if="competition.summary.next.opponentPosition"
                    :position="competition.summary.next.opponentPosition"
                  />{{ ' ' }}
                  <span>{{ competition.summary.next.opponent }}</span>
                </span>
              </template>
            </component>
            <span
              v-else
              class="muted"
            >–</span>
          </td>
          <td>
            <!-- El estado a la izquierda y ↻ a la derecha (plan R4, decisión 7). Bloqueado mientras está «En marcha»:
                 ya se están trayendo. -->
            <div class="ingestion">
              <div>
                <HealthStatus
                  :health="competition.health"
                  :name="competition.healthName"
                  :previous-failed="competition.previousFailed"
                />
              </div>
              <IconAction
                class="relaunch"
                label="Volver a traer los datos de la Federación"
                :subject="competition.name"
                icon="rotate-cw"
                :disabled="competition.health === 'pending'"
                @press="$emit('relaunch', competition.id)"
              />
            </div>
          </td>
          <td>{{ competition.lastSynced }}</td>
          <td
            v-if="index === 0"
            class="actions"
            :rowspan="row.competitions.length"
          >
            <IconAction
              :label="syncLabel(row)"
              :subject="row.team"
              icon="link"
              :to="syncTarget(row)"
            />
          </td>
        </tr>
      </template>
    </tbody>
  </table>
</template>

<style scoped>
.teams {
  width: 100%;
  border-collapse: collapse;
  background: var(--p-content-background);
}
th,
td {
  padding: 0.625rem 0.75rem;
  text-align: left;
  vertical-align: top;
  border-bottom: 1px solid var(--p-content-border-color);
}
thead th {
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
/* El estado y ↻ en la misma línea. El texto, a la altura del de las otras celdas; el icono, de 40 px, centrado con
   su primera línea, sin hacer la fila más alta. */
.ingestion {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 0.5rem;
}
.relaunch {
  margin: -0.5rem 0;
}
/* El icono, de 40 px, ocupa casi toda la altura de la fila. */
.actions {
  width: 1px;
  padding: 0.125rem 0.375rem;
  white-space: nowrap;
}
.muted {
  color: var(--p-text-muted-color);
}
/* Un partido en una línea, que parte en dos si el nombre del rival es largo (decisión 5). */
.match {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.25rem 0.375rem;
  min-width: 10rem;
}
/* El nombre del rival es lo que parte, no lo que baja entero a otra línea. */
.match > span:last-child {
  flex: 1 1 6rem;
  min-width: 0;
}
.score {
  font-weight: 700;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
/* El próximo: el día y la hora encima, y el partido debajo. Todo él es el enlace a su jornada. */
.next {
  display: block;
  color: inherit;
}
a.next {
  text-decoration: none;
}
a.next:hover .match > span:last-child,
a.next:hover .when {
  text-decoration: underline;
}
.when {
  display: block;
  margin-bottom: 0.25rem;
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
  white-space: nowrap;
}
.note {
  display: block;
  margin-top: 0.25rem;
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
/* «Sincronizar con la Federación», bajo «Sin competición»: 24 px de alto como mínimo, como en FormErrorList
   (WCAG 2.5.8). */
.note a {
  display: inline-block;
  min-height: 1.5rem;
  line-height: 1.5rem;
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
