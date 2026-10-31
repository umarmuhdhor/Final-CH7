import CoreGraphics
import Foundation
import Testing
@testable import Shoo

/// Fixture scan ids (contracts/fixtures, inlined in activity-family.json).
enum FixtureScan {
    static let warning41 = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e01"
    static let warning63 = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e02"
    static let blocked92 = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03"
    static let verifiedScam = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e04"
    static let markedSafe = "6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e05"
}

/// Wraps `MockRepository` and lets a test fail or watch individual calls.
actor StubRepository: ShooRepository {
    private let base: MockRepository
    private var failLoads: Int
    private var verdictFailures: Int
    private let verdictError: RepositoryError
    private let onVerdict: (@Sendable () async -> Void)?
    private var onScan: (@Sendable () async -> Void)?
    private(set) var verdictCalls = 0

    init(
        mode: UserMode = .guardian,
        failLoads: Int = 0,
        verdictFailures: Int = 0,
        verdictError: RepositoryError = .network,
        onVerdict: (@Sendable () async -> Void)? = nil
    ) {
        base = MockRepository(mode: mode, latency: .zero)
        self.failLoads = failLoads
        self.verdictFailures = verdictFailures
        self.verdictError = verdictError
        self.onVerdict = onVerdict
    }

    func registerDevice(name: String, mode: UserMode, avatarId: String?, apnsToken: String?) async throws -> DeviceRegistration {
        try await base.registerDevice(name: name, mode: mode, avatarId: avatarId, apnsToken: apnsToken)
    }
    func me() async throws -> DeviceProfile { try await base.me() }
    func updateMe(_ update: DeviceUpdate) async throws { try await base.updateMe(update) }
    func createFamilyCode(refresh: Bool) async throws -> FamilyCode { try await base.createFamilyCode(refresh: refresh) }
    func joinFamily(code: String) async throws -> GuardianInfo { try await base.joinFamily(code: code) }
    func familyMembers() async throws -> [FamilyMember] { try await base.familyMembers() }
    func removeMember(deviceId: String) async throws { try await base.removeMember(deviceId: deviceId) }
    func leaveGuardian() async throws { try await base.leaveGuardian() }
    func setMemberNotify(deviceId: String, notify: Bool) async throws { try await base.setMemberNotify(deviceId: deviceId, notify: notify) }
    func remindMember(deviceId: String) async throws { try await base.remindMember(deviceId: deviceId) }
    func becomeProtected(code: String) async throws -> ProtectedSwitch { try await base.becomeProtected(code: code) }
    func deleteMe() async throws { try await base.deleteMe() }
    func scans(owner: ScanOwnerFilter, status: ScanStatus?, cursor: String?) async throws -> ScanPage {
        try await base.scans(owner: owner, status: status, cursor: cursor)
    }

    func scan(id: String) async throws -> ScanResult {
        if failLoads > 0 {
            failLoads -= 1
            throw RepositoryError.network
        }
        // Read first, then let the test act: the answer is a snapshot from before that action.
        scanCalls += 1
        if let goneFromCall, scanCalls >= goneFromCall {
            throw RepositoryError.api(.notFound, message: "Scan not found")
        }
        var scan = try await base.scan(id: id)
        editScan?(&scan, scanCalls)
        if let hook = onScan {
            onScan = nil
            await hook()
        }
        return scan
    }

    /// `scan(id:)` calls so far, the load's own included.
    private(set) var scanCalls = 0
    private var editScan: (@Sendable (inout ScanResult, Int) -> Void)?

    private var goneFromCall: Int?

    /// From this call on (counted like `scanCalls`), `scan(id:)` answers 404.
    func setGone(fromCall: Int) { goneFromCall = fromCall }

    /// The next `count` loads fail with `.network` (not counted in `scanCalls`).
    func failNextLoads(_ count: Int) { failLoads = count }

    /// Changes every scan `scan(id:)` returns; gets the call number (from 1).
    func setEditScan(_ edit: @escaping @Sendable (inout ScanResult, Int) -> Void) {
        editScan = edit
    }

    /// Runs once during the next `scan(id:)`, after the scan was read.
    func setOnScan(_ hook: @escaping @Sendable () async -> Void) {
        onScan = hook
    }

    func setVerdict(scanId: String, value: Verdict.Value) async throws -> Verdict {
        verdictCalls += 1
        await onVerdict?()
        if verdictFailures > 0 {
            verdictFailures -= 1
            throw verdictError
        }
        return try await base.setVerdict(scanId: scanId, value: value)
    }
}

