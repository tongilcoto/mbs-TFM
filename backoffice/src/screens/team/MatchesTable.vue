<!-- La tabla de la pestaña Resultados: un partido por fila, en orden de jornada (plan R4, §3.3 y decisión 6). A la
     derecha, sin título de grupo, la línea del equipo tras la jornada, solo en los jugados; y ☰, que lleva a esa
     jornada en la pantalla de su competición. -->
<script setup lang="ts">
import IconAction from '../../components/IconAction.vue'
import { competitionPath } from './header'
import type { MatchRow } from './matches'

const props = defineProps<{ rows: MatchRow[]; caption: string; seasonLabel: string }>()

// Las columnas de la derecha: la abreviatura que se ve y lo que lee el lector.
const lineColumns = [
  { short: 'Pos.', long: 'Puesto' },
  { short: 'Pts', long: 'Puntos' },
  { short: 'G', long: 'Ganados' },
  { short: 'E', long: 'Empatados' },
  { short: 'P', long: 'Perdidos' },
  { short: 'DG', long: 'Diferencia de goles' },
]

const outcomeNames = { V: 'Victoria', E: 'Empate', D: 'Derrota' }

function roundTarget(row: MatchRow) {
  return { path: competitionPath(props.seasonLabel, row.competitionId), query: { jornada: String(row.round) } }
}
</script>

<template>
  <table class="matches">
    <caption class="visually-hidden">
      {{ caption }}
    </caption>
    <thead>
      <tr>
        <th scope="col">
          <abbr title="Jornada">J</abbr>
        </th>
        <th scope="col">
          Fecha
        </th>
        <th scope="col">
          Local
        </th>
        <th
          scope="col"
          class="center"
        >
          Resultado
        </th>
        <th scope="col">
          Visitante
        </th>
        <!-- Sin título a la vista: la letra en su cuadro ya se entiende. El lector sí lo lee. -->
        <th scope="col">
          <span class="visually-hidden">Resultado del equipo</span>
        </th>
        <th
          v-for="column in lineColumns"
          :key="column.short"
          scope="col"
          class="number"
        >
          <abbr :title="column.long">{{ column.short }}</abbr>
        </th>
        <th scope="col">
          <span class="visually-hidden">Acciones</span>
        </th>
      </tr>
    </thead>
    <tbody>
      <tr
        v-for="row in rows"
        :key="row.id"
      >
        <td class="number">
          {{ row.round }}
        </td>
        <td class="date">
          {{ row.date }}
        </td>
        <!-- En espejo: el puesto del local a su izquierda y el del visitante a su derecha. -->
        <td :class="['team', 'home', { own: row.home.own }]">
          <span
            v-if="row.home.position"
            class="position"
          >{{ row.home.position }}º</span>
          <span>{{ row.home.name }}</span>
        </td>
        <td class="result center">
          <template v-if="row.result.kind === 'score' || row.result.kind === 'time'">
            {{ row.result.text }}
          </template>
          <span
            v-else-if="row.result.kind === 'unset'"
            class="muted"
          >por fijar</span>
          <span
            v-else-if="row.result.kind === 'postponed'"
            class="postponed"
          >Aplazado</span>
          <template v-else>
            <span
              v-if="row.result.text"
              class="muted"
            >{{ row.result.text }}</span>
            <span class="suspended">Suspendido</span>
          </template>
        </td>
        <td :class="['team', 'away', { own: row.away.own }]">
          <span>{{ row.away.name }}</span>
          <span
            v-if="row.away.position"
            class="position"
          >{{ row.away.position }}º</span>
        </td>
        <td>
          <!-- La letra, siempre: el color no es lo único que lo dice (LLD-B §9.4). -->
          <abbr
            v-if="row.outcome"
            :class="['outcome', row.outcome]"
            :title="outcomeNames[row.outcome]"
          >{{ row.outcome }}</abbr>
        </td>
        <template v-if="row.line">
          <td class="number strong">
            {{ row.line.position }}º
          </td>
          <td class="number strong">
            {{ row.line.points }}
          </td>
          <td class="number">
            {{ row.line.won }}
          </td>
          <td class="number">
            {{ row.line.drawn }}
          </td>
          <td class="number">
            {{ row.line.lost }}
          </td>
          <td class="number">
            {{ row.line.goalDifference }}
          </td>
        </template>
        <td
          v-else
          :colspan="lineColumns.length"
        />
        <td class="actions">
          <IconAction
            :label="`Ver la jornada ${row.round} y la clasificación`"
            icon="list"
            :to="roundTarget(row)"
          />
        </td>
      </tr>
    </tbody>
  </table>
</template>

<style scoped>
.matches {
  width: 100%;
  border-collapse: collapse;
  background: var(--p-content-background);
  font-size: 0.9375rem;
}
th,
td {
  padding: 0.375rem 0.5rem;
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
.number {
  width: 1px;
  text-align: right;
  white-space: nowrap;
  font-variant-numeric: tabular-nums;
}
.center {
  text-align: center;
}
.date {
  white-space: nowrap;
}
.team.home {
  text-align: right;
}
/* El de la ficha, resaltado. */
.own {
  font-weight: 700;
}
.position {
  font-size: 0.8125rem;
  font-weight: 400;
  color: var(--p-text-muted-color);
}
.away .position {
  margin-left: 0.375rem;
}
.home .position {
  margin-right: 0.375rem;
}
.result {
  white-space: nowrap;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.muted {
  font-weight: 400;
  color: var(--p-text-muted-color);
}
.postponed {
  color: var(--p-estado-aviso);
}
.suspended {
  display: block;
  font-size: 0.8125rem;
  color: var(--p-estado-fallo);
}
.strong {
  font-weight: 700;
}
/* V, E o D en su cuadro: verde, gris y rojo, con el texto del color del fondo para que se lea en los dos modos. */
.outcome {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: 0.25rem;
  font-size: 0.8125rem;
  font-weight: 800;
  color: var(--p-content-background);
}
.V {
  background: var(--p-estado-bien);
}
.E {
  background: var(--p-estado-sin-datos);
}
.D {
  background: var(--p-estado-fallo);
}
/* El icono, de 40 px, ocupa casi toda la altura de la fila. */
.actions {
  width: 1px;
  padding: 0.125rem 0.375rem;
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
