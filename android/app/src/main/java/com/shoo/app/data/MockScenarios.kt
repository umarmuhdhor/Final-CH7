package com.shoo.app.data

import com.shoo.app.support.Log
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * QA data for the Figma parity report (plan/alief/qa/figma-parity-2026-10-31.md). Debug and tests only:
 * `-mock.scenario <name>` (launch extra, see `AppEnvironment.live`). Not in contracts/fixtures: these copy what the
 * Figma frames show (names, domains, "10.42 WIB", signal weights), so a screenshot can be laid next to its frame.
 */
data class MockDataset(
    /** Guardian mode (also "Pribadi" with Family mode off): Adhella. */
    var guardian: DeviceProfile,
    /** Protected mode: Maria, connected to Virellia (Figma 455:10275). */
    var protected: DeviceProfile,
    var members: List<FamilyMember>,
    /** Scans of every device: the repository filters by owner as the API does. */
    var scans: List<ScanResult>,
)

object MockScenarios {
    val jakarta: ZoneId = ZoneId.of("Asia/Jakarta")

    const val meId = "dev_me"
    const val mariaId = "dev_maria"
    val virellia = GuardianInfo(deviceId = "dev_virellia", name = "Virellia", avatarId = "avatar_01")

    /** The data for a QA scenario, or null for the fixture scenarios (`STANDARD`, `EMPTY`, …). */
    fun dataset(scenario: MockRepository.Scenario, now: Instant, fixtures: (String) -> String?): MockDataset? =
        when (scenario) {
            MockRepository.Scenario.STANDARD, MockRepository.Scenario.EMPTY, MockRepository.Scenario.UNPAIRED,
            MockRepository.Scenario.ONE_MEMBER, MockRepository.Scenario.THREE_MEMBERS -> null
            MockRepository.Scenario.FIGMA -> figma(now)
            MockRepository.Scenario.MIXED_VERDICTS -> mixedVerdicts(now)
            MockRepository.Scenario.HEAVY -> heavy(now)
            MockRepository.Scenario.EDGE -> edge(now)
            MockRepository.Scenario.ALL_SAFE -> allSafe(now)
            MockRepository.Scenario.ALL_BLOCKED -> allBlocked(now)
            MockRepository.Scenario.CORPUS -> corpus(now, fixtures)
            MockRepository.Scenario.ADDRESS_MARKS -> addressMarks(now)
            MockRepository.Scenario.HOME_PRIBADI, MockRepository.Scenario.HOME_PRIBADI_ALONE,
            MockRepository.Scenario.PROTECTED_QUIET, MockRepository.Scenario.PROTECTED_BLOCKED,
            MockRepository.Scenario.PROTECTED_BLOCKED_SCAM, MockRepository.Scenario.PROTECTED_BLOCKED_SAFE,
            MockRepository.Scenario.PROTECTED_WARNING, MockRepository.Scenario.PROTECTED_WARNING_SCAM,
            MockRepository.Scenario.PROTECTED_WARNING_SAFE, MockRepository.Scenario.PROTECTED_ALONE -> home(scenario, now)
        }

    /** Figma "Scam Terbaru Pengguna Shoo" cards (Pribadi/Home 1115:13601, protected/Home 1115:17238); the third one
     * scrolls in. The titles stand in for admin category labels; the server's are shorter. */
    fun scamCases(now: Instant): List<ScamCase> = listOf(
        ScamCase("phishing_bank", LocalizedText(en = "Asks for m-banking PIN", id = "Minta PIN m-banking"), now),
        ScamCase("undian_palsu", LocalizedText(en = "Fake Shopee prize draw", id = "Undian palsu Shopee"), now),
        ScamCase(
            "bansos_palsu", LocalizedText(en = "Fake aid asks for ID photo", id = "Bansos palsu minta foto KTP"),
            now.minusSeconds(2 * 86_400),
        ),
    )

    // MARK: Figma (416:8768, 416:8541, 416:9255, 416:10447, 455:10275)

