# ADR-001 · Selección de tecnologías de API backend y Base de datos

- **Estado:** Cerrado (ver §2). Todas las decisiones (1–6) tomadas; quedan detalles de implementación en §10–§11.
- **Fecha:** 2026-08-01
- **Decisores:** desarrollador único (+ Claude Code)
- **Relacionado:** [Project HLD-001](./Project%20HLD-001.md), [Project Seed](./Project%20Seed.md)

> **Cómo leer este ADR.** El cuerpo (§3 en adelante) recorre cada **punto de decisión** con el mismo
> formato: **opciones (pros/contras) → decisión → razones**. Los **anexos A–D** contienen el material de
> apoyo ampliado que respalda esas razones. La §2 resume todas las decisiones de un vistazo.

---

## 1. Contexto y requisitos

Se elige la tecnología de **base de datos** y **API backend** para el sistema de gestión técnica de
pequeños clubs de fútbol (ver HLD-001). Ambas decisiones están acopladas (ORM, proveedor cloud, auth) y se
toman de forma conjunta. El producto ha pasado de servir a un club a ser un **SaaS B2B multi-tenant**.

**Requisitos que guían la decisión:**

1. **Datos fuertemente relacionales** (categoría → equipo → jugador, partidos, estadísticas). → favorece **SQL**.
2. **ORM obligatorio** con migraciones de esquema versionadas.
3. **Integración cloud sin fricción API ↔ BD.**
4. **Auth facilitada por la BD/plataforma** (se implementa más adelante, pero la elección debe prepararla).
5. **Un desarrollador + coste contenido: tope 20 $/mes** para los servicios cloud del backend.
6. **Un solo backend, varios clientes** (web backoffice de escritura; apps móviles de lectura). La API es la
   única frontera de acceso a la BD.
7. **RGPD — requisito duro.** Datos de **menores** → **residencia de datos en la UE** obligatoria.
8. **Multi-tenancy (SaaS).** Se vende a varios clubs, con **dos modelos de propiedad**: (a) el club
   **mantiene su propio proyecto/claves** (instancia dedicada); (b) el club (pequeño) prefiere que **el
   desarrollador lo gestione** (instancia compartida). Requiere **aislamiento de datos por club**.
   > **Alcance:** esto **amplía el HLD-001** (asumía un solo club); convendrá actualizarlo y, quizá,
   > dedicar un **ADR propio** al modelo de tenancy/auth.

---

## 2. Resumen de decisiones

| # | Punto de decisión | Estado | Decisión |
|---|-------------------|--------|----------|
| 1 | Motor de base de datos | ✅ Decidido | **PostgreSQL** |
| 2 | Proveedor de BD + hosting de datos | ✅ Decidido | **Supabase** (BD + Auth + Storage), región UE |
| 3 | Autenticación | ✅ Decidido | **Supabase Auth**, *pool* `auth.users` **compartido** |
| 4 | Modelo de multi-tenancy | ✅ Decidido | **Híbrido, código único**: managed = *schema* por club; silo = proyecto por club. **Pooled descartado** |
| 5 | Lenguaje/framework de la API + ORM | ✅ Decidido | **Swift — Vapor + Fluent** (ORM oficial) |
| 6 | Despliegue de la API | ✅ Decidido | **PaaS con Docker**; **Fly.io** preferente para Vapor (Railway/Render posibles) |

**Stack resultante:** **API en Swift (Vapor + Fluent)** sobre **PostgreSQL en Supabase (BD + Auth), región
UE**, desplegada en un **PaaS vía Docker (Fly.io preferente)**, con **multi-tenancy híbrida y una sola base
de código**. Quedan solo detalles de implementación (§10–§11).

---

## 3. Decisión 1 — Motor de base de datos

**En discusión:** qué paradigma y motor de BD usar, dado el carácter relacional de los datos y el requisito de ORM.

| Opción | Pros | Contras |
|--------|------|---------|
| **PostgreSQL** | Encaje relacional; ORMs de primera clase; **RLS**; JSONB/extensiones; soporte universal en proveedores; *free tiers* | Requiere pensar esquema/migraciones desde el inicio |
| **MySQL / MariaDB** | Relacional, extendido, buen soporte de ORMs | Menos rico (tipos, RLS, extensiones); el ecosistema con auth integrada (Supabase) gira en torno a Postgres |
| **NoSQL** (MongoDB, Firestore) | Esquema flexible; Firestore trae auth/realtime | **Mal encaje** con datos relacionales y estadísticas; `JOIN`/integridad en la app; migraciones y consistencia manuales |

