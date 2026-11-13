<!-- La tabla de la pestaña Resultados: un partido por fila, en orden de jornada (plan R4, §3.3 y decisión 6). A la
     derecha, sin título de grupo, la línea del equipo tras la jornada, solo en los jugados; y ☰, que lleva a esa
     jornada en la pantalla de su competición. -->
<script setup lang="ts">
import ScrollBox from '../../components/ScrollBox.vue'
import IconAction from '../../components/IconAction.vue'
import OutcomeLetter from '../../components/OutcomeLetter.vue'
import PositionBadge from '../../components/PositionBadge.vue'
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


function roundTarget(row: MatchRow) {
  return { path: competitionPath(props.seasonLabel, row.competitionId), query: { jornada: String(row.round) } }
}
</script>

<template>
  <ScrollBox :label="caption">
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
          :class="{ rest: row.rest }"
        >
          <td class="number">
            {{ row.round }}
          </td>
          <td class="date">
            {{ row.date }}
          </td>
          <!-- El puesto, a la izquierda del nombre en los dos equipos, en su óvalo. -->
          <td :class="['team', 'home', { own: row.home.own }]">
            <div class="side">
              <PositionBadge
                v-if="row.home.position"
                :position="row.home.position"
              />
              <span>{{ row.home.name }}</span>
            </div>
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
            <div class="side">
              <PositionBadge
                v-if="row.away.position"
                :position="row.away.position"
              />
              <span>{{ row.away.name }}</span>
            </div>
          </td>
          <td>
            <OutcomeLetter
              v-if="row.outcome"
              :outcome="row.outcome"
            />
          </td>
          <template v-if="row.line">
            <!-- El puesto tras la jornada, en el mismo óvalo que el de los equipos. -->
            <td class="number">
              <PositionBadge :position="row.line.position" />
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
  </ScrollBox>
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
/* El óvalo junto al nombre entero: si el nombre parte en dos líneas, las dos van a su derecha. */
.side {
  display: flex;
  align-items: flex-start;
}
.home .side {
  justify-content: flex-end;
}
/* El óvalo, a un paso del nombre. */
.side .position-badge {
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
/* La jornada de descanso, apagada: el fondo de la página, el texto suave y en cursiva. Los textos, los mismos. */
.rest td {
  background: var(--p-fondo);
  color: var(--p-text-muted-color);
  font-style: italic;
}
.rest .own {
  font-weight: 400;
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
