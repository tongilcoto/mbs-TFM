<!-- Un aviso dentro de una pantalla que no es un error (plan R3, §3.3): `info`, algo que conviene saber («se creará
     la temporada»); `warning`, algo que hay que mirar antes de seguir («no cuadra con el equipo»). Nunca solo el
     color: la marca de la izquierda cambia con él (LLD-B §9.4). El contenido lo pone quien lo usa. -->
<script setup lang="ts">
defineProps<{ kind: 'info' | 'warning' }>()
</script>

<template>
  <div :class="['notice-box', kind]">
    <span
      aria-hidden="true"
      class="mark"
    >{{ kind === 'info' ? 'i' : '!' }}</span>
    <div class="text">
      <slot />
    </div>
  </div>
</template>

<style scoped>
.notice-box {
  display: flex;
  gap: 0.625rem;
  align-items: flex-start;
  padding: 0.75rem 0.875rem;
  border: 1px solid var(--p-content-border-color);
  border-left-width: 4px;
  background: var(--p-content-background);
}
.info {
  border-left-color: var(--p-estado-en-marcha);
}
.warning {
  border-left-color: var(--p-estado-aviso);
}
.mark {
  display: inline-flex;
  flex: none;
  align-items: center;
  justify-content: center;
  width: 1.375rem;
  height: 1.375rem;
  border-radius: 50%;
  font-weight: 800;
  font-size: 0.875rem;
  color: var(--p-content-background);
}
.info .mark {
  background: var(--p-estado-en-marcha);
}
.warning .mark {
  background: var(--p-estado-aviso);
}
.text :deep(p) {
  margin: 0;
}
.text :deep(p + p),
.text :deep(p + ul),
.text :deep(ul + p) {
  margin-top: 0.375rem;
}
.text :deep(ul) {
  margin: 0.375rem 0 0;
  padding-left: 1.25rem;
}
</style>
