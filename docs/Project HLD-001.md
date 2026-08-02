# Definición de Alto Nivel del Proyecto (HLD)

> Documento de diseño de alto nivel. Describe los artefactos que componen el sistema, sus objetivos y cómo se relacionan entre sí. Este documento se mantiene **agnóstico de tecnología**; las opciones que se citan son ejemplos. **La elección tecnológica concreta ya está tomada** en [ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md) (BD/API y su despliegue) — cada artefacto de servidor remite a ese ADR para la decisión.

## 1. Contexto y propósito

El proyecto cubre las necesidades de **gestión técnica de pequeños clubs de fútbol españoles**. Su ámbito es la gestión manual de estadísticas de los distintos equipos del club, en todas las categorías (desde pre-benjamín a senior), pudiendo existir varios equipos por categoría.

El sistema se compone de cinco artefactos software y de los servicios cloud que los alojan. Tres artefactos (base de datos, API backend y web backoffice) se despliegan en cloud; las dos aplicaciones móviles se distribuyen a los usuarios finales como clientes de consulta.

### Alcance de negocio: de un club a varios (multi-tenant)

El caso base sigue siendo **un único club**: el sistema es plenamente útil para un solo club sin ninguna otra consideración. Como **evolución del alcance de negocio**, el producto puede ofrecerse a **varios clubs** en modo **SaaS multi-tenant**, con **dos modelos de propiedad**:

- **Gestionado por el proveedor:** varios clubs (habitualmente pequeños) conviven en una instancia compartida, con **aislamiento de datos por club**.
- **Instancia dedicada del club:** un club dispone de su propia instancia/proyecto y sus propias claves.

Esta ampliación **no cambia el caso de un solo club**; es una decisión de alcance soportada por la arquitectura elegida (ver [ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md), decisión de multi-tenancy). El detalle fino de tenancy/auth podrá abordarse en un ADR propio.

### Objetivo general

Ofrecer al club una herramienta sencilla para **registrar y consultar** la información deportiva de sus equipos y jugadores: composición de equipos, partidos, y estadísticas asociadas, con una entrada de datos manual y una consulta cómoda desde el móvil.

### Roles de usuario (preliminar)

- **Personal técnico / administrativo del club**: introduce y mantiene los datos a través del backoffice web (rol de escritura) y se monitorizan en las apps móviles.
- No hay acceso a aficionados o familiares

## 2. Artefactos

### 2.1. Base de datos

**Qué es.** El repositorio central y única fuente de verdad de la información del club: estructura organizativa (categorías, equipos, jugadores, staff), partidos y estadísticas.

**Objetivos.**

- Modelar de forma consistente la jerarquía categoría → equipo → jugador y la relación con partidos y estadísticas.
- Garantizar la integridad de los datos que se introducen manualmente.
- Servir de base para las consultas que realizan el resto de artefactos (siempre a través de la API, nunca de forma directa).
- Contemplar el **ciclo de vida del dato**: conservación activa, **archivado reversible** de temporadas concluidas (se ocultan sin perderse) y **borrado definitivo** cuando proceda — relevante por **RGPD** y por tratarse de **datos de menores**. El mecanismo concreto se define en el LLD.

**Opciones tecnológicas a valorar (ejemplos, no decididas).**

- Relacional: PostgreSQL, MySQL/MariaDB, SQL Server.
- Documental / NoSQL: MongoDB, DynamoDB, Firestore.
- La naturaleza fuertemente estructurada y relacional de los datos (jerarquías y estadísticas agregadas) sugiere evaluar primero las opciones relacionales, sin descartar alternativas.

**Decisión ([ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md)):** **PostgreSQL** gestionado en **Supabase** (BD + Auth + Storage), **región UE** (RGPD). Aislamiento por club vía *schema* (gestionado) o proyecto (dedicado).

### 2.2. API backend

**Qué es.** El servicio central que expone la lógica de negocio y media todo acceso a los datos. Es el único componente que habla con la base de datos.

**Objetivos.**

- Exponer operaciones de **escritura** (alta/edición/baja de equipos, jugadores, partidos, estadísticas) consumidas por el backoffice.
- Exponer operaciones de **lectura** (consulta de equipos, jugadores y estadísticas) consumidas por las apps móviles.
- Centralizar validación, reglas de negocio, autenticación y autorización.
- Desacoplar los clientes (web y móviles) del modelo de datos concreto.

**Opciones tecnológicas a valorar (ejemplos, no decididas).**

- Estilo de API: REST, GraphQL.
- Plataformas/lenguajes: Node.js (NestJS, Express), Python (FastAPI, Django REST), Java/Kotlin (Spring Boot), .NET, Go, Vapor (Swift).

**Decisión ([ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md)):** API **REST** en **Swift con Vapor + Fluent** (ORM oficial). Autenticación con **Supabase Auth**. API *tenant-aware* (enruta al *schema* del club).

### 2.3. Web backoffice

**Qué es.** La aplicación web de gestión utilizada por el personal del club para introducir y mantener manualmente toda la información.

**Objetivos.**

