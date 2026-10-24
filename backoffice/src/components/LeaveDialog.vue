<!-- Salir de un formulario con cambios sin guardar pregunta antes (LLD-B §5.5). La ventana retiene el foco, y
     Escape la cierra como «Seguir editando» (§10.1). -->
<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { nextTick } from 'vue'

defineProps<{ visible: boolean }>()
const emit = defineEmits<{ stay: []; leave: [] }>()

// Al abrirse, el foco va a «Seguir editando», el botón que no pierde nada. Lo pone la web: PrimeVue solo lo mete
// en la ventana si un elemento lleva `autofocus`, y el revisor de accesibilidad no lo deja usar.
async function focusStay() {
  await nextTick()
  document.getElementById('leave-dialog-stay')?.focus()
}
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Cambios sin guardar"
    :closable="false"
    @update:visible="emit('stay')"
    @show="focusStay"
  >
    <p>Tienes cambios sin guardar. ¿Salir sin guardar?</p>
    <template #footer>
      <Button
        id="leave-dialog-stay"
        label="Seguir editando"
        @click="emit('stay')"
      />
      <Button
        label="Salir sin guardar"
        severity="secondary"
        @click="emit('leave')"
      />
    </template>
  </Dialog>
</template>
