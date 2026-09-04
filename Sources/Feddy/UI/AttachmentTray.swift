#if canImport(UIKit)
import PhotosUI
import SwiftUI
import UIKit

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

/// The image area: what has been picked, plus the tile that picks more.
///
/// Deliberately an area rather than a paperclip tucked in beside Send. A
/// paperclip is the icon for "file", and this only ever takes pictures; more
/// to the point, an icon crowded in with the buttons is not where anyone
/// looks for it — on the compose screen it was in the keyboard toolbar,
/// which meant it did not exist until the keyboard was already up.
@available(iOS 15.0, macOS 12.0, *)
struct AttachmentArea: View {
    @ObservedObject var model: AttachmentTrayModel
    var disabled: Bool

    private let side: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.items) { item in
                        thumbnail(item)
                    }
                    if !model.isFull {
                        addTile
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(height: side + 2)
            if let error = model.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var addTile: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            AttachmentPicker(model: model, disabled: disabled) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color(.separator),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
                    .frame(width: side, height: side)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(.secondaryLabel))
                    }
            }
            .accessibilityLabel(Strings.attach)
        }
    }

    private func thumbnail(_ item: AttachmentTrayModel.Item) -> some View {
        item.image
            .resizable()
            .scaledToFill()
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    model.remove(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .padding(2)
                .disabled(disabled)
            }
    }
}

/// Wraps `PhotosPicker` so the caller decides what the control looks like —
/// the compose screen wants a tile, and nothing else should have to know
/// that the picker is what sits underneath.
@available(iOS 16.0, macOS 13.0, *)
struct AttachmentPicker<Label: View>: View {
    @ObservedObject var model: AttachmentTrayModel
    var disabled: Bool
    @ViewBuilder var label: () -> Label
    @State private var selection: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(
            selection: $selection,
            maxSelectionCount: AttachmentLimits.maxPerMessage,
            matching: .images
        ) {
            label()
        }
        .buttonStyle(.plain)
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