    fun figma(now: Instant): MockDataset {
        val members = figmaMembers(now)
        val syahnaz = owner(members[0])
        val bayu = owner(members[1])
        val renatta = owner(members[2])
        val scans = mutableListOf(
            // Hari ini: Guardian/Home 435:20373 and the Detail frames.
            scan("figma-blocked-92", Site.BCA_BLOCKED, owner = syahnaz, at = today(10, 42, now)),
            scan("figma-shopee", Site.SHOPEE, owner = bayu, at = today(10, 41, now)),
            scan("figma-warning-72", Site.BCA_WARNING, owner = bayu, at = today(10, 40, now)),
            // 25 Oktober, 8 September, 3 September (Aktivitas - Profil Guardian 416:8768).
            scan("figma-oct-1", Site.BCA_WARNING, owner = renatta, at = day(2026, 10, 25, 10, 42)),
            scan("figma-oct-2", Site.BANSOS, owner = syahnaz, at = day(2026, 10, 25, 10, 41)),
            scan("figma-sep8-1", Site.BCA_WARNING, owner = bayu, at = day(2026, 9, 8, 10, 42)),
            scan("figma-sep8-2", Site.BANSOS, owner = renatta, at = day(2026, 9, 8, 10, 41)),
            scan("figma-sep3-1", Site.SHOPEE, owner = syahnaz, at = day(2026, 9, 3, 10, 42)),
        )
        // Own scans (Pribadi, 416:8541): Adhella's device.
        val me = owner(meId, "Adhella")
        scans += listOf(
            scan("figma-me-1", Site.BCA_WARNING, owner = me, at = today(10, 42, now)),
            scan("figma-me-2", Site.BCA_WARNING, owner = me, at = day(2026, 10, 25, 10, 42)),
            scan("figma-me-3", Site.SHOPEE, owner = me, at = day(2026, 10, 25, 10, 41)),
            scan("figma-me-4", Site.BANSOS, owner = me, at = day(2026, 10, 25, 10, 40)),
            scan("figma-me-5", Site.BCA_WARNING, owner = me, at = day(2026, 9, 8, 10, 42)),
            scan("figma-me-6", Site.SHOPEE, owner = me, at = day(2026, 9, 8, 10, 41)),
        )
        scans += mariaScans(now)
        return MockDataset(
            guardian = guardianProfile(now, blocked = 5, warnings = 7),
            protected = mariaProfile(now, blocked = 3, warnings = 7),
            members = members, scans = scans,
        )
    }

    /** Maria's own list (Aktivitas - Profil Pribadi 450:8443): Virellia said "berbahaya" on one, not yet on another. */
    fun mariaScans(now: Instant): List<ScanResult> {
        val maria = owner(mariaId, "Maria")
        val byVirellia = { value: Verdict.Value ->
            Verdict(value = value, byDeviceId = virellia.deviceId, byName = virellia.name, decidedAt = today(10, 50, now))
        }
        return listOf(
            scan("maria-1", Site.BCA_BLOCKED, owner = maria, at = today(10, 42, now)),
            scan("maria-2", Site.BCA_WARNING, owner = maria, at = day(2026, 10, 25, 10, 42)),
            scan("maria-3", Site.SHOPEE, owner = maria, at = day(2026, 10, 25, 10, 41), verdict = byVirellia(Verdict.Value.NOT_SAFE)),
            scan("maria-4", Site.BANSOS, owner = maria, at = day(2026, 10, 25, 10, 40)),
            scan(
                "maria-5", Site.BCA_WARNING, owner = owner(mariaId, "Maria", domainSuffix = "-2"), at = day(2026, 9, 8, 10, 42),
                verdict = byVirellia(Verdict.Value.SAFE),
            ),
        )
    }

