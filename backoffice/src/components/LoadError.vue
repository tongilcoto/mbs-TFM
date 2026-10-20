<!-- Un error al cargar una pantalla, en el hueco de sus datos (LLD-B §4.3). Lo que va dentro (un enlace, por
     ejemplo) lo pone la pantalla. -->
<script setup lang="ts">
import Button from 'primevue/button'

defineProps<{ message: string; code?: string; retry: boolean }>()
defineEmits<{ retry: [] }>()
</script>

<template>
  <div
    class="load-error"
    role="alert"
  >
    <p class="message">
      {{ message }}
    </p>
    <slot />
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
  </div>
</template>

<style scoped>
.load-error {
  padding: 1rem;
  border: 1px solid var(--p-content-border-color);
  border-left: 4px solid var(--p-estado-fallo);
  background: var(--p-content-background);
}
.message {
  margin-top: 0;
  font-weight: 600;
}
.code {
  margin-bottom: 0;
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
</style>
