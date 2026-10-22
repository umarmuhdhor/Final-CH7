import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

/// GD-04: the guardian's family code. A new code every 60 s while the screen is open (R4 §1),
/// the people connected (x/3), and removing one.
@MainActor
@Observable
final class FamilyCodeModel {
    enum CodeState: Equatable {
        case loading
        case ready(FamilyCode)
        /// `503 code_unavailable` or no connection: "Try again".
        case unavailable
        /// 3 people connected: no code is asked for.
        case full
    }

    /// Longest a code lives (contracts/api.md). A device clock far from the server's never makes
    /// the countdown longer than this or stuck at zero.
    static let codeLifetime: TimeInterval = 60
    /// Members are re-read this often, so someone joining shows up while the code is on screen.
    static let membersInterval = 5

    private(set) var codeState: CodeState = .loading
    private(set) var secondsLeft = 0
    private(set) var members: [FamilyMember] = []
    private(set) var membersFailed = false
    private(set) var removingId: String?
    /// "Copied" on the button, for the code on screen only.
    private(set) var copied = false
    /// Remove failed; shown as an alert.
    var actionError: String.LocalizationValue?

    @ObservationIgnored private let repository: any ShooRepository
    @ObservationIgnored private let now: () -> Date
    /// Local end of the current code (see `codeLifetime`).
    @ObservationIgnored private var expiry: Date?
    @ObservationIgnored private var ticks = 0
    /// Bumped by `remove`: a members answer asked for before it is out of date.
    @ObservationIgnored private var membersVersion = 0
    @ObservationIgnored private var isLoadingMembers = false

    init(repository: any ShooRepository, now: @escaping () -> Date = Date.init) {
        self.repository = repository
        self.now = now
    }

    var isFull: Bool { members.count >= FamilyShieldModel.maxMembers }

    var code: FamilyCode? {
        if case .ready(let code) = codeState { return code }
        return nil
    }

    /// The code's invite link, only when it is one of ours for this very code: the QR and the
    /// copied text never send anyone elsewhere, whatever the server answers.
    var inviteURL: URL? { code.flatMap(Self.checkedInviteURL) }

    static func checkedInviteURL(for code: FamilyCode) -> URL? {
        DeepLink(url: code.inviteUrl) == .join(code: code.code) ? code.inviteUrl : nil
    }

    /// Runs while the screen is open (`.task`): first code, then the countdown and new codes.
    func run(sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async {
        // Members first: a full family asks for no code (D-alief-C09).
        await loadMembers()
        await refreshCode()
        var membersRefresh: Task<Void, Never>?
        defer { membersRefresh?.cancel() }
        while !Task.isCancelled {
            do { try await sleep(.seconds(1)) } catch { return }
            ticks += 1
            // Beside the countdown, so a slow answer never freezes it.
            if ticks % Self.membersInterval == 0, !isLoadingMembers {
                membersRefresh = Task { await self.loadMembers() }
            }
            if tick() { await refreshCode() }
        }
    }

    func loadMembers() async {
        isLoadingMembers = true
        defer { isLoadingMembers = false }
        let version = membersVersion
        do {
            let fresh = try await repository.familyMembers()
            guard version == membersVersion else { return }
            members = fresh
            membersFailed = false
            if isFull {
                codeState = .full
            } else if codeState == .full {
                await refreshCode()
            }
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Family members failed", error)
            membersFailed = true
        }
    }

    /// Asks for a new code (the old one stops working on the server).
    func refreshCode() async {
        guard !isFull else {
            codeState = .full
            return
        }
        if code == nil { codeState = .loading }
        do {
            let fresh = try await repository.createFamilyCode()
            // Screen closed meanwhile: the code is never shown.
            guard !Task.isCancelled else { return }
            let start = now()
            let validFor = fresh.expiresAt.timeIntervalSince(start)
            expiry = start.addingTimeInterval((1...Self.codeLifetime).contains(validFor) ? validFor : Self.codeLifetime)
            // Members may have filled up while this was asked for.
            guard !isFull else {
                codeState = .full
                return
            }
            if fresh.code != code?.code { copied = false }
            codeState = .ready(fresh)
            _ = tick()
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Family code failed", error)
            expiry = nil
            codeState = isFull ? .full : .unavailable
            secondsLeft = 0
        }
    }

    /// Updates the countdown; `true` when the code just ran out.
    @discardableResult
    func tick() -> Bool {
        guard case .ready = codeState, let expiry else { return false }
        let left = expiry.timeIntervalSince(now())
        // A clock set back never shows more than the code's lifetime.
        secondsLeft = min(Int(Self.codeLifetime), max(0, Int(left.rounded(.up))))
        return secondsLeft == 0
    }

    func remove(_ member: FamilyMember) async {
        guard removingId == nil else { return }
        removingId = member.deviceId
        defer { removingId = nil }
        do {
            try await repository.removeMember(deviceId: member.deviceId)
        } catch RepositoryError.api(.notFound, _) {
            // Already gone (they left, or an earlier answer got lost).
        } catch {
            guard !error.isCancellation else { return }
            Log.ui.error("Remove member failed", error)
            actionError = "Couldn't remove. Check your connection and try again."
            return
        }
        membersVersion += 1
        members.removeAll { $0.deviceId == member.deviceId }
        if codeState == .full { await refreshCode() }
    }

    /// "Copy invite link": the text people paste into WhatsApp.
    func copyInvite(language: AppLanguage, to pasteboard: any PasteboardWriting = UIPasteboard.general) -> Bool {
        guard let code, inviteURL != nil else { return false }
        Self.copy(Self.inviteText(for: code, language: language), until: code.expiresAt, to: pasteboard, now: now())
        copied = true
        return true
    }

    static func inviteText(for code: FamilyCode, language: AppLanguage) -> String {
        L10n.string("Join my family on Shoo so I can help keep you safe from scam sites. Open \(code.inviteUrl.absoluteString) or enter code \(code.code) in Shoo.", language: language)
    }

    /// This device only, gone when the code expires (SECURITY §3 P8).
    static func copy(_ text: String, until expiry: Date, to pasteboard: any PasteboardWriting, now: Date) {
        let lifetime = min(max(expiry.timeIntervalSince(now), 1), codeLifetime)
        pasteboard.setItems(
            [[UTType.plainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: now.addingTimeInterval(lifetime)]
        )
    }
}
