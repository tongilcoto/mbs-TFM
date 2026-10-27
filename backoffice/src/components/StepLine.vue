<!-- La línea de un asistente que dice en qué paso se está (plan R3, decisión 2): «1 La dirección › 2 Tu equipo». El
     paso en curso lleva `aria-current="step"`, que el lector anuncia como «paso actual». Los pasos no se pulsan:
     se cambia de paso con los botones de la pantalla. -->
<script setup lang="ts">
defineProps<{ steps: string[]; current: number }>()
</script>

<template>
  <ol
    class="steps"
    aria-label="Pasos"
  >
    <li
      v-for="(step, index) in steps"
      :key="step"
      :class="{ current: index === current }"
      :aria-current="index === current ? 'step' : undefined"
    >
      <span
        aria-hidden="true"
        class="number"
      >{{ index + 1 }}</span>
      <span class="visually-hidden">Paso {{ index + 1 }}:</span>
      {{ step }}
    </li>
  </ol>
</template>

<style scoped>
.steps {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem 1.75rem;
  margin: 0;
  padding: 0;
  list-style: none;
}
li {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--p-text-muted-color);
}
li.current {
  color: var(--p-text-color);
  font-weight: 700;
}
.number {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.625rem;
  height: 1.625rem;
  border: 2px solid currentColor;
  border-radius: 50%;
  font-weight: 700;
}
/* El paso en curso, relleno: no solo con el color, también con la forma (LLD-B §9.4). */
.current .number {
  border-color: var(--p-primary-color);
  background: var(--p-primary-color);
  color: var(--p-primary-contrast-color);
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
