<!-- La confirmación de la baja de un jugador (plan R6, decisión 7). Dice qué pasa: deja de salir en la plantilla y su
     dorsal queda libre, sus goles y tarjetas siguen contando, y sincronizar no lo vuelve a añadir (D-120). La fila
     solo se esconde (D-36): el perfil del jugador sigue ahí (D-119). El foco empieza en «Cancelar», el botón que no
     cambia nada, como al salir sin guardar. -->
<script setup lang="ts">
import Button from 'primevue/button'
import Dialog from 'primevue/dialog'
import { nextTick, onMounted, ref } from 'vue'
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult } from '../../api/result'
import LoadError from '../../components/LoadError.vue'

const props = defineProps<{
  playerId: string
  // «Marcos Díaz» y «Cadete A», para la pregunta.
  playerName: string
  teamTitle: string
}>()
const emit = defineEmits<{ close: []; removed: [] }>()

const removing = ref(false)
const failure = ref<ShownError>()

onMounted(async () => {
  await nextTick()
  document.getElementById('remove-player-cancel')?.focus()
})

async function remove() {
  removing.value = true
  failure.value = undefined
  try {
    const removed = await asResult(api.DELETE('/players/{playerId}', { params: { path: { playerId: props.playerId } } }))
    if (removed.ok) emit('removed')
    else failure.value = removed.error
  } finally {
    removing.value = false
  }
}
</script>

<template>
  <Dialog
    visible
    modal
    header="Dar de baja"
    :style="{ width: '30rem' }"
    :breakpoints="{ '640px': '95vw' }"
    @update:visible="emit('close')"
  >
    <div class="remove">
      <LoadError
        v-if="failure"
        :message="failure.message"
        :code="failure.code"
        :retry="failure.retry"
        @retry="remove"
      />
      <p class="question">
        ¿Dar de baja a {{ playerName }} del {{ teamTitle }}?
      </p>
      <ul>
        <li>Deja de salir en la plantilla, y su dorsal queda libre.</li>
        <li>Sus goles y tarjetas siguen contando para el equipo.</li>
        <li>Sincronizar con la Federación no lo volverá a añadir.</li>
      </ul>
    </div>
    <template #footer>
      <Button
        label="Dar de baja"
        severity="danger"
        :loading="removing"
        @click="remove"
      />
      <Button
        id="remove-player-cancel"
        label="Cancelar"
        severity="secondary"
        @click="emit('close')"
      />
    </template>
  </Dialog>
</template>

<style scoped>
.remove p,
.remove ul {
  margin: 0 0 0.5rem;
}
.question {
  font-weight: 600;
}
</style>
