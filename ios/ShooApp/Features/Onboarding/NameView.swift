import SwiftUI

/// ON-02: name only (D-alief-22). 1–20 characters, Continue stays disabled until valid.
struct NameView: View {
    @Bindable var model: OnboardingModel
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingPage {
            VStack(alignment: .leading, spacing: 16) {
                Text("What's your name?")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Your family sees this name.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                TextField(text: $model.name) { Text("Your name") }
                    .font(.title2)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .focused($focused)
                    .onSubmit { model.submitName() }
                    .padding(16)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityIdentifier("name.field")
                if let message = problemMessage {
                    Label { Text(message) } icon: { Image(systemName: "exclamationmark.circle.fill") }
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("name.error")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            OnboardingPrimaryButton(title: "Continue") { model.submitName() }
                .disabled(!model.canSubmitName)
                .accessibilityIdentifier("name.continue")
        }
        .onAppear { focused = true }
    }

    /// Nothing typed yet is not an error; spaces only or too long is.
    private var problemMessage: LocalizedStringKey? {
        guard !model.name.isEmpty, let problem = model.nameProblem else { return nil }
        switch problem {
        case .empty: return "Enter your name."
        case .tooLong: return "Use 20 characters or fewer."
        }
    }
}
