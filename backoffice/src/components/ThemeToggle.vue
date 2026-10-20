<!-- El interruptor de modo (LLD-B §9.3). Dice lo que hace, no solo un dibujo, para que lo entienda un lector de pantalla. -->
<script setup lang="ts">
import Button from 'primevue/button'
import { computed, ref } from 'vue'
import { currentMode, setMode } from '../theme/mode'

const mode = ref(currentMode())
const label = computed(() => (mode.value === 'oscuro' ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro'))

function toggle() {
  mode.value = mode.value === 'oscuro' ? 'claro' : 'oscuro'
  setMode(mode.value)
}
</script>

<template>
  <Button
    :label="label"
    variant="text"
    @click="toggle"
  />
</template>
