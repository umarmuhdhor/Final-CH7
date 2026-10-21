import Foundation
import Testing
@testable import Shoo

struct LocalizationTests {
    @Test(arguments: [
        ("Activity", "Activity", "Aktivitas"),
        ("Shield", "Shield", "Perisai"),
        ("Verified scam", "Verified scam", "Penipuan terverifikasi"),
        ("Continue", "Continue", "Lanjut"),
        ("Turn on", "Turn on", "Nyalakan"),
        ("Not now", "Not now", "Nanti saja"),
        ("You can't change this later.", "You can't change this later.", "Pilihan ini tidak bisa diganti nanti."),
    ])
    func catalogLookupFollowsInAppLanguage(key: String, english: String, indonesian: String) {
        #expect(L10n.string(String.LocalizationValue(key), language: .english) == english)
        #expect(L10n.string(String.LocalizationValue(key), language: .indonesian) == indonesian)
    }

    @Test func greetingInterpolatesTheName() {
        #expect(L10n.string("Hi, \("Rina")!", language: .english) == "Hi, Rina!")
        #expect(L10n.string("Hi, \("Rina")!", language: .indonesian) == "Hai, Rina!")
    }

    @Test func everyCatalogKeyHasAnIndonesianTranslation() throws {
        let url = RepoPaths.root.appending(path: "ios/ShooApp/Resources/Localizable.xcstrings")
        let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try #require(catalog["strings"] as? [String: [String: Any]])
        let missing = strings.filter { _, entry in
            let id = (entry["localizations"] as? [String: Any])?["id"] as? [String: Any]
            let unit = id?["stringUnit"] as? [String: Any]
            return (unit?["value"] as? String ?? "").isEmpty
        }
        #expect(missing.isEmpty, "Missing ID: \(missing.keys.sorted())")
    }

    @Test(arguments: [
        (["id-ID", "en-US"], AppLanguage.indonesian),
        (["id"], .indonesian),
        (["en-GB"], .english),
        (["ja-JP", "id-ID"], .english),
        ([], .english),
    ])
    func defaultLanguageFollowsIPhone(preferred: [String], expected: AppLanguage) {
        #expect(AppLanguage.fromSystem(preferredLanguages: preferred) == expected)
    }

    @Test func signalTextUsesLanguageCode() throws {
        let url = try #require(Bundle.main.url(forResource: "blocked-92", withExtension: "json"))
        let scan = try JSONDecoder.shoo.decode(ScanResult.self, from: Data(contentsOf: url))
        #expect(scan.signals[0].labelSimple.text(for: AppLanguage.indonesian.code) == "Situs ini baru dibuat 3 hari lalu")
        #expect(scan.signals[0].labelSimple.text(for: AppLanguage.english.code) == "This site was made 3 days ago")
    }
}
