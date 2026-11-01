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
        case alreadyConnected
        /// "Punya kode undangan?" while still protecting someone (PF-01).
        case hasMembers
        case offline
        case other
        /// U4 (fase 26): the pasted text is not a Shoo invite link. Nothing was sent.
        case notAnInvite
        /// U5 (fase 26, K5): a code from a link, QR or paste that the server no longer knows or that
        /// expired. "Check the 6 digits" would mislead: the user never typed them.
        case staleInvite

        init(_ error: any Error) {
            switch (error as? RepositoryError)?.apiCode {
            case .codeInvalid?: self = .invalid
            case .codeExpired?: self = .expired
            case .familyFull?: self = .full
            case .tooManyAttempts?, .rateLimited?: self = .tooManyAttempts
            case .alreadyConnected?: self = .alreadyConnected
            case .hasMembers?: self = .hasMembers
            case nil where (error as? RepositoryError) == .network: self = .offline
            default: self = .other
            }
        }

        var message: String.LocalizationValue {
            switch self {
            case .invalid: "That code doesn't match a family. Check the 6 digits and try again."
            case .expired: "That code has expired. Ask your guardian for the new code."
            case .full: "This family already has 3 people. Ask your guardian to remove someone first."
            case .tooManyAttempts: "Too many tries. Wait a few minutes, then try again."
            case .alreadyConnected: "You're already connected to a guardian. Disconnect in Profile first."
            case .hasMembers: "You still protect someone. Disconnect them in Profile first."
            case .offline: "No connection. Check your internet and try again."
            case .other: "Something went wrong. Try again."
            case .notAnInvite: "That isn't a Shoo invite link. Ask your family to send it again, or type the 6-digit code."
            case .staleInvite: "This invite has expired. Ask your family for a new link."
            }
        }
    }

    static let codeLength = DeepLink.codeLength

    private(set) var state: State = .entering
    private(set) var problem: Problem?
    /// Digits only, at most 6; editing clears the last problem. A pasted invite link or invite message
    /// gives the link's code (U6), not every digit in the text.
    var code = "" {
        didSet {
            let linked = code.unicodeScalars.allSatisfy { ("0"..."9").contains($0) } ? nil : InvitePaste.code(inText: code)
            let digits = linked ?? String(code.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init).prefix(Self.codeLength))
            if digits != code { code = digits }
            if code != oldValue { problem = nil }
            if code != linkedCode { linkedCode = nil }
        }
    }

    /// The code as it came from a link, a QR or a paste, until the user edits it (K5).
    @ObservationIgnored private var linkedCode: String?
    @ObservationIgnored private let joinWithCode: (String) async throws -> GuardianInfo
    /// The app's pasteboard watcher (fase 26); `nil` in previews.
    let clipboard: InviteClipboard?

    /// `join` replaces `POST /family/join`, e.g. a guardian joining as protected (PF-01).
    init(
        repository: any ShooRepository, code: String? = nil, clipboard: InviteClipboard? = nil,
        join: ((String) async throws -> GuardianInfo)? = nil
    ) {
        joinWithCode = join ?? { try await repository.joinFamily(code: $0) }
        self.clipboard = clipboard
        if let code { prefill(code) }
    }

    var canJoin: Bool { state == .entering && DeepLink.isCode(code) }

    /// From `shoo://join?code=` or a QR: fills the field, never joins (T11).
    func prefill(_ code: String) {
        guard state == .entering, DeepLink.isCode(code) else { return }
        self.code = code
        linkedCode = code
    }

    /// U2: the text the system Paste button gave. Our invite link fills the code (never joins, T11);
    /// anything else says so and sends nothing.
    func pasted(_ items: [String]) {
        guard state == .entering else { return }
        let code = if let clipboard { clipboard.accept(items) } else { InvitePaste.code(from: items) }
        guard let code else {
            problem = .notAnInvite
            return
        }
        prefill(code)
        problem = nil
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

    func join() async {
        guard canJoin else { return }
        state = .joining
        problem = nil
        do {
            // `ApiRepository` keeps `guardian.name` in the App Group for the extension (EX-06).
            let guardian = try await joinWithCode(code)
            state = .joined(guardian)
            clipboard?.joined(code: code)
        } catch {
            state = .entering
            guard !error.isCancellation else { return }
            Log.ui.error("Join failed", error)
            let problem = Problem(error)
            self.problem = linkedCode == code && (problem == .invalid || problem == .expired) ? .staleInvite : problem
        }
    }
}
