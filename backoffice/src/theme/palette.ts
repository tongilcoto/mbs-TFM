// Los colores de la web, todos aquí (plan R1, decisión 7). Cambiar los colores es tocar este fichero y nada más:
// ninguna pantalla escribe un color a mano (LLD-B §9.2).
//
// Son provisionales. El oscuro sale del boceto 1 (docs/design-assets/mobile/1-Teams_Dashboard.png), medido
// sobre sus píxeles; el claro, que el boceto no tiene, es el de Aura, el tema de PrimeVue del que se parte.
// Cada texto se lee sobre su fondo con el contraste mínimo de nivel AA (LLD-B §9.4): lo vigila palette.test.ts.
export const palette = {
  // Botones, enlaces y lo seleccionado. PrimeVue calcula sus tonos (más claro, más oscuro) a partir de este.
  // En modo claro se usa un tono más oscuro del mismo verde, porque este no se lee sobre blanco (primevue.ts).
  principal: '#60ca3b',
  oscuro: {
    fondo: '#0b1424',
    superficie: '#131c2c', // tarjetas, tablas y menús, encima del fondo
    texto: '#dae3f9',
    // El del boceto, #77829b, se queda en 4,43 sobre la superficie: este es el más parecido que llega a 4,5.
    textoSuave: '#7a859e',
  },
  claro: {
    fondo: '#f8fafc',
    superficie: '#ffffff',
    texto: '#334155',
    textoSuave: '#64748b',
  },
}