**Decisión:** **PostgreSQL.**

**Razones:**
- Es el que mejor cumple los requisitos 1 (relacional), 2 (ORM) y 4 (RLS como base de autorización).
- Portable entre proveedores (evita *lock-in* del modelo de datos) y disponible en todas las opciones de hosting.

---

## 4. Decisión 2 — Proveedor de BD y hosting de datos

**En discusión:** dónde vive el Postgres y con qué servicios se integra (auth, storage), bajo el tope de
20 $/mes y con **región UE** obligatoria.

| Opción | Pros | Contras |
|--------|------|---------|
| **Supabase** (Postgres + Auth + Storage) | Postgres puro gestionado (portable); **Auth + RLS + Storage** integrados; *free tier*; **región UE**; buena DX solo-dev | La suite rinde al máximo con su modelo; salto a **Pro 25 $** supera el tope |
| **Postgres integrado del PaaS** (Railway/Render) | **Máxima** integración API↔BD (misma red, `DATABASE_URL` inyectada); un solo proveedor; coste bajo/predecible | **Sin auth ni storage** de fábrica; sin RLS de producto ni panel rico |
| **Neon** | Postgres *serverless*, *branching* para pruebas | Sin auth integrada |
| **Hyperscaler** (RDS/Cloud SQL/Azure) | Robustez, escalado, catálogo de servicios | **Complejidad operativa/coste** excesivos para un dev único |

**Decisión:** **Supabase** (BD + Auth + Storage), configurado en **región UE**.

**Razones:**
- Trae **Auth + RLS + Storage** junto a los datos → cubre el requisito 4 y el almacenamiento de imágenes
  (escudos/fotos) sin proveedores extra.
- Postgres estándar por debajo → **portable**, sin *lock-in*.
- **Consecuencia de la Decisión 3:** al elegir **Supabase Auth**, `auth.users` debe vivir en el Postgres de
  Supabase → **la BD queda en Supabase en ambos tiers**. Por eso se **descarta** la opción "Postgres del
  PaaS" *para la base de datos* (el PaaS solo alojará la **API**, ver §8).
- El salto a **Pro (25 $)** se gestiona en el presupuesto por *tier* (ver §9 y Anexo A.6).

**Más detalle:** comparativa de proveedores, "Postgres del PaaS vs Supabase" y coste → **Anexo A**.

---

## 5. Decisión 3 — Autenticación

**En discusión:** cómo se autentican los usuarios (personal del club), preparando el terreno para
implementarlo más adelante, y de forma coherente con la multi-tenancy (§6).

| Opción | Pros | Contras |
|--------|------|---------|
| **Supabase Auth** (GoTrue) | Cero infra extra; **gratis**; **RLS**; región UE; usuarios en la misma Postgres; rápido | Acoplado a Supabase; menos features *enterprise* (SSO, orgs) |
| **Clerk / Auth0** (IdP externo) | Features ricas; **"Organizations"** (multi-tenant nativo); portable | Tercero adicional; **residencia UE** del IdP a verificar; coste escala |
| **Propia** (JWT en la API) | Control total; datos 100 % en tu Postgres/UE; coste 0 | **Seguridad a tu cargo** (alto riesgo); más código y mantenimiento |

**Decisión:** **Supabase Auth**, con **un *pool* de usuarios `auth.users` compartido**.

**Razones:**
- **El mismo código sirve para los dos tiers** (managed y silo): en ambos la auth es Supabase Auth con
  `auth.users` + JWT con *claim* `club_id` + la API haciéndolo cumplir. Solo cambia la **provisión** (un
  proyecto compartido con *schema* por club vs un proyecto por club). Se **descarta IdP externo** para no
  duplicar mecanismo entre tiers.
- **Asunción aceptada:** el co-mingling de **cuentas de staff** en un `auth.users` compartido (tier managed)
  es de **bajo riesgo** (baja sensibilidad frente a los datos deportivos de menores, poco volumen). El
  aislamiento de **datos de dominio** se mantiene por ***schema* por club** (no pooled).
- **Matiz técnico asumido:** que "cada usuario solo vea su club" lo garantizan los *claims* + la API/RLS,
  **no** la plataforma (GoTrue autentica, no autoriza por *schema*). Ver Anexo B.5.

