/// Dónde corre lo que no cabe en la respuesta (`D-87`).
///
/// # Por qué existe como puerto y no es un `Task { }` suelto
///
/// El `202` de `POST /ingestion-runs` promete que el recorrido ocurrirá
/// **después**, y esa promesa es justo lo que un test de nivel 4 no puede
/// esperar sentado: un `Task { }` dentro del handler termina cuando quiere, así
/// que la aserción o corre antes de tiempo o se convierte en una espera con
/// reloj — que es la receta de un test intermitente.
///
/// Con esto, el ejecutor de producción lanza y se olvida, y el de test ejecuta
/// **en línea**: la misma ruta de código, sin carrera que arbitrar.
public protocol BackgroundWork: Sendable {
    func enqueue(_ work: @escaping @Sendable () async -> Void) async
}

/// Producción: lanza y se olvida.
///
/// `Task { }` y no `Task.detached`: hereda los valores `@TaskLocal`, y uno de
/// ellos es el tenant que fijó el middleware (§6.1). Con `detached` el trabajo
/// de fondo perdería el club y tendría que volver a resolverlo.
///
/// **Lo que esto no es: una cola.** Si el proceso muere en mitad del recorrido,
/// no hay reintento — y no hace falta que lo haya, porque la pasada es atómica
/// (`D-83`) y la siguiente del cron recoge lo que quedó. El camino fiable es el
/// comando; éste es el botón.
public struct DetachedBackgroundWork: BackgroundWork {
    public init() {}
    public func enqueue(_ work: @escaping @Sendable () async -> Void) async {
        Task { await work() }
    }
}

/// Test: ejecuta en línea, para que la aserción vea el resultado sin esperar.
public struct InlineBackgroundWork: BackgroundWork {
    public init() {}
    public func enqueue(_ work: @escaping @Sendable () async -> Void) async {
        await work()
    }
}
