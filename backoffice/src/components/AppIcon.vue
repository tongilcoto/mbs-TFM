<!-- Los iconos de la web (plan R3, R3.9): los dibujos de Lucide, copiados aquí en vez de instalarlo, porque son
     pocos. De trazo, del color del texto que los rodea. No se leen: quien los usa pone el nombre al lado (en el
     enlace o el botón), así que el dibujo va siempre con `aria-hidden`.

     Lucide, https://lucide.dev (lucide-static 1.62.0): licencia ISC, y MIT los que vienen de Feather, como `link`.
     El texto de las dos, tal cual, en AppIcon.LICENSE.txt, que tiene que acompañar a los dibujos. -->
<script setup lang="ts">
// Cada icono, con el nombre que tiene en Lucide y sus trazos (en un cuadro de 24 × 24). Se añaden según hagan falta.
const drawings = {
  // Sincronizar con la Federación (R3).
  link: [
    'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71',
    'M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71',
  ],
}

export type IconName = keyof typeof drawings

defineProps<{ name: IconName }>()
</script>

<template>
  <svg
    aria-hidden="true"
    class="icon"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
  >
    <path
      v-for="(d, index) in drawings[name]"
      :key="index"
      :d="d"
    />
  </svg>
</template>

<style scoped>
.icon {
  width: 1.25rem;
  height: 1.25rem;
  flex: none;
}
</style>
