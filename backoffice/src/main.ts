import PrimeVue from 'primevue/config'
import { createApp } from 'vue'
import App from './App.vue'
import { router } from './router'
import { primeVueOptions } from './theme/primevue'

createApp(App).use(router).use(PrimeVue, primeVueOptions).mount('#app')
