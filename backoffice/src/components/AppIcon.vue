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
  // Editar (R3, la dirección comprobada).
  pencil: [
    'M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z',
    'm15 5 4 4',
  ],
  // Volver a comprobar (R3, la dirección comprobada).
  'rotate-cw': ['M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8', 'M21 3v5h-5'],
  // Ver la jornada y la clasificación de un partido (R4, la pestaña Resultados).
  list: ['M3 5h.01', 'M3 12h.01', 'M3 19h.01', 'M8 5h13', 'M8 12h13', 'M8 19h13'],
  // En casa y fuera, en el último y el próximo partido de la portada (R5, decisión 5).
  house: [
    'M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8',
    'M3 10a2 2 0 0 1 .709-1.528l7-6a2 2 0 0 1 2.582 0l7 6A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
  ],
  plane: [
    'M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z',
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
