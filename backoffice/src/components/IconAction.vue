<!-- Una acción con icono y su texto (LLD-B §3.7, plan R3, decisión 1): un enlace si lleva a otra pantalla (`to`), y
     si no, un botón que avisa al pulsarlo. El texto sale al pasar el ratón y al llegar con el teclado (tip.ts).
     El lector de pantalla no necesita el texto: lo lee en el nombre. En una fila, con la fila detrás (`subject`:
     «Sincronizar otra competición, Cadete A»), para que diez enlaces iguales se distingan. -->
<script setup lang="ts">
import { computed } from 'vue'
import type { RouteLocationRaw } from 'vue-router'
import AppIcon, { type IconName } from './AppIcon.vue'
import TipBubble from './TipBubble.vue'
import { useTip } from './tip'

const props = defineProps<{ label: string; subject?: string; icon: IconName; to?: RouteLocationRaw; disabled?: boolean }>()
defineEmits<{ press: [] }>()

const name = computed(() => (props.subject ? `${props.label}, ${props.subject}` : props.label))

const tip = useTip()
</script>

<template>
  <!-- El puntero, en la acción entera, para que el texto siga a la vista con el puntero encima de él; el teclado,
       en el enlace o el botón, que es lo único que recibe el foco. -->
  <span
    class="action"
    @pointerenter="tip.hover"
    @pointerleave="tip.leave"
  >
    <RouterLink
      v-if="props.to"
      :to="props.to"
      :aria-label="name"
      class="target"
      @focus="tip.focus"
      @blur="tip.blur"
    >
      <AppIcon :name="icon" />
    </RouterLink>
    <button
      v-else
      type="button"
      :aria-label="name"
      :disabled="disabled"
      class="target"
      @click="$emit('press')"
      @focus="tip.focus"
      @blur="tip.blur"
    >
      <AppIcon :name="icon" />
    </button>
    <TipBubble
      v-if="tip.shown.value"
      :text="label"
      align="end"
    />
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
button.target {
  padding: 0;
  border: 1px solid var(--p-content-border-color);
  background: none;
  cursor: pointer;
}
button.target:disabled {
  color: var(--p-text-muted-color);
  cursor: default;
}
.target:hover:not(:disabled) {
  background: var(--p-content-hover-background);
}
.target:focus-visible {
  outline: 2px solid var(--p-primary-color);
  outline-offset: 1px;
}
</style>