**Más detalle:** las 3 opciones a fondo y el alcance de GoTrue (authN vs authZ, alcance de proyecto) → **Anexo B**.

---

## 6. Decisión 4 — Modelo de multi-tenancy

**En discusión:** cómo se aíslan los datos de cada club, dado que el producto se vende a varios y ninguno
aceptará compartir tablas con otros (RGPD, datos de menores).

| Opción | ¿Co-mingla filas? | Aislamiento | Coste/ops | Veredicto |
|--------|-------------------|-------------|-----------|-----------|
| **Pooled** (`club_id` + RLS, mismas tablas) | **Sí** | Solo lógico | Mínimo | ❌ **Descartado** (no vendible) |
| ***Schema* por club** (misma BD, tablas separadas) | **No** (datos) | Bueno | Bajo (1 instancia) | ✅ **Tier managed** |
| **Proyecto por club** (silo) | **No** (datos e identidades) | Máximo (físico) | Alto (×N) | ✅ **Tier dedicado** |

**Decisión:** **arquitectura híbrida con una sola base de código**, **descartando pooled**:
- **Tier managed** (clubs gestionados por ti): varios clubs en **un** proyecto Supabase, ***schema* por
  club** + `auth.users` compartido.
- **Tier dedicado / silo** (clubs que quieren su propiedad/claves): **un proyecto Supabase por club**.
- La API es **tenant-aware**: resuelve el club (subdominio / *claim* `club_id`) y **enruta al *schema***
  correspondiente. **Mismo código en ambos tiers; solo cambia la provisión.**

**Razones:**
- Un club **no firma** un modelo de datos co-minglados → *schema* por club aísla los **datos de dominio** sin
  necesidad de una instancia por club en el tier económico.
- El `auth.users` compartido (Decisión 3) es coherente: mismo mecanismo de auth en los dos tiers.
- Escala de **decenas–cientos** de clubs por instancia: más que suficiente; pooled solo se justificaría a miles.

**Más detalle:** patrones, alcance de `auth.users`, arquitectura y automatización de migraciones → **Anexo C**.

---

## 7. Decisión 5 — Lenguaje/framework de la API + ORM

**En discusión:** en qué lenguaje/framework se construye la API y con qué ORM, sabiendo que (a) el web
backoffice será TS/React, (b) las apps móviles son **nativas** (iOS Swift, Android Kotlin) y (c) el ORM debe
**enrutar la conexión por tenant** (*schema* por club).

| Opción | Pros | Contras |
|--------|------|---------|
| **Swift — Vapor + Fluent** *(elegida)* | **Unifica con la app iOS nativa** (Swift, DTOs `Codable`); **ORM oficial** (Fluent) integrado; enruta varias BD (multi-tenant); velocidad de un dev que domina el ecosistema Apple | **Comunidad menor**; **despliegue vía Docker** (compilar Swift consume RAM → se resuelve en CI/builder remoto); no unifica con el backoffice |
| **TypeScript — NestJS + Drizzle/Prisma** | Unifica con el **web backoffice** (TS); ecosistema grande; despliegue ligero; OpenAPI | Prisma flojo en multi-tenant → Drizzle/TypeORM; no unifica con iOS |
| **Python — FastAPI + SQLAlchemy** | Muy productivo; **SQLAlchemy** excelente en multi-tenant; OpenAPI automático | Segundo lenguaje frente al front |

**Decisión:** **Swift — Vapor + Fluent.**

**Razones:**
- **Eje de unificación elegido: API ↔ app iOS nativa** (ambas Swift), con posibilidad de **compartir DTOs
  `Codable`**. El backoffice (TS/React) y Android (Kotlin) van aparte en cualquier caso (mismo nº de
  lenguajes que con NestJS; ver Anexo D.4).
- **Productividad del desarrollador:** dominio del ecosistema Apple → un dev único **entrega más rápido** en
  un stack que conoce y disfruta (input de negocio legítimo).
- **ORM oficial (Fluent)** cumple el requisito 2 sin terceros, con Postgres recomendado y **enrutado por
  tenant** (registrar varias BD / `search_path`), que encaja con la Decisión 4.
- **El riesgo de RAM en *build* se neutraliza** compilando en **CI o *builder* remoto** (no en el host) →
  el host solo ejecuta el binario, con footprint pequeño (ver Anexo D.2).

