import { createRouter, createWebHistory } from 'vue-router'
import CompetitionScreen from './screens/competition/CompetitionScreen.vue'
import HomeScreen from './screens/home/HomeScreen.vue'
import NewTeamScreen from './screens/new-team/NewTeamScreen.vue'
import NotFoundScreen from './screens/not-found/NotFoundScreen.vue'
import SyncTeamScreen from './screens/sync-team/SyncTeamScreen.vue'
import TeamScreen from './screens/team/TeamScreen.vue'

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
    // La ficha del equipo, con la temporada en el camino (plan R4, decisión 3; LLD-B §6.4 y §6.5). Sin pestaña, la
    // de Resultados; sin temporada, la pantalla pone la que toca en cuanto sabe cuáles hay.
    { path: '/temporadas/:temporada/equipos/:id/resultados', component: TeamScreen, meta: { title: 'Resultados' } },
    { path: '/temporadas/:temporada/equipos/:id', redirect: (to) => `${to.path.replace(/\/$/, '')}/resultados` },
    { path: '/equipos/:id', component: TeamScreen, meta: { title: 'Resultados' } },
    // Jornada y clasificación de una competición, con la jornada detrás de `?` (plan R4, decisión 3).
    { path: '/temporadas/:temporada/competiciones/:id', component: CompetitionScreen, meta: { title: 'Jornada y clasificación' } },
    // Cualquier otro camino (LLD-B §6.7).
    { path: '/:anything(.*)*', component: NotFoundScreen, meta: { title: 'Esta página no existe' } },
  ],
})