    fun figmaMembers(now: Instant): List<FamilyMember> {
        val since = day(2026, 9, 14, 9, 0)
        return listOf(
            FamilyMember(
                deviceId = "dev_syahnaz", name = "Syahnaz", avatarId = "avatar_01", extensionActive = true,
                lastScan = FamilyMember.LastScan(ScanStatus.BLOCKED, 92, Site.BCA_BLOCKED.url, today(10, 42, now)),
                connectedAt = since, lastSeenAt = now.minusSeconds(2 * 60), deviceModel = "iPhone 15", osVersion = "26",
                notify = true, stats = FamilyMember.Stats(blocked = 3, warnings = 5),
            ),
            FamilyMember(
                deviceId = "dev_bayu", name = "Bayu", avatarId = "avatar_02", extensionActive = true,
                lastScan = FamilyMember.LastScan(ScanStatus.BLOCKED, 88, Site.SHOPEE.url, today(10, 41, now)),
                connectedAt = since, lastSeenAt = now.minusSeconds(3600), deviceModel = "iPad", osVersion = "26",
                notify = true, stats = FamilyMember.Stats(blocked = 1, warnings = 2),
            ),
            FamilyMember(
                deviceId = "dev_renatta", name = "Renatta", avatarId = "avatar_03", extensionActive = false,
                lastScan = FamilyMember.LastScan(ScanStatus.WARNING, 72, Site.BCA_WARNING.url, day(2026, 10, 25, 10, 42)),
                connectedAt = since, lastSeenAt = now.minusSeconds(2 * 86_400), deviceModel = "iPhone 13", osVersion = "26",
                notify = true, stats = FamilyMember.Stats(blocked = 1, warnings = 1),
            ),
        )
    }

    // MARK: Home (Pribadi 435:20058 / 1382:10567, protected/Home 1115:17162 … 1373:12752)

    /** One Figma HOME frame each. The list under the card is always Waspada, Diblokir, Diblokir. Pribadi and
     * "no recent" have them yesterday: today they would turn the hero orange (Pribadi) or take the card (protected). */
    fun home(scenario: MockRepository.Scenario, now: Instant): MockDataset {
        val data = figma(now)
        val at = today(10, 42, now)
        val yesterday = at.minusSeconds(86_400)
        val verdict = { value: Verdict.Value ->
            Verdict(value = value, byDeviceId = virellia.deviceId, byName = virellia.name, decidedAt = at.plusSeconds(40))
        }
        val list = { owner: Owner, base: Instant ->
            listOf(
                scan("home-${owner.deviceId}-1", Site.BCA_WARNING, owner = owner, at = base.plusSeconds(20)),
                scan("home-${owner.deviceId}-2", Site.SHOPEE, owner = owner, at = base.plusSeconds(10)),
                scan("home-${owner.deviceId}-3", Site.BANSOS, owner = owner, at = base),
            )
        }
        val maria = owner(mariaId, "Maria")
        val card = { site: Site, value: Verdict.Value? ->
            scan("home-card", site, owner = maria, at = at.plusSeconds(30), verdict = value?.let(verdict))
        }
        when (scenario) {
            MockRepository.Scenario.HOME_PRIBADI, MockRepository.Scenario.HOME_PRIBADI_ALONE -> {
                data.scans = list(owner(meId, "Adhella"), yesterday)
                if (scenario == MockRepository.Scenario.HOME_PRIBADI_ALONE) data.members = emptyList()
            }
            MockRepository.Scenario.PROTECTED_QUIET -> data.scans = list(maria, yesterday)
            MockRepository.Scenario.PROTECTED_BLOCKED -> data.scans = listOf(card(Site.BCA_BLOCKED, null)) + list(maria, at)
            MockRepository.Scenario.PROTECTED_BLOCKED_SCAM ->
                data.scans = listOf(card(Site.BCA_BLOCKED, Verdict.Value.NOT_SAFE)) + list(maria, at)
            MockRepository.Scenario.PROTECTED_BLOCKED_SAFE ->
                data.scans = listOf(card(Site.BCA_BLOCKED, Verdict.Value.SAFE)) + list(maria, at)
            MockRepository.Scenario.PROTECTED_WARNING -> data.scans = listOf(card(Site.BCA_WARNING_70, null)) + list(maria, at)
            MockRepository.Scenario.PROTECTED_WARNING_SCAM ->
                data.scans = listOf(card(Site.BCA_WARNING_70, Verdict.Value.NOT_SAFE)) + list(maria, at)
            MockRepository.Scenario.PROTECTED_WARNING_SAFE ->
                data.scans = listOf(card(Site.BCA_WARNING_70, Verdict.Value.SAFE)) + list(maria, at)
            MockRepository.Scenario.PROTECTED_ALONE -> {
                data.scans = listOf(card(Site.BCA_WARNING_70, null)) + list(maria, at)
                data.protected = data.protected.copy(guardian = null)
            }
            else -> Unit
        }
        return data
    }

