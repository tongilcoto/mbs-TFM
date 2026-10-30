<!-- La clasificación tras una jornada (plan R4, §3.4): Pos., Equipo, J, G, E, P, GF, GC, DG, Pts, Ant. y Racha. La
     fila del club, resaltada. Ant., el puesto anterior con una flecha de cuánto subió o bajó. La racha, un cuadro por
     partido con el número de su jornada sobre el color del resultado, el más reciente a la izquierda. -->
<script setup lang="ts">
import type { StandingLine } from './round'

defineProps<{ lines: StandingLine[]; caption: string }>()

// Las columnas de números: la abreviatura que se ve y lo que lee el lector.
const numbers = [
  { key: 'played', short: 'J', long: 'Jugados' },
  { key: 'won', short: 'G', long: 'Ganados' },
  { key: 'drawn', short: 'E', long: 'Empatados' },
  { key: 'lost', short: 'P', long: 'Perdidos' },
  { key: 'goalsFor', short: 'GF', long: 'Goles a favor' },
  { key: 'goalsAgainst', short: 'GC', long: 'Goles en contra' },
  { key: 'goalDifference', short: 'DG', long: 'Diferencia de goles' },
] as const

function changeText(change: number): string {
  if (change > 0) return `subió ${change}`
  if (change < 0) return `bajó ${-change}`
  return 'igual'
}
</script>

<template>
  <table class="standing">
    <caption class="visually-hidden">
      {{ caption }}
    </caption>
    <thead>
      <tr>
        <th
          scope="col"
          class="number"
        >
          <abbr title="Puesto">Pos.</abbr>
        </th>
        <th scope="col">
          Equipo
        </th>
        <th
          v-for="column in numbers"
          :key="column.key"
          scope="col"
          class="number"
        >
          <abbr :title="column.long">{{ column.short }}</abbr>
        </th>
        <th
          scope="col"
          class="number"
        >
          <abbr title="Puntos">Pts</abbr>
        </th>
        <th
          scope="col"
          class="number"
        >
          <abbr title="Puesto anterior">Ant.</abbr>
        </th>
        <th scope="col">
          Racha
        </th>
      </tr>
    </thead>
    <tbody>
      <tr
        v-for="line in lines"
        :key="line.position"
        :class="{ own: line.own }"
      >
        <td class="number strong">
          {{ line.position }}
        </td>
        <th
          scope="row"
          class="team"
        >
          {{ line.name }}
        </th>
        <td
          v-for="column in numbers"
          :key="column.key"
          class="number"
        >
          {{ line[column.key] }}
        </td>
        <td class="number strong">
          {{ line.points }}
        </td>
        <td class="number previous">
          <template v-if="line.previous">
            {{ line.previous.position }}
            <!-- La flecha y su número no se leen tal cual: el lector oye «subió 2». -->
            <span
              aria-hidden="true"
              :class="['change', line.previous.change > 0 ? 'up' : line.previous.change < 0 ? 'down' : 'same']"
            >{{ line.previous.change > 0 ? `▲${line.previous.change}` : line.previous.change < 0 ? `▼${-line.previous.change}` : '=' }}</span>
            <span class="visually-hidden">, {{ changeText(line.previous.change) }}</span>
          </template>
          <span
            v-else
            class="muted"
          >–</span>
        </td>
        <td>
          <ol class="form">
            <li
              v-for="box in line.form"
              :key="box.round"
              :class="['box', box.outcome]"
              :title="box.label"
            >
              <span aria-hidden="true">{{ box.round }}</span>
              <span class="visually-hidden">{{ box.label }}</span>
            </li>
          </ol>
        </td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.standing {
  width: 100%;
  border-collapse: collapse;
  background: var(--p-content-background);
  font-size: 0.9375rem;
}
th,
td {
  padding: 0.4375rem 0.5rem;
  text-align: left;
  vertical-align: middle;
  border-bottom: 1px solid var(--p-content-border-color);
}
thead th {
  font-size: 0.8125rem;
  color: var(--p-text-muted-color);
  white-space: nowrap;
}
abbr {
  text-decoration: none;
}
.team {
  font-weight: 400;
}
.number {
  width: 1px;
  text-align: right;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.strong {
  font-weight: 700;
}
/* La fila del club: el fondo de lo que se señala, y en negrita. */
.own td,
.own th {
  background: var(--p-content-hover-background);
  font-weight: 700;
}
.muted {
  color: var(--p-text-muted-color);
}
.change {
  display: inline-block;
  min-width: 2rem;
  margin-left: 0.25rem;
  font-size: 0.75rem;
  font-weight: 700;
  text-align: left;
}
.up {
  color: var(--p-estado-bien);
}
.down {
  color: var(--p-estado-fallo);
}
.same {
  color: var(--p-text-muted-color);
}
.form {
  display: flex;
  gap: 0.25rem;
  margin: 0;
  padding: 0;
  list-style: none;
}
/* Cada partido, el número de su jornada sobre el color del resultado, en los dos modos. */
.box {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.625rem;
  height: 1.5rem;
  border-radius: 0.25rem;
  font-size: 0.75rem;
  font-weight: 800;
  color: var(--p-content-background);
}
.victoria {
  background: var(--p-estado-bien);
}
.empate {
  background: var(--p-estado-sin-datos);
}
.derrota {
  background: var(--p-estado-fallo);
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
