import Foundation

/// QA data for the Figma parity report (plan/alief/qa/figma-parity-2026-10-31.md). Debug and tests only:
/// `-UITestMock YES -mock.scenario <name>`. Not in contracts/fixtures: these copy what the Figma frames show
/// (names, domains, "10.42 WIB", signal weights), so a screenshot can be laid next to its frame.
struct MockDataset: Sendable {
    /// Guardian mode (also "Pribadi" with `-settings.familyModeOn NO`): Adhella.
    var guardian: DeviceProfile
    /// Protected mode: Maria, connected to Virellia (Figma 455:10275).
    var protected: DeviceProfile
    var members: [FamilyMember]
    /// Scans of every device: the repository filters by owner as the API does.
    var scans: [ScanResult]
}

enum MockScenarios {
    static let jakarta = TimeZone(identifier: "Asia/Jakarta")!

    static let meId = "dev_me"
    static let mariaId = "dev_maria"
    static let virellia = GuardianInfo(deviceId: "dev_virellia", name: "Virellia", avatarId: "avatar_09")

    /// The data for a QA scenario, or `nil` for the fixture scenarios (`standard`, `empty`, …).
    static func dataset(for scenario: MockRepository.Scenario, now: Date, bundle: Bundle) -> MockDataset? {
        switch scenario {
        case .standard, .empty, .oneMember, .threeMembers: nil
        case .figma: figma(now: now)
        case .mixedVerdicts: mixedVerdicts(now: now)
        case .heavy: heavy(now: now)
        case .edge: edge(now: now)
        case .allSafe: allSafe(now: now)
        case .allBlocked: allBlocked(now: now)
        case .corpus: corpus(now: now, bundle: bundle)
        }
    }

    // MARK: Figma (416:8768, 416:8541, 416:9255, 416:10447, 455:10275)

    static func figma(now: Date) -> MockDataset {
        let members = figmaMembers(now: now)
        let syahnaz = owner(members[0]), bayu = owner(members[1]), renatta = owner(members[2])
        var scans: [ScanResult] = [
            // Hari ini: Guardian/Home 435:20373 and the Detail frames.
            scan("figma-blocked-92", .bcaBlocked, owner: syahnaz, at: today(10, 42, now)),
            scan("figma-shopee", .shopee, owner: bayu, at: today(10, 41, now)),
            scan("figma-warning-72", .bcaWarning, owner: bayu, at: today(10, 40, now)),
            // 25 Oktober, 8 September, 3 September (Aktivitas - Profil Guardian 416:8768).
            scan("figma-oct-1", .bcaWarning, owner: renatta, at: day(2026, 10, 25, 10, 42)),
            scan("figma-oct-2", .bansos, owner: syahnaz, at: day(2026, 10, 25, 10, 41)),
            scan("figma-sep8-1", .bcaWarning, owner: bayu, at: day(2026, 9, 8, 10, 42)),
            scan("figma-sep8-2", .bansos, owner: renatta, at: day(2026, 9, 8, 10, 41)),
            scan("figma-sep3-1", .shopee, owner: syahnaz, at: day(2026, 9, 3, 10, 42)),
        ]
        // Own scans (Pribadi, 416:8541): Adhella's device.
        let me = owner(meId, "Adhella")
        scans += [
            scan("figma-me-1", .bcaWarning, owner: me, at: today(10, 42, now)),
            scan("figma-me-2", .bcaWarning, owner: me, at: day(2026, 10, 25, 10, 42)),
            scan("figma-me-3", .shopee, owner: me, at: day(2026, 10, 25, 10, 41)),
            scan("figma-me-4", .bansos, owner: me, at: day(2026, 10, 25, 10, 40)),
            scan("figma-me-5", .bcaWarning, owner: me, at: day(2026, 9, 8, 10, 42)),
            scan("figma-me-6", .shopee, owner: me, at: day(2026, 9, 8, 10, 41)),
        ]
        scans += mariaScans(now: now)
        return MockDataset(
            guardian: guardianProfile(now: now, blocked: 5, warnings: 7),
            protected: mariaProfile(now: now, blocked: 3, warnings: 7),
            members: members, scans: scans
        )
    }

