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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var avatarSize: CGFloat = 56

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
                    dataSection
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
                model.onSessionEnd = { [router = env.router] in
                    router.reset()
                    DeliveredPushes.clear()
                }
                await model.load()
            }
            .task(id: scenePhase) {
                if scenePhase == .active { extensionStatus = env.extensionStatus() }
            }
            .sheet(isPresented: $isTurnOnPresented, onDismiss: { extensionStatus = env.extensionStatus() }) {
                TurnOnExtensionSheet()
            }
            .sheet(isPresented: $isFamilyCodePresented, onDismiss: { Task { await model.load() } }) {
                FamilyCodeView(repository: env.repository)
                    .environment(\.locale, locale)
            }
            .onChange(of: model.nameError) { _, message in
                guard let message else { return }
                announce(message)
            }
            .onChange(of: model.nameProblem) { _, problem in
                switch problem {
                case .empty: announce("Enter a name.")
                case .tooLong: announce("Use 20 characters or fewer.")
                case nil: break
                }
            }
            .onChange(of: model.membersFailed) { _, failed in
                if failed { announce("Couldn't load your family") }
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
            // Avatar above the field at accessibility sizes, so a 20-character name still fits.
            stackedAtLargeSizes(spacing: 16) {
                AvatarView(id: model.profile?.avatarId ?? "", size: min(avatarSize, 96))
                    .accessibilityHidden(true)
                // Same word as the section header, so Voice Control "Tap Name" works (WCAG 2.5.3).
                TextField(text: $model.nameDraft, axis: .vertical) { Text("Name") }
                    .lineLimit(1...3)
                    .font(.title3.weight(.semibold))
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { Task { await saveName() } }
                    .accessibilityHint(Text("1 to 20 characters"))
                    .accessibilityIdentifier("profile.name")
            }
            // Always present (only disabled), so VoiceOver focus never lands on a vanished button.
            Button { Task { await saveName() } } label: {
                Text("Save name").frame(minHeight: 44)
            }
            .disabled(model.nameDraft == model.profile?.name || model.nameProblem != nil || model.isWorking)
            .accessibilityIdentifier("profile.saveName")
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
                    Label {
                        Text(verbatim: L10n.string(message, language: language))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.readableRed)
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
            .labelsHidden()
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
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(extensionStatus.isActive ? "profile.extension.active" : "profile.extension.off")
            if !extensionStatus.isActive {
                Button { isTurnOnPresented = true } label: { Text("Turn on").frame(minHeight: 44) }
                    .accessibilityLabel(Text("Turn on Shoo in Safari"))
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
                    Text("Disconnect").frame(minHeight: 44).foregroundStyle(Color.readableRed)
                }
                .disabled(model.isWorking)
                .accessibilityIdentifier("profile.disconnect")
                .confirmationDialog(
                    Text("Disconnect from \(guardian.name)?"),
                    isPresented: $isDisconnectConfirming,
                    titleVisibility: .visible
                ) {
                    Button(role: .destructive) { Task { await disconnect() } } label: { Text("Disconnect from \(guardian.name)") }
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
                    stackedAtLargeSizes(spacing: 2) {
                        Text(verbatim: member.name).font(.body)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        if !member.isConnected {
                            Text("Not connected").font(.subheadline).foregroundStyle(.readableSecondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if model.membersFailed {
                Text("Couldn't load your family")
                Button { Task { await model.load() } } label: {
                    Text("Try again").frame(minHeight: 44)
                }
                .accessibilityIdentifier("profile.members.retry")
            }
            Button { isFamilyCodePresented = true } label: {
                Label { Text("Family code") } icon: { Image(systemName: "qrcode") }
                    .frame(minHeight: 44)
            }
            .disabled(model.membersFailed || model.members.count >= FamilyShieldModel.maxMembers)
            .accessibilityHint(model.members.count >= FamilyShieldModel.maxMembers ? Text("Your family is full (3 people).") : Text(verbatim: ""))
            .accessibilityIdentifier("profile.familyCode")
        } header: {
            Group {
                if model.membersFailed {
                    Text("Family")
                } else {
                    Text(verbatim: L10n.string("Family \(model.members.count)/\(FamilyShieldModel.maxMembers)", language: language))
                        .accessibilityLabel(Text(verbatim: L10n.string(
                            "Family, \(model.members.count) of \(FamilyShieldModel.maxMembers) people", language: language
                        )))
                }
            }
            .accessibilityAddTraits(.isHeader)
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
                Text("Delete my data").frame(minHeight: 44).foregroundStyle(Color.readableRed)
            }
            .disabled(model.isWorking)
            .accessibilityIdentifier("profile.delete")
            .confirmationDialog(Text("Delete your data?"), isPresented: $isDeleteConfirming, titleVisibility: .visible) {
                Button(role: .destructive) { Task { await deleteMyData() } } label: { Text("Delete my data") }
                    .accessibilityIdentifier("profile.delete.confirm")
            } message: {
                Text("Your name, family link and history are deleted right away. This can't be undone.")
            }
        }
    }

    // MARK: Actions

    private func saveName() async {
        if await model.saveName() {
            isNameFocused = false
            announce("Name saved")
        }
    }

    private func announce(_ message: String.LocalizationValue) {
        AccessibilityNotification.Announcement(L10n.string(message, language: language)).post()
    }

    /// Side by side normally, stacked at accessibility text sizes.
    private func stackedAtLargeSizes<Content: View>(spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout(content)
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
