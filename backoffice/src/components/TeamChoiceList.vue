<!-- Elegir el equipo del club entre los del grupo (plan R3, decisión 4): botones de opción, uno solo y obligatorio,
     ninguno elegido de entrada. Los que no se pueden elegir se ven, desactivados y con el motivo, que el lector lee
     al llegar a ellos. Con `error`, la lista se marca y dice qué falta, como un campo (LLD-B §5.1). -->
<script setup lang="ts">
import RadioButton from 'primevue/radiobutton'
import { computed } from 'vue'

export interface TeamOption {
  code: string | null
  name: string
  reason?: string
}

const props = defineProps<{ id: string; legend: string; hint: string; options: TeamOption[]; error?: string }>()
const chosen = defineModel<string>()

// Para quien lleva a la lista desde fuera (la lista de errores): el primero que se puede elegir.
const firstId = computed(() => {
  const index = props.options.findIndex((option) => option.reason === undefined)
  return index < 0 ? undefined : optionId(index)
})
defineExpose({ firstId })

function optionId(index: number) {
  return `${props.id}-${index}`
}

const describedBy = computed(() => [`${props.id}-hint`, props.error && `${props.id}-error`].filter(Boolean).join(' '))
</script>

<template>
  <fieldset
    :class="['team-choice', { invalid: error }]"
    :aria-describedby="describedBy"
  >
    <!-- El asterisco se ve; «obligatorio» se lee (LLD-B §10.4). -->
    <legend>
      {{ legend }}<span aria-hidden="true">*</span> <span class="visually-hidden">(obligatorio)</span>
    </legend>
    <p
      :id="`${id}-hint`"
      class="hint"
    >
      {{ hint }}
    </p>
    <p
      v-if="error"
      :id="`${id}-error`"
      class="error"
    >
      {{ error }}
    </p>
    <div class="options">
      <div
        v-for="(option, index) in options"
        :key="option.code ?? `sin-codigo-${index}`"
        :class="['option', { taken: option.reason, chosen: option.code !== null && option.code === chosen }]"
      >
        <RadioButton
          v-model="chosen"
          :input-id="optionId(index)"
          :name="id"
          :value="option.code ?? ''"
          :disabled="option.reason !== undefined"
          :invalid="error !== undefined"
          :pt="{ input: { 'aria-describedby': option.reason ? `${optionId(index)}-reason` : undefined } }"
        />
        <!-- El motivo, fuera de la etiqueta: el nombre es el del equipo, y el motivo se lee después, como descripción. -->
        <div class="text">
          <label :for="optionId(index)">{{ option.name }}</label>
          <span
            v-if="option.reason"
            :id="`${optionId(index)}-reason`"
            class="reason"
          >{{ option.reason }}</span>
        </div>
      </div>
    </div>
  </fieldset>
</template>

<style scoped>
.team-choice {
  margin: 0;
  padding: 0.75rem 0.875rem;
  border: 1px solid var(--p-content-border-color);
}
.team-choice.invalid {
  border-color: var(--p-estado-fallo);
}
legend {
  padding: 0 0.375rem;
  font-weight: 600;
}
.hint {
  margin: 0 0 0.5rem;
  color: var(--p-text-muted-color);
  font-size: 0.875rem;
}
.error {
  margin: 0 0 0.5rem;
  color: var(--p-estado-fallo);
  font-weight: 600;
}
/* Dos columnas si caben; en el móvil, una. */
.options {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 18rem), 1fr));
  gap: 0.125rem 1rem;
}
.option {
  display: flex;
  gap: 0.625rem;
  align-items: flex-start;
  padding: 0.5rem;
}
.text {
  flex: 1;
}
.option label {
  display: block;
  min-height: 1.5rem;
  cursor: pointer;
}
.option.chosen {
  outline: 1px solid var(--p-primary-color);
}
.option.taken .text {
  color: var(--p-text-muted-color);
}
.option.taken label {
  cursor: default;
}
.reason {
  display: block;
  font-size: 0.8125rem;
}
.visually-hidden {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip-path: inset(50%);
  white-space: nowrap;
}
</style>
