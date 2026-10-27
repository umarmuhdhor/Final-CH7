import SwiftUI

/// GD-04: QR + big 6-digit code with its 30-min countdown, "Copy invite link", and the people connected (x/3).
/// Opened from Profile and "Invite your family" (Family Shield).
struct FamilyCodeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var model: FamilyCodeModel
    @State private var memberToRemove: FamilyMember?
    @ScaledMetric(relativeTo: .largeTitle) private var codeSize: CGFloat = 48

    init(repository: any ShooRepository) {
        _model = State(initialValue: FamilyCodeModel(repository: repository))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        NavigationStack {
            List {
                Section { codeSection }
                membersSection
            }
            .navigationTitle(localized: "Family code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("familyCode.done")
                }
            }
            .task { await model.run() }
            .privacyCover()
            .confirmationDialog(
                Text("Remove from your family?"),
                isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
                titleVisibility: .visible,
                presenting: memberToRemove
            ) { member in
                Button(role: .destructive) { Task { await model.remove(member) } } label: { Text("Remove") }
                    .accessibilityIdentifier("familyCode.remove.confirm")
            } message: { member in
                Text("\(member.name) won't be protected by you anymore. You won't see their activity.")
            }
            .alert(
                Text("Couldn't remove"),
                isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.actionError.map { L10n.string($0, language: language) } ?? "")
            }
        }
    }

    @ViewBuilder
    private var codeSection: some View {
        switch model.codeState {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 280)
                .accessibilityLabel(Text("Getting a code"))
        case .ready(let code):
            VStack(spacing: 16) {
                Text("Ask your family member to scan this code, or enter the 6 digits in Shoo.")
                    .font(.subheadline)
                    .foregroundStyle(.readableSecondary)
                    .multilineTextAlignment(.center)
                if let url = model.inviteURL, let qr = QRCode.image(for: url.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(Text("QR code to join your family"))
                        .accessibilityIdentifier("familyCode.qr")
                }
                Text(verbatim: FamilyCodeModel.display(code.code))
                    .font(.system(size: min(codeSize, 72), weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(Text("Code \(code.code.map(String.init).joined(separator: " "))"))
                    .accessibilityIdentifier("familyCode.code")
                Text("Valid for \(model.timeLeft)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.readableSecondary)
                    .accessibilityIdentifier("familyCode.countdown")
                if model.inviteURL != nil {
                    Button {
                        if model.copyInvite(language: language) {
                            AccessibilityNotification.Announcement(L10n.string("Invite link copied", language: language)).post()
                        }
                    } label: {
                        Label { Text(model.copied ? "Copied" : "Copy invite link") } icon: {
                            Image(systemName: model.copied ? "checkmark" : "doc.on.doc")
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("familyCode.copy")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        case .unavailable:
            VStack(spacing: 12) {
                Text("Couldn't get a code").font(.headline)
                Button { Task { await model.refreshCode() } } label: {
                    Text("Try again").frame(minHeight: 44)
                }
                .accessibilityIdentifier("familyCode.retry")
            }
            .frame(maxWidth: .infinity)
        case .full:
            Text("Your family is full (3 people). Remove someone to invite another person.")
                .foregroundStyle(.readableSecondary)
                .accessibilityIdentifier("familyCode.full")
        }
    }

    private var membersSection: some View {
        Section {
            if model.members.isEmpty && !model.membersFailed {
                Text("No one connected yet").foregroundStyle(.readableSecondary)
            }
            ForEach(model.members) { member in
                HStack(spacing: 12) {
                    AvatarView(id: member.avatarId, size: 40).accessibilityHidden(true)
                    Text(verbatim: member.name)
                    Spacer(minLength: 8)
                    if model.removingId == member.deviceId {
                        ProgressView()
                    } else {
                        Button(role: .destructive) { memberToRemove = member } label: {
                            Text("Remove").frame(minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove \(member.name)"))
                        .accessibilityIdentifier("familyCode.remove.\(member.deviceId)")
                    }
                }
            }
            if model.membersFailed {
                Button { Task { await model.loadMembers() } } label: {
                    Text("Couldn't load your family. Try again").frame(minHeight: 44)
                }
            }
        } header: {
            Text(verbatim: L10n.string("Connected \(model.members.count)/\(FamilyShieldModel.maxMembers)", language: language))
                .accessibilityLabel(Text(verbatim: L10n.string(
                    "Connected, \(model.members.count) of \(FamilyShieldModel.maxMembers) people", language: language
                )))
                .accessibilityIdentifier("familyCode.members")
        }
    }
}

#Preview {
    FamilyCodeView(repository: MockRepository(latency: .zero))
}
