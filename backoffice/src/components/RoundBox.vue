<!-- Una jornada, con su número sobre el color del resultado del equipo, como cada cuadro de la racha (StreakBoxes,
     DW-23): en la caja Posición de la ficha, «tras la jornada [8]» (R6.19f). El color es lo único que dice el resultado a
     la vista; el lector lee el número y el resultado («8, victoria»), y el ratón lo enseña entero. -->
<script setup lang="ts">
import type { StreakBox } from './streak'

defineProps<{ box: StreakBox }>()
</script>

<template>
  <span
    :class="['round-box', box.outcome]"
    :title="box.label"
  >
    <span aria-hidden="true">{{ box.round }}</span>
    <span class="visually-hidden">{{ box.round }}, {{ box.outcome }}</span>
  </span>
</template>

<style scoped>
/* Como los cuadros de la racha (StreakBoxes.vue), con los mismos colores en los dos modos. `round-box` y no `box`: la
   ficha tiene su propio `.box`, el de sus cajas, que alcanzaría a la raíz de esta pieza. */
.round-box {
  box-sizing: border-box;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.625rem;
  height: 1.5rem;
  border-radius: 0.25rem;
  font-size: 0.75rem;
  font-weight: 800;
  color: var(--p-content-background);
  vertical-align: middle;
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
.descanso {
  border: 1px solid var(--p-estado-sin-datos);
  background: transparent;
  color: var(--p-text-color);
}
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}
</style>
