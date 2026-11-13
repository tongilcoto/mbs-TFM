<!-- La racha (plan R5, decisión 3 · DW-23): un cuadro por jornada con su número sobre el color del resultado, la más
     reciente a la izquierda. El descanso (D-114), un cuadro vacío: solo el borde y su número. La usan la clasificación
     (R4.13) y la portada (R5.8). `to`, adónde lleva cada cuadro: solo en la portada (decisión 6); en la clasificación ya
     se está en la competición, y el texto sale con `title` al pasar el ratón. -->
<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'
import StreakLink from './StreakLink.vue'
import type { StreakBox } from './streak'

defineProps<{ boxes: StreakBox[]; to?: (round: number) => RouteLocationRaw }>()
</script>

<template>
  <ol class="streak">
    <li
      v-for="box in boxes"
      :key="box.round"
      :class="['box', box.outcome]"
      :title="to ? undefined : box.label"
    >
      <StreakLink
        v-if="to"
        :round="box.round"
        :label="box.label"
        :to="to(box.round)"
      />
      <template v-else>
        <span aria-hidden="true">{{ box.round }}</span>
        <span class="visually-hidden">{{ box.label }}</span>
      </template>
    </li>
  </ol>
</template>

<style scoped>
.streak {
  display: flex;
  gap: 0.25rem;
  margin: 0;
  padding: 0;
  list-style: none;
}
/* Cada jornada, el número sobre el color del resultado, en los dos modos. */
.box {
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
/* El descanso, vacío: el borde gris del empate y el número del color del texto. */
.descanso {
  border: 1px solid var(--p-estado-sin-datos);
  background: transparent;
  color: var(--p-text-color);
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
