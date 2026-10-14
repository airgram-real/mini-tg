import UIKit

final class ProfileViewController: UIViewController {
    private let avatar = AvatarView()
    private let nameLabel = UILabel()
    private let phoneLabel = UILabel()
    private let usernameLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        view.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Log out",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(logOut))

        avatar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(avatar)

        nameLabel.font = .boldSystemFont(ofSize: 22)
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)

        phoneLabel.font = .systemFont(ofSize: 15)
        phoneLabel.textColor = .darkGray
        phoneLabel.textAlignment = .center
        phoneLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phoneLabel)

        usernameLabel.font = .systemFont(ofSize: 15)
        usernameLabel.textColor = .tgBlue
        usernameLabel.textAlignment = .center
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameLabel)

        NSLayoutConstraint.activate([
            avatar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            avatar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 96),
            avatar.heightAnchor.constraint(equalToConstant: 96),

            nameLabel.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            phoneLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            phoneLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            phoneLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            usernameLabel.topAnchor.constraint(equalTo: phoneLabel.bottomAnchor, constant: 4),
            usernameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            usernameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        if let me = (UIApplication.shared.delegate as? AppDelegate)?.appState.me {
            var name = tdString(me["first_name"])
            let last = tdString(me["last_name"])
            if !last.isEmpty { name += (name.isEmpty ? "" : " ") + last }
            nameLabel.text = name.isEmpty ? "Telegram user" : name
            phoneLabel.text = "+" + tdString(me["phone_number"])
            let uname = tdString(me["username"])
            usernameLabel.text = uname.isEmpty ? "" : "@" + uname
            avatar.set(name: name.isEmpty ? "TG" : name)
        }
    }

    @objc private func logOut() {
        let alert = UIAlertController(title: "Log out?",
                                      message: "Your session will be removed from this device.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Log out", style: .destructive) { _ in
            TDClient.shared.send(["@type": "logOut"])
        })
        present(alert, animated: true)
    }
}
