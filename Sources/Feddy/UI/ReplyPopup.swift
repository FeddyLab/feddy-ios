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
        guard let window else { return }
        self.window = nil
        window.controller.slideOut { window.isHidden = true }
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
        // Recorded only once it is on screen: a reply marked as shown but
        // never drawn would never get another chance.
        if let pick, !show(pick) { return }
        saveShown(ReplyPopupPicker.record(pick, into: shown, listed: list))
    }

    private func loadShown() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: Self.shownKey) as? [String: Int] ?? [:]
    }

    private func saveShown(_ shown: [String: Int]) {
        UserDefaults.standard.set(shown, forKey: Self.shownKey)
    }

    // MARK: - Presentation

    @discardableResult
    private func show(_ pick: ReplyPopupPick) -> Bool {
        guard let scene = Presenter.activeScene else { return false }
        let controller = ReplyPopupViewController(pick: pick)
        controller.onOpen = { [weak self] in self?.open(pick) }
        controller.onClose = { [weak self] in self?.hide() }
        controller.onInteracting = { [weak self] in self?.interacting = $0 }
        let window = ReplyPopupWindow(windowScene: scene, controller: controller)
        // Above the host's screens, below the keyboard and system alerts.
        window.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue + 1)
        // Visible but never key: the host keeps its keyboard and focus.
        window.isHidden = false
        self.window = window
        controller.slideIn()

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: controller.spokenSummary)
        } else {
            scheduleAutoDismiss()
        }
        return true
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

    private func open(_ pick: ReplyPopupPick) {
        hide()
        Presenter.present(startInCompose: false, conversationId: pick.conversationId)
    }
}

/// Takes touches only on the card; everywhere else falls through to the
/// host's window underneath.
final class ReplyPopupWindow: UIWindow {
    let controller: ReplyPopupViewController

    init(windowScene: UIWindowScene, controller: ReplyPopupViewController) {
        self.controller = controller
        super.init(windowScene: windowScene)
        backgroundColor = .clear
        rootViewController = controller
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        controller.cardContains(convert(point, to: controller.view))
    }

    override var canBecomeKey: Bool { false }
}

/// Reads like a system notification banner, which every iPhone user
/// already knows how to read and dismiss: who, when, two lines, swipe up.
/// No app name (it is the app the user is in) and no close button.
final class ReplyPopupViewController: UIViewController {
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}
    var onInteracting: (Bool) -> Void = { _ in }

    private let pick: ReplyPopupPick
    private let card = ReplyPopupCardView()

    init(pick: ReplyPopupPick) {
        self.pick = pick
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Defers the status bar to whatever the host is showing, so the card
    /// coming and going never flips it.
    override var preferredStatusBarStyle: UIStatusBarStyle {
        Presenter.topViewController()?.preferredStatusBarStyle ?? .default
    }

    override var prefersStatusBarHidden: Bool {
        Presenter.topViewController()?.prefersStatusBarHidden ?? false
    }

    var spokenSummary: String {
        "\(spokenTitle). \(message)"
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        card.configure(title: heading, time: time, message: message)
        card.isAccessibilityElement = true
        card.accessibilityLabel = spokenSummary
        card.accessibilityTraits = .button
        card.onActivate = { [weak self] in self?.onOpen() }
        card.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: Strings.close) { [weak self] _ in
                self?.onClose()
                return true
            },
        ]
        card.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        card.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned)))

        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let fill = card.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -20)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -20),
            fill,
        ])
    }

    /// The card's resting frame: a moving card still answers where it is
    /// headed, which is where the finger is aiming.
    /// Built from center and bounds because `frame` is undefined while a
    /// transform is set.
    func cardContains(_ point: CGPoint) -> Bool {
        let size = card.bounds.size
        let center = card.center
        return CGRect(
            x: center.x - size.width / 2, y: center.y - size.height / 2,
            width: size.width, height: size.height
        ).contains(point)
    }

    // MARK: Motion

    private var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    /// Fully above the top edge, shadow included.
    private var offscreen: CGAffineTransform {
        CGAffineTransform(translationX: 0, y: -(card.center.y + card.bounds.height / 2 + 24))
    }

    func slideIn() {
        view.layoutIfNeeded()
        card.alpha = 0
        if !reduceMotion { card.transform = offscreen }
        UIView.animate(
            withDuration: 0.45, delay: 0,
            usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
            options: [.allowUserInteraction]
        ) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
    }

    func slideOut(completion: @escaping () -> Void) {
        UIView.animate(
            withDuration: 0.3, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]
        ) {
            self.card.alpha = 0
            if !self.reduceMotion { self.card.transform = self.offscreen }
        } completion: { _ in
            completion()
        }
    }

    @objc private func tapped() {
        onOpen()
    }

    /// Up dismisses, the way a system banner does; down only gives a
    /// little, so the card still feels attached to the top edge.
    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let y = pan.translation(in: view).y
        switch pan.state {
        case .began, .changed:
            onInteracting(true)
            card.transform = CGAffineTransform(translationX: 0, y: y < 0 ? y : y / 6)
        case .ended, .cancelled, .failed:
            onInteracting(false)
            if pan.state == .ended, y < -30 || pan.velocity(in: view).y < -500 {
                onClose()
            } else {
                UIView.animate(
                    withDuration: 0.3, delay: 0,
                    usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                    options: [.allowUserInteraction]
                ) {
                    self.card.transform = .identity
                }
            }
        default:
            break
        }
    }

    // MARK: Text

    /// "Yu replied" with the name in bold. The sentence is a localized
    /// format so each language puts the name where it belongs.
    private var heading: NSAttributedString {
        let regular = ReplyPopupCardView.font(.subheadline)
        let bold = ReplyPopupCardView.font(.subheadline, weight: .semibold)
        guard let name = pick.authorName, !name.isEmpty else {
            return NSAttributedString(string: Strings.newReply, attributes: [.font: bold])
        }
        let parts = Strings.repliedFormat.components(separatedBy: "%@")
        guard parts.count == 2 else {
            return NSAttributedString(string: name, attributes: [.font: bold])
        }
        let title = NSMutableAttributedString(string: parts[0], attributes: [.font: regular])
        title.append(NSAttributedString(string: name, attributes: [.font: bold]))
        title.append(NSAttributedString(string: parts[1], attributes: [.font: regular]))
        return title
    }

    private var spokenTitle: String {
        guard let name = pick.authorName, !name.isEmpty else { return Strings.newReply }
        return String(format: Strings.repliedFormat, name)
    }

    private var message: String {
        let text = pick.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? Strings.newReply : text
    }

    /// Compact, like a system banner: "now", then 5m, 3h, 2d. The card
    /// usually appears seconds after the reply, and "12 sec. ago" reads
    /// like a stopwatch.
    private var time: String {
        let minutes = Int(Date().timeIntervalSince(pick.sentAt) / 60)
        if minutes < 1 { return Self.nowFormatter.localizedString(fromTimeInterval: 0) }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }

    private static let nowFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter
    }()
}