    // MARK: Variants

    /** Every verdict state on warning and blocked: none, safe, not safe (Activity 450:8734/8739/8744). */
    fun mixedVerdicts(now: Instant): MockDataset {
        val data = figma(now)
        val me = data.guardian
        val verdict = { value: Verdict.Value ->
            Verdict(value = value, byDeviceId = me.deviceId, byName = me.name, decidedAt = now.minusSeconds(600))
        }
        val syahnaz = owner("dev_syahnaz", "Syahnaz")
        data.scans = listOf(
            scan("mixed-blocked-none", Site.BCA_BLOCKED, owner = syahnaz, at = today(10, 42, now)),
            scan("mixed-blocked-notsafe", Site.BANSOS, owner = syahnaz, at = today(10, 30, now), verdict = verdict(Verdict.Value.NOT_SAFE)),
            scan("mixed-blocked-safe", Site.SHOPEE, owner = syahnaz, at = today(10, 20, now), verdict = verdict(Verdict.Value.SAFE)),
            scan("mixed-warning-none", Site.BCA_WARNING, owner = owner("dev_bayu", "Bayu"), at = today(10, 10, now)),
            scan(
                "mixed-warning-safe", Site.BCA_WARNING, owner = owner("dev_renatta", "Renatta"), at = today(9, 50, now),
                verdict = verdict(Verdict.Value.SAFE),
            ),
            scan(
                "mixed-warning-notsafe", Site.BCA_WARNING, owner = syahnaz, domainSuffix = "-2", at = today(9, 40, now),
                verdict = verdict(Verdict.Value.NOT_SAFE),
            ),
        )
        return data
    }

    /** 3 members, 60 scans over 30 days, counters past 999 ("1.284", "999+"). */
    fun heavy(now: Instant): MockDataset {
        val data = figma(now)
        val owners = data.members.map { owner(it.deviceId, it.name) } + owner(meId, "Adhella")
        val sites = listOf(Site.BCA_BLOCKED, Site.BCA_WARNING, Site.SHOPEE, Site.BANSOS)
        data.scans = (0 until 60).map { i ->
            scan(
                "heavy-$i", sites[i % sites.size], owner = owners[i % owners.size], domainSuffix = "-${i / 4}",
                at = now.minusSeconds(i.toLong() * 11 * 3600),
            )
        }
        val stats = ProfileStats(blocked = 1284, warnings = 2731, since = now.minusSeconds(400L * 86_400))
        data.guardian = data.guardian.copy(stats = stats)
        data.protected = data.protected.copy(stats = stats)
        data.members = data.members.mapIndexed { i, member ->
            member.copy(stats = FamilyMember.Stats(blocked = 999 + i, warnings = 1500 + i))
        }
        return data
    }

