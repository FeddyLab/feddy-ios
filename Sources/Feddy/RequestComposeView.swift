#if canImport(SwiftUI)
import SwiftUI

/// A SwiftUI sheet for collecting feedback / feature requests / bug
/// reports. Drop into your view hierarchy with `.sheet(isPresented:)`:
///
/// ```swift
/// .sheet(isPresented: $showFeedback) {
///     RequestComposeView()
/// }
/// ```
///
/// On Submit, the form calls ``Feddy/submitRequest(title:description:type:)``
/// — fire-and-forget — and dismisses. Failures are handled by the SDK's
/// offline retry queue; the user does not see a network spinner blocking
/// the dismiss.
///
/// Localized in English / Spanish / Japanese / German / French via the
/// SDK's bundled string catalog.
@available(iOS 15.0, macOS 12.0, *)
public struct RequestComposeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var selectedType: String = Feddy.RequestType.feature
    @FocusState private var titleFieldFocused: Bool

    public init() {}

    public var body: some View {
        navigationContainer {
            formContent
                .navigationTitle(Localization.string("feddy.compose.title"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .task {
                    // Run focus assignment after the sheet's present
                    // animation has had a tick to settle. Doing this in
                    // `onAppear` races the transition on iOS 15-17 and
                    // the field silently fails to receive focus.
                    titleFieldFocused = true
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Localization.string("feddy.action.cancel")) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Localization.string("feddy.action.submit")) {
                            submit()
                        }
                        .disabled(trimmedTitle.isEmpty)
                    }
                }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    /// Use NavigationStack on iOS 16+/macOS 13+; fall back to NavigationView
    /// for the iOS 15 / macOS 12 floor declared by Package.swift. Both wrap
    /// the form so `.toolbar` items render in a real navigation chrome —
    /// without this, the macOS sheet would have no visible Submit / Cancel
    /// affordance.
    @ViewBuilder
    private func navigationContainer<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            NavigationStack { content() }
        } else {
            NavigationView { content() }
        }
    }

    private var formContent: some View {
        Form {
            Section {
                TextField(
                    Localization.string("feddy.compose.titleField.placeholder"),
                    text: $title
                )
                .focused($titleFieldFocused)
                .submitLabel(.next)
            }

            Section {
                detailsEditor
            }

            Section {
                Picker(
                    Localization.string("feddy.compose.type.label"),
                    selection: $selectedType
                ) {
                    Text(Localization.string("feddy.compose.type.feature"))
                        .tag(Feddy.RequestType.feature)
                    Text(Localization.string("feddy.compose.type.bug"))
                        .tag(Feddy.RequestType.bug)
                    Text(Localization.string("feddy.compose.type.other"))
                        .tag(Feddy.RequestType.other)
                }
            }
        }
    }

    /// TextEditor on the iOS 15 / macOS 12 floor has no built-in placeholder
    /// support and no `.scrollContentBackground(.hidden)` (iOS 16+). The
    /// editor's opaque scroll background sits on top of any view drawn
    /// behind it in a `ZStack`, so the placeholder Text must be drawn
    /// **after** the editor and have hit-testing disabled so taps pass
    /// through to the editor underneath.
    private var detailsEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $details)
                .frame(minHeight: 120)
            if details.isEmpty {
                Text(Localization.string("feddy.compose.descriptionField.placeholder"))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDetails: String? {
        let value = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func submit() {
        let titleValue = trimmedTitle
        guard !titleValue.isEmpty else { return }
        Feddy.submitRequest(
            title: titleValue,
            description: trimmedDetails,
            type: selectedType
        )
        dismiss()
    }
}
#endif
