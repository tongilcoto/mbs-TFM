<!-- El marco (LLD-B §8.1): pide el club al arrancar, y hasta tenerlo no pinta ninguna pantalla. -->
<script setup lang="ts">
import { nextTick, onMounted, ref, watchEffect } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from './api/client'
import type { ShownError } from './api/errors'
import { asResult } from './api/result'
import type { components } from './api/schema'
import AppHeader from './components/AppHeader.vue'
import FullPageError from './components/FullPageError.vue'
import SideMenu from './components/SideMenu.vue'

type Club = components['schemas']['ClubResponse']

const club = ref<Club>()
const failure = ref<ShownError>()
const route = useRoute()

async function loadClub() {
  failure.value = undefined
  const result = await asResult(api.GET('/club'))
  if (result.ok) club.value = result.data
  else failure.value = result.error
}

onMounted(loadClub)

// La pestaña dice dónde se está y de qué club: «Equipos · Celtic Castilla» (LLD-B §10.2).
watchEffect(() => {
  document.title = club.value ? `${route.meta.title} · ${club.value.shortName}` : 'Backoffice'
})

// Al cambiar de pantalla, el foco va a su título, y el lector de pantalla lo lee (LLD-B §10.2). Solo si cambia
// el camino: cambiar de temporada en la portada cambia la dirección, y el foco tiene que seguir en el selector.
// Al abrir la web, tampoco: el foco empieza al principio de la página, donde está «Saltar al contenido».
useRouter().afterEach((to, from) => {
  if (from.matched.length === 0 || to.path === from.path) return
  nextTick(() => {
    const title = document.querySelector<HTMLElement>('main h1')
    title?.setAttribute('tabindex', '-1')
    title?.focus()
  })
})

// Si falta el club en la dirección, cómo abrirla bien (LLD-B §8.3). En local, con el club de desarrollo.
function exampleAddress(): string {
  const host = location.host.replace(/^www\./, '')
  return import.meta.env.DEV ? `celtic-castilla.${host}` : `tu-club.${host}`
}
</script>

<template>
  <FullPageError
    v-if="failure"
    :message="failure.message"
    :code="failure.code"
    :retry="failure.retry"
    :hint="failure.code === 'TENANT_NOT_RESOLVED' ? `Por ejemplo: ${exampleAddress()}` : undefined"
    @retry="loadClub"
  />
  <div
    v-else
    class="frame"
  >
    <!-- Lo primero que alcanza el tabulador, para no recorrer el menú entero cada vez (LLD-B §10.1). -->
    <a
      class="skip-link"
      href="#contenido"
    >Saltar al contenido</a>
    <AppHeader
      class="header"
      :short-name="club?.shortName"
      :crest-url="club?.crestUrl"
    />
    <SideMenu
      v-if="club"
      class="menu"
    />
    <main
      id="contenido"
      class="content"
      tabindex="-1"
    >
      <RouterView v-if="club" />
      <!-- Se lee en voz alta sin mover el foco (LLD-B §10.3). -->
      <p
        v-else
        role="status"
      >
        Cargando…
      </p>
    </main>
  </div>
</template>

<style scoped>
.frame {
  display: grid;
  grid-template-columns: 14rem 1fr;
  grid-template-rows: auto 1fr;
  grid-template-areas:
    'header header'
    'menu content';
  min-height: 100vh;
}
.header {
  grid-area: header;
}
.menu {
  grid-area: menu;
}
.content {
  grid-area: content;
  padding: 1.5rem;
}
.content:focus {
  outline: none;
}
/* En una pantalla estrecha, el menú pasa arriba, debajo de la cabecera. */
@media (max-width: 40rem) {
  .frame {
    grid-template-columns: 1fr;
    grid-template-rows: auto auto 1fr;
    grid-template-areas: 'header' 'menu' 'content';
  }
}
/* Fuera de la vista hasta que recibe el foco con el tabulador. */
.skip-link {
  position: absolute;
  left: 1rem;
  top: -10rem;
  z-index: 1;
  padding: 0.5rem 1rem;
  background: var(--p-primary-color);
  color: var(--p-primary-contrast-color);
}
.skip-link:focus {
  top: 0.5rem;
}
</style>
