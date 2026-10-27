<!-- La dirección ya comprobada, en una línea, con sus dos iconos (plan R3, §3.2 y decisión 2): editarla, que vuelve
     al paso anterior, y volver a comprobarla sin salir. Mientras se comprueba, los dos se bloquean y la línea lo
     dice. Sin el `https://`: no distingue nada y quita sitio. -->
<script setup lang="ts">
import { computed } from 'vue'
import IconAction from './IconAction.vue'

const props = defineProps<{ address: string; checking: boolean }>()
defineEmits<{ edit: []; recheck: [] }>()

const shown = computed(() => props.address.replace(/^https?:\/\//, ''))
</script>

<template>
  <div class="checked-address">
    <span class="label">Dirección:</span>
    <span class="address">{{ shown }}</span>
    <!-- Se lee en voz alta sin mover el foco (LLD-B §10.3). Vacía, sigue ahí: si apareciera con el texto, el lector
         no lo anunciaría. -->
    <span
      role="status"
      class="status"
    >{{ checking ? 'Comprobando…' : '' }}</span>
    <IconAction
      label="Editar la dirección"
      icon="pencil"
      :disabled="checking"
      @press="$emit('edit')"
    />
    <IconAction
      label="Volver a comprobar en la Federación"
      icon="rotate-cw"
      :disabled="checking"
      @press="$emit('recheck')"
    />
  </div>
</template>

<style scoped>
.checked-address {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0.5rem 0.5rem 1rem;
  border: 1px solid var(--p-content-border-color);
  background: var(--p-content-background);
  font-size: 0.875rem;
}
.label {
  color: var(--p-text-muted-color);
}
/* Larga y sin espacios: se corta con «…» para que los iconos no se vayan de la línea. El lector la lee entera. Con
   `width: 0`, ocupa lo que sobra y no lo que mide: si no, la página entera reserva su ancho y en el móvil se sale. */
.address {
  flex: 1;
  width: 0;
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.status {
  color: var(--p-text-muted-color);
}
</style>
