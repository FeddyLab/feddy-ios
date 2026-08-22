#if canImport(UIKit)
import SwiftUI
import UIKit

/// Presents the support UI modally from whatever is on top, so a single
/// static call works from both UIKit and SwiftUI hosts.
@MainActor
enum Presenter {
    static func present(startInCompose: Bool) {
        guard FeddyCore.shared.isConfigured else {
            NSLog("[Feddy] present() called before configure(projectId:)")
            return
        }
        guard let top = topViewController(), !(top is FeddyHostingController) else { return }
        let host = FeddyHostingController(
            rootView: FeddyRootView(startInCompose: startInCompose)
        )
        host.modalPresentationStyle = .pageSheet
        top.present(host, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let window = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard var top = window?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

final class FeddyHostingController: UIHostingController<FeddyRootView> {}
#endif
