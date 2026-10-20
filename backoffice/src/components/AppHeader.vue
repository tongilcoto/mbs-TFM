<!-- La cabecera (LLD-B §8.1): el escudo y el nombre corto del club, y el interruptor de modo. Mientras llega el
     club, solo el interruptor. -->
<script setup lang="ts">
import ThemeToggle from './ThemeToggle.vue'

defineProps<{ shortName?: string; crestUrl?: string | null }>()
</script>

<template>
  <header class="app-header">
    <p
      v-if="shortName"
      class="club"
    >
      <!-- El escudo no lleva texto alternativo: al lado ya está el nombre, y el lector lo diría dos veces. -->
      <img
        v-if="crestUrl"
        :src="crestUrl"
        alt=""
        class="crest"
      >
      {{ shortName }}
    </p>
    <ThemeToggle />
  </header>
</template>

<style scoped>
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.5rem 1rem;
  background: var(--p-content-background);
  border-bottom: 1px solid var(--p-content-border-color);
}
.club {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  margin: 0;
  font-size: 1.25rem;
  font-weight: 600;
}
.crest {
  width: 2rem;
  height: 2rem;
  object-fit: contain;
}
</style>
