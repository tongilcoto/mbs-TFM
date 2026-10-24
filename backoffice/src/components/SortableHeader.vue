<!-- Una cabecera de columna que ordena la tabla al pincharla (bloque T del plan R2). Un botón con el nombre de la
     columna, que se alcanza con el tabulador y se pulsa con Intro o Espacio (LLD-B §10.1); y `aria-sort` solo en
     la columna por la que se ordena, para que el lector diga «orden ascendente» o «descendente». Qué es
     «ascendente» lo decide la regla de cada columna: el orden de su primer clic. -->
<script setup lang="ts">
defineProps<{ label: string; sort?: 'ascending' | 'descending' }>()
defineEmits<{ sort: [] }>()
</script>

<template>
  <th
    scope="col"
    :aria-sort="sort"
  >
    <button
      type="button"
      class="sort"
      @click="$emit('sort')"
    >
      {{ label }}
      <!-- La flecha se ve; el orden lo lee aria-sort. Sin ordenar, las dos, para que se vea que se puede. -->
      <span
        aria-hidden="true"
        class="arrow"
        :class="{ active: sort }"
      >{{ sort === 'ascending' ? '▲' : sort === 'descending' ? '▼' : '↕' }}</span>
    </button>
  </th>
</template>

<style scoped>
.sort {
  display: inline-flex;
  align-items: center;
  gap: 0.375rem;
  min-height: 1.5rem;
  padding: 0;
  border: 0;
  background: none;
  color: inherit;
  font: inherit;
  cursor: pointer;
}
.arrow {
  color: var(--p-text-muted-color);
  font-size: 0.75em;
}
.arrow.active {
  color: inherit;
}
</style>
