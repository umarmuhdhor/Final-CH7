import SwiftUI

/// Profile (PF-01), opened from the top-right button in every mode.
struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var model: ProfileModel
    @State private var extensionStatus = ExtensionStatus.off(lastSeen: nil)
    @State private var isTurnOnPresented = false
    @State private var isDisconnectConfirming = false
    @State private var isDeleteConfirming = false
    @State private var isFamilyCodePresented = false
    @FocusState private var isNameFocused: Bool

    init(repository: any ShooRepository, settings: AppSettings) {
        _model = State(initialValue: ProfileModel(repository: repository, settings: settings))
    }

    private var language: AppLanguage { AppLanguage(locale: locale) }

    var body: some View {
        NavigationStack {
            Form {
                switch model.state {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Loading"))
                case .failed:
                    Section {
                        Text("Couldn't load your profile").font(.headline)
                        Button { Task { await model.retry() } } label: { Text("Try again") }
                    }
                case .loaded:
                    nameSection
                    languageSection
                    extensionSection
                    if model.showsDisconnect { guardianSection }
                    if model.showsFamilyCode { familySection }
                    if model.canDeleteData { dataSection }
                }
            }
            .navigationTitle(localized: "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                        .accessibilityIdentifier("profile.done")
                }
            }
            .task {
                // Disconnect / delete hand the app back to onboarding: clear navigation first.
                model.onSessionEnd = { [router = env.router] in router.reset() }
                await model.load()
            }
            .task(id: scenePhase) {
                if scenePhase == .active { extensionStatus = env.extensionStatus() }
            }
            .sheet(isPresented: $isTurnOnPresented, onDismiss: { extensionStatus = env.extensionStatus() }) {
                TurnOnExtensionSheet()
            }
            .alert(Text("Family code"), isPresented: $isFamilyCodePresented) {
                Button("OK", role: .cancel) {}
            } message: {
                // TODO(sync:alief): open Family code (GD-04) — replace after fase 14
                Text("Family codes are coming soon.")
            }
            .onChange(of: model.nameError) { _, message in
                guard let message else { return }
                AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
            }
            .alert(
                Text(verbatim: model.actionError.map { L10n.string($0, language: language) } ?? ""),
                isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        }
        // Names and the family list stay out of the app switcher snapshot (D-alief-A36).
        .privacyCover()
    }

    // MARK: Sections

    private var nameSection: some View {
        Section {
            HStack(spacing: 16) {
                AvatarView(id: model.profile?.avatarId ?? "", size: 56)
                    .accessibilityHidden(true)
                TextField(text: $model.nameDraft) { Text("Your name") }
                    .font(.title3.weight(.semibold))
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { Task { await saveName() } }
                    .accessibilityLabel(Text("Your name"))
                    .accessibilityIdentifier("profile.name")
            }
            if model.nameDraft != model.profile?.name {
                Button { Task { await saveName() } } label: {
                    Text("Save name").frame(minHeight: 44)
                }
                .disabled(model.nameProblem != nil || model.isWorking)
                .accessibilityIdentifier("profile.saveName")
            }
        } header: {
            Text("Name")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                switch model.nameProblem {
                case .empty: Text("Enter a name.")
                case .tooLong: Text("Use 20 characters or fewer.")
                case nil: Text("1–20 characters. Your family sees this name.")
                }
                if let message = model.nameError {
                    Text(verbatim: L10n.string(message, language: language))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("profile.error")
                }
            }
            .foregroundStyle(.readableSecondary)
        }
    }

    private var languageSection: some View {
        Section {
            Picker(selection: Binding(
                get: { env.settings.language },
                set: { model.chooseLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(Self.spokenName(language)).tag(language)
                }
            } label: {
                Text("Language")
            }
            // Both choices always visible: no menu to find, no truncated name at large text sizes.
            .pickerStyle(.inline)
            .accessibilityIdentifier("languagePicker")
        } header: {
            Text("Language")
        } footer: {
            Text("Shoo and its alerts use this language.")
                .foregroundStyle(.readableSecondary)
        }
    }

    private var extensionSection: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack { extensionTitle; Spacer(); extensionValue }
                VStack(alignment: .leading, spacing: 6) { extensionTitle; extensionValue }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(extensionStatus.isActive ? "profile.extension.active" : "profile.extension.off")
            if !extensionStatus.isActive {
                Button { isTurnOnPresented = true } label: { Text("Turn on").frame(minHeight: 44) }
                    .accessibilityHint(Text("Shows how to switch Shoo on in Safari"))
                    .accessibilityIdentifier("profile.turnOn")
            }
        }
    }

    private var extensionTitle: some View {
        Text("Safari extension")
    }

    private var extensionValue: some View {
        Label {
            Text(extensionStatus.isActive ? "Active" : "Off")
        } icon: {
            Image(systemName: extensionStatus.isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(extensionStatus.isActive ? Color.green : Color.red)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.primary)
    }

    private var guardianSection: some View {
        Section {
            if let guardian = model.profile?.guardian {
                HStack(spacing: 12) {
                    AvatarView(id: guardian.avatarId, size: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protected by").font(.subheadline).foregroundStyle(.readableSecondary)
                        Text(verbatim: guardian.name).font(.headline)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("profile.guardian")
                Button(role: .destructive) { isDisconnectConfirming = true } label: {
                    Text("Disconnect").frame(minHeight: 44)
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("profile.disconnect")
                .confirmationDialog(
                    Text("Disconnect from \(guardian.name)?"),
                    isPresented: $isDisconnectConfirming,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) { Task { await disconnect() } } label: { Text("Disconnect") }
                        .accessibilityIdentifier("profile.disconnect.confirm")
                } message: {
                    Text("\(guardian.name) will no longer see the sites Shoo warns you about.")
                }
            } else {
                Text("Not connected to a guardian yet")
                    .accessibilityIdentifier("profile.guardian.none")
            }
        } header: {
            Text("Guardian")
        }
    }

    private var familySection: some View {
        Section {
            ForEach(model.members) { member in
                HStack(spacing: 12) {
                    AvatarView(id: member.avatarId, size: 40)
                        .accessibilityHidden(true)
                    Text(verbatim: member.name).font(.body)
                    Spacer()
                    if !member.isConnected {
                        Text("Not connected").font(.subheadline).foregroundStyle(.readableSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if model.membersFailed {
                Button { Task { await model.load() } } label: {
                    Text("Couldn't load your family. Try again").frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile.members.retry")
            }
            Button { isFamilyCodePresented = true } label: {
                Label { Text("Family code") } icon: { Image(systemName: "qrcode") }
                    .frame(minHeight: 44)
            }
            .disabled(model.members.count >= FamilyShieldModel.maxMembers)
            .accessibilityIdentifier("profile.familyCode")
        } header: {
            Text(verbatim: L10n.string("Family \(model.members.count)/\(FamilyShieldModel.maxMembers)", language: language))
                .accessibilityIdentifier("profile.members")
        } footer: {
            if model.members.count >= FamilyShieldModel.maxMembers {
                Text("Your family is full (3 people).").foregroundStyle(.readableSecondary)
            }
        }
    }

    private var dataSection: some View {
        Section {
            Button(role: .destructive) { isDeleteConfirming = true } label: {
                Text("Delete my data").frame(minHeight: 44)
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("profile.delete")
            .confirmationDialog(Text("Delete your data?"), isPresented: $isDeleteConfirming, titleVisibility: .visible) {
                Button(role: .destructive) { Task { await deleteMyData() } } label: { Text("Delete") }
            } message: {
                Text("Your name, family link and history are deleted right away. This can't be undone.")
            }
        }
    }

    // MARK: Actions

    private func saveName() async {
        if await model.saveName() { isNameFocused = false }
    }

    private func disconnect() async {
        _ = await model.disconnect()
    }

    private func deleteMyData() async {
        _ = await model.deleteMyData()
    }

    /// The language's own name, read by VoiceOver in that language.
    private static func spokenName(_ language: AppLanguage) -> AttributedString {
        var name = AttributedString(language.nativeName)
        name.languageIdentifier = language.code
        return name
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return ProfileView(repository: env.repository, settings: env.settings).environment(env)
}
