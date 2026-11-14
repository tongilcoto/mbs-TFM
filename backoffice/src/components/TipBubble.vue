<!-- El texto de useTip (tip.ts), encima de lo que lo saca. `align`, de qué borde sale: `end`, alineado con el derecho
     (las acciones, en la última columna); `start`, con el izquierdo. Sin rol ni `aria-describedby`: quien lo usa ya
     lo dice al lector en su nombre, y lo leería dos veces. -->
<script setup lang="ts">
withDefaults(defineProps<{ text: string; align?: 'start' | 'end' }>(), { align: 'start' })
</script>

<template>
  <span
    aria-hidden="true"
    :class="['tip', align]"
  ><span class="bubble">{{ text }}</span></span>
</template>

<style scoped>
/* El hueco de abajo forma parte del texto, para que el ratón pase de lo que lo saca al texto sin que se esconda. */
.tip {
  position: absolute;
  bottom: 100%;
  z-index: 1;
  padding-bottom: 0.375rem;
  white-space: nowrap;
}
.start {
  left: 0;
}
.end {
  right: 0;
}
/* Los colores del texto, al revés: se distingue de la tabla en los dos modos. */
.bubble {
  display: block;
  padding: 0.375rem 0.625rem;
  border-radius: var(--p-content-border-radius);
  background: var(--p-text-color);
  color: var(--p-content-background);
  font-size: 0.875rem;
  font-style: normal;
  font-weight: 400;
}
</style>
