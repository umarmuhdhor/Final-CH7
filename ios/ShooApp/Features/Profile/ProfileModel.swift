import Foundation
import Observation

/// Profile (PF-01) for both modes: name, language, the guardian link (Protected) or the family (Guardian).
/// Figma has three variants: Pribadi (Guardian, Family mode off), Guardian (Family mode on), Protected.
@MainActor
@Observable
final class ProfileModel {
    enum State: Equatable {
        case loading
        case loaded
        case failed
    }

    enum Variant: Equatable {
        /// Guardian with Family mode off: protects only themself.
        case personal
        /// Guardian with Family mode on.
        case guardian
        case protected
    }

    private(set) var state: State = .loading
    private(set) var profile: DeviceProfile?
    /// Guardian only: the people connected (x/3).
    private(set) var members: [FamilyMember] = []
    /// The family list could not be read; the rest of Profile still works.
    private(set) var membersFailed = false
    private(set) var isWorking = false
    /// Why the name was not saved; cleared as soon as the name is edited.
    private(set) var nameError: String.LocalizationValue?
    /// Disconnect / delete / language failures, shown as an alert.
    var actionError: String.LocalizationValue?
    var nameDraft = "" {
        didSet { if nameDraft != oldValue { nameError = nil } }
    }
    /// The running language sync; a newer choice cancels it.
    private(set) var languageTask: Task<Void, Never>?
    /// "Hapus akun" sheet: who loses what.
    func deleteMessage(language: AppLanguage) -> String {
        var text = L10n.string("Your name, family link and history are deleted right away. This can't be undone.", language: language)
        switch variant {
        case .guardian, .personal:
            if !members.isEmpty {
                text += " " + L10n.string("\(members.count) people you protect will be disconnected.", language: language)
            }
        case .protected:
            if let guardian = profile?.guardian {
                text += " " + L10n.string("\(guardian.name) will no longer get your warnings.", language: language)
            }
        }
        return text
    }

    /// Called right before disconnect or delete hands the app back to onboarding
    /// (close the sheet, clear pushed screens).
    @ObservationIgnored var onSessionEnd: () -> Void = {}

    /// "Notifikasi" row: Aktif / Mati.
    private(set) var notificationStatus: NotificationAuthorization?

    /// Protected "Akun Tertaut", "Link terblokir" and the "Situs diperiksa" counter (App Group, proposed keys).
    let linked: LinkedAccountSettings

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let notifications: (any NotificationPermission)?
    @ObservationIgnored private let now: () -> Date

    init(
        repository: any ShooRepository,
        settings: AppSettings,
        notifications: (any NotificationPermission)? = nil,
        linked: LinkedAccountSettings? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.linked = linked ?? LinkedAccountSettings()
        self.repository = repository
        self.settings = settings
        self.notifications = notifications
        self.now = now
    }

    var variant: Variant {
        switch settings.mode {
        case .protected: .protected
        default: settings.familyModeOn ? .guardian : .personal
        }
    }

    /// "Mode akun": Pribadi ↔ Guardian is Family mode (members stay connected, D Q5).
    func setFamilyMode(_ on: Bool) {
        guard settings.mode == .guardian else { return }
        settings.familyModeOn = on
    }

    // MARK: Stats