    /** Long domain and path, the longest names (20 characters), emoji, no title, favicon or screenshot. */
    fun edge(now: Instant): MockDataset {
        val data = figma(now)
        data.guardian = data.guardian.copy(name = "Adhella Putri Ayu S.")
        data.protected = data.protected.copy(name = "Maria 👵🏻 Nenek Kita")
        val members = data.members.toMutableList()
        members[0] = members[0].copy(name = "Syahnaz Kartika Dewi")
        members[1] = members[1].copy(name = "Bayu 🧑‍💻", lastScan = null)
        members[2] = members[2].copy(deviceModel = null, osVersion = null, lastSeenAt = null)
        data.members = members
        val long = "verifikasi-akun-nasabah-prioritas-bca-mobile-banking-indonesia-resmi.secure-login.site"
        val longRegistrable = "verifikasi-akun-nasabah-prioritas-bca-mobile-banking-resmi.site"
        val scans = mutableListOf(
            ScanResult(
                id = "edge-long", url = "https://$long/login/verifikasi/pin/ulang?ref=wa&campaign=promo-akhir-tahun",
                domain = long, pageTitle = null, faviconUrl = null, score = 100, status = ScanStatus.BLOCKED,
                signals = Site.BCA_BLOCKED.signals + Site.BANSOS.signals, screenshotUrl = null, pageReplicaUrl = null,
                ownerDeviceId = "dev_syahnaz", ownerName = members[0].name, detectedAt = now.minusSeconds(60), verdict = null,
            ),
            // U-05: the backend stores the `domain` the extension sends (the registrable domain here; the full host
            // only on a shared platform such as sites.google.com, #495), so a long one is what a real row shows.
            ScanResult(
                id = "edge-long-registrable",
                url = "https://login.$longRegistrable/login/verifikasi/pin?ref=wa",
                domain = longRegistrable, pageTitle = null, faviconUrl = null, score = 92, status = ScanStatus.BLOCKED,
                signals = Site.BCA_BLOCKED.signals, screenshotUrl = null, pageReplicaUrl = null,
                ownerDeviceId = "dev_syahnaz", ownerName = members[0].name, detectedAt = now.minusSeconds(90), verdict = null,
            ),
            ScanResult(
                id = "edge-one-signal", url = "https://xn--bc-xja.site/", domain = "xn--bc-xja.site",
                pageTitle = null, faviconUrl = null, score = 30, status = ScanStatus.WARNING, signals = listOf(Site.SHOPEE.signals[0]),
                screenshotUrl = null, pageReplicaUrl = null, ownerDeviceId = "dev_bayu", ownerName = members[1].name,
                detectedAt = now.minusSeconds(3600), verdict = null,
            ),
        )
        scans += data.scans.filter { it.ownerDeviceId == meId || it.ownerDeviceId == mariaId }
        data.scans = scans
        return data
    }

    /** Every scan marked safe by the Guardian. */
    fun allSafe(now: Instant): MockDataset {
        val data = figma(now)
        val verdict = Verdict(value = Verdict.Value.SAFE, byDeviceId = meId, byName = "Adhella", decidedAt = now.minusSeconds(300))
        data.scans = data.scans.map { it.copy(verdict = verdict) }
        return data
    }

    /** Only blocked scans. */
    fun allBlocked(now: Instant): MockDataset {
        val data = figma(now)
        data.scans = data.scans.filter { it.status == ScanStatus.BLOCKED }
        return data
    }

    /**
     * Imelda's eval corpus run through the detector (test 2a): `corpus-scans.json`, written by
     * `plan/alief/qa/corpus-to-scans.mjs`. The scans keep their real score, status and signals.
     * Android: the file lives in ios/ShooApp/Data/Fixtures, not contracts/fixtures, so the build doesn't copy it
     * yet; without it the list is empty, as on iOS when the file is missing.
     */
    fun corpus(now: Instant, fixtures: (String) -> String?): MockDataset {
        val data = figma(now)
        val page = try {
            fixtures("corpus-scans")?.let { ScanPage.fromJson(parseObject(it)) }
        } catch (_: Exception) {
            null
        }
        if (page == null) {
            Log.data.error("Missing fixture", "corpus-scans")
            data.scans = emptyList()
            return data
        }
        data.scans = page.items
        return data
    }

    /**
     * DT-04 (#497): the address card with the detector's `host`. `brand_plus_keyword` marks "bca" and "verifikasi"
     * and names the real address, `cheap_tld` marks ".site", `new_domain` has no `host` (whole domain).
     * Open with `-debug.detail address-marks`.
     */
    fun addressMarks(now: Instant): MockDataset {
        val data = figma(now)
        val syahnaz = owner("dev_syahnaz", "Syahnaz")
        val brand = signal(
            "brand_plus_keyword", 2, 40, "BCA name with extra words", "Nama BCA dengan kata tambahan",
            "The address uses the BCA name", "Alamatnya memakai nama BCA", evidence = "bca · level 2 · verifikasi",
        ).copy(host = Signal.Host(marks = listOf("bca", "verifikasi"), official = "bca.co.id", brand = "BCA"))
        val ending = signal(
            "cheap_tld", 1, 18, "Cheap .site ending", "Akhiran .site murah", "Scam sites often use .site",
            "Situs penipuan sering memakai .site",
        ).copy(host = Signal.Host(marks = listOf(".site")))
        val result = scan("address-marks", Site.BCA_BLOCKED, owner = syahnaz, at = today(10, 42, now)).copy(
            signals = listOf(
                brand,
                signal(
                    "new_domain", 3, 32, "Domain age 3 days", "Umur domain 3 hari", "This site was made 3 days ago",
                    "Situs ini baru dibuat 3 hari lalu",
                ),
                ending,
            ),
            score = 90,
        )
        data.scans = listOf(result) + data.scans.filter { it.ownerDeviceId == meId || it.ownerDeviceId == mariaId }
        return data
    }