    /// Maria's own list (Aktivitas - Profil Pribadi 450:8443): Virellia said "berbahaya" on one, not yet on another.
    static func mariaScans(now: Date) -> [ScanResult] {
        let maria = owner(mariaId, "Maria")
        let byVirellia = { (value: Verdict.Value) in
            Verdict(value: value, byDeviceId: virellia.deviceId, byName: virellia.name, decidedAt: today(10, 50, now))
        }
        return [
            scan("maria-1", .bcaBlocked, owner: maria, at: today(10, 42, now)),
            scan("maria-2", .bcaWarning, owner: maria, at: day(2026, 10, 25, 10, 42)),
            scan("maria-3", .shopee, owner: maria, at: day(2026, 10, 25, 10, 41), verdict: byVirellia(.notSafe)),
            scan("maria-4", .bansos, owner: maria, at: day(2026, 10, 25, 10, 40)),
            scan("maria-5", .bcaWarning, owner: owner(mariaId, "Maria", domainSuffix: "-2"), at: day(2026, 9, 8, 10, 42),
                 verdict: byVirellia(.safe)),
        ]
    }

    static func figmaMembers(now: Date) -> [FamilyMember] {
        let since = day(2026, 9, 14, 9, 0)
        return [
            FamilyMember(
                deviceId: "dev_syahnaz", name: "Syahnaz", avatarId: "avatar_02", extensionActive: true,
                lastScan: .init(status: .blocked, score: 92, url: Site.bcaBlocked.url, detectedAt: today(10, 42, now)),
                connectedAt: since, lastSeenAt: now.addingTimeInterval(-2 * 60), deviceModel: "iPhone 15", osVersion: "26",
                notify: true, stats: .init(blocked: 3, warnings: 5)
            ),
            FamilyMember(
                deviceId: "dev_bayu", name: "Bayu", avatarId: "avatar_07", extensionActive: true,
                lastScan: .init(status: .blocked, score: 88, url: Site.shopee.url, detectedAt: today(10, 41, now)),
                connectedAt: since, lastSeenAt: now.addingTimeInterval(-3600), deviceModel: "iPad", osVersion: "26",
                notify: true, stats: .init(blocked: 1, warnings: 2)
            ),
            FamilyMember(
                deviceId: "dev_renatta", name: "Renatta", avatarId: "avatar_05", extensionActive: false,
                lastScan: .init(status: .warning, score: 72, url: Site.bcaWarning.url, detectedAt: day(2026, 10, 25, 10, 42)),
                connectedAt: since, lastSeenAt: now.addingTimeInterval(-2 * 86_400), deviceModel: "iPhone 13", osVersion: "26",
                notify: true, stats: .init(blocked: 1, warnings: 1)
            ),
        ]
    }

    // MARK: Variants

    /// Every verdict state on warning and blocked: none, safe, not safe (Activity 450:8734/8739/8744).
    static func mixedVerdicts(now: Date) -> MockDataset {
        var data = figma(now: now)
        let me = data.guardian
        let verdict = { (value: Verdict.Value) in
            Verdict(value: value, byDeviceId: me.deviceId, byName: me.name, decidedAt: now.addingTimeInterval(-600))
        }
        let syahnaz = owner("dev_syahnaz", "Syahnaz")
        data.scans = [
            scan("mixed-blocked-none", .bcaBlocked, owner: syahnaz, at: today(10, 42, now)),
            scan("mixed-blocked-notsafe", .bansos, owner: syahnaz, at: today(10, 30, now), verdict: verdict(.notSafe)),
            scan("mixed-blocked-safe", .shopee, owner: syahnaz, at: today(10, 20, now), verdict: verdict(.safe)),
            scan("mixed-warning-none", .bcaWarning, owner: owner("dev_bayu", "Bayu"), at: today(10, 10, now)),
            scan("mixed-warning-safe", .bcaWarning, owner: owner("dev_renatta", "Renatta"), at: today(9, 50, now),
                 verdict: verdict(.safe)),
            scan("mixed-warning-notsafe", .bcaWarning, owner: syahnaz, domainSuffix: "-2", at: today(9, 40, now),
                 verdict: verdict(.notSafe)),
        ]
        return data
    }

