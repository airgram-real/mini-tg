import UIKit

final class MainSplitViewController: UISplitViewController {
    private var chatListVC: ChatListViewController!

    init() {
        let list = ChatListViewController()
        chatListVC = list
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = .tgBackground
        super.init(nibName: nil, bundle: nil)
        viewControllers = [UINavigationController(rootViewController: list),
                           UINavigationController(rootViewController: placeholder)]
        delegate = self
        preferredDisplayMode = .allVisible
    }

    required init?(coder: NSCoder) { fatalError() }

    func openChat(id: Int64, title: String) {
        let dialog = DialogViewController(chatId: id, title: title)
        if viewControllers.count > 1 {
            let nav = viewControllers[1] as? UINavigationController
            nav?.setViewControllers([dialog], animated: false)
        } else {
            let nav = UINavigationController(rootViewController: dialog)
            showDetailViewController(nav, sender: nil)
        }
    }
}

extension MainSplitViewController: UISplitViewControllerDelegate {
    func splitViewController(_ svc: UISplitViewController,
                             collapseSecondary secondaryViewController: UIViewController,
                             onto primaryViewController: UIViewController) -> Bool {
        // On narrow layout show chat list first
        return true
    }
}
