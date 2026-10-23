#if canImport(UIKit)
import SwiftUI
import UIKit

/// Presents the support UI modally from whatever is on top, so a single
/// static call works from both UIKit and SwiftUI hosts.
@MainActor
enum Presenter {
    static func present(startInCompose: Bool, conversationId: String? = nil) {
        guard FeddyCore.shared.isConfigured else {
            NSLog("[Feddy] present() called before configure(projectId:)")
            return
        }
        // The panel shows the same replies; a card on top of it says nothing.
        ReplyPopupCoordinator.shared.hide()
        guard let top = topViewController(), !(top is FeddyHostingController) else { return }
        let host = FeddyHostingController(
            rootView: FeddyRootView(
                startInCompose: startInCompose, initialConversationId: conversationId
            )
        )
        host.modalPresentationStyle = .pageSheet
        top.present(host, animated: true)
    }

    static var activeScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    static func topViewController() -> UIViewController? {
        presentationChain().last
    }

    /// True while the panel, or anything it presented, is up.
    static var isFeddyOnScreen: Bool {
        presentationChain().contains { $0 is FeddyHostingController }
    }

    private static func presentationChain() -> [UIViewController] {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard var top = window?.rootViewController else { return [] }
        var chain = [top]
        while let presented = top.presentedViewController {
            top = presented
            chain.append(top)
        }
        return chain
    }
}

final class FeddyHostingController: UIHostingController<FeddyRootView> {}
#endif
