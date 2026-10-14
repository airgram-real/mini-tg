import UIKit

final class ProfileViewController: UIViewController {
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let phoneLabel = UILabel()
    private let usernameLabel = UILabel()
    private let themeToggle = UISwitch()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Profile"
        styleUI()
        setupLayout()
        fillData()
        loadAvatar()

        NotificationCenter.default.addObserver(forName: .themeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.styleUI()
        }
    }

    private func styleUI() {
        view.backgroundColor = .background
        navigationController?.navigationBar.barTintColor = .navTint
        navigationController?.navigationBar.tintColor = Theme.dark ? .white : .white

        nameLabel.textColor = .text
        phoneLabel.textColor = .subText
        usernameLabel.textColor = .accent
        avatarView.backgroundColor = .fieldBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Log out",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(logOut))
    }

    private func setupLayout() {
        avatarView.layer.cornerRadius = 48
        avatarView.clipsToBounds = true
        avatarView.contentMode = .scaleAspectFill
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(avatarView)

        nameLabel.font = .boldSystemFont(ofSize: 22)
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nameLabel)

        phoneLabel.font = .systemFont(ofSize: 15)
        phoneLabel.textAlignment = .center
        phoneLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(phoneLabel)

        usernameLabel.font = .systemFont(ofSize: 15)
        usernameLabel.textAlignment = .center
        usernameLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(usernameLabel)

        let themeLabel = UILabel()
        themeLabel.text = "Dark mode"
        themeLabel.font = .systemFont(ofSize: 16)
        themeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(themeLabel)

        themeToggle.isOn = Theme.dark
        themeToggle.onTintColor = .accent
        themeToggle.translatesAutoresizingMaskIntoConstraints = false
        themeToggle.addTarget(self, action: #selector(themeSwitched(_:)), for: .valueChanged)
        view.addSubview(themeToggle)

        NSLayoutConstraint.activate([
            avatarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 30),
            avatarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 96),
            avatarView.heightAnchor.constraint(equalToConstant: 96),

            nameLabel.topAnchor.constraint(equalTo: avatarView.bottomAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            phoneLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            phoneLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            phoneLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            usernameLabel.topAnchor.constraint(equalTo: phoneLabel.bottomAnchor, constant: 4),
            usernameLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            usernameLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            themeLabel.topAnchor.constraint(equalTo: usernameLabel.bottomAnchor, constant: 36),
            themeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),

            themeToggle.centerYAnchor.constraint(equalTo: themeLabel.centerYAnchor),
            themeToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func fillData() {
        guard let me = (UIApplication.shared.delegate as? AppDelegate)?.appState.me else { return }
        var name = tdString(me["first_name"])
        let last = tdString(me["last_name"])
        if !last.isEmpty { name += (name.isEmpty ? "" : " ") + last }
        nameLabel.text = name.isEmpty ? "Telegram user" : name
        phoneLabel.text = "+" + tdString(me["phone_number"])
        let uname = tdString(me["username"])
        usernameLabel.text = uname.isEmpty ? "" : "@" + uname

        // No photo yet -> initials
        if tdDict(me["profile_photo"]) == nil {
            let av = AvatarView()
            av.frame = CGRect(x: 0, y: 0, width: 96, height: 96)
            av.set(name: name.isEmpty ? "TG" : name)
            // render initials into image
            UIGraphicsBeginImageContextWithOptions(CGSize(width: 96, height: 96), false, 0)
            av.layer.render(in: UIGraphicsGetCurrentContext()!)
            let img = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            avatarView.image = img
        }
    }

    private func loadAvatar() {
        guard let me = (UIApplication.shared.delegate as? AppDelegate)?.appState.me,
              let photo = tdDict(me["profile_photo"]),
              let big = tdDict(photo["big"]) else { return }
        let fileId = tdInt(big["id"])
        FileLoader.shared.load(fileId: fileId) { [weak self] img in
            DispatchQueue.main.async {
                if let img = img { self?.avatarView.image = img }
            }
        }
    }

    @objc private func themeSwitched(_ sender: UISwitch) {
        Theme.setDark(sender.isOn)
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
