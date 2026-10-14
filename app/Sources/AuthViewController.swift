import UIKit

enum AuthStage {
    case phone
    case code
    case password
}

final class AuthViewController: UIViewController, UITextFieldDelegate {
    var stage: AuthStage = .phone
    var phoneNumber: String = ""

    private let gradientLayer = CAGradientLayer()

    private let brandLabel = UILabel()
    private let brandSubtitle = UILabel()

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textField = UITextField()
    private let nextButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .white)
    private let themeButton = UIButton(type: .system)

    private var cardCenterConstraint: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupGradient()
        setupUI()
        applyStage()

        NotificationCenter.default.addObserver(forName: .themeChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyStage()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(kbShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(kbHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradientLayer.frame = view.bounds
    }

    private func setupGradient() {
        gradientLayer.colors = [UIColor(hex: 0x2AABEE).cgColor, UIColor(hex: 0x1C86B8).cgColor]
        gradientLayer.startPoint = CGPoint(x: 0.3, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.7, y: 1)
        view.layer.addSublayer(gradientLayer)
    }

    private func setupUI() {
        // Brand header
        brandLabel.text = "MiniTG"
        brandLabel.font = .systemFont(ofSize: 40, weight: .bold)
        brandLabel.textColor = .white
        brandLabel.textAlignment = .center
        brandLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(brandLabel)

        brandSubtitle.text = "Minimal Telegram client.\nJust your chats — nothing else."
        brandSubtitle.font = .systemFont(ofSize: 14)
        brandSubtitle.textColor = UIColor.white.withAlphaComponent(0.85)
        brandSubtitle.textAlignment = .center
        brandSubtitle.numberOfLines = 0
        brandSubtitle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(brandSubtitle)

        // Card
        cardView.layer.cornerRadius = 18
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.25
        cardView.layer.shadowRadius = 16
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(subtitleLabel)

        textField.borderStyle = .roundedRect
        textField.keyboardType = .phonePad
        textField.autocorrectionType = .no
        textField.textAlignment = .center
        textField.font = .systemFont(ofSize: 17)
        textField.backgroundColor = .fieldBackground
        textField.textColor = .text
        textField.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(textField)

        nextButton.setTitle("Continue", for: .normal)
        nextButton.backgroundColor = .accent
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.layer.cornerRadius = 12
        nextButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        cardView.addSubview(nextButton)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(spinner)

        // Theme toggle
        themeButton.setTitle(Theme.dark ? "\u{2600}\u{FE0F}" : "\u{1F319}", for: .normal)
        themeButton.titleLabel?.font = .systemFont(ofSize: 26)
        themeButton.translatesAutoresizingMaskIntoConstraints = false
        themeButton.addTarget(self, action: #selector(toggleTheme), for: .touchUpInside)
        view.addSubview(themeButton)

        let cardWidth: CGFloat = min(340, UIScreen.main.bounds.width - 48)
        cardCenterConstraint = cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor)

        NSLayoutConstraint.activate([
            brandLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            brandLabel.bottomAnchor.constraint(equalTo: cardView.topAnchor, constant: -56),

            brandSubtitle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            brandSubtitle.topAnchor.constraint(equalTo: brandLabel.bottomAnchor, constant: 6),

            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardCenterConstraint,
            cardView.widthAnchor.constraint(equalToConstant: cardWidth),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),

            textField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
            textField.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            textField.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            textField.heightAnchor.constraint(equalToConstant: 46),

            nextButton.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 16),
            nextButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            nextButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            nextButton.heightAnchor.constraint(equalToConstant: 48),
            nextButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -20),

            spinner.centerXAnchor.constraint(equalTo: nextButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),

            themeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            themeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    @objc private func toggleTheme() {
        Theme.setDark(!Theme.dark)
    }

    @objc private func kbShow(_ n: Notification) {
        guard let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let overflow = (view.bounds.height + 56) - frame.origin.y
        cardCenterConstraint.constant = overflow > 0 ? -overflow / 2 : 0
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    @objc private func kbHide(_ n: Notification) {
        cardCenterConstraint.constant = 0
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    func applyStage() {
        cardView.backgroundColor = .card
        titleLabel.textColor = .text
        subtitleLabel.textColor = .subText
        textField.textColor = .text
        textField.backgroundColor = .fieldBackground
        themeButton.setTitle(Theme.dark ? "\u{2600}\u{FE0F}" : "\u{1F319}", for: .normal)

        switch stage {
        case .phone:
            titleLabel.text = "Your phone number"
            subtitleLabel.text = "Please confirm your country code and enter your phone number."
            textField.placeholder = "+7 900 000-00-00"
            textField.keyboardType = .phonePad
            textField.isSecureTextEntry = false
        case .code:
            titleLabel.text = "Enter code"
            subtitleLabel.text = "We sent a code to \(phoneNumber). Check your Telegram app."
            textField.placeholder = "Code"
            textField.keyboardType = .numberPad
            textField.isSecureTextEntry = false
        case .password:
            titleLabel.text = "Cloud password"
            subtitleLabel.text = "Your account is protected with two-step verification."
            textField.placeholder = "Password"
            textField.keyboardType = .default
            textField.isSecureTextEntry = true
        }
        textField.text = ""
        nextButton.isEnabled = true
        spinner.stopAnimating()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        nextTapped()
        return true
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func nextTapped() {
        view.endEditing(true)
        let value = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return }
        nextButton.isEnabled = false
        spinner.startAnimating()

        let onFail: ([String: Any]) -> Void = { [weak self] resp in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let msg = tdString(resp["message"])
                self.showError(msg.isEmpty ? "Something went wrong" : msg)
                self.spinner.stopAnimating()
                self.nextButton.isEnabled = true
            }
        }

        switch stage {
        case .phone:
            var phone = value
            if !phone.hasPrefix("+") { phone = "+" + phone }
            phoneNumber = phone
            TDClient.shared.send([
                "@type": "setAuthenticationPhoneNumber",
                "phone_number": phone,
                "allow_flash_call": false,
                "is_current_phone_number": true
            ]) { resp in
                if tdString(resp["@type"]) == "error" { onFail(resp) }
            }
        case .code:
            TDClient.shared.send([
                "@type": "checkAuthenticationCode",
                "code": value
            ]) { resp in
                if tdString(resp["@type"]) == "error" { onFail(resp) }
            }
        case .password:
            TDClient.shared.send([
                "@type": "checkAuthenticationPassword",
                "password": value
            ]) { resp in
                if tdString(resp["@type"]) == "error" { onFail(resp) }
            }
        }
        // Success moves us via updateAuthorizationState -> AppDelegate.showAuth
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, !self.nextButton.isEnabled else { return }
            self.spinner.stopAnimating()
            self.nextButton.isEnabled = true
        }
    }
}
