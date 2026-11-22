<!-- El selector de temporada (plan R1, decisión 5): con su etiqueta, no solo el desplegable. En la portada y en la
     cabecera de la ficha del equipo. Con el gris secundario del tema, como los botones grises y el óvalo del puesto
     (R6.19f): la clase `selector-secundario` del tema. -->
<script setup lang="ts">
import Select from 'primevue/select'

defineProps<{ labels: string[]; modelValue: string }>()
defineEmits<{ 'update:modelValue': [label: string] }>()
</script>

<template>
  <div class="season-picker">
    <!-- Con label-id, PrimeVue pone ese id en la parte que recibe el foco, y al pulsar la etiqueta lo lleva allí. -->
    <label
      id="season-picker-label"
      for="season-picker"
    >Temporada</label>
    <!-- El gris secundario, del tema (`selector-secundario`). -->
    <Select
      class="selector-secundario"
      label-id="season-picker"
      :options="labels"
      :model-value="modelValue"
      aria-labelledby="season-picker-label"
      @update:model-value="$emit('update:modelValue', $event)"
    />
  </div>
</template>

<style scoped>
.season-picker {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
</style>
