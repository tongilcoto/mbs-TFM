import { createRouter, createWebHistory } from 'vue-router'
import HomeScreen from './screens/home/HomeScreen.vue'
import NewTeamScreen from './screens/new-team/NewTeamScreen.vue'
import NotFoundScreen from './screens/not-found/NotFoundScreen.vue'
import SyncTeamScreen from './screens/sync-team/SyncTeamScreen.vue'

// Lo que cada pantalla pone delante del nombre del club en la pestaña del navegador (LLD-B §10.2).
declare module 'vue-router' {
  interface RouteMeta {
    title: string
  }
}

// El mapa de pantallas (LLD-B §6).
export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', component: HomeScreen, meta: { title: 'Equipos' } },
    // La lista de equipos es la portada; /equipos lleva a ella, como el resto de secciones del menú (LLD-B §6.1).
    { path: '/equipos', redirect: '/' },
    { path: '/equipos/nuevo', component: NewTeamScreen, meta: { title: 'Alta de equipo' } },
    // El enganche, en dos pasos en el mismo camino (plan R3, decisión 2).
    { path: '/equipos/:id/federacion', component: SyncTeamScreen, meta: { title: 'Sincronizar con la Federación' } },
    // Cualquier otro camino (LLD-B §6.7).
    { path: '/:anything(.*)*', component: NotFoundScreen, meta: { title: 'Esta página no existe' } },
  ],
})
