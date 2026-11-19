<!-- De dónde sale una clasificación (D-29, D-55): «Federación» o «Calculada», la que calcula la aplicación cuando la
     federación del club no publica la de cada jornada. Junto a la clasificación de la competición (R6.19c); no en la
     caja Posición de la ficha, que enseña siempre la última, de la Federación. Con el color gris secundario del tema,
     como el óvalo del puesto. Es texto: el lector lo lee con lo que tiene al lado. -->
<script setup lang="ts">
import type { StandingsSource } from '../screens/team/header'

defineProps<{ source: StandingsSource }>()
</script>

<template>
  <span class="source-mark">{{ source }}</span>
</template>

<style scoped>
.source-mark {
  display: inline-block;
  padding: 0.0625rem 0.5rem;
  border: 1px solid var(--p-secundario-borde);
  border-radius: 999px;
  background: var(--p-secundario-fondo);
  color: var(--p-secundario-texto);
  font-size: 0.8125rem;
  font-weight: 600;
}
</style>
