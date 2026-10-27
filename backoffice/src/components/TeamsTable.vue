<!-- La tabla de la portada: los equipos de una temporada, con su competición y cómo va su ingesta (plan R1, §3.2).
     Un equipo con dos competiciones ocupa dos líneas, con su nombre y sus acciones una sola vez (rowspan). -->
<script setup lang="ts">
import RowAction from './RowAction.vue'
import SortableHeader from './SortableHeader.vue'
import type { HealthState, TeamRow } from './teamRow'

// `order`, por qué columna está ordenada y si al revés; sin él, el orden del servidor. Las filas llegan ya
// ordenadas: la tabla solo dice cómo, y avisa de qué cabecera pinchan (bloque T del plan R2). `seasonLabel`, la
// temporada que se está viendo, para que la pantalla a la que lleva una acción sepa volver a ella.
const props = defineProps<{
  rows: TeamRow[]
  caption: string
  order?: { column: string; reversed: boolean }
  seasonLabel?: string
}>()
defineEmits<{ sort: [column: string] }>()

// Las columnas, con su nombre en la dirección (`?orden=ingesta`) y el que se ve.
const columns = [
  { column: 'equipo', label: 'Equipo' },
  { column: 'competicion', label: 'Competición' },
  { column: 'ingesta', label: 'Ingesta' },
  { column: 'sincronizacion', label: 'Última sincronización' },
]

function sortOf(column: string): 'ascending' | 'descending' | undefined {
  if (props.order?.column !== column) return undefined
  return props.order.reversed ? 'descending' : 'ascending'
}

// Cada estado, con su icono y su color. Nunca solo el color: la palabra va siempre al lado (LLD-B §9.4).
const icons: Record<HealthState, string> = { ok: '✓', failing: '✕', pending: '↻', stale: '◷', never: '○' }

// Sincronizar: lo que dice depende de si el equipo ya tiene competición en la temporada (plan R3, decisión 1). La
// temporada va en el estado de la navegación, no en la dirección, como al dar de alta (plan R2, decisión 5).
function syncLabel(row: TeamRow): string {
  return row.competitions.length === 0 ? 'Sincronizar con la Federación' : 'Sincronizar otra competición'
}
function syncTarget(row: TeamRow) {
  return { path: `/equipos/${row.id}/federacion`, state: props.seasonLabel ? { seasonLabel: props.seasonLabel } : {} }
}
</script>

<template>
  <table class="teams">
    <caption class="visually-hidden">
      {{ caption }}
    </caption>
    <thead>
      <tr>
        <SortableHeader
          v-for="header in columns"
          :key="header.column"
          :label="header.label"
          :sort="sortOf(header.column)"
          @sort="$emit('sort', header.column)"
        />
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
            {{ row.team }}
          </th>
          <td colspan="3">
            Sin competición
            <!-- Es el caso que más lo pide: además del icono, el enlace con su texto (LLD-B §3.7). -->
            <span class="note">
              <RouterLink :to="syncTarget(row)">Sincronizar con la Federación</RouterLink>
            </span>
          </td>
          <td class="actions">
            <RowAction
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
            {{ row.team }}
          </th>
          <td>{{ competition.name }}</td>
          <td>
            <span
              v-if="competition.health"
              class="health"
            >
              <span
                aria-hidden="true"
                :class="['icon', competition.health]"
              >{{ icons[competition.health] }}</span>
              <span>{{ competition.healthName }}</span>
            </span>
            <span
              v-if="competition.previousFailed"
              class="note"
            >
              <span
                aria-hidden="true"
                class="icon failing"
              >{{ icons.failing }}</span>
              <span>La anterior tuvo fallos</span>
            </span>
          </td>
          <td>{{ competition.lastSynced }}</td>
          <td
            v-if="index === 0"
            class="actions"
            :rowspan="row.competitions.length"
          >
            <RowAction
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
/* El icono, de 40 px, ocupa casi toda la altura de la fila. */
.actions {
  width: 1px;
  padding: 0.125rem 0.375rem;
  white-space: nowrap;
}
.note {
  display: block;
  margin-top: 0.25rem;
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
/* «Sincronizar con la Federación», bajo «Sin competición»: del color de los enlaces del tema, no el azul del
   navegador, y 24 px de alto como mínimo, como en FormErrorList (WCAG 2.5.8). */
.note a {
  display: inline-block;
  min-height: 1.5rem;
  line-height: 1.5rem;
  color: var(--p-primary-color);
}
.icon {
  display: inline-block;
  width: 1.25em;
  font-weight: 700;
}
.ok {
  color: var(--p-estado-bien);
}
.failing {
  color: var(--p-estado-fallo);
}
.pending {
  color: var(--p-estado-en-marcha);
}
.stale {
  color: var(--p-estado-aviso);
}
.never {
  color: var(--p-estado-sin-datos);
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
