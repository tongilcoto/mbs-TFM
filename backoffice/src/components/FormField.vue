<!-- Un campo de formulario con su etiqueta visible, su ayuda y su error (LLD-B §10.3 y §10.4). El campo lo pone
     quien lo usa, con el `id` de aquí, y recibe a qué textos unirse y si está mal. -->
<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{ id: string; label: string; required: boolean; help?: string; error?: string }>()

// Lo que el lector de pantalla lee al llegar al campo, después de su nombre: la ayuda y el error.
const describedBy = computed(() => {
  const ids = [props.help && `${props.id}-help`, props.error && `${props.id}-error`].filter(Boolean)
  return ids.length > 0 ? ids.join(' ') : undefined
})
</script>

<template>
  <div class="form-field">
    <!-- El asterisco se ve; «obligatorio» se lee (LLD-B §10.4). -->
    <label
      :id="`${id}-label`"
      :for="id"
    >
      {{ label }}<template v-if="required">
        <span aria-hidden="true">*</span> <span class="visually-hidden">(obligatorio)</span>
      </template>
    </label>
    <slot
      :described-by="describedBy"
      :invalid="error !== undefined"
    />
    <small
      v-if="help"
      :id="`${id}-help`"
      class="help"
    >{{ help }}</small>
    <small
      v-if="error"
      :id="`${id}-error`"
      class="error"
    >{{ error }}</small>
  </div>
</template>

<style scoped>
.form-field {
  display: flex;
  flex-direction: column;
  gap: 0.375rem;
}
label {
  font-weight: 600;
}
.help {
  color: var(--p-text-muted-color);
}
.error {
  color: var(--p-estado-fallo);
  font-weight: 600;
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
