<script setup lang="ts">
import ThemeToggle from './components/ThemeToggle.vue'
</script>

<!-- El interruptor, aquí de momento: se muda a la cabecera con el marco (R1.13). -->
<template>
  <ThemeToggle />
  <RouterView />
</template>
