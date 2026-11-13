<!-- Cómo va la ingesta de una competición, en la portada y en la ficha del equipo (plan R1, decisión 2): su icono, de
     color, y su palabra, y debajo «La anterior tuvo fallos» si está en marcha y la anterior falló. Nunca solo el
     color: la palabra va siempre al lado (LLD-B §9.4). -->
<script setup lang="ts">
import type { HealthState } from './teamRow'

defineProps<{ health?: HealthState; name?: string; previousFailed: boolean }>()

const icons: Record<HealthState, string> = { ok: '✓', failing: '✕', pending: '↻', stale: '◷', never: '○' }
</script>

<template>
  <span
    v-if="health"
    class="health"
  >
    <span
      aria-hidden="true"
      :class="['icon', health]"
    >{{ icons[health] }}</span>
    <span>{{ name }}</span>
  </span>
  <span
    v-if="previousFailed"
    class="note"
  >
    <span
      aria-hidden="true"
      class="icon failing"
    >{{ icons.failing }}</span>
    <span>La anterior tuvo fallos</span>
  </span>
</template>

<style scoped>
.note {
  display: block;
  margin-top: 0.25rem;
  font-size: 0.875rem;
  color: var(--p-text-muted-color);
}
.icon {
  display: inline-block;
  width: 1.25em;
  font-weight: 700;
}
.ok {
  color: var(--p-estado-bien);
}
.failing {
  color: var(--p-estado-fallo);
}
.pending {
  color: var(--p-estado-en-marcha);
}
.stale {
  color: var(--p-estado-aviso);
}
.never {
  color: var(--p-estado-sin-datos);
}
</style>
