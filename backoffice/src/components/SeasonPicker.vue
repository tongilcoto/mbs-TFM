<!-- El selector de temporada de la portada (plan R1, decisión 5): con su etiqueta, no solo el desplegable. -->
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
    <Select
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