    /// 3 members, 60 scans over 30 days, counters past 999 ("1.284", "999+").
    static func heavy(now: Date) -> MockDataset {
        var data = figma(now: now)
        let owners = data.members.map { owner($0.deviceId, $0.name) } + [owner(meId, "Adhella")]
        let sites: [Site] = [.bcaBlocked, .bcaWarning, .shopee, .bansos]
        data.scans = (0..<60).map { i in
            scan("heavy-\(i)", sites[i % sites.count], owner: owners[i % owners.count], domainSuffix: "-\(i / 4)",
                 at: now.addingTimeInterval(-Double(i) * 11 * 3600))
        }
        data.guardian.stats = ProfileStats(blocked: 1284, warnings: 2731, since: now.addingTimeInterval(-400 * 86_400))
        data.protected.stats = ProfileStats(blocked: 1284, warnings: 2731, since: now.addingTimeInterval(-400 * 86_400))
        for i in data.members.indices { data.members[i].stats = .init(blocked: 999 + i, warnings: 1500 + i) }
        return data
    }

    /// Long domain and path, the longest names (20 characters), emoji, no title, favicon or screenshot.
    static func edge(now: Date) -> MockDataset {
        var data = figma(now: now)
        data.guardian.name = "Adhella Putri Ayu S."
        data.protected.name = "Maria 👵🏻 Nenek Kita"
        data.members[0].name = "Syahnaz Kartika Dewi"
        data.members[1].name = "Bayu 🧑‍💻"
        data.members[1].lastScan = nil
        data.members[2].deviceModel = nil
        data.members[2].osVersion = nil
        data.members[2].lastSeenAt = nil
        let long = "verifikasi-akun-nasabah-prioritas-bca-mobile-banking-indonesia-resmi.secure-login.site"
        var scans = [
            ScanResult(
                id: "edge-long", url: URL(string: "https://\(long)/login/verifikasi/pin/ulang?ref=wa&campaign=promo-akhir-tahun")!,
                domain: long, pageTitle: nil, faviconUrl: nil, score: 100, status: .blocked,
                signals: Site.bcaBlocked.signals + Site.bansos.signals, screenshotUrl: nil, pageReplicaUrl: nil,
                ownerDeviceId: "dev_syahnaz", ownerName: data.members[0].name, detectedAt: now.addingTimeInterval(-60), verdict: nil
            ),
            ScanResult(
                id: "edge-one-signal", url: URL(string: "https://xn--bc-xja.site/")!, domain: "xn--bc-xja.site",
                pageTitle: nil, faviconUrl: nil, score: 30, status: .warning, signals: [Site.shopee.signals[0]],
                screenshotUrl: nil, pageReplicaUrl: nil, ownerDeviceId: "dev_bayu", ownerName: data.members[1].name,
                detectedAt: now.addingTimeInterval(-3600), verdict: nil
            ),
        ]
        scans += data.scans.filter { $0.ownerDeviceId == meId || $0.ownerDeviceId == mariaId }
        data.scans = scans
        return data
    }

    /// Every scan marked safe by the Guardian.
    static func allSafe(now: Date) -> MockDataset {
        var data = figma(now: now)
        let verdict = Verdict(value: .safe, byDeviceId: meId, byName: "Adhella", decidedAt: now.addingTimeInterval(-300))
        for i in data.scans.indices { data.scans[i].verdict = verdict }
        return data
    }

