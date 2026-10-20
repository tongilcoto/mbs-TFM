import { createRouter, createWebHistory } from 'vue-router'
import HomeScreen from './screens/home/HomeScreen.vue'
import NotFoundScreen from './screens/not-found/NotFoundScreen.vue'

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
    // Cualquier otro camino (LLD-B §6.7).
    { path: '/:anything(.*)*', component: NotFoundScreen, meta: { title: 'Esta página no existe' } },
  ],
})