**Riesgos asumidos (Anexo D.4):** cantera/*handoff* más pequeña (server-Swift) y ecosistema SaaS (Stripe,
email…) menos maduro que Node/Python; mitigables, no bloqueantes.

**Más detalle:** ORM/conectividad, despliegue (RAM, CI, hosting/precio), OpenAPI y comparación de negocio → **Anexo D**.

---

## 8. Decisión 6 — Despliegue de la API

**En discusión:** cómo se despliega la API Swift/Vapor (la BD ya está en Supabase, §4), sabiendo que Vapor
se despliega **vía Docker** y que compilar Swift consume RAM.

| Opción | Pros | Contras |
|--------|------|---------|
| **PaaS con Docker** (Fly.io, Railway, Render) | Despliegue automatizado; bajo coste; **región UE**; mínima fricción solo-dev | Compilar Swift necesita RAM → resolver dónde se hace el *build* |
| **Serverless** (Cloud Run, Lambda…) | Escala a cero, pago por uso | *Cold starts*; *pooling* de conexiones a Postgres |
| **Contenedores/K8s** | Máximo control | Sobredimensionado hoy |

**Decisión:** **PaaS con Docker**, con **Fly.io como opción preferente para Vapor**; **Railway/Render**
como alternativas válidas. La elección fina es **aplazable al despliegue** (no afecta al código).

**Razones:**
- Para Swift/Vapor, **Fly.io es el host más cómodo**: su CD estándar es una **GitHub Action que ejecuta
  `fly deploy`**, y el *build* corre en un ***builder* remoto dimensionable** → **compila Swift sin OOM** sin
  montar el ciclo "build en CI + push de imagen". Mantiene "push → deploy".
- **Railway/Render** siguen sirviendo (build nativo desde GitHub); si su *builder* se queda corto de RAM con
  Swift, se compila en **CI** (GitHub Actions, ~16 GB) y se despliega la imagen ya construida.
- **Coste** dentro de presupuesto: host de runtime pequeño (~512 MB–1 GB) ≈ **3–7 $/mes**; *build* en CI ≈ **0 $**.
- Todos ofrecen **región UE**.

**Más detalle:** RAM de *build* vs *runtime*, modelos de despliegue, hosting/precio y por qué Fly encaja
mejor con Vapor → **Anexo D.2**; proveedores y coste → **Anexo A**.

---

## 9. Consecuencias y presupuesto

**Consecuencias:**
- **Positivas:** BD + Auth + Storage integrados (Supabase); Postgres portable; una sola base de código para
  los dos tiers de tenancy; coste de arranque bajo; datos en la UE.
- **Negativas / riesgos:** dependencia de Supabase (mitigada por Postgres estándar); el aislamiento de
  **identidades** en el tier managed es lógico (no físico) → exige *claims*/RLS correctos; **migraciones por
  tenant** que hay que automatizar; salto a Supabase Pro (25 $) a vigilar; **cantera server-Swift pequeña** y
  ecosistema SaaS menos maduro (riesgo de *handoff*, ver Anexo D.4).
- **Reversibilidad:** alta en la capa de datos (Postgres portable); **media-baja en el framework** (Vapor/Fluent
  son específicos de Swift; migrar de lenguaje reescribe la API, aunque el modelo de datos se conserva); la auth
  queda acoplada a Supabase (migrar a otro IdP tendría coste).

**Presupuesto (tope 20 $/mes), por *tier*:**

| Tier | BD + Auth | API (Vapor, runtime) | *Build* | Coste aprox. | ¿Cabe? |
|------|-----------|----------------------|---------|--------------|--------|
| **Managed (arranque/TFM)** | Supabase Free/Pro | Fly.io/Railway ~512 MB–1 GB | CI o builder remoto | ~3–7 $ (Free) / ~30 $ (Pro) | ✅ Free / ⚠️ Pro supera |
| **Dedicado (silo)** | Proyecto Supabase por club | (según modelo) | — | ~10 $/proyecto | Financiado/repercutido al club |

Estrategia y detalle → **Anexo A.6**.

---

## 10. Aspectos transversales (a resolver en implementación / ADRs siguientes)

- **Autorización:** modelo de roles (escritura backoffice vs lectura apps) y *claims* de tenant (`club_id`,
  `role`) vía **Auth Hook**; **RLS** como capa extra dentro de cada *schema*.
