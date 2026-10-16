import { createRouter, createWebHistory } from 'vue-router'
import HomeScreen from './screens/home/HomeScreen.vue'

// El mapa de pantallas (LLD-B §6). De momento, solo la portada, en blanco.
export const router = createRouter({
  history: createWebHistory(),
  routes: [{ path: '/', component: HomeScreen }],
})