    /// Calendar days since `date`, counting today (registered today = 1).
    func days(since date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now())
        return max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
    }

    /// Pribadi and Protected: days protected, blocked, sites checked ("—" until the extension counts them).
    /// Guardian: members, days since the earliest member still connected, the members' blocked total.
    /// Empty when the server sends no stats, or a guardian protects nobody yet (the strip is hidden).
    func stats(language: AppLanguage) -> [ProfileStat] {
        let number = { (n: Int) in n.formatted(.number.locale(language.locale)) }
        switch variant {
        case .personal, .protected:
            guard let stats = profile?.stats else { return [] }
            return [
                ProfileStat(value: number(days(since: stats.since)), label: "Days protected"),
                ProfileStat(value: number(stats.blocked), label: "Sites blocked"),
                ProfileStat(value: linked.checkedCount.map(number) ?? "—", label: "Sites checked"),
            ]
        case .guardian:
            guard !membersFailed, !members.isEmpty, members.allSatisfy({ $0.stats != nil }) else { return [] }
            let since = members.compactMap(\.connectedAt).min()
            return [
                ProfileStat(value: number(members.count), label: "People protected"),
                ProfileStat(value: since.map { number(days(since: $0)) } ?? number(0), label: "Days as guardian"),
                ProfileStat(value: number(members.reduce(0) { $0 + ($1.stats?.blocked ?? 0) }), label: "Sites blocked"),
            ]
        }
    }

    /// "@adhella": the name in lower case without spaces (Kelola profil "Username").
    var username: String {
        "@" + (profile?.name ?? "").lowercased().filter { !$0.isWhitespace }
    }

    /// "@adhella · Pribadi" (Figma "Handle"): the username, then the mode. Protected has none (Figma).
    func handle(language: AppLanguage) -> String {
        switch variant {
        case .protected: return ""
        case .personal: return username + " · " + L10n.string("Personal", language: language)
        case .guardian: return username + " · " + L10n.string("Guardian", language: language)
        }
    }

    // MARK: Notifications

    func refreshNotifications() async {
        notificationStatus = await notifications?.status()
    }

    /// "Notifikasi": asks in the app the first time; `true` when only Settings can change it now.
    func notificationsTapped() async -> Bool {
        guard let notifications else { return true }
        switch await notifications.status() {
        case .notDetermined:
            notificationStatus = await notifications.request()
            return false
        case .denied, .authorized:
            return true
        }
    }

    var showsFamilyCode: Bool { settings.mode == .guardian }

    /// "Aktif sejak 20 Juni" (Protected Kelola profil): when this device registered.
    func activeSince(language: AppLanguage) -> String? {
        guard let since = profile?.stats?.since else { return nil }
        let date = since.formatted(.dateTime.day().month(.wide).locale(language.locale))
        return L10n.string("Active since \(date)", language: language)
    }

    // MARK: Mode Guardian card (Pribadi)

    var showsGuardianCard: Bool { variant == .personal && !settings.guardianCardDismissed }

    /// "Menjadi Guardian": Family mode on, so Profile turns into the Guardian layout.
    func becomeGuardian() { setFamilyMode(true) }

    func dismissGuardianCard() { settings.guardianCardDismissed = true }

    /// Same rule as ON-02.
    var nameProblem: NameRule.Problem? {
        if case .failure(let problem) = NameRule.validate(nameDraft) { return problem }
        return nil
    }

    func load() async {
        do {
            let me = try await repository.me()
            // Keep a name the user is still editing.
            if nameDraft.isEmpty || nameDraft == profile?.name { nameDraft = me.name }
            profile = me
            state = .loaded
            // The server missed the last language change (offline then): send it again.
            if me.language != settings.language.code { chooseLanguage(settings.language, force: true) }
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Profile load failed", error)
            if state != .loaded { state = .failed }
            return
        }
        guard settings.mode == .guardian else { return }
        do {
            members = try await repository.familyMembers()
            membersFailed = false
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Profile members failed", error)
            membersFailed = true
        }
    }

    /// "Try again": shows the spinner while it retries.
    func retry() async {
        state = .loading
        await load()
    }

    /// Saves the edited name; `false` when it breaks the rule or the server says no (old name stays).
    func saveName() async -> Bool {
        guard case .success(let trimmed) = NameRule.validate(nameDraft), !isWorking else { return false }
        nameError = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.updateMe(DeviceUpdate(name: trimmed))
            profile?.name = trimmed
            nameDraft = trimmed
            return true
        } catch {
            Log.ui.error("Name save failed", error)
            nameError = "Couldn't save. Check your connection and try again."
            return false
        }
    }

    /// The app switches at once; the server learns it for localized pushes (D-alief-05).
    /// Only the newest choice is sent.
    func chooseLanguage(_ language: AppLanguage, force: Bool = false) {
        guard force || language != settings.language else { return }
        settings.language = language
        languageTask?.cancel()
        languageTask = Task { [repository] in
            do {
                try await repository.updateMe(DeviceUpdate(language: language.code))
                guard !Task.isCancelled else { return }
                profile?.language = language.code
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                // The app keeps the choice; `load()` sends it again next time.
                Log.ui.error("Language save failed", error)
                actionError = "Couldn't save. Check your connection and try again."
            }
        }
    }

    /// "Ingatkan" (PF-01 proposed): a message to announce, or `nil` when sent. Marks the member as reminded.
    func remind(_ member: FamilyMember) async -> String.LocalizationValue? {
        let result = await MemberActions.remind(member, repository: repository)
        if result == nil, let index = members.firstIndex(where: { $0.deviceId == member.deviceId }) {
            members[index].remindedAt = now()
        }
        return result ?? "Reminder sent to \(member.name)"
    }

    // MARK: Pengaturan/Notifikasi

    /// What the notification page shows: the server's settings, or its defaults before the first load.
    var notificationSettings: NotificationSettings { profile?.notifications ?? .defaults }

    /// Changes at once; the server decides which pushes go out, so a failed save goes back and says so.
    func updateNotifications(_ update: NotificationSettingsUpdate) async {
        guard profile != nil else { return }
        let before = profile?.notifications
        let after = notificationSettings.applying(update)
        profile?.notifications = after
        do {
            try await repository.updateMe(DeviceUpdate(notifications: update))
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Notification settings save failed", error)
            profile?.notifications = before
            actionError = "Couldn't save. Check your connection and try again."
        }
    }

    // MARK: Kelola profil

    /// "Ubah foto": one of the onboarding avatars. `false` (old avatar stays) when the server says no.
    func chooseAvatar(_ avatarId: String) async -> Bool {
        guard avatarId != profile?.avatarId, !isWorking else { return avatarId == profile?.avatarId }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.updateMe(DeviceUpdate(avatarId: avatarId))
            profile?.avatarId = avatarId
            return true
        } catch {
            Log.ui.error("Avatar save failed", error)
            actionError = "Couldn't save. Check your connection and try again."
            return false
        }
    }

    /// "Punya kode undangan?": only a guardian who protects nobody can join another family.
    var canJoinAnotherFamily: Bool { settings.mode == .guardian && members.isEmpty && !membersFailed }

    /// SECURITY §3 P3: gone on the server first, then a fresh install here (onboarding from the start).
    func deleteMyData() async -> Bool {
        guard !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await repository.deleteMe()
        } catch RepositoryError.api(.notFound, _), RepositoryError.api(.unauthorized, _) {
            // Already deleted (an earlier answer got lost): same end state.
        } catch {
            Log.ui.error("Delete data failed", error)
            actionError = "Couldn't delete your data. Check your connection and try again."
            return false
        }
        // `ApiRepository.deleteMe` has already cleared the Keychain token and App Group session keys.
        linked.clear()
        onSessionEnd()
        settings.reset()
        return true
    }
}
