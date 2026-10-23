#if canImport(UIKit)
import SwiftUI
import UIKit

/// Puts a reply the user has not seen in front of them when they come
/// back to the app. Most unread replies were never missed for lack of a
/// return visit: the user came back and never opened the panel. The badge
/// depends on where the host app puts its entry point; this does not.
///
/// Not a notification: no permission, nothing in Notification Center, and
/// the host's notification delegate is never touched. A card the SDK draws
/// over the host's own screen, once per reply.
@MainActor
final class ReplyPopupCoordinator {
    static let shared = ReplyPopupCoordinator()

    private static let shownKey = "feddy.reply_popup_shown"
    /// Long enough for the host's launch screen or paywall to settle, and
    /// it collapses the several triggers of one launch into one check.
    private static let settleDelay: UInt64 = 2_000_000_000
    private static let visibleFor: UInt64 = 8_000_000_000
    private static let exitDuration: UInt64 = 350_000_000

    var enabled = true {
        didSet {
            if !enabled {
                hide()
            } else if !oldValue {
                scheduleCheck()
            }
        }
    }

    private var started = false
    private var checkTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var window: ReplyPopupWindow?
    private var state: ReplyPopupState?
    private var interacting = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleCheck() }
        }
        scheduleCheck()
    }

    /// Every trigger lands here: launch, back to the foreground, the
    /// unread count going up. Waiting folds them into one check.
    func scheduleCheck() {
        guard started else { return }
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.settleDelay)
            guard !Task.isCancelled else { return }
            await self?.check()
        }
    }

    func hide() {
        dismissTask?.cancel()
        interacting = false
        guard let window, let state else { return }
        state.visible = false
        self.window = nil
        self.state = nil
        Task {
            try? await Task.sleep(nanoseconds: Self.exitDuration)
            window.isHidden = true
        }
    }

    // MARK: - Check

    private var canShow: Bool {
        enabled && window == nil
            && UIApplication.shared.applicationState == .active
            && !Presenter.isFeddyOnScreen
    }

    private func check() async {
        guard canShow, let client = FeddyCore.shared.client else { return }
        // The count is the cheap question; the list is fetched only when
        // there is something unread to look at.
        guard let unread = try? await client.unreadCount(), unread.unreadCount > 0,
              let list = try? await client.conversations().conversations
        else { return }
        await FeddyCore.shared.loadConfig()
        guard !Task.isCancelled, canShow else { return }
        let shown = loadShown()
        let pick = ReplyPopupPicker.pick(from: list, shown: shown)
        saveShown(ReplyPopupPicker.record(pick, into: shown, listed: list))
        if let pick { show(pick) }
    }

    private func loadShown() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: Self.shownKey) as? [String: Int] ?? [:]
    }

    private func saveShown(_ shown: [String: Int]) {
        UserDefaults.standard.set(shown, forKey: Self.shownKey)
    }

    // MARK: - Presentation

    private func show(_ pick: ReplyPopupPick) {
        guard let scene = Presenter.activeScene else { return }
        let state = ReplyPopupState()
        let window = ReplyPopupWindow(windowScene: scene)
        // Above the host's screens, below the keyboard and system alerts.
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        window.backgroundColor = .clear
        let view = ReplyPopupView(
            pick: pick,
            state: state,
            onOpen: { [weak self] in self?.open(pick) },
            onClose: { [weak self] in self?.hide() },
            onInteracting: { [weak self] in self?.interacting = $0 },
            onCardFrame: { [weak window] in window?.cardFrame = $0 }
        )
        let host = ReplyPopupHostingController(rootView: view)
        host.view.backgroundColor = .clear
        window.rootViewController = host
        // Visible but never key: the host keeps its keyboard and focus.
        window.isHidden = false
        self.window = window
        self.state = state
        // One runloop later, so the card animates in instead of appearing.
        DispatchQueue.main.async { state.visible = true }

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: view.spokenSummary)
        } else {
            scheduleAutoDismiss()
        }
    }

    /// A timed card cannot be read in time with VoiceOver, so it stays
    /// until dismissed there.
    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.visibleFor)
            guard !Task.isCancelled, let self else { return }
            if self.interacting {
                self.scheduleAutoDismiss()
            } else {
                self.hide()
            }
        }
    }

    /// One reply opens its thread; a card standing for several opens the
    /// home screen, where all of them are listed.
    private func open(_ pick: ReplyPopupPick) {
        hide()
        Presenter.present(
            startInCompose: false,
            conversationId: pick.otherCount == 0 ? pick.conversationId : nil
        )
    }
}

@MainActor
final class ReplyPopupState: ObservableObject {
    @Published var visible = false
}

/// Takes touches only on the card; everywhere else falls through to the
/// host's window underneath.
final class ReplyPopupWindow: UIWindow {
    var cardFrame: CGRect = .zero

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        cardFrame.contains(point)
    }
}

/// Defers the status bar to whatever the host is showing, so the card
/// coming and going never flips it.
final class ReplyPopupHostingController: UIHostingController<ReplyPopupView> {
    override var preferredStatusBarStyle: UIStatusBarStyle {
        Presenter.topViewController()?.preferredStatusBarStyle ?? .default
    }

    override var prefersStatusBarHidden: Bool {
        Presenter.topViewController()?.prefersStatusBarHidden ?? false
    }
}

struct ReplyPopupView: View {
    let pick: ReplyPopupPick
    @ObservedObject var state: ReplyPopupState
    let onOpen: () -> Void
    let onClose: () -> Void
    let onInteracting: (Bool) -> Void
    let onCardFrame: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    private var config: FeddyConfig? { FeddyCore.shared.config }

    private var title: String {
        pick.authorName ?? config?.brand.name ?? Strings.newReply
    }

    private var message: String {
        let text = pick.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? Strings.newReply : text
    }

    private var more: String? {
        pick.otherCount > 0 ? String(format: Strings.replyPopupMore, pick.otherCount) : nil
    }

    var spokenSummary: String {
        [title, message, more].compactMap { $0 }.joined(separator: ". ")
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.visible {
                card
                    .offset(y: dragOffset)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.visible)
        .onPreferenceChange(CardFrameKey.self, perform: onCardFrame)
    }

    private var card: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(message)
                        .font(.subheadline)
                        .lineLimit(2)
                    if let more {
                        Text(more)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onOpen)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Strings.close)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        )
        .frame(maxWidth: 500)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: CardFrameKey.self, value: proxy.frame(in: .global))
            }
        )
        .gesture(swipeUp)
    }

    /// Up dismisses, the way a system banner does; down only gives a
    /// little, so the card still feels attached to the top edge.
    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                onInteracting(true)
                let y = value.translation.height
                dragOffset = y < 0 ? y : y / 6
            }
            .onEnded { value in
                onInteracting(false)
                if value.translation.height < -30 || value.predictedEndTranslation.height < -80 {
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }
}

private struct CardFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
#endif