- **Migraciones:** versionadas y en CI; **automatizar la aplicación por *schema*/proyecto** (recorrer todos los tenants).
- **Enrutado por tenant:** resolver club → `SET search_path`; **resetear `search_path`** al devolver la
  conexión al *pool* (evitar fugas de contexto).
- **Contrato de la API (OpenAPI):** elegir entre **swift-openapi-generator + `vapor/swift-openapi-vapor`**
  (*design-first*, oficial) o **VaporToOpenAPI** (*code-first*, anota rutas → Swagger UI). Ver Anexo D.3.
- **Despliegue/CI:** Dockerfile multi-stage de Vapor; compilar en **CI/builder remoto** (no en el host);
  GitHub Action `fly deploy` (o build+push de imagen en Railway/Render). Ver Anexo D.2.
- **Provisión de tenants:** automatizar alta (crear *schema*/proyecto) vía Management API + IaC/CI.
- **Copias de seguridad, gestión de secretos, observabilidad, entornos (dev/staging/prod).**

---

## 11. Cuestiones abiertas / próximos pasos

1. **Afinar el PaaS** (Fly.io preferente para Vapor; Railway/Render alternativas) y el flujo de *build*
   (`fly deploy` con builder remoto vs build en CI + push de imagen). → Anexo D.2 / A.4.
2. **Elegir el enfoque OpenAPI** de Vapor (design-first oficial vs VaporToOpenAPI). → Anexo D.4.
3. **Tier dedicado:** ¿proyecto Supabase por club (Management API) o despliegue completo? ¿quién posee/factura?
4. **Automatización de migraciones/provisión por tenant** (Fluent `AsyncMigration` recorriendo *schemas*/proyectos).
5. **Actualizar HLD-001** (naturaleza SaaS/multi-tenant) y valorar un **ADR dedicado a tenancy/auth**.

---
---

# Anexos (material de apoyo)

## Anexo A · Proveedores cloud, "Postgres del PaaS vs Supabase" y presupuesto

*(respalda las Decisiones 2, 6 y §9)*

### A.1 · Supabase (BD + Auth + Storage)
- Postgres gestionado con **Auth** (GoTrue, ver Anexo B), **Storage** (imágenes), *Realtime*, PostgREST y Studio.
- Se usa por **cadena de conexión** estándar → cualquier ORM externo; sin *lock-in*.
- **Región UE** (Frankfurt/otras). **Coste:** Free 0 $ (500 MB, se **pausa** por inactividad, sin backups
  diarios); **Pro 25 $/mes** (backups diarios/PITR, sin pausas). Proyectos adicionales ~**10 $/mes**.

### A.2 · Railway (PaaS para la API)
- Despliegue desde Git; aloja la API (contenedor) y, si se quisiera, Postgres; admite **Dockerfile propio**.
- **Región UE** (Amsterdam). **Coste:** por uso, ~5–15 $/mes. DX muy pulida.

### A.3 · Render (PaaS para la API)
- *Web services*, *cron*, Postgres gestionado; despliegue vía Docker o buildpacks.
- **Región UE** (Frankfurt). **Coste:** Free con *cold starts* o **Starter ~7 $/mes**; precios planos.

### A.4 · Railway vs Render (elección de la Decisión 6)
| Criterio | Railway | Render |
|----------|---------|--------|
| Precio | Por uso (crédito + consumo) | Planos fijos predecibles |
| Free tier | Crédito mensual | Web service free con *cold starts* |
| Región UE | Amsterdam | Frankfurt |
| Cuándo | DX moderna, API+extras juntos | Coste fijo y predecible |

> Ambos despliegan **imágenes Docker**, así que sirven también para **Vapor** (Anexo D.2). Elección aplazable.

### A.5 · Por qué se descartó "Postgres del PaaS" para la BD
El Postgres integrado del PaaS da la **mejor integración API↔BD** (misma red, `DATABASE_URL` inyectada) y
evita el salto a Supabase Pro. **Pero** no trae Auth ni Storage. Al haberse decidido **Supabase Auth**
(Decisión 3), `auth.users` debe estar en el Postgres de Supabase → la BD queda en Supabase y esta opción
sale **para la BD** (el PaaS solo aloja la API). Se conserva como alternativa si algún día se cambiara de
estrategia de auth.

