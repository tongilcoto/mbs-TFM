<!-- Los partidos de una jornada (plan R4, §3.4): fecha, hora, local, resultado y visitante, con los estados de partido
     de Resultados. El del club, resaltado; el descanso de un grupo impar, apagado (D-105). -->
<script setup lang="ts">
import ScrollBox from '../../components/ScrollBox.vue'
import type { RoundMatchRow } from './round'

defineProps<{ rows: RoundMatchRow[]; caption: string }>()
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
            Fecha
          </th>
          <th scope="col">
            Hora
          </th>
          <th
            scope="col"
            class="home"
          >
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
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="row.id"
          :class="{ own: row.own, rest: row.rest }"
        >
          <td class="nowrap">
            {{ row.date }}
          </td>
          <td class="nowrap">
            <template v-if="row.time">
              {{ row.time }}
            </template>
            <span
              v-else
              class="muted"
            >por fijar</span>
          </td>
          <td :class="['home', { strong: row.home.own }]">
            {{ row.home.name }}
          </td>
          <td class="result center">
            <template v-if="row.result?.kind === 'score'">
              {{ row.result.text }}
            </template>
            <span
              v-else-if="row.result?.kind === 'postponed'"
              class="postponed"
            >Aplazado</span>
            <template v-else-if="row.result?.kind === 'suspended'">
              <span
                v-if="row.result.text"
                class="muted"
              >{{ row.result.text }}</span>
              <span class="suspended">Suspendido</span>
            </template>
          </td>
          <td :class="{ strong: row.away.own }">
            {{ row.away.name }}
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
  padding: 0.5rem;
  text-align: left;
  vertical-align: middle;
  border-bottom: 1px solid var(--p-content-border-color);
}
thead th {
  font-size: 0.8125rem;
  color: var(--p-text-muted-color);
}
.home {
  text-align: right;
}
.center {
  text-align: center;
}
.nowrap {
  width: 1px;
  white-space: nowrap;
}
.result {
  white-space: nowrap;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
/* El partido del club: el fondo de la página, una barra del principal a la izquierda y su equipo en negrita. El
   fondo de «señalado» de PrimeVue deja el texto suave por debajo de 4,5 de contraste en los dos modos (R4.14, axe). */
.own td {
  background: var(--p-fondo);
}
.own td:first-child {
  box-shadow: inset 3px 0 0 var(--p-primary-color);
}
.strong {
  font-weight: 700;
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
/* El descanso, apagado, como en Resultados. */
.rest td {
  background: var(--p-fondo);
  color: var(--p-text-muted-color);
  font-style: italic;
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
