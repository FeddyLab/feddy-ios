#if canImport(UIKit)
import SwiftUI

/// Compose form (body + optional category), followed by the post-submit
/// optional email ask. Email is never a required field before submitting.
struct NewConversationView: View {
    let onOpenConversation: (String) -> Void

    @StateObject private var model = ComposeModel()
    @FocusState private var editorFocused: Bool
    @Environment(\.presentationMode) private var presentationMode

    private var accent: Color { Theme.accent(FeddyCore.shared.config) }
    private var categories: [FeddyConfig.Category] { FeddyCore.shared.config?.categories ?? [] }

    var body: some View {
        NavigationView {
            Group {
                if let conversationId = model.createdConversationId {
                    if FeddyCore.shared.emailKnown {
                        Color.clear.onAppear { onOpenConversation(conversationId) }
                    } else {
                        SubmittedView(accent: accent) {
                            onOpenConversation(conversationId)
                        }
                    }
                } else {
                    composeForm
                }
            }
            .navigationTitle(Strings.newMessage)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    // A form sheet cancels; only the root panel closes.
                    Button(Strings.cancel) { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(Strings.done) { editorFocused = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var composeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !categories.isEmpty {
                categoryField
            }
            editor
            if let error = model.submitError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            Color(.systemGroupedBackground)
                .onTapGesture { editorFocused = false }
        )
        .safeAreaInset(edge: .bottom, spacing: 0) { sendBar }
    }

    /// One tap, always one line: a dropdown that wrapped onto two lines
    /// read as a form field nobody wanted to fill in.
    private var categoryField: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.code) { category in
                    let isSelected = model.categoryCode == category.code
                    Button {
                        editorFocused = false
                        model.categoryCode = isSelected ? nil : category.code
                    } label: {
                        Text(category.label)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? accent : Color(.secondarySystemGroupedBackground)
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.text)
                .focused($editorFocused)
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(maxHeight: .infinity)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if model.text.isEmpty {
                Text(Strings.composePlaceholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
    }

    private var sendBar: some View {
        Button {
            Task { await model.submit() }
        } label: {
            if model.isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text(Strings.send)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(accent)
        .disabled(
            model.isSubmitting
                || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
        .padding(16)
        .background(.bar)
    }
}

/// Post-submit confirmation with the optional email ask (spec flow:
/// confirm first, then offer email notifications, always skippable).
private struct SubmittedView: View {
    let accent: Color
    let onContinue: () -> Void

    @State private var email = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(accent)
            Text(FeddyCore.shared.config?.replySlaText ?? Strings.submittedFallback)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(Strings.emailPromptTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(Strings.emailPlaceholder, text: $email)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button(Strings.emailSave) { save() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(isSaving || email.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(Strings.emailSkip, action: onContinue)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func save() {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard EmailValidation.isValid(trimmed) else {
            error = Strings.emailInvalid
            return
        }
        error = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            guard let client = FeddyCore.shared.client else { return }
            do {
                _ = try await client.setEmail(trimmed)
                FeddyCore.shared.markEmailKnown()
                onContinue()
            } catch {
                self.error = Strings.errorGeneric
            }
        }
    }
}
#endif