### A.6 · Presupuesto por *tier* y estrategia
- **Managed:** arranca en **Supabase Free + PaaS Starter (~5–7 $)**. Vigilar límites del Free (tamaño, pausa,
  backups). El salto a **Pro (25 $)** supera el tope de 20 $/mes → valorar cuándo es imprescindible (backups
  diarios/PITR) y si se traslada a precio del servicio.
- **Dedicado (silo):** **financiado por el club** (su cuenta/claves) o **repercutido** (~10 $/proyecto). La
  multi-tenancy **no rompe** el tope del tier managed y traslada el coste del dedicado al club.
- **Región UE** en todos: Supabase (Frankfurt), Railway (Amsterdam), Render (Frankfurt).

---

## Anexo B · Autenticación en detalle

*(respalda la Decisión 3)*

Patrón común a las 3 opciones: el cliente obtiene un **JWT** y la API lo **valida** (JWKS/secreto) y mapea
el usuario a roles (escritura vs lectura) y a su club.

### B.1 · Supabase Auth (GoTrue) — *elegida*
- Usuarios en `auth.users` (esquema `auth` de la Postgres del proyecto); email/OAuth/*magic links*/MFA; JWT; RLS.
- **Pros:** cero infra, gratis, RLS, UE, rapidísimo. **Contras:** acoplamiento a Supabase; features *enterprise* limitadas.

### B.2 · Clerk / Auth0 (IdP externo)
- Emiten JWT; la API valida por JWKS. **"Organizations"** modelan multi-tenant de forma nativa.
- **Pros:** features ricas, portabilidad. **Contras:** tercero extra; **residencia UE** a verificar; coste escala.

### B.3 · Auth propia (JWT en la API)
- Tabla `users`, *hashing*, JWT, *refresh*, recuperación. **Pros:** control total, datos en UE, coste 0.
  **Contras:** **seguridad a tu cargo** (alto riesgo), más mantenimiento.

### B.4 · Comparativa
| Criterio | Supabase Auth | Clerk/Auth0 | Propia |
|----------|---------------|-------------|--------|
| Integración BD | Máxima (RLS) | Media | Total |
| Esfuerzo | Muy bajo | Bajo | Alto |
| Coste | 0 $ | Free amplio → escala | 0 $ |
| Datos usuarios en UE | ✅ | ⚠️ verificar | ✅ |
| Multi-tenant | *memberships*/claims | **Organizations** | A medida |
| Riesgo seguridad propio | Bajo | Bajo | **Alto** |

### B.5 · Alcance de GoTrue: authN ≠ authZ, y ámbito de proyecto (clave para §6)
- **GoTrue autentica, no autoriza.** Emite el JWT; **no concede acceso a *schemas* por usuario**. En Supabase
  **todos los usuarios autenticados usan el MISMO rol Postgres `authenticated`** (+ `anon`, `service_role`),
  así que un `GRANT ... ON SCHEMA ... TO authenticated` da acceso a **todos**. No hay "GRANT por usuario".
  - **Quién autoriza:** (1) **RLS** leyendo un *claim* (`club_id`, `role`); o (2) **la API**, que enruta al
    *schema* del club (`SET search_path`) según el *claim*.
  - GoTrue sí permite **inyectar *claims*** (Custom Access Token / **Auth Hook**), pero **la app/RLS los hacen cumplir**.
- **Alcance = proyecto (= una BD).** Un proyecto Supabase tiene **una** Postgres y **un** *pool* `auth.users`.
  → *Schema* por club en un proyecto ⇒ **identidades compartidas**; proyecto por club ⇒ identidades aisladas.
  "Otra BD" en Supabase = **otro proyecto** (no hay multi-BD por proyecto).

---

## Anexo C · Multi-tenancy con Supabase

*(respalda la Decisión 4)*

### C.1 · Patrones (recordatorio)
Pooled (mismas tablas + `club_id`, **descartado**) · *Schema* por club (tablas separadas, misma instancia) ·
Silo (proyecto/instancia por club, aislamiento físico).

### C.2 · Los dos modelos de propiedad → los dos tiers
- **Club mantiene sus claves → Silo:** proyecto Supabase por club (Postgres + Auth + claves propias),
  provisión vía **Management API + OAuth2**. Aislamiento físico (ideal RGPD), coste ×N (financiado/repercutido).
- **Desarrollador gestiona → *Schema* por club:** un proyecto, un *schema* por club, `auth.users` compartido.
  Una instancia (barato), datos aislados; **identidades compartidas** (asumido, Decisión 3).

