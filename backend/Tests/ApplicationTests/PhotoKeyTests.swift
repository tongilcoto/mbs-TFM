import Application
import Domain
import Foundation
import Testing

/// La clave que llega de fuera (en el enlace de la foto) solo vale con su forma exacta: así no puede salirse de la
/// carpeta del club (`D-115`).
@Suite("Application · R6.8 · la clave de una foto")
struct PhotoKeyTests {

    @Test("ida y vuelta: <club>/<código en minúsculas>.jpg")
    func roundTrip() throws {
        let key = PhotoKey(club: try Slug("celtic-castilla"), id: UUID())
        #expect(key.value.hasPrefix("celtic-castilla/") && key.value.hasSuffix(".jpg"))
        #expect(PhotoKey(key.value) == key)
    }

    @Test("lo que no tiene esa forma exacta no es una clave",
          arguments: ["../etc/passwd", "celtic-castilla/../../x.jpg", "celtic-castilla/abc.jpg",
                      "celtic-castilla/6F9619FF-8B86-D011-B42D-00C04FC964FF.jpg",
                      "celtic-castilla/6f9619ff-8b86-d011-b42d-00c04fc964ff.png",
                      "a/b/6f9619ff-8b86-d011-b42d-00c04fc964ff.jpg",
                      "celtic-castilla/6f9619ff-8b86-d011-b42d-00c04fc964ff.jpg/otra.jpg", "/6f9619ff-8b86-d011-b42d-00c04fc964ff.jpg",
                      "Celtic/6f9619ff-8b86-d011-b42d-00c04fc964ff.jpg", ""])
    func rejectsOtherShapes(_ raw: String) {
        #expect(PhotoKey(raw) == nil)
    }
}
