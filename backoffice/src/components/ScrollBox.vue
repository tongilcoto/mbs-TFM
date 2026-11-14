<!-- La caja de una tabla ancha (Resultados, los partidos de una jornada y la clasificación): si la tabla no cabe, se
     desplaza a los lados ella sola, y la página no. Con el zoom al 200 % (LLD-B §10.5) la página se salía por la
     derecha y cortaba la cabecera y las cajas; lo vio el desarrollador en la revisión de R4.15.
     Solo cuando de verdad se desplaza, la caja recibe el foco y se nombra (`label`): así se mueve con las flechas del
     teclado y el lector dice qué es. Si cabe, el tabulador no se para en ella. -->
<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'

defineProps<{ label: string }>()

const box = ref<HTMLElement>()
const scrolls = ref(false)

let watcher: ResizeObserver | undefined
function measure() {
  if (box.value) scrolls.value = box.value.scrollWidth > box.value.clientWidth
}
onMounted(() => {
  measure()
  // jsdom no lo tiene: en las pruebas de piezas, la caja nunca se desplaza.
  if (typeof ResizeObserver === 'undefined' || !box.value) return
  watcher = new ResizeObserver(measure)
  watcher.observe(box.value)
  if (box.value.firstElementChild) watcher.observe(box.value.firstElementChild)
})
onBeforeUnmount(() => watcher?.disconnect())
</script>

<template>
  <div
    ref="box"
    class="scroll-box"
    :tabindex="scrolls ? 0 : undefined"
    :role="scrolls ? 'group' : undefined"
    :aria-label="scrolls ? label : undefined"
  >
    <slot />
  </div>
</template>

<style scoped>
/* `relative`, para que los textos ocultos de la tabla (los del lector, en `position: absolute`) se queden dentro de la
   caja: sin ella se salían y estiraban la página a lo ancho (R5.10, el «Acciones» de la portada). */
.scroll-box {
  position: relative;
  max-width: 100%;
  overflow-x: auto;
}
.scroll-box:focus-visible {
  outline: 2px solid var(--p-primary-color);
  outline-offset: 2px;
}
</style>
