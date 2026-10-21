import SwiftUI

/// Stand-in for Profile (PF-01, fase 06). Already switches the in-app language.
struct ProfilePlaceholderView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            Form {
                Picker(selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(verbatim: language.nativeName).tag(language)
                    }
                } label: {
                    Text("Language")
                }
                .accessibilityIdentifier("languagePicker")
            }
            .navigationTitle(localized: "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done") }
                }
            }
        }
    }
}
