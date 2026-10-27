<!-- Una acción de una fila: un icono que lleva a otra pantalla, con su texto (LLD-B §3.7, plan R3, decisión 1).
     El texto sale al pasar el ratón y al llegar con el teclado, se queda mientras el ratón está encima de él, y
     Escape lo esconde sin mover el foco (WCAG 1.4.13). El `Tooltip` de PrimeVue hace lo uno o lo otro, no los dos.
     El lector de pantalla no necesita el texto: lo lee en el nombre del enlace, con la fila detrás («Sincronizar
     otra competición, Cadete A»), para que diez enlaces iguales se distingan. -->
<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import AppIcon, { type IconName } from './AppIcon.vue'

const props = defineProps<{ label: string; subject: string; icon: IconName; to: RouteLocationRaw }>()

const hovered = ref(false)
const focused = ref(false)
// Escondido con Escape: vuelve a salir al llegar otra vez, con el ratón o con el teclado.
const dismissed = ref(false)
const shown = computed(() => (hovered.value || focused.value) && !dismissed.value)

function hover() {
  hovered.value = true
  dismissed.value = false
}
function focus() {
  focused.value = true
  dismissed.value = false
}

// Escape vale también con el foco en otro sitio y el ratón encima: se escucha en todo el documento mientras se ve.
function onKey(event: KeyboardEvent) {
  if (event.key === 'Escape') dismissed.value = true
}
watch(shown, (now) => {
  if (now) document.addEventListener('keydown', onKey)
  else document.removeEventListener('keydown', onKey)
})
onBeforeUnmount(() => document.removeEventListener('keydown', onKey))
</script>

<template>
  <!-- El puntero, en la acción entera, para que el texto siga a la vista con el puntero encima de él; el teclado,
       en el enlace, que es lo único que recibe el foco. -->
  <span
    class="action"
    @pointerenter="hover"
    @pointerleave="hovered = false"
  >
    <RouterLink
      :to="props.to"
      :aria-label="`${label}, ${subject}`"
      class="target"
      @focus="focus"
      @blur="focused = false"
    >
      <AppIcon :name="icon" />
    </RouterLink>
    <!-- Sin rol ni `aria-describedby`: el nombre del enlace ya lo dice, y el lector lo leería dos veces. -->
    <span
      v-if="shown"
      aria-hidden="true"
      class="tip"
    ><span class="bubble">{{ label }}</span></span>
  </span>
</template>

<style scoped>
.action {
  position: relative;
  display: inline-flex;
}
/* 40 × 40 px (LLD-B §3.7; WCAG 2.5.8 pide 24). */
.target {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  border-radius: var(--p-content-border-radius);
  color: var(--p-text-color);
}
.target:hover {
  background: var(--p-content-hover-background);
}
.target:focus-visible {
  outline: 2px solid var(--p-primary-color);
  outline-offset: 1px;
}
/* Encima del icono y alineado con su borde derecho: la columna de acciones es la última. El hueco de abajo forma
   parte del texto, para que el ratón pase del icono al texto sin que se esconda. */
.tip {
  position: absolute;
  right: 0;
  bottom: 100%;
  z-index: 1;
  padding-bottom: 0.375rem;
  white-space: nowrap;
}
/* Los colores del texto, al revés: se distingue de la tabla en los dos modos. */
.bubble {
  display: block;
  padding: 0.375rem 0.625rem;
  border-radius: var(--p-content-border-radius);
  background: var(--p-text-color);
  color: var(--p-content-background);
  font-size: 0.875rem;
  font-weight: 400;
}
</style>
