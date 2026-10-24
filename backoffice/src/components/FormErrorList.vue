<!-- Al fallar un formulario, la lista de todos sus errores, arriba, cada uno con un enlace a su campo (LLD-B
     §10.3). Quien la usa le pasa el foco al enseñarla, con `focus()`. -->
<script setup lang="ts">
import { ref } from 'vue'

export interface FormError {
  // El `id` del campo, al que lleva el enlace.
  fieldId: string
  label: string
  message: string
}

defineProps<{ errors: FormError[] }>()

const box = ref<HTMLElement>()

defineExpose({ focus: () => box.value?.focus() })

// El enlace lleva el foco al campo sin tocar la dirección: un `#campo` en ella sería una entrada más del historial.
function goTo(fieldId: string) {
  document.getElementById(fieldId)?.focus()
}
</script>

<template>
  <div
    ref="box"
    class="form-error-list"
    role="group"
    tabindex="-1"
    aria-labelledby="form-error-list-title"
  >
    <p
      id="form-error-list-title"
      class="title"
    >
      Revisa {{ errors.length === 1 ? 'este campo' : 'estos campos' }}:
    </p>
    <ul>
      <li
        v-for="error in errors"
        :key="error.fieldId"
      >
        <a
          :href="`#${error.fieldId}`"
          @click.prevent="goTo(error.fieldId)"
        >{{ error.label }}: {{ error.message }}</a>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.form-error-list {
  padding: 1rem;
  border: 1px solid var(--p-content-border-color);
  border-left: 4px solid var(--p-estado-fallo);
  background: var(--p-content-background);
}
.title {
  margin-top: 0;
  font-weight: 600;
}
ul {
  margin-bottom: 0;
}
/* Cada enlace, al menos 24 px de alto y con aire entre uno y otro: lo que se pulsa mide 24 × 24 (LLD-B §10.5,
   WCAG 2.2, 2.5.8). Lo vio axe en los escenarios de R2.16. */
a {
  display: inline-block;
  min-height: 1.5rem;
  line-height: 1.5rem;
}
li + li {
  margin-top: 0.25rem;
}
</style>
