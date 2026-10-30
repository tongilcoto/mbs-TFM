<!-- Un puesto en la clasificación, en su óvalo: junto a cada equipo de un partido y en las columnas Pos. (plan R4,
     §3.3 y §3.4). Del ancho de dos cifras, para que lo de al lado empiece alineado. -->
<script setup lang="ts">
defineProps<{ position: number }>()
</script>

<template>
  <span class="position-badge">{{ position }}º</span>
</template>

<style scoped>
.position-badge {
  display: inline-block;
  flex: none;
  min-width: 2.25rem;
  padding: 0 0.375rem;
  border: 1px solid var(--p-content-border-color);
  border-radius: 999px;
  background: var(--p-fondo);
  color: var(--p-text-muted-color);
  font-size: 0.75rem;
  font-style: normal;
  font-weight: 600;
  line-height: 1.25rem;
  text-align: center;
  font-variant-numeric: tabular-nums;
}
</style>