    /// Only blocked scans.
    static func allBlocked(now: Date) -> MockDataset {
        var data = figma(now: now)
        data.scans.removeAll { $0.status != .blocked }
        return data
    }

    /// Imelda's eval corpus run through the detector (test 2a): `Fixtures/corpus-scans.json`, written by
    /// `plan/alief/qa/corpus-to-scans.mjs`. The scans keep their real score, status and signals.
    static func corpus(now: Date, bundle: Bundle) -> MockDataset {
        var data = figma(now: now)
        guard let url = bundle.url(forResource: "corpus-scans", withExtension: "json"),
              let json = try? Data(contentsOf: url),
              let page = try? JSONDecoder.shoo.decode(ScanPage.self, from: json)
        else {
            Log.data.error("Missing fixture", "corpus-scans")
            data.scans = []
            return data
        }
        data.scans = page.items
        return data
    }

    // MARK: Building blocks

    struct Owner {
        var deviceId: String
        var name: String
        var domainSuffix: String = ""
    }

    static func owner(_ deviceId: String, _ name: String, domainSuffix: String = "") -> Owner {
        Owner(deviceId: deviceId, name: name, domainSuffix: domainSuffix)
    }

    static func owner(_ member: FamilyMember) -> Owner { owner(member.deviceId, member.name) }

    /// The four sites Figma draws, with the reasons of its evidence cards.
    enum Site {
        case bcaBlocked, bcaWarning, shopee, bansos

        var domain: String {
            switch self {
            case .bcaBlocked, .bcaWarning: "bca-verifikasi.site"
            case .shopee: "promo-shopee88.xyz"
            case .bansos: "bansos-2026.site"
            }
        }

        var url: URL {
            switch self {
            case .bcaBlocked, .bcaWarning: URL(string: "https://bca-verifikasi.site/login")!
            case .shopee: URL(string: "https://promo-shopee88.xyz/klaim")!
            case .bansos: URL(string: "https://bansos-2026.site/cek")!
            }
        }

        var title: String {
            switch self {
            case .bcaBlocked, .bcaWarning: "BCA m-Banking - Verifikasi Akun"
            case .shopee: "Klaim Hadiah Shopee"
            case .bansos: "Cek Penerima Bansos 2026"
            }
        }

        var score: Int {
            switch self {
            case .bcaBlocked: 92
            case .bcaWarning: 72
            case .shopee: 88
            case .bansos: 85
            }
        }

        var status: ScanStatus { score >= ScoreThreshold.blocked ? .blocked : .warning }

        /// Figma weights as drawn: +35 / +35 / +32 on 416:9255, +32 / +25 on 416:9469.
        var signals: [Signal] {
            switch self {
            case .bcaBlocked: [
                    signal("asks_pin", 3, 35, "Sensitive form", "Formulir sensitif", "Asks for m-banking PIN", "Meminta PIN m-banking", evidence: "pin"),
                    signal("brand_logo_offsite", 2, 35, "Copied logo", "Logo tiruan", "Copies the BCA logo", "Meniru logo BCA"),
                    signal("new_domain", 3, 32, "Domain age 3 days", "Umur domain 3 hari", "This site was made 3 days ago", "Situs ini baru dibuat 3 hari lalu"),
                ]
            case .bcaWarning: [
                    signal("asks_pin", 3, 32, "Sensitive form", "Formulir sensitif", "Asks for m-banking PIN", "Meminta PIN m-banking", evidence: "pin"),
                    signal("brand_logo_offsite", 2, 25, "Copied logo", "Logo tiruan", "Copies the BCA logo", "Meniru logo BCA"),
                    signal("new_domain", 3, 15, "Domain age 3 days", "Umur domain 3 hari", "This site was made 3 days ago", "Situs ini baru dibuat 3 hari lalu"),
                ]
            case .shopee: [
                    signal("lookalike_domain", 1, 40, "Looks like shopee.co.id", "Mirip shopee.co.id", "The address imitates Shopee", "Alamatnya meniru Shopee"),
                    signal("cheap_tld", 1, 18, "Cheap .xyz ending", "Akhiran .xyz murah", "Scam sites often use .xyz", "Situs penipuan sering memakai .xyz"),
                    signal("urgent_language", 4, 30, "Urgent wording", "Bahasa mendesak", "Pushes you to claim within minutes", "Mendesak klaim dalam hitungan menit"),
                ]
            case .bansos: [
                    signal("hoax_claim", 4, 40, "Fake aid claim", "Klaim bansos palsu", "Promises government aid that doesn't exist", "Menjanjikan bansos yang tidak ada"),
                    signal("asks_nik", 3, 30, "Asks for NIK", "Meminta NIK", "Asks for your ID number", "Meminta nomor KTP kamu", evidence: "nik"),
                    signal("cheap_tld", 1, 15, "Cheap .site ending", "Akhiran .site murah", "Scam sites often use .site", "Situs penipuan sering memakai .site"),
                ]
            }
        }
    }

