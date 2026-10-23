import Foundation
import Observation

/// PR-01 / PR-02 / PR-03: a protected device joins its guardian's family with the 4-digit code.
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
        case offline
        case other

        init(_ error: any Error) {
            switch (error as? RepositoryError)?.apiCode {
            case .codeInvalid?: self = .invalid
            case .codeExpired?: self = .expired
            case .familyFull?: self = .full
            case .tooManyAttempts?, .rateLimited?: self = .tooManyAttempts
            case .alreadyConnected?: self = .alreadyConnected
            case nil where (error as? RepositoryError) == .network: self = .offline
            default: self = .other
            }
        }

        var message: String.LocalizationValue {
            switch self {
            case .invalid: "That code doesn't match a family. Check the 4 digits and try again."
            case .expired: "That code has expired. Ask your guardian for the new code."
            case .full: "This family already has 3 people. Ask your guardian to remove someone first."
            case .tooManyAttempts: "Too many tries. Wait a few minutes, then try again."
            case .alreadyConnected: "You're already connected to a guardian. Disconnect in Profile first."
            case .offline: "No connection. Check your internet and try again."
            case .other: "Something went wrong. Try again."
            }
        }
    }

    static let codeLength = 4

    private(set) var state: State = .entering
    private(set) var problem: Problem?
    /// Digits only, at most 4; editing clears the last problem.
    var code = "" {
        didSet {
            let digits = String(code.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init).prefix(Self.codeLength))
            if digits != code { code = digits }
            if code != oldValue { problem = nil }
        }
    }

    @ObservationIgnored private let repository: any ShooRepository

    init(repository: any ShooRepository, code: String? = nil) {
        self.repository = repository
        if let code { prefill(code) }
    }

    var canJoin: Bool { state == .entering && DeepLink.isCode(code) }

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

    func join() async {
        guard canJoin else { return }
        state = .joining
        problem = nil
        do {
            // `ApiRepository` keeps `guardian.name` in the App Group for the extension (EX-06).
            let guardian = try await repository.joinFamily(code: code)
            state = .joined(guardian)
        } catch {
            state = .entering
            guard !error.isCancellation else { return }
            Log.ui.error("Join failed", error)
            problem = Problem(error)
        }
    }
}
