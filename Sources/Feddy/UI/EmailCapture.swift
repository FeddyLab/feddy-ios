#if canImport(UIKit)
import SwiftUI

/// The one path that turns a typed address into a saved contact email.
/// Three screens ask for it — the post-submit confirmation, the in-thread
/// banner, and the toolbar sheet — and each used to carry its own copy of
/// this. Returns the message to show, or nil once it saved.
enum EmailCapture {
    static func save(_ raw: String) async -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard EmailValidation.isValid(trimmed) else { return Strings.emailInvalid }
        guard let client = FeddyCore.shared.client else { return Strings.errorGeneric }
        do {
            _ = try await client.setEmail(trimmed)
            FeddyCore.shared.markEmailKnown()
            return nil
        } catch {
            return Strings.errorGeneric
        }
    }
}

/// The way back to the ask once it has been declined. Reachable from the
/// thread's toolbar for as long as we have no email, which is what makes
/// "skip" safe to honour permanently.
struct EmailAskSheet: View {
    let accent: Color
    let onSaved: () -> Void

    @Environment(\.presentationMode) private var presentationMode
    @State private var email = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                Text(Strings.emailPromptTitle)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                TextField(Strings.emailPlaceholder, text: $email)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color(.systemRed))
                }
                Button(Strings.emailSave) { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .disabled(isSaving || email.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.page)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(Strings.cancel) { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func save() {
        isSaving = true
        Task {
            let message = await EmailCapture.save(email)
            isSaving = false
            guard message == nil else {
                error = message
                return
            }
            error = nil
            onSaved()
            presentationMode.wrappedValue.dismiss()
        }
    }
}
#endif
