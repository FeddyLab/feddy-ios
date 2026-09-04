#if canImport(SwiftUI)
import PhotosUI
import SwiftUI

/// Images picked but not yet sent, shared by the compose screen and the
/// reply composer.
///
/// The bytes are held rather than uploaded on pick: someone who changes
/// their mind should not have already spent their data, and the upload has
/// to finish before the message is written anyway — a message pointing at an
/// object still in flight renders as a broken image.
@available(iOS 15.0, macOS 12.0, *)
@MainActor
final class AttachmentTrayModel: ObservableObject {
    struct Item: Identifiable {
        let id = UUID()
        let data: Data
        let filename: String
        let image: Image
    }

    @Published private(set) var items: [Item] = []
    @Published var error: String?

    var isFull: Bool { items.count >= AttachmentLimits.maxPerMessage }

    func add(_ data: Data, filename: String) {
        guard !isFull else {
            error = Strings.attachCountError
            return
        }
        guard data.count <= AttachmentLimits.maxBytes else {
            error = Strings.attachSizeError
            return
        }
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else {
            error = Strings.attachTypeError
            return
        }
        let preview = Image(uiImage: uiImage)
        #else
        let preview = Image(systemName: "photo")
        #endif
        error = nil
        items.append(Item(data: data, filename: filename, image: preview))
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func clear() {
        items = []
        error = nil
    }

    /// Uploads in order and returns the descriptors the message write needs.
    /// Throws on the first failure: a half-attached message is worse than a
    /// send that can be retried with everything still in the tray.
    func upload(using client: APIClient) async throws -> [UploadedAttachment] {
        var out: [UploadedAttachment] = []
        for item in items {
            out.append(try await AttachmentUpload.send(item.data, filename: item.filename, api: client))
        }
        return out
    }
}

/// The picker button and the strip of thumbnails under whichever field it
/// belongs to. `PhotosPicker` is iOS 16+; on 15 the button is simply absent
/// rather than the package dropping its deployment target.
@available(iOS 15.0, macOS 12.0, *)
struct AttachmentTray: View {
    @ObservedObject var model: AttachmentTrayModel
    var disabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !model.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.items) { item in
                            thumbnail(item)
                        }
                    }
                }
                .frame(height: 56)
            }
            if let error = model.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func thumbnail(_ item: AttachmentTrayModel.Item) -> some View {
        item.image
            .resizable()
            .scaledToFill()
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    model.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(2)
                .disabled(disabled)
            }
    }
}

/// The button that opens the photo library. Kept apart from the strip so
/// each writing surface can put it where its own toolbar wants it.
@available(iOS 16.0, macOS 13.0, *)
struct AttachmentPickerButton: View {
    @ObservedObject var model: AttachmentTrayModel
    var disabled: Bool
    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: AttachmentLimits.maxPerMessage,
            matching: .images
        ) {
            Image(systemName: "paperclip")
                .font(.system(size: 17))
        }
        .disabled(disabled || model.isFull)
        .onChange(of: selection) { picked in
            guard !picked.isEmpty else { return }
            selection = []
            Task {
                for item in picked {
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        model.error = Strings.attachTypeError
                        continue
                    }
                    model.add(data, filename: item.itemIdentifier ?? "image.jpg")
                }
            }
        }
    }
}
#endif
