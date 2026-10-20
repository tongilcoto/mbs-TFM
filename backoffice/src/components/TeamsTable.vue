<!-- La tabla de la portada: los equipos de una temporada, con su competición y cómo va su ingesta (plan R1, §3.2).
     Un equipo con dos competiciones ocupa dos líneas, con su nombre una sola vez (rowspan). -->
<script setup lang="ts">
import type { HealthState, TeamRow } from './teamRow'

defineProps<{ rows: TeamRow[]; caption: string }>()

// Cada estado, con su icono y su color. Nunca solo el color: la palabra va siempre al lado (LLD-B §9.4).
const icons: Record<HealthState, string> = { ok: '✓', failing: '✕', pending: '↻', stale: '◷', never: '○' }
</script>

<template>
  <table class="teams">
    <caption class="visually-hidden">
      {{ caption }}
    </caption>
    <thead>
      <tr>
        <th scope="col">
          Equipo
        </th>
        <th scope="col">
          Competición
        </th>
        <th scope="col">
          Ingesta
        </th>
        <th scope="col">
          Última sincronización
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
            <span class="note">Se engancha con la federación desde la ficha del equipo</span>
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
.note {
  display: block;
  margin-top: 0.25rem;
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
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
