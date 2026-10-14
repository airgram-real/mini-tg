import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var appState = AppState()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .tgBackground

        let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        TDClient.shared.start(databasePath: docs + "/tdlib-db", filesPath: docs + "/tdlib-files")

        appState.bootstrap(window: window!)
        window?.makeKeyAndVisible()
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return [.portrait, .landscapeLeft, .landscapeRight]
    }
}

/// Tracks TDLib auth state and swaps root view controllers.
final class AppState {
    private(set) var me: [String: Any]?
    private weak var window: UIWindow?
    var isAuthorized = false

    func bootstrap(window: UIWindow) {
        self.window = window
        showLoading()

        TDClient.shared.onReady = { [weak self] in
            self?.wireUpdates()
        }
    }

    private func showLoading() {
        let vc = UIViewController()
        vc.view.backgroundColor = .tgBlue
        let spinner = UIActivityIndicatorView(style: .whiteLarge)
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        vc.view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: vc.view.centerYAnchor)
        ])
        window?.rootViewController = vc
    }

    private func wireUpdates() {
        TDClient.shared.onUpdate = { [weak self] update in
            guard let self = self else { return }
            let type = tdString(update["@type"])

            switch type {
            case "updateAuthorizationState":
                let state = tdDict(update["authorization_state"])
                self.handleAuthState(state)
            case "updateOption":
                let name = tdString(update["name"])
                if name == "my_id" {
                    //authorization became ready-ish
                }
            case "updateNewMessage", "updateChatLastMessage", "updateChatReadOutbox",
                 "updateChatReadInbox", "updateDeleteMessages", "updateChatTitle",
                 "updateChatPhoto", "updateUser", "updateChatIsPinned", "updateChatOrder",
                 "updateFile", "updateChatAction", "updateUserFullInfo", "updateChatPosition":
                NotificationCenter.default.post(name: .tdUpdate, object: update)
            default:
                break
            }
        }
    }

    private func handleAuthState(_ state: [String: Any]?) {
        guard let state = state else { return }
        let type = tdString(state["@type"])
        switch type {
        case "authorizationStateWaitPhoneNumber":
            showAuth { authVC in authVC.stage = .phone }
        case "authorizationStateWaitCode":
            showAuth { authVC in
                authVC.stage = .code
                if let codeInfo = tdDict(state["code_info"]),
                   let phone = tdString(codeInfo["phone_number"]) as String?, !phone.isEmpty {
                    authVC.phoneNumber = phone
                }
            }
        case "authorizationStateWaitPassword":
            showAuth { authVC in authVC.stage = .password }
        case "authorizationStateWaitRegistration":
            showAuth { authVC in authVC.stage = .phone }
        case "authorizationStateReady":
            isAuthorized = true
            self.loadMeAndShowMain()
        case "authorizationStateLoggingOut", "authorizationStateClosed":
            isAuthorized = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                // TDLib auto-restarts with fresh state
                self?.showLoading()
            }
        default:
            break
        }
    }

    private func showAuth(_ configure: @escaping (AuthViewController) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            if let existing = window.rootViewController as? UINavigationController,
               let auth = existing.viewControllers.first as? AuthViewController {
                configure(auth)
                auth.applyStage()
                return
            }
            let auth = AuthViewController()
            let nav = UINavigationController(rootViewController: auth)
            nav.isNavigationBarHidden = true
            nav.navigationBar.barTintColor = .clear
            nav.navigationBar.tintColor = .white
            nav.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
            window.rootViewController = nav
            configure(auth)
            auth.applyStage()
        }
    }

    private func loadMeAndShowMain() {
        TDClient.shared.send(["@type": "getMe"]) { [weak self] response in
            DispatchQueue.main.async {
                self?.me = response
                self?.showMain()
            }
        }
    }

    private func showMain() {
        guard let window = window else { return }
        let split = MainSplitViewController()
        window.rootViewController = split
    }
}

extension Notification.Name {
    static let tdUpdate = Notification.Name("tdUpdate")
}
