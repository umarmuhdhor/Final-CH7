import Foundation
import Observation

/// ON-02: a name is 1–20 characters after trimming spaces. Characters are graphemes, so "👨‍👩‍👧" is one.
enum NameRule {
    enum Problem: Error, Equatable {
        case empty
        case tooLong
    }

    static let maxLength = 20

    /// The trimmed name, or why it is not allowed.
    static func validate(_ raw: String) -> Result<String, Problem> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(.empty) }
        if trimmed.count > maxLength { return .failure(.tooLong) }
        return .success(trimmed)
    }
}

/// Onboarding screens in order. Protected goes through Connect (PR-01, fase 14) before ON-04.
enum OnboardingStep: Equatable {
    /// ON-01
    case splash
    /// ON-02
    case name
    /// ON-03
    case mode
    /// "Hi, [name]" with the random avatar (D-alief-22).
    case greeting
    /// Protected only: PR-01 placeholder until fase 14.
    case connect
    /// ON-04
    case turnOnExtension
    /// ON-05
    case notifications
    case done
}

/// State of the whole onboarding flow (ON-01 … ON-05). Steps only move forward; once the device is
/// registered there is no way back to the mode choice, also not after a relaunch.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep
    var name = ""
    var selectedMode: UserMode?
    private(set) var registration: DeviceRegistration?
    private(set) var registeredName = ""
    private(set) var isWorking = false
    private(set) var registrationFailed = false

    @ObservationIgnored private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        // Registered earlier but onboarding not finished (app closed in between): continue at ON-04.
        step = environment.settings.mode == nil ? .splash : .turnOnExtension
    }

    var mode: UserMode? { environment.settings.mode }

    var nameProblem: NameRule.Problem? {
        if case .failure(let problem) = NameRule.validate(name) { return problem }
        return nil
    }

    var canSubmitName: Bool { nameProblem == nil }

    /// Notifications matter for the Guardian (pushes); Protected may skip ON-05.
    var canSkipNotifications: Bool { mode == .protected }

    func skipSplash() {
        guard step == .splash else { return }
        step = .name
    }

    func submitName() {
        guard step == .name, canSubmitName else { return }
        step = .mode
    }

    func register() async {
        guard step == .mode, !isWorking, let selectedMode, case .success(let trimmed) = NameRule.validate(name) else { return }
        isWorking = true
        registrationFailed = false
        defer { isWorking = false }
        do {
            registration = try await environment.register(name: trimmed, mode: selectedMode)
            registeredName = trimmed
            step = .greeting
        } catch {
            Log.app.error("Registration failed", error)
            registrationFailed = true
        }
    }

    func continueFromGreeting() {
        guard step == .greeting else { return }
        step = mode == .protected ? .connect : .turnOnExtension
    }

    func continueFromConnect() {
        guard step == .connect else { return }
        step = .turnOnExtension
    }

    /// Called on appear and every time the app comes back to the foreground (ON-04).
    func refreshExtensionStatus() {
        guard step == .turnOnExtension, environment.extensionStatus().isActive else { return }
        step = .notifications
    }

    /// ON-05: asks once; whatever the answer, onboarding ends (a Guardian who said no gets the Home reminder).
    func requestNotifications() async {
        guard step == .notifications, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        if await environment.notifications.status() == .notDetermined {
            _ = await environment.notifications.request()
        }
        finish()
    }

    func skipNotifications() {
        guard step == .notifications, canSkipNotifications else { return }
        finish()
    }

    private func finish() {
        environment.finishOnboarding()
        step = .done
    }
}
