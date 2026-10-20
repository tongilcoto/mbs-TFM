<!-- La página entera cuando el club no se puede cargar (LLD-B §8.3): sin menú, porque sin club no funciona nada. -->
<script setup lang="ts">
import Button from 'primevue/button'

defineProps<{
  message: string
  // El código del servidor, en pequeño, para poder contar exactamente qué pasó (LLD-B §4.2).
  code?: string
  // Una línea más, cuando ayuda a arreglarlo: la dirección de ejemplo si falta el club.
  hint?: string
  retry: boolean
}>()
defineEmits<{ retry: [] }>()
</script>

<template>
  <main class="full-page-error">
    <h1>{{ message }}</h1>
    <p v-if="hint">
      {{ hint }}
    </p>
    <Button
      v-if="retry"
      label="Reintentar"
      @click="$emit('retry')"
    />
    <p
      v-if="code"
      class="code"
    >
      Código: {{ code }}
    </p>
  </main>
</template>

<style scoped>
.full-page-error {
  max-width: 40rem;
  margin: 4rem auto;
  padding: 0 1rem;
}
h1 {
  font-size: 1.5rem;
}
.code {
  margin-top: 2rem;
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
</style>