/// Brand mark, who and when, two lines of the reply.
final class ReplyPopupCardView: UIView {
    var onActivate: () -> Void = {}

    private static let cornerRadius: CGFloat = 18
    private static let markSize: CGFloat = 40

    private let mark = UIView()
    private let titleLabel = UILabel()
    private let timeLabel = UILabel()
    private let messageLabel = UILabel()

    static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let size = UIFontDescriptor.preferredFontDescriptor(withTextStyle: style).pointSize
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = Self.cornerRadius
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 8)

        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .label
        timeLabel.font = Self.font(.footnote)
        timeLabel.textColor = .secondaryLabel
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        messageLabel.font = Self.font(.subheadline)
        messageLabel.textColor = .label
        messageLabel.numberOfLines = 2

        let header = UIStackView(arrangedSubviews: [titleLabel, timeLabel])
        header.alignment = .firstBaseline
        header.spacing = 8
        let text = UIStackView(arrangedSubviews: [header, messageLabel])
        text.axis = .vertical
        text.spacing = 1
        let row = UIStackView(arrangedSubviews: [mark, text])
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            mark.widthAnchor.constraint(equalToConstant: Self.markSize),
            mark.heightAnchor.constraint(equalToConstant: Self.markSize),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
        ])
        buildMark()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: NSAttributedString, time: String, message: String) {
        titleLabel.attributedText = title
        timeLabel.text = time
        messageLabel.text = message
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(
            roundedRect: bounds, cornerRadius: Self.cornerRadius
        ).cgPath
    }

    override func accessibilityActivate() -> Bool {
        onActivate()
        return true
    }

    /// The same mark the panel uses: the project logo, or its initial on
    /// the brand colour.
    private func buildMark() {
        let config = FeddyCore.shared.config
        mark.layer.cornerRadius = Self.markSize * 0.25
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true

        if let logo = config?.brand.logoUrl, let url = URL(string: logo) {
            mark.backgroundColor = UIColor(Theme.surface)
            let image = UIImageView(frame: CGRect(origin: .zero, size: CGSize(width: Self.markSize, height: Self.markSize)))
            image.contentMode = .scaleAspectFill
            mark.addSubview(image)
            Task { @MainActor [weak image] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let loaded = UIImage(data: data)
                else { return }
                image?.image = loaded
            }
        } else {
            mark.backgroundColor = UIColor(Theme.accent(config))
            let initial = UILabel(frame: CGRect(origin: .zero, size: CGSize(width: Self.markSize, height: Self.markSize)))
            initial.text = (config?.brand.name.first).map { String($0).uppercased() } ?? "F"
            initial.font = .systemFont(ofSize: Self.markSize * 0.45, weight: .semibold)
            initial.textColor = UIColor(Theme.onAccent(config))
            initial.textAlignment = .center
            mark.addSubview(initial)
        }
    }
}
#endif