- Proporcionar la interfaz principal de **entrada y mantenimiento de datos**.
- Cubrir la gestión de categorías, equipos, jugadores/staff, partidos y sus estadísticas.
- Ofrecer autenticación y control de acceso para el personal autorizado.

**Opciones tecnológicas a valorar (ejemplos, no decididas).**

- SPA: React, Vue, Angular, Svelte.
- Frameworks con render en servidor: Next.js, Nuxt, Remix.

### 2.4. App iOS de consulta

**Qué es.** Aplicación móvil nativa o multiplataforma para dispositivos iOS, orientada exclusivamente a la **consulta** de información.

**Objetivos.**

- Permitir al cuerpo técnico del club consultar equipos, jugadores y estadísticas de forma cómoda desde el móvil.
- Ofrecer una experiencia adaptada a iOS.

**Opciones tecnológicas a valorar (ejemplos, no decididas).**

- Nativo: Swift / SwiftUI.
- Multiplataforma (compartida con Android): React Native, Flutter, Kotlin Multiplatform.

### 2.5. App Android de consulta

**Qué es.** Equivalente a la app iOS, para dispositivos Android, también orientada exclusivamente a la **consulta**.

**Objetivos.**

- Los mismos que la app iOS, adaptados al ecosistema Android.

**Opciones tecnológicas a valorar (ejemplos, no decididas).**

- Nativo: Kotlin / Jetpack Compose.
- Multiplataforma (compartida con iOS): React Native, Flutter, Kotlin Multiplatform.

> Nota: las apps móviles serán **nativas** (iOS en **Swift/SwiftUI**, Android en **Kotlin/Jetpack Compose**); no comparten base de código entre sí. La app iOS **comparte lenguaje con la API** (Swift → posible reutilización de DTOs `Codable`), según la decisión de backend del [ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md).

### 2.6. Servicios cloud (alojamiento)

**Qué es.** La infraestructura contratada para desplegar y operar los tres artefactos de servidor (base de datos, API backend y web backoffice).

**Objetivos.**

- Alojar de forma fiable y accesible los componentes de servidor.
- Cubrir necesidades transversales: red, seguridad, copias de seguridad, escalado y observabilidad, dimensionadas para un club pequeño (coste contenido).

**Opciones tecnológicas a valorar (ejemplos, no decididas).**

- Proveedores: AWS, Google Cloud, Microsoft Azure, y opciones más sencillas orientadas a proyectos pequeños (Render, Railway, Fly.io, Vercel, Supabase).
- Modelo de despliegue: contenedores, plataforma gestionada (PaaS) o serverless.

**Decisión ([ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md)):** **Supabase** (BD + Auth + Storage) para los datos + **PaaS con Docker** para la API (**Fly.io** preferente por el *build* de Swift; Railway/Render alternativas). Todo en **región UE**. Multi-tenancy híbrida (una base de código; provisión por *schema* o por proyecto según el modelo de propiedad).

## 3. Relación entre artefactos

El sistema sigue una arquitectura cliente–servidor con la **API backend como punto central**. Ningún cliente accede directamente a la base de datos.

```
   ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐
   │  Web backoffice │        │    App iOS      │        │   App Android   │
   │   (escritura)   │        │   (consulta)    │        │   (consulta)    │
   └────────┬────────┘        └────────┬────────┘        └────────┬────────┘
            │                          │                          │
            │  escritura + lectura     │  lectura                 │  lectura
            └──────────────┬───────────┴──────────────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │   API backend   │   (lógica de negocio, auth,
                  │                 │    validación, autorización)
                  └────────┬────────┘
                           │  único acceso a datos
                           ▼
                  ┌─────────────────┐
                  │  Base de datos  │
                  └─────────────────┘

   Servicios cloud alojan: API backend, Web backoffice y Base de datos.
```

**Flujos principales.**

- **Entrada de datos (escritura).** El personal del club usa el *web backoffice* → llama a la *API backend* → la API valida y persiste en la *base de datos*.
- **Consulta (lectura).** Las *apps iOS/Android* → llaman a la *API backend* → la API lee de la *base de datos* y devuelve la información. El *web backoffice* también consulta datos por esta misma vía.
- **Alojamiento.** *Base de datos*, *API backend* y *web backoffice* se ejecutan sobre los *servicios cloud*. Las apps móviles se distribuyen a los dispositivos de los usuarios y se comunican con la API a través de Internet.

**Principios de relación.**

- La **API backend es la única frontera de acceso a la base de datos**; concentra reglas de negocio, autenticación y autorización.
- Los **clientes están desacoplados** del modelo de datos: solo conocen el contrato de la API.
- **Separación de responsabilidades por rol**: el backoffice es el canal de escritura; las apps móviles son canales de solo lectura.

## 4. Alcance y próximos pasos

Este documento fija el marco de alto nivel. La **selección de tecnologías de BD/API y su estrategia de despliegue** ya está resuelta en [ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md), incluida la ampliación de alcance a **multi-tenant**. Quedan para **propuestas/ADRs posteriores**: el **modelo de datos detallado**, el **contrato de la API**, el **detalle fino de tenancy/auth** (roles, provisión y migraciones por tenant) y la **estimación de costes cloud** por *tier*.