    static func signal(
        _ id: String, _ layer: Int, _ weight: Int, _ en: String, _ idText: String, _ simpleEn: String, _ simpleId: String,
        evidence: String? = nil
    ) -> Signal {
        Signal(
            id: id, layer: layer, weight: weight, label: LocalizedText(en: en, id: idText),
            labelSimple: LocalizedText(en: simpleEn, id: simpleId), evidence: evidence
        )
    }

    static func scan(
        _ id: String, _ site: Site, owner: Owner, domainSuffix: String = "", at date: Date, verdict: Verdict? = nil
    ) -> ScanResult {
        let suffix = domainSuffix + owner.domainSuffix
        // A suffix keeps two scans of one owner on separate domains, so a verdict on one leaves the other alone.
        let domain = suffix.isEmpty ? site.domain : site.domain.replacingOccurrences(of: ".", with: "\(suffix).", options: [], range: site.domain.range(of: "."))
        var components = URLComponents(url: site.url, resolvingAgainstBaseURL: false)!
        components.host = domain
        return ScanResult(
            id: id, url: components.url!, domain: domain, pageTitle: site.title, faviconUrl: nil, score: site.score,
            status: site.status, signals: site.signals,
            screenshotUrl: URL(string: "https://example.invalid/screens/\(id).png"), pageReplicaUrl: nil,
            ownerDeviceId: owner.deviceId, ownerName: owner.name, detectedAt: date, verdict: verdict
        )
    }

    static func guardianProfile(now: Date, blocked: Int, warnings: Int) -> DeviceProfile {
        DeviceProfile(
            deviceId: meId, name: "Adhella", avatarId: "avatar_01", mode: .guardian, language: "id", guardian: nil,
            stats: ProfileStats(blocked: blocked, warnings: warnings, since: now.addingTimeInterval(-42 * 86_400)),
            timeZone: jakarta.identifier, notifications: .defaults
        )
    }

    static func mariaProfile(now: Date, blocked: Int, warnings: Int) -> DeviceProfile {
        DeviceProfile(
            deviceId: mariaId, name: "Maria", avatarId: "avatar_03", mode: .protected, language: "id", guardian: virellia,
            stats: ProfileStats(blocked: blocked, warnings: warnings, since: now.addingTimeInterval(-42 * 86_400)),
            timeZone: jakarta.identifier, notifications: .defaults
        )
    }

    /// Today at `hour:minute` WIB, or a minute ago when that is still ahead ("Hari ini · 10.42 WIB").
    static func today(_ hour: Int, _ minute: Int, _ now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jakarta
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return min(date, now.addingTimeInterval(-60))
    }

    static func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = jakarta
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
