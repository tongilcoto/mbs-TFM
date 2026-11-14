<!-- Un cuadro de la racha que lleva a su jornada (plan R5, decisión 6), dentro de StreakBoxes: el número a la vista,
     «Victoria en la jornada 7» para el lector, y lo mismo al pasar el ratón y al llegar con el teclado (tip.ts). -->
<script setup lang="ts">
import type { RouteLocationRaw } from 'vue-router'
import TipBubble from './TipBubble.vue'
import { useTip } from './tip'

defineProps<{ round: number; label: string; to: RouteLocationRaw }>()

const tip = useTip()
</script>

<template>
  <span
    class="streak-link"
    @pointerenter="tip.hover"
    @pointerleave="tip.leave"
  >
    <RouterLink
      :to="to"
      class="target"
      @focus="tip.focus"
      @blur="tip.blur"
    >
      <span aria-hidden="true">{{ round }}</span>
      <span class="visually-hidden">{{ label }}</span>
    </RouterLink>
    <TipBubble
      v-if="tip.shown.value"
      :text="label"
    />
  </span>
</template>

<style scoped>
.streak-link {
  position: relative;
  display: flex;
  width: 100%;
  height: 100%;
}
/* El cuadro entero es el enlace, del color del número. */
.target {
  display: flex;
  flex: 1;
  align-items: center;
  justify-content: center;
  border-radius: inherit;
  color: inherit;
  text-decoration: none;
}
.target:hover {
  text-decoration: underline;
}
.target:focus-visible {
  outline: 2px solid var(--p-primary-color);
  outline-offset: 2px;
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