@MainActor
struct DetailModelTests {
    private func loaded(
        _ id: String,
        mode: UserMode = .guardian,
        repository: (any ShooRepository)? = nil
    ) async -> DetailModel {
        let model = DetailModel(scanId: id, repository: repository ?? MockRepository(mode: mode, latency: .zero))
        await model.load()
        return model
    }

    // MARK: Load

    @Test func loadsScanAndViewer() async {
        let model = await loaded(FixtureScan.blocked92)
        #expect(model.state == .loaded)
        #expect(model.scan?.domain == "bca-verifikasi.site")
        #expect(model.viewer?.deviceId == "dev_me")
    }

    @Test func unknownScanIsNotFound() async {
        let model = await loaded("missing")
        #expect(model.state == .notFound)
        #expect(model.scan == nil)
    }

    @Test func protectedCannotOpenSomeoneElsesScan() async {
        let model = await loaded(FixtureScan.warning63, mode: .protected)
        #expect(model.state == .notFound)
    }

    @Test func networkErrorFailsThenRetryLoads() async {
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: StubRepository(failLoads: 1))
        await model.load()
        #expect(model.state == .failed)
        await model.load()
        #expect(model.state == .loaded)
    }

    // MARK: DT-02 label

    @Test(arguments: [
        (FixtureScan.warning41, ScanBadge.warning),
        (FixtureScan.warning63, .warning),
        (FixtureScan.blocked92, .blocked),
        (FixtureScan.verifiedScam, .verifiedScam),
        (FixtureScan.markedSafe, .markedSafe),
    ])
    func badgeFollowsStatusAndVerdict(id: String, badge: ScanBadge) async {
        #expect(await loaded(id).badge == badge)
    }

    // MARK: DT-05 who sees the buttons

    @Test(arguments: [
        (FixtureScan.warning41, UserMode.guardian, true),
        (FixtureScan.warning63, .guardian, true),
        (FixtureScan.blocked92, .guardian, true),
        (FixtureScan.verifiedScam, .guardian, true),
        (FixtureScan.markedSafe, .guardian, true),
        (FixtureScan.warning41, .protected, false),
        (FixtureScan.blocked92, .protected, false),
        (FixtureScan.markedSafe, .protected, false),
    ])
    func onlyGuardianValidatesWarningAndBlockedItems(id: String, mode: UserMode, expected: Bool) async {
        let model = await loaded(id, mode: mode)
        #expect(model.state == .loaded)
        #expect(model.canValidate == expected)
    }

    // MARK: DT-04 evidence

    @Test func guardianEvidenceIsTopThreeByWeightWithFullLabels() async {
        let evidence = await loaded(FixtureScan.blocked92).evidence(language: .english)
        #expect(evidence.map(\.weight) == [30, 25, 22])
        #expect(evidence.map(\.text) == [
            "Domain age 3 days",
            "Form asks for m-banking PIN",
            "Verification page asks for PIN + OTP",
        ])
        #expect(evidence[0].weightText(language: .english) == "+30%")
        #expect(evidence.map(\.runningWeights) == [[30], [30, 25], [30, 25, 22]])
        #expect(evidence.map(\.index) == [0, 1, 2])
        #expect(evidence.map(\.kind) == [.newDomain, .sensitiveForm, .unusualRequest])
    }

    @Test func protectedEvidenceUsesSimpleLabels() async {
        let model = await loaded(FixtureScan.blocked92, mode: .protected)
        #expect(model.evidence(language: .english).map(\.text) == [
            "This site was made 3 days ago",
            "Asks for your bank PIN — banks never do this",
            "A real bank page would not ask this",
        ])
        #expect(model.evidence(language: .indonesian)[0].text == "Situs ini baru dibuat 3 hari lalu")
    }

    @Test func voiceOverReadsTheWeightInWords() async {
        let item = await loaded(FixtureScan.blocked92).evidence(language: .english)[0]
        #expect(item.spokenLine(language: .english) == "Domain age 3 days, adds 30 percent to the risk score")
        #expect(item.spokenLine(language: .indonesian) == "Domain age 3 days, menambah 30 persen ke skor risiko")
    }

    @Test func equalWeightsKeepContractOrder() {
        let scan = FixtureLoader.scan("blocked-marked-safe")
        let evidence = Evidence.top(scan.signals, mode: .guardian, language: .english)
        #expect(evidence.map(\.weight) == [30, 30, 21])
        #expect(evidence.map(\.text).first == "Form asks for card number + CVV")
    }

    @Test func evidenceIsSortedEvenWhenTheContractIsNot() {
        var scan = FixtureLoader.scan("warning-41")
        scan.signals.reverse()
        let evidence = Evidence.top(scan.signals, mode: .guardian, language: .english)
        #expect(evidence.map(\.weight) == [15, 14, 12])
    }

    @Test func marksGoToTheirSignal() {
        let scan = FixtureLoader.scan("blocked-92")
        let pin = CGRect(x: 20, y: 120, width: 350, height: 52)
        let marks = [ReplicaMark(signalId: "asks_pin", rect: pin), ReplicaMark(signalId: "other", rect: .zero)]
        let evidence = Evidence.top(scan.signals, mode: .guardian, language: .english, marks: marks)
        #expect(evidence.map(\.highlights) == [[], [pin], []])
    }

    @Test(arguments: [
        ("asks_otp", SignalKind.sensitiveForm),
        ("asks_selfie_ktp", .sensitiveForm),
        ("brand_logo_offsite", .copiedLogo),
        ("new_domain", .newDomain),
        ("db_match", .knownScam),
        ("something_new", .other),
    ])
    func signalKindFollowsTheId(id: String, kind: SignalKind) {
        #expect(SignalKind(signalId: id) == kind)
    }

    @Test(arguments: [
        ([30, 25, 22], [0.3, 0.25, 0.22]),
        ([70, 50], [0.7, 0.3]),
        ([-5, 10], [0, 0.1]),
    ])
    func contributionBarNeverPassesTheWholeBar(weights: [Int], expected: [Double]) {
        let fractions = ContributionBar.fractions(weights)
        #expect(zip(fractions, expected).allSatisfy { abs($0 - $1) < 0.0001 })
        #expect(fractions.reduce(0, +) <= 1.0001)
    }

    @Test func singleSignalGivesOneItem() {
        let scan = FixtureLoader.scan("blocked-verified-scam")
        #expect(Evidence.top(scan.signals, mode: .protected, language: .english).count == 1)
    }

    // MARK: DT-06 verification note

    @Test func ownVerdictSaysByYou() async {
        let model = await loaded(FixtureScan.verifiedScam)
        #expect(model.verdictNote(language: .english) == "Verified scam by you")
        #expect(model.verdictNote(language: .indonesian) == "Penipuan terverifikasi oleh kamu")
    }

    @Test func guardianVerdictSeenByProtectedNamesTheGuardian() async {
        let model = await loaded(FixtureScan.markedSafe, mode: .protected)
        #expect(model.verdictNote(language: .english) == "Marked safe by Adhella")
        #expect(model.verdictNote(language: .indonesian) == "Ditandai aman oleh Adhella")
    }

    @Test func noVerdictNoNote() async {
        #expect(await loaded(FixtureScan.blocked92).verdictNote(language: .english) == nil)
    }

    // MARK: DT-03 owner

    @Test func ownerShownForFamilyItemsOnly() async {
        let moms = await loaded(FixtureScan.blocked92)
        #expect(moms.showsOwner(familyModeOn: false))
        let mine = await loaded(FixtureScan.warning63)
        #expect(!mine.showsOwner(familyModeOn: false))
        #expect(mine.showsOwner(familyModeOn: true))
        #expect(mine.isOwnScan)
        let asProtected = await loaded(FixtureScan.blocked92, mode: .protected)
        #expect(!asProtected.showsOwner(familyModeOn: true))
    }

    // MARK: DT-05 / GD-07 verdict

    @Test func verdictAppliesAtOnceWithoutConfirmation() async {
        let model = await loaded(FixtureScan.blocked92)
        await model.setVerdict(.notSafe)
        #expect(model.badge == .verifiedScam)
        #expect(model.verdictNote(language: .english) == "Verified scam by you")
        #expect(!model.verdictFailed)
        #expect(!model.isSubmittingVerdict)
    }

    @Test func verdictIsOptimistic() async {
        let ref = ModelRef()
        let stub = StubRepository(onVerdict: {
            await MainActor.run {
                let model = ref.model!
                #expect(model.scan?.verdict?.value == .safe)
                #expect(model.scan?.verdict?.byDeviceId == "dev_me")
                #expect(model.badge == .markedSafe)
                #expect(model.isSubmittingVerdict)
            }
        })
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: stub)
        ref.model = model
        await model.load()
        await model.setVerdict(.safe)
        #expect(await stub.verdictCalls == 1)
        #expect(model.badge == .markedSafe)
    }

    @Test func failedVerdictRollsBackToNoVerdict() async {
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: StubRepository(verdictFailures: 1))
        await model.load()
        await model.setVerdict(.notSafe)
        #expect(model.scan?.verdict == nil)
        #expect(model.badge == .blocked)
        #expect(model.verdictFailed)
        #expect(!model.isSubmittingVerdict)
    }

    @Test func failedVerdictRollsBackToPreviousVerdict() async {
        let stub = StubRepository(verdictFailures: 1, verdictError: .api(.verdictNotAllowed, message: "no"))
        let model = DetailModel(scanId: FixtureScan.markedSafe, repository: stub)
        await model.load()
        let before = model.scan?.verdict
        await model.setVerdict(.notSafe)
        #expect(model.scan?.verdict == before)
        #expect(model.badge == .markedSafe)
        #expect(model.verdictFailed)
    }

    @Test func nextVerdictClearsTheError() async {
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: StubRepository(verdictFailures: 1))
        await model.load()
        await model.setVerdict(.notSafe)
        #expect(model.verdictFailed)
        await model.setVerdict(.notSafe)
        #expect(!model.verdictFailed)
        #expect(model.badge == .verifiedScam)
    }

    @Test func reloadDuringVerdictKeepsTheNewVerdict() async {
        let ref = ModelRef()
        let stub = StubRepository()
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: stub)
        ref.model = model
        await model.load()
        // The reload reads the scan, then the guardian taps before the stale answer lands.
        await stub.setOnScan { await ref.model!.setVerdict(.notSafe) }
        await model.load()
        #expect(model.badge == .verifiedScam)
        #expect(model.scan?.verdict?.byDeviceId == "dev_me")
    }

    @Test func verdictOnDeletedScanShowsGone() async {
        let stub = StubRepository(verdictFailures: 1, verdictError: .api(.notFound, message: "gone"))
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: stub)
        await model.load()
        let outcome = await model.setVerdict(.notSafe)
        #expect(outcome == .gone)
        #expect(model.state == .notFound)
        #expect(model.scan == nil)
    }

    @Test func outcomesTellTheViewWhatHappened() async {
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: StubRepository(verdictFailures: 1))
        await model.load()
        #expect(await model.setVerdict(.notSafe) == .rolledBack)
        #expect(await model.setVerdict(.notSafe) == .saved)
        #expect(model.verdictSaves == 1)
        let warning = DetailModel(scanId: FixtureScan.warning41, repository: MockRepository(latency: .zero))
        await warning.load()
        #expect(await warning.setVerdict(.safe) == .saved)
    }

    @Test func protectedNeverSendsAVerdict() async {
        let stub = StubRepository(mode: .protected)
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: stub)
        await model.load()
        await model.setVerdict(.safe)
        #expect(await stub.verdictCalls == 0)
        #expect(model.scan?.verdict == nil)
    }

    @Test func warningTakesAVerdictToo() async {
        let stub = StubRepository()
        let model = DetailModel(scanId: FixtureScan.warning41, repository: stub)
        await model.load()
        #expect(await model.setVerdict(.notSafe) == .saved)
        #expect(await stub.verdictCalls == 1)
        #expect(model.scan?.verdict?.value == .notSafe)
    }

    @Test func secondTapWhileSendingIsIgnored() async {
        let ref = ModelRef()
        let stub = StubRepository(onVerdict: {
            await ref.model!.setVerdict(.safe)
        })
        let model = DetailModel(scanId: FixtureScan.blocked92, repository: stub)
        ref.model = model
        await model.load()
        await model.setVerdict(.notSafe)
        #expect(await stub.verdictCalls == 1)
        #expect(model.badge == .verifiedScam)
    }
}

/// Lets a stub callback reach the model it is injected into.
@MainActor
final class ModelRef {
    var model: DetailModel?
}

/// Decodes a fixture copy from the app bundle.
enum FixtureLoader {
    static func scan(_ name: String) -> ScanResult {
        let url = Bundle.main.url(forResource: name, withExtension: "json")!
        // swiftlint:disable:next force_try
        return try! JSONDecoder.shoo.decode(ScanResult.self, from: Data(contentsOf: url))
    }
}
