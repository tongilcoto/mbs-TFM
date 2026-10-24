<!-- «Crear nueva temporada» (plan R2, §3.3): un diálogo con un solo campo. Pinta y avisa; la comprobación y la
     petición las hace la pantalla, que le devuelve los errores. Al abrirse, el foco va al campo; el tabulador no
     sale de él; y Escape lo cierra como «Cancelar» (LLD-B §10.1). -->
<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import InputText from 'primevue/inputtext'
import { nextTick, ref, watch } from 'vue'
import FormField from './FormField.vue'
import LoadError from './LoadError.vue'

const props = defineProps<{
  visible: boolean
  required: boolean
  saving: boolean
  // El error de la etiqueta, junto al campo: el formato, o el motivo del servidor.
  fieldError?: string
  // Lo que no es del campo, arriba del diálogo: «ya existe», o que el servidor no responde.
  banner?: { message: string; code?: string }
}>()
const emit = defineEmits<{ create: [label: string]; cancel: []; closed: [] }>()

const label = ref('')

// Cada vez que se abre, vacío.
watch(
  () => props.visible,
  (visible) => {
    if (visible) label.value = ''
  },
)

// Al abrirse, el foco va al campo (como en LeaveDialog: PrimeVue solo lo mete si hay `autofocus`, y el revisor no
// lo deja usar). Y un error en el campo lo lleva otra vez a él, para que el lector lea el motivo.
async function focusField() {
  await nextTick()
  document.getElementById('new-season-label')?.focus()
}
watch(
  () => props.fieldError,
  (error) => {
    if (error !== undefined) focusField()
  },
)
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Crear nueva temporada"
    :closable="false"
    @update:visible="emit('cancel')"
    @show="focusField"
    @after-hide="emit('closed')"
  >
    <form
      class="new-season"
      novalidate
      @submit.prevent="emit('create', label)"
    >
      <LoadError
        v-if="banner"
        :message="banner.message"
        :code="banner.code"
        :retry="false"
      />
      <FormField
        id="new-season-label"
        v-slot="{ describedBy, invalid }"
        label="Temporada"
        :required="required"
        :error="fieldError"
      >
        <InputText
          id="new-season-label"
          v-model="label"
          :invalid="invalid"
          :aria-describedby="describedBy"
        />
      </FormField>
      <div class="actions">
        <Button
          type="submit"
          label="Crear"
          :loading="saving"
        />
        <Button
          type="button"
          label="Cancelar"
          severity="secondary"
          @click="emit('cancel')"
        />
      </div>
    </form>
  </Dialog>
</template>

<style scoped>
.new-season {
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
}
.actions {
  display: flex;
  gap: 0.75rem;
}
</style>