### C.3 · Arquitectura decidida: código único
La app es **tenant-aware** por *schema* (no por columna): resuelve el club (subdominio / *claim* `club_id`)
y **enruta a su *schema*** (`SET search_path`). **Mismo código en managed y silo**; solo cambia la provisión.
> Coste a asumir: **automatizar provisión y migraciones por tenant**. Nota: **resetear `search_path`** al
> devolver conexiones al *pool*.

### C.4 · Alcance de `auth.users` (ver Anexo B.5)
En managed, `auth.users` es **compartido** (aislamiento de identidades solo lógico, vía *claims*/RLS/API); en
silo, **aislado** por proyecto. Aceptado por tratarse de cuentas de staff (bajo riesgo) frente a los datos de menores.

### C.5 · Impacto en otras decisiones
- **Framework/ORM (§7 — decidido):** el ORM debe **enrutar por tenant**. Con **Vapor/Fluent** se resuelve
  registrando **varias BD** y/o fijando el `search_path` del *schema* del club por petición (ver Anexo D.1).
- **BD/proveedor (§4):** el silo es **llave en mano con Supabase** (Management API); en managed, provisión y
  migración por *schema* las montas tú.
- **Presupuesto (§9):** managed barato (una instancia); dedicado financiado por el club.

### C.6 · Estado de decisiones de tenancy
**Decididas:** aislamiento por defecto (pooled fuera); managed = *schema* por club; auth = Supabase Auth
compartido; BD = Supabase; **ORM de enrutado = Fluent** (§7). **Pendientes:** forma exacta del silo (proyecto
vs despliegue completo); propiedad/facturación del silo; automatización de migraciones por tenant.

