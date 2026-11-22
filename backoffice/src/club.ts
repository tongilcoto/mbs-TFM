// El club que pide el marco al arrancar (LLD-B §2.1, DW-24): su nombre y su escudo, y lo que publica su federación.
// Lo guarda App.vue al recibirlo y lo leen las pantallas, que solo se pintan cuando ya está (§8.1). Como el aviso
// «Guardado» (notice.ts): uno solo para toda la web, mientras la pestaña está abierta.
import { computed, ref } from 'vue'
import type { components } from './api/schema'

export type Club = components['schemas']['ClubResponse']

export const club = ref<Club>()

// Si la federación del club publica la clasificación de cada jornada (D-29, D-55). Si no, solo la de hoy: las
// jornadas anteriores las calcula la aplicación con los resultados.
export const roundStandingsPublished = computed(() => club.value?.federationProvidesRoundStandings !== false)
