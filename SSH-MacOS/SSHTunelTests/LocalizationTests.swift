import Foundation
import Testing
@testable import SSHTunel

struct LocalizationTests {
    private let app = Bundle(for: SSHConfigStore.self)

    private func bundle(_ lang: String) throws -> Bundle {
        try #require(app.path(forResource: lang, ofType: "lproj").flatMap(Bundle.init(path:)), "\(lang).lproj missing")
    }

    @Test func shipsCatalanAndSpanish() {
        #expect(Set(app.localizations).isSuperset(of: ["en", "ca", "es"]))
    }

    @Test(arguments: [
        ("ca", "Connect", "Connecta"),
        ("es", "Connect", "Conectar"),
        ("ca", "Port Forwarding Rules", "Regles de reenviament de port"),
        ("es", "Delete “%@”?", "¿Eliminar «%@»?"),
    ])
    func translates(_ lang: String, _ key: String, _ expected: String) throws {
        #expect(try bundle(lang).localizedString(forKey: key, value: "MISSING", table: nil) == expected)
    }

    @Test func pluralizesQuitTitle() throws {
        let ca = try bundle("ca")
        let format = ca.localizedString(forKey: "Close %lld open tunnels before quitting?", value: nil, table: nil)
        let locale = Locale(identifier: "ca")
        #expect(String(format: format, locale: locale, 1) == "Vols tancar el túnel obert abans de sortir?")
        #expect(String(format: format, locale: locale, 3) == "Vols tancar els 3 túnels oberts abans de sortir?")
    }

    @Test func localizesInfoPlist() throws {
        let es = try bundle("es")
        let text = es.localizedString(forKey: "NSLocalNetworkUsageDescription", value: nil, table: "InfoPlist")
        #expect(text.contains("red local"))
    }
}