**Fuentes:**
[Supabase RLS Best Practices · Makerkit](https://makerkit.dev/blog/tutorials/supabase-rls-best-practices) ·
[Supabase Multi-Tenancy · Stacksync](https://www.stacksync.com/blog/supabase-multi-tenancy-crm-integration) ·
[Supabase for Platforms · Docs](https://supabase.com/docs/guides/integrations/supabase-for-platforms) ·
[Management API · Docs](https://supabase.com/docs/reference/api/introduction) ·
[Billing FAQ · Docs](https://supabase.com/docs/guides/platform/billing-faq)

---

## Anexo D · Vapor + Fluent (Swift) — ORM/conectividad y despliegue

*(respalda la Decisión 5; investigación específica sobre Vapor)*

### D.1 · ORM y conectividad — Fluent (oficial, ya incluido)
- **Fluent es el ORM oficial de Vapor** (no un tercero). **Drivers:** **PostgreSQL (recomendado)**, MySQL,
  SQLite, MongoDB. `FluentPostgresDriver` (sobre PostgresNIO, con *pooling*) conecta con **Supabase** por
  cadena de conexión estándar.
- **Capacidades:** modelos tipados, **relaciones** (`@Parent`/`@Children`/`@Siblings`), **migraciones**
  (`AsyncMigration`), **async/await**. SQL avanzado vía **SQLKit**.
- **Multi-tenant:** permite **registrar varias BD** y **enrutar por petición** (útil para §7).
- **Auth:** valida JWT de Supabase con **JWTKit/`vapor/jwt`** (JWKS) o *component* Authentication propio.

### D.2 · Despliegue — RAM de *build* vs *runtime*, modelos y hosting/precio
- **Compila para Linux** vía el **Dockerfile multi-stage** de Vapor; **migraciones** como paso separado.
- **La RAM crítica es la de *build*, no la de *runtime*** — y **no se paga en el host**:
  - **Qué dispara la RAM de *build*:** el **grafo de dependencias** (Vapor, SwiftNIO, drivers, compilados
    desde fuente) y el **enlazado**, más que los *endpoints* o las LOC. Fija un **suelo de ~2–4 GB** que se
    alcanza casi de inmediato, **casi independiente del tamaño de tu app**; crece despacio. El modo `release`
    + *whole-module optimization* dispara el pico. **Métrica real:** RSS pico en `swift build -c release`
    (paso de enlazado), medido empíricamente — no cuentes *endpoints*.
  - **Runtime**, en cambio, es **ligero**: un servicio Vapor pequeño va cómodo en **512 MB–1 GB**.
- **Modelos de despliegue (todos mantienen "push → deploy"):**

  | Modelo | Dónde compila | Ventaja | Coste |
  |--------|---------------|---------|-------|
  | 1. Build nativo del PaaS (Railway/Render conectan repo) | *builder* del PaaS | Cero config | Riesgo **OOM/lento** con Swift |
  | 2. **`fly deploy` vía GitHub Action** (Fly) | ***builder* remoto dimensionable** de Fly | Automatizado y **sin OOM**, sin registry | Recomendado para Vapor |
  | 3. Build en **CI** (GitHub Actions ~16 GB) → *push* imagen | *runner* de CI | A prueba de OOM, caché | +registry/credenciales |

- **Por qué Fly encaja mejor con Vapor:** su CD estándar **es** una Action que lanza `fly deploy`, y el
  *build* corre en un **builder remoto que puedes dimensionar** → compila Swift sin el baile de "CI + push".
  (Railway/Render tienen integración GitHub *más* nativa, pero su *builder* es el que puede quedarse corto.)
- **Hosting/precio (runtime pequeño):** **Fly.io** `shared-cpu-1x` 256 MB ≈ **2 $/mes**, +RAM ≈ **5 $/GB-mes**
  (512 MB ≈ ~3 $, 1 GB ≈ ~5–7 $); **Railway** Hobby **5 $/mes** (incl. 5 $ de uso), RAM ≈ **10 $/GB-mes**,
  hasta 8 GB/servicio. **Build en CI ≈ 0 $** (Actions, *runners* ~16 GB). Todos con **región UE**.

### D.3 · OpenAPI / Swagger en Vapor
Sí, con dos enfoques (elegir uno — ver §10):
- **Design-first (oficial):** **`swift-openapi-generator`** (Apple) + **`vapor/swift-openapi-vapor`**
  (bindings del propio Vapor). Escribes el *spec* OpenAPI → genera **stubs de servidor con tipos**.
- **Code-first (comunidad):** **VaporToOpenAPI** — anotas las rutas → genera el documento OpenAPI + **Swagger UI**.
- **Matiz:** ninguno es tan **automático** como FastAPI (OpenAPI gratis desde los *type hints*); requieren
  elegir y cablear uno. NestJS quedaría en medio (`@nestjs/swagger`).

### D.4 · Balance y comparación de negocio (por qué se eligió Vapor)
- **A favor:** unifica con la **app iOS nativa** (Swift, DTOs `Codable`); **ORM oficial** (Fluent) con
  enrutado multi-tenant; Supabase sin fricción; **productividad** de un dev que domina el ecosistema Apple.
- **Simetría de lenguajes:** son **3 lenguajes en ambos casos** — Vapor: Swift(API+iOS)+TS(backoffice)+
  Kotlin(Android); NestJS: TS(API+backoffice)+Swift(iOS)+Kotlin(Android). La diferencia es **qué par comparte
  código**: Vapor **API↔iOS** vs NestJS **API↔backoffice**. Se elige el eje **API↔iOS**.
- **Riesgos de negocio asumidos:** **cantera server-Swift pequeña** (peor *handoff*/contratación que TS/Python);
  **ecosistema SaaS** (Stripe, email…) menos maduro; patrones multi-tenant menos documentados que SQLAlchemy/
  TypeORM. Mitigables, no bloqueantes; el temor a la **RAM de *build* queda neutralizado** compilando fuera del host.

**Fuentes:**
[Fluent · Vapor Docs](https://docs.vapor.codes/fluent/overview/) ·
[FluentPostgresDriver](https://swiftpackageregistry.com/vapor/fluent-postgres-driver) ·
[Deploy → Docker · Vapor Docs](https://docs.vapor.codes/deploy/docker/) ·
[Deploy → Fly · Vapor Docs](https://docs.vapor.codes/deploy/fly/) ·
[Swift linking memory (swiftlang#58380)](https://github.com/swiftlang/swift/issues/58380) ·
[Railway pricing 2026](https://costbench.com/software/developer-tools/railway/) ·
[Fly.io pricing · Docs](https://fly.io/docs/about/pricing/) ·
[swift-openapi-vapor (Vapor org)](https://github.com/vapor/swift-openapi-vapor) ·
[VaporToOpenAPI](https://swiftpackageindex.com/dankinsoid/VaporToOpenAPI) ·
[Introducing Swift OpenAPI Generator](https://www.swift.org/blog/introducing-swift-openapi-generator/)
