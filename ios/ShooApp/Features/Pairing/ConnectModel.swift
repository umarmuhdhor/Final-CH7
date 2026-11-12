import Foundation
import Observation

/// PR-01 / PR-02 / PR-03: a protected device joins its guardian's family with the 6-digit code.
/// A code from a link or a QR only fills the field; joining always needs the Connect tap (T11).
@MainActor
@Observable
final class ConnectModel {
    enum State: Equatable {
        case entering
        case joining
        /// PR-02: "You're protected by [name]".
        case joined(GuardianInfo)
    }

    /// Why the join didn't work, worded for the person holding the phone (contracts/api.md join errors).
    enum Problem: Equatable {
        case invalid
        case expired
        case full
        case tooManyAttempts
        /// `rate_limited` from `POST /devices` (a join in onboarding registers first): too many new
        /// devices from this IP, often a carrier's shared IP. No join was tried, and the wait can be an hour.
        case signUpLimit
        case alreadyConnected
        /// "Punya kode undangan?" while still protecting someone (PF-01).
        case hasMembers
        case offline
        case other

        init(_ error: any Error) {
            switch (error as? RepositoryError)?.apiCode {
            case .codeInvalid?: self = .invalid
            case .codeExpired?: self = .expired
            case .familyFull?: self = .full
            case .tooManyAttempts?: self = .tooManyAttempts
            case .rateLimited?: self = .signUpLimit
            case .alreadyConnected?: self = .alreadyConnected
            case .hasMembers?: self = .hasMembers
            case nil where (error as? RepositoryError) == .network: self = .offline
            default: self = .other
            }
        }

        var message: String.LocalizationValue {
            switch self {
            // Figma "Connect with Guardian · Kode salah / Keluarga penuh / Terlalu banyak …" (1681:4712–4824).
            case .invalid: "That code doesn't match. Check it again, or ask your Guardian for a new code."
            case .expired: "That code has expired. Ask your guardian for the new code."
            case .full: "This family already has 3 people. Ask your Guardian to remove one person first."
            case .tooManyAttempts: "Too many tries. For your safety, wait a moment before trying again."
            case .signUpLimit: "Too many sign-ups from this network. Try again in 1 hour."
            case .alreadyConnected: "You're already connected to a guardian. Only they can disconnect you: ask them first."
            case .hasMembers: "You still protect someone. Disconnect them in Profile first."
            case .offline: "No connection. Check your internet and try again."
            case .other: "Something went wrong. Try again."
            }
        }

        /// The server holds every join for a while: the button counts down instead of "Connect".
        var isWait: Bool { self == .tooManyAttempts || self == .signUpLimit }
    }

    static let codeLength = DeepLink.codeLength

    private(set) var state: State = .entering
    private(set) var problem: Problem?
    /// `too_many_attempts` / `rate_limited` with a `Retry-After`: no join before this time (Figma "Coba lagi dalam 04:59").
    private(set) var retryAt: Date?
    /// Onboarding is undoing a failed invite registration (fase 27d): no join may start meanwhile.
    private(set) var isHeld = false
    /// Digits only, at most 6; editing clears the last problem.
    var code = "" {
        didSet {
            let digits = String(code.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init).prefix(Self.codeLength))
            if digits != code { code = digits }
            // A wait stays on screen while the code is edited: the server still refuses until it ends.
            if code != oldValue, retryAt == nil { problem = nil }
        }
    }

    @ObservationIgnored private let joinWithCode: (String) async throws -> GuardianInfo

    /// `join` replaces `POST /family/join`, e.g. a guardian joining as protected (PF-01).
    init(repository: any ShooRepository, code: String? = nil, join: ((String) async throws -> GuardianInfo)? = nil) {
        joinWithCode = join ?? { try await repository.joinFamily(code: $0) }
        if let code { prefill(code) }
    }

    var canJoin: Bool { state == .entering && !isHeld && retryAt == nil && DeepLink.isCode(code) }

    /// Seconds left of the wait, rounded up; `nil` with no wait.
    func secondsToWait(now: Date = Date()) -> Int? {
        retryAt.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) }
    }

    /// The wait is over (the view's timer): Connect comes back and the line goes.
    func waitEnded(now: Date = Date()) {
        guard let retryAt, now >= retryAt else { return }
        self.retryAt = nil
        problem = nil
    }

    /// "Ketik ulang kode": empties the field for a fresh try.
    func retype() {
        guard state == .entering, retryAt == nil else { return }
        code = ""
        problem = nil
    }

    /// Busy with a join or with something onboarding does on this screen: Back and "Not now" wait.
    var isBusy: Bool { state == .joining || isHeld }

    /// From `shoo://join?code=` or a QR: fills the field, never joins (T11).
    func prefill(_ code: String) {
        guard state == .entering, DeepLink.isCode(code) else { return }
        self.code = code
    }

    /// A scanned QR: our invite link fills the code; anything else is refused (`false`).
    func scanned(_ payload: String) -> Bool {
        // An invite link is under 100 characters; anything much longer is not ours.
        guard payload.utf8.count <= 512, let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              case .join(let code) = DeepLink(url: url)
        else { return false }
        prefill(code)
        return true
    }

    /// A failure outside `join()` that belongs on this screen (onboarding "Not now").
    func report(_ error: any Error) {
        show(error)
    }

    private func show(_ error: any Error, now: Date = Date()) {
        let problem = Problem(error)
        if problem.isWait, let seconds = (error as? RepositoryError)?.retryAfter, seconds > 0 {
            retryAt = now.addingTimeInterval(seconds)
        }
        self.problem = problem
    }

    /// Set by onboarding around its own work on this screen (`isHeld`).
    func hold(_ held: Bool) {
        isHeld = held
    }

    /// The server says this device has a guardian after all (a join whose answer got lost): PR-02.
    func showJoined(_ guardian: GuardianInfo) {
        problem = nil
        retryAt = nil
        state = .joined(guardian)
    }

    #if DEBUG
    /// UI-gate screenshots only (`-debug.onboardingStep connected`).
    func showJoinedForScreenshot() {
        state = .joined(GuardianInfo(deviceId: "dev_nisrina", name: "Nisrina", avatarId: "avatar_04"))
    }
    #endif

    func join() async {
        guard canJoin else { return }
        state = .joining
        problem = nil
        do {
            // `ApiRepository` keeps `guardian.name` in the App Group for the extension (EX-06).
            let guardian = try await joinWithCode(code)
            state = .joined(guardian)
        } catch {
            state = .entering
            guard !error.isCancellation else { return }
            Log.ui.error("Join failed", error)
            show(error)
        }
    }
}
