#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import PhotosUI
import UIKit
#endif

/// A SwiftUI sheet for collecting feedback. Drop into your view hierarchy
/// with `.sheet(isPresented:)`:
///
/// ```swift
/// // Default: shows the workspace's two system boards (Feature, Bug)
/// .sheet(isPresented: $showFeedback) {
///     RequestComposeView()
/// }
///
/// // Custom: pass your dashboard boards explicitly
/// .sheet(isPresented: $showFeedback) {
///     RequestComposeView(boards: [
///         .featureRequest,
///         .bugReport,
///         .init(key: "discussions",
///               name: "Discussions"),
///     ])
/// }
/// ```
///
/// On Submit, the form calls ``Feddy/submitRequest(title:description:boardKey:)``
/// — fire-and-forget — and dismisses. Failures are handled by the SDK's
/// offline retry queue; the user does not see a network spinner blocking
/// the dismiss.
///
/// Localized in English / Spanish / Japanese / German / French via the
/// SDK's bundled string catalog. Custom board display names are the
/// caller's responsibility — the SDK does not know about them.
@available(iOS 15.0, macOS 12.0, *)
public struct RequestComposeView: View {
    @Environment(\.dismiss) private var dismiss

    private let boards: [FeedbackBoard]

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var selectedBoardKey: String
    @State private var isSubmitting: Bool = false
    @FocusState private var titleFieldFocused: Bool

    #if canImport(UIKit)
    @State private var pickerItems: [Any] = []
    @State private var selectedImages: [UIImage] = []
    #endif

    public init(boards: [FeedbackBoard] = FeedbackBoard.systemDefaults) {
        precondition(
            !boards.isEmpty,
            "RequestComposeView requires at least one board"
        )
        self.boards = boards
        self._selectedBoardKey = State(initialValue: boards[0].key)
    }

    public var body: some View {
        navigationContainer {
            formContent
                .disabled(isSubmitting)
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
                    // Icon-only cancel: localized labels for "Cancel" range
                    // from 6 chars (en) to 16+ (de "Abbrechen", ja "キャンセル"
                    // measured wide). On narrow nav bars the longest variants
                    // truncate; an SF Symbol stays compact across all locales.
                    // The `accessibilityLabel` keeps the localized word for
                    // VoiceOver, so the affordance is still announced as
                    // "Cancel" (or its translation) to assistive tech.
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(
                            Localization.string("feddy.action.cancel")
                        )
                        .disabled(isSubmitting)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSubmitting {
                            ProgressView()
                                .accessibilityLabel(
                                    Localization.string("feddy.action.submit")
                                )
                        } else {
                            Button(Localization.string("feddy.action.submit")) {
                                submit()
                            }
                            .disabled(trimmedTitle.isEmpty)
                        }
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
            } header: {
                Text(Localization.string("feddy.compose.titleField.label"))
            }

            Section {
                detailsEditor
            } header: {
                Text(Localization.string("feddy.compose.descriptionField.label"))
            }

            // Hide the picker entirely when the host app passed a single
            // board — the user has nothing to choose, and an unselectable
            // picker is just visual noise.
            if boards.count > 1 {
                Section {
                    Picker(
                        Localization.string("feddy.compose.board.label"),
                        selection: $selectedBoardKey
                    ) {
                        ForEach(boards) { board in
                            Text(board.name).tag(board.key)
                        }
                    }
                }
            }

            #if canImport(UIKit)
            if Feddy.attachmentsEnabled {
                if #available(iOS 16.0, *) {
                    attachmentsSection
                }
            }
            #endif
        }
    }

    #if canImport(UIKit)
    @available(iOS 16.0, *)
    private var attachmentsSection: some View {
        Section {
            PhotosPicker(
                selection: pickerSelectionBinding,
                maxSelectionCount: 3,
                matching: .images
            ) {
                Label(
                    Localization.string("feddy.compose.attachments.add"),
                    systemImage: "photo.on.rectangle"
                )
            }

            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) {
                            index, image in
                            attachmentThumbnail(image: image, index: index)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @available(iOS 16.0, *)
    private var pickerSelectionBinding: Binding<[PhotosPickerItem]> {
        Binding(
            get: { (pickerItems as? [PhotosPickerItem]) ?? [] },
            set: { newItems in
                pickerItems = newItems
                Task { await loadImages(from: newItems) }
            }
        )
    }

    @available(iOS 16.0, *)
    private func attachmentThumbnail(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button {
                removeImage(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(2)
        }
    }

    @available(iOS 16.0, *)
    private func loadImages(from items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        await MainActor.run { selectedImages = loaded }
    }

    @available(iOS 16.0, *)
    private func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
        if var items = pickerItems as? [PhotosPickerItem],
           index < items.count {
            items.remove(at: index)
            pickerItems = items
        }
    }
    #endif

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
        guard !isSubmitting else { return }
        isSubmitting = true

        // Run the upload + create through the internal client so the
        // toolbar can show a spinner while attachments stream to R2.
        // The public `Feddy.submitRequest(...)` API stays fire-and-
        // forget; this view's flow is the SDK-internal exception that
        // "Internal async/throws variants are fine" allows.
        Task {
            #if canImport(UIKit)
            let jpegs: [Data] = selectedImages.compactMap { image in
                guard let data = ImageCompression.compressJPEG(image) else {
                    print("[Feddy] image compression failed — skipping one attachment")
                    return nil
                }
                return data
            }
            #else
            let jpegs: [Data] = []
            #endif

            if let client = try? Feddy.currentClient() {
                await client.submitRequestFireAndForget(
                    title: titleValue,
                    description: trimmedDetails,
                    boardKey: selectedBoardKey,
                    attachmentJPEGs: jpegs
                )
            }

            await MainActor.run {
                isSubmitting = false
                dismiss()
            }
        }
    }
}
#endif
