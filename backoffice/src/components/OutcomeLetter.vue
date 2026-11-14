<!-- El resultado de un partido suelto, su letra V, E o D sobre su color (DW-23): en la pestaña Resultados (R4) y en
     el último partido de la portada (R5). La letra, siempre: el color no es lo único que lo dice (LLD-B §9.4). -->
<script setup lang="ts">
defineProps<{ outcome: 'V' | 'E' | 'D' }>()

const names = { V: 'Victoria', E: 'Empate', D: 'Derrota' }
</script>

<template>
  <abbr
    :class="['outcome', outcome]"
    :title="names[outcome]"
  >{{ outcome }}</abbr>
</template>

<style scoped>
.outcome {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  width: 1.5rem;
  height: 1.5rem;
  border-radius: 0.25rem;
  font-size: 0.8125rem;
  font-style: normal;
  font-weight: 800;
  text-decoration: none;
  color: var(--p-content-background);
}
.V {
  background: var(--p-estado-bien);
}
.E {
  background: var(--p-estado-sin-datos);
}
.D {
  background: var(--p-estado-fallo);
}
</style>
