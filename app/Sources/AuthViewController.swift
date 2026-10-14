import UIKit

enum AuthStage {
    case phone
    case code
    case password
}

final class AuthViewController: UIViewController, UITextFieldDelegate {
    var stage: AuthStage = .phone
    var phoneNumber: String = ""

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let textField = UITextField()
    private let nextButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        navigationItem.title = "MiniTG"

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = .darkGray
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subtitleLabel)

        textField.borderStyle = .roundedRect
        textField.keyboardType = .phonePad
        textField.autocorrectionType = .no
        textField.textAlignment = .center
        textField.font = .systemFont(ofSize: 18)
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textField)

        nextButton.setTitle("Next", for: .normal)
        nextButton.backgroundColor = .tgBlue
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.layer.cornerRadius = 10
        nextButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        view.addSubview(nextButton)

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            textField.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 32),
            textField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textField.widthAnchor.constraint(equalToConstant: 320),
            textField.heightAnchor.constraint(equalToConstant: 48),

            nextButton.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 20),
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 320),
            nextButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        applyStage()
    }

    private func applyStage() {
        switch stage {
        case .phone:
            titleLabel.text = "Your phone number"
            subtitleLabel.text = "Please confirm your country code and enter your phone number."
            textField.placeholder = "+7 900 000-00-00"
            textField.keyboardType = .phonePad
            textField.isSecureTextEntry = false
            textField.text = ""
        case .code:
            titleLabel.text = "Enter code"
            subtitleLabel.text = "We sent a code to \(phoneNumber). Check your Telegram app."
            textField.placeholder = "Code"
            textField.keyboardType = .numberPad
            textField.isSecureTextEntry = false
            textField.text = ""
        case .password:
            titleLabel.text = "Cloud password"
            subtitleLabel.text = "Your account is protected with a two-step verification password."
            textField.placeholder = "Password"
            textField.keyboardType = .default
            textField.isSecureTextEntry = true
            textField.text = ""
        }
        nextButton.isEnabled = true
        spinner.stopAnimating()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        nextTapped()
        return true
    }

    @objc private func nextTapped() {
        view.endEditing(true)
        let value = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return }
        nextButton.isEnabled = false
        spinner.startAnimating()

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
            ])
        case .code:
            TDClient.shared.send([
                "@type": "checkAuthenticationCode",
                "code": value
            ])
        case .password:
            TDClient.shared.send([
                "@type": "checkAuthenticationPassword",
                "password": value
            ])
        }
        // On success, updateAuthorizationState moves us forward.
        // On failure, show error via generic error handling below.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, !self.nextButton.isEnabled else { return }
            // If state didn't change, re-enable
            self.spinner.stopAnimating()
            self.nextButton.isEnabled = true
        }
    }
}
