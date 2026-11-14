<!-- En casa o fuera (plan R5, decisión 5): una casa o un avión, con su texto al pasar el ratón y para el lector de
     pantalla, como las acciones con icono (DW-19). No recibe el foco: el texto ya lo lee el lector. -->
<script setup lang="ts">
import AppIcon from './AppIcon.vue'
import TipBubble from './TipBubble.vue'
import { useTip } from './tip'

defineProps<{ atHome: boolean }>()

const tip = useTip()
</script>

<template>
  <span
    class="venue"
    @pointerenter="tip.hover"
    @pointerleave="tip.leave"
  >
    <AppIcon :name="atHome ? 'house' : 'plane'" />
    <span class="visually-hidden">{{ atHome ? 'En casa' : 'Fuera' }}</span>
    <TipBubble
      v-if="tip.shown.value"
      :text="atHome ? 'En casa' : 'Fuera'"
    />
  </span>
</template>

<style scoped>
.venue {
  position: relative;
  display: inline-flex;
  flex: none;
  color: var(--p-text-muted-color);
}
/* Lo lee el lector de pantalla y no se ve. */
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}
</style>
