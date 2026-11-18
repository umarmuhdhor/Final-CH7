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

    /// A-15 (fase 28m): "Connect" is "Hubungkan" (link up), not "Hubungi" (contact someone).
    @Test(arguments: ["Connect so someone you love can double-check for you", "Connect so someone you love can check it again"])
    func connectCopyLinksUpInsteadOfContacting(key: String) {
        let indonesian = L10n.string(String.LocalizationValue(key), language: .indonesian)
        #expect(!indonesian.contains("Hubungi agar"))
        #expect(indonesian.hasPrefix("Hubungkan "))
    }

    /// A-14 (fase 28m): "Hapus akun" with one protected person says "1 person", not "1 people".
    @Test func disconnectedPeopleFollowEnglishPlural() {
        #expect(L10n.string("\(1) people you protect will be disconnected.", language: .english)
            == "1 person you protect will be disconnected.")
        #expect(L10n.string("\(2) people you protect will be disconnected.", language: .english)
            == "2 people you protect will be disconnected.")
        #expect(L10n.string("\(1) people you protect will be disconnected.", language: .indonesian)
            == "1 orang yang kamu lindungi akan terputus.")
    }

    /// PF-01 (#494): the delete-account sheet's sentence when the family list did not load (Umar's wording, *kamu*).
    @Test func disconnectedFamilyWithoutACount() {
        #expect(L10n.string("Anyone you protect will be disconnected.", language: .english)
            == "Anyone you protect will be disconnected.")
        #expect(L10n.string("Anyone you protect will be disconnected.", language: .indonesian)
            == "Semua orang yang kamu lindungi akan terputus.")
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

    /// A fresh install starts in Bahasa Indonesia, not in the iPhone language.
    @Test func defaultLanguageIsIndonesian() {
        #expect(AppLanguage.defaultLanguage == .indonesian)
    }

    @Test func signalTextUsesLanguageCode() throws {
        let url = try #require(Bundle.main.url(forResource: "blocked-92", withExtension: "json"))
        let scan = try JSONDecoder.shoo.decode(ScanResult.self, from: Data(contentsOf: url))
        #expect(scan.signals[0].labelSimple.text(for: AppLanguage.indonesian.code) == "Situs ini baru dibuat 3 hari lalu")
        #expect(scan.signals[0].labelSimple.text(for: AppLanguage.english.code) == "This site was made 3 days ago")
    }
}
