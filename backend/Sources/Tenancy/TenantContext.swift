/// Tenant de la petición en curso.
///
/// Es un `@TaskLocal` porque `registerHandlers` del código generado monta **una**
/// instancia del handler para todo el transporte (D-65): el tenant no puede
/// viajar en su `init`, tiene que ser ambiental a la tarea. Es además el patrón
/// que documenta `swift-openapi-vapor` para inyectar contexto por petición.
///
/// Lo fija `TenantResolutionMiddleware` y nadie más.
public enum TenantContext {
    @TaskLocal public static var current: Tenant?
}
