<!-- Salir de un formulario con cambios sin guardar pregunta antes (LLD-B §5.5). La ventana retiene el foco, y
     Escape la cierra como «Seguir editando» (§10.1). -->
<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'

defineProps<{ visible: boolean }>()
const emit = defineEmits<{ stay: []; leave: [] }>()
</script>

<template>
  <Dialog
    :visible="visible"
    modal
    header="Cambios sin guardar"
    :closable="false"
    @update:visible="emit('stay')"
  >
    <p>Tienes cambios sin guardar. ¿Salir sin guardar?</p>
    <template #footer>
      <!-- El primero recibe el foco al abrirse: el que no pierde nada. -->
      <Button
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
