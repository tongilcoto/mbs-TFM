<!-- Elegir una foto (plan R6): un botón con el texto de la web, que abre el selector de ficheros. El campo del
     fichero del navegador sale con su propio texto, en su idioma («Choose File»); aquí va escondido y lo abre el
     botón. Sigue en la página, con su `id`, para que una etiqueta de fuera («Foto») lo nombre. -->
<script setup lang="ts">
import Button from 'primevue/button'
import { ref } from 'vue'

defineProps<{
  inputId: string
  // «Elegir foto», «Cambiar foto»…
  label: string
  // Los tipos que se ofrecen: con JPEG y PNG, Safari en el iPhone convierte la foto HEIC al elegirla.
  accept: string
  describedBy?: string
  disabled?: boolean
}>()
const emit = defineEmits<{ pick: [file: File] }>()

const input = ref<HTMLInputElement>()

function picked() {
  const file = input.value?.files?.[0]
  // Vacío otra vez: si no, elegir el mismo fichero dos veces no avisaría.
  if (input.value) input.value.value = ''
  if (file) emit('pick', file)
}
</script>

<template>
  <span class="photo-picker">
    <Button
      type="button"
      :label="label"
      severity="secondary"
      size="small"
      :disabled="disabled"
      :aria-describedby="describedBy"
      @click="input?.click()"
    />
    <input
      :id="inputId"
      ref="input"
      class="visually-hidden"
      type="file"
      tabindex="-1"
      :accept="accept"
      @change="picked"
    >
  </span>
</template>

<style scoped>
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}
</style>
