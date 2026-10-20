<!-- El menú lateral (LLD-B §6.6): solo lo que ya existe. En la rebanada 1, «Equipos». -->
<template>
  <nav
    class="side-menu"
    aria-label="Menú principal"
  >
    <ul>
      <li>
        <!-- RouterLink marca la entrada de la pantalla abierta con aria-current, que el lector dice en voz alta. -->
        <RouterLink to="/">
          Equipos
        </RouterLink>
      </li>
    </ul>
  </nav>
</template>

<style scoped>
.side-menu {
  padding: 1rem;
  background: var(--p-content-background);
  border-right: 1px solid var(--p-content-border-color);
}
ul {
  margin: 0;
  padding: 0;
  list-style: none;
}
a {
  display: block;
  padding: 0.5rem 0.75rem;
  border-radius: 0.375rem;
  color: var(--p-text-color);
  text-decoration: none;
}
a:hover {
  background: var(--p-content-hover-background);
}
/* La pantalla abierta: en otro color y en negrita, para no depender solo del color (LLD-B §9.4). */
a[aria-current='page'] {
  color: var(--p-primary-color);
  font-weight: 600;
}
</style>