    // MARK: Building blocks

    data class Owner(val deviceId: String, val name: String, val domainSuffix: String = "")

    fun owner(deviceId: String, name: String, domainSuffix: String = ""): Owner = Owner(deviceId, name, domainSuffix)

    fun owner(member: FamilyMember): Owner = owner(member.deviceId, member.name)

    /** The four sites Figma draws, with the reasons of its evidence cards. */
    enum class Site {
        BCA_BLOCKED,
        BCA_WARNING,
        SHOPEE,
        BANSOS,
        /** The 70/100 warning of protected/Home/warning 1363:12167: two reasons. */
        BCA_WARNING_70;

        val domain: String
            get() = when (this) {
                BCA_BLOCKED, BCA_WARNING, BCA_WARNING_70 -> "bca-verifikasi.site"
                SHOPEE -> "promo-shopee88.xyz"
                BANSOS -> "bansos-2026.site"
            }

        /** The page path after the host. */
        val path: String
            get() = when (this) {
                BCA_BLOCKED, BCA_WARNING, BCA_WARNING_70 -> "/login"
                SHOPEE -> "/klaim"
                BANSOS -> "/cek"
            }

        val url: String get() = "https://$domain$path"

        val title: String
            get() = when (this) {
                BCA_BLOCKED, BCA_WARNING, BCA_WARNING_70 -> "BCA m-Banking - Verifikasi Akun"
                SHOPEE -> "Klaim Hadiah Shopee"
                BANSOS -> "Cek Penerima Bansos 2026"
            }

        val score: Int
            get() = when (this) {
                BCA_BLOCKED -> 92
                BCA_WARNING -> 72
                BCA_WARNING_70 -> 70
                SHOPEE -> 88
                BANSOS -> 85
            }

        val status: ScanStatus get() = if (score >= ScoreThreshold.blocked) ScanStatus.BLOCKED else ScanStatus.WARNING

        /** Figma weights as drawn: +35 / +35 / +32 on 416:9255, +32 / +25 on 416:9469. */
        val signals: List<Signal>
            get() = when (this) {
                BCA_BLOCKED -> listOf(
                    signal("asks_pin", 3, 35, "Sensitive form", "Formulir sensitif", "Asks for m-banking PIN", "Meminta PIN m-banking", evidence = "pin"),
                    signal("brand_logo_offsite", 2, 35, "Copied logo", "Logo tiruan", "Copies the BCA logo", "Meniru logo BCA"),
                    signal("new_domain", 3, 32, "Domain age 3 days", "Umur domain 3 hari", "This site was made 3 days ago", "Situs ini baru dibuat 3 hari lalu"),
                )
                BCA_WARNING -> listOf(
                    signal("asks_pin", 3, 32, "Sensitive form", "Formulir sensitif", "Asks for m-banking PIN", "Meminta PIN m-banking", evidence = "pin"),
                    signal("brand_logo_offsite", 2, 25, "Copied logo", "Logo tiruan", "Copies the BCA logo", "Meniru logo BCA"),
                    signal("new_domain", 3, 15, "Domain age 3 days", "Umur domain 3 hari", "This site was made 3 days ago", "Situs ini baru dibuat 3 hari lalu"),
                )
                BCA_WARNING_70 -> listOf(
                    signal("asks_pin", 3, 35, "Sensitive form", "Formulir sensitif", "Asks for m-banking PIN", "Meminta PIN m-banking", evidence = "pin"),
                    signal("brand_logo_offsite", 2, 35, "Copied logo", "Logo tiruan", "Copies the BCA logo", "Meniru logo BCA"),
                )
                SHOPEE -> listOf(
                    signal("lookalike_domain", 1, 40, "Looks like shopee.co.id", "Mirip shopee.co.id", "The address imitates Shopee", "Alamatnya meniru Shopee"),
                    signal("cheap_tld", 1, 18, "Cheap .xyz ending", "Akhiran .xyz murah", "Scam sites often use .xyz", "Situs penipuan sering memakai .xyz"),
                    signal("urgent_language", 4, 30, "Urgent wording", "Bahasa mendesak", "Pushes you to claim within minutes", "Mendesak klaim dalam hitungan menit"),
                )
                BANSOS -> listOf(
                    signal("hoax_claim", 4, 40, "Fake aid claim", "Klaim bansos palsu", "Promises government aid that doesn't exist", "Menjanjikan bansos yang tidak ada"),
                    signal("asks_nik", 3, 30, "Asks for NIK", "Meminta NIK", "Asks for your ID number", "Meminta nomor KTP kamu", evidence = "nik"),
                    signal("cheap_tld", 1, 15, "Cheap .site ending", "Akhiran .site murah", "Scam sites often use .site", "Situs penipuan sering memakai .site"),
                )
            }
    }

