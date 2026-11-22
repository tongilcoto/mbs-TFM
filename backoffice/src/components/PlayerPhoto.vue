<!-- La foto de un jugador, o sus iniciales si no tiene (plan R6, §3): en la plantilla y en la ficha. La foto dice al
     lector el nombre del jugador, que la web le pone al pintarla y no se guarda en ningún sitio (R6.3). Las
     iniciales, no: son un relleno, y el nombre ya está al lado. Si la foto no carga —el enlace firmado dura una hora
     (D-117), y al relanzar el servidor cambia su clave—, las iniciales hasta que llegue otra. -->
<script setup lang="ts">
import { ref, watch } from 'vue'

const props = defineProps<{ url?: string; name: string; initials: string }>()

const failed = ref(false)
watch(() => props.url, () => (failed.value = false))
</script>

<template>
  <img
    v-if="url && !failed"
    class="player-photo"
    :src="url"
    :alt="name"
    @error="failed = true"
  >
  <span
    v-else
    class="player-photo initials"
    aria-hidden="true"
  >{{ initials }}</span>
</template>

<style scoped>
/* `player-photo` y no `photo`: una pantalla con su propio `.photo` (la celda de la plantilla) alcanzaría la raíz de esta
   pieza y la dejaría de 16 px (R6.21). */
.player-photo {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 50%;
  object-fit: cover;
}
/* Las iniciales, sobre el color de los bordes: con el texto de siempre se leen en los dos modos. */
.initials {
  border: 1px solid var(--p-content-border-color);
  background: var(--p-content-hover-background);
  color: var(--p-text-color);
  font-size: 0.875rem;
  font-weight: 700;
}
</style>