    fun signal(
        id: String, layer: Int, weight: Int, en: String, idText: String, simpleEn: String, simpleId: String,
        evidence: String? = null,
    ): Signal = Signal(
        id = id, layer = layer, weight = weight, label = LocalizedText(en = en, id = idText),
        labelSimple = LocalizedText(en = simpleEn, id = simpleId), evidence = evidence,
    )

    fun scan(
        id: String, site: Site, owner: Owner, domainSuffix: String = "", at: Instant, verdict: Verdict? = null,
    ): ScanResult {
        val suffix = domainSuffix + owner.domainSuffix
        // A suffix keeps two scans of one owner on separate domains, so a verdict on one leaves the other alone.
        val domain = if (suffix.isEmpty()) site.domain else site.domain.replaceFirst(".", "$suffix.")
        return ScanResult(
            id = id, url = "https://$domain${site.path}", domain = domain, pageTitle = site.title, faviconUrl = null,
            score = site.score, status = site.status, signals = site.signals,
            screenshotUrl = "https://example.invalid/screens/$id.png", pageReplicaUrl = null,
            ownerDeviceId = owner.deviceId, ownerName = owner.name, detectedAt = at, verdict = verdict,
        )
    }

    fun guardianProfile(now: Instant, blocked: Int, warnings: Int): DeviceProfile = DeviceProfile(
        deviceId = meId, name = "Adhella", avatarId = "avatar_01", mode = UserMode.GUARDIAN, language = "id", guardian = null,
        stats = ProfileStats(blocked = blocked, warnings = warnings, since = now.minusSeconds(42L * 86_400)),
        timeZone = jakarta.id, notifications = NotificationSettings.defaults,
    )

    fun mariaProfile(now: Instant, blocked: Int, warnings: Int): DeviceProfile = DeviceProfile(
        deviceId = mariaId, name = "Maria", avatarId = "avatar_03", mode = UserMode.PROTECTED, language = "id", guardian = virellia,
        stats = ProfileStats(blocked = blocked, warnings = warnings, since = now.minusSeconds(42L * 86_400)),
        timeZone = jakarta.id, notifications = NotificationSettings.defaults,
    )

    /** Today at `hour:minute` WIB, or a minute ago when that is still ahead ("Hari ini · 10.42 WIB"). */
    fun today(hour: Int, minute: Int, now: Instant): Instant {
        val date = ZonedDateTime.ofInstant(now, jakarta).withHour(hour).withMinute(minute).withSecond(0).withNano(0).toInstant()
        val minuteAgo = now.minusSeconds(60)
        return if (date.isBefore(minuteAgo)) date else minuteAgo
    }

    fun day(year: Int, month: Int, day: Int, hour: Int, minute: Int): Instant =
        ZonedDateTime.of(year, month, day, hour, minute, 0, 0, jakarta).toInstant()
}
