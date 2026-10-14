import UIKit
import MobileCoreServices

struct MessageEntry {
    var id: Int64
    var senderId: Int64
    var isOut: Bool
    var text: String
    var kind: Kind = .text
    var date: Int

    enum Kind {
        case text
        case photo(fileId: Int64, width: Int, height: Int)
        case document(fileId: Int64, name: String, size: Int)
    }
}

final class DialogViewController: UIViewController, UITableViewDataSource, UITableViewDelegate,
                                 UITextFieldDelegate, UIDocumentPickerDelegate,
                                 UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let chatId: Int64
    private let chatTitle: String

    private var messages: [MessageEntry] = []
    private var knownIds = Set<Int64>()

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let inputBar = UIView()
    private let inputField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let attachButton = UIButton(type: .system)
    private var bottomConstraint: NSLayoutConstraint!

    private let cellId = "MsgCell"
    private let emptyLabel = UILabel()

    init(chatId: Int64, title: String) {
        self.chatId = chatId
        self.chatTitle = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        title = chatTitle
        navigationController?.navigationBar.barTintColor = .navTint

        setupTable()
        setupInputBar()
        observeKeyboard()
        NotificationCenter.default.addObserver(self, selector: #selector(handleUpdate(_:)),
                                               name: .tdUpdate, object: nil)
        markRead()
        loadHistory()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func markRead() {
        TDClient.shared.send([
            "@type": "viewMessages",
            "chat_id": chatId,
            "message_ids": [],
            "force_read": true
        ])
    }

    // MARK: - History

    private func loadHistory() {
        emptyLabel.text = "Loading..."
        var retryDone = false
        TDClient.shared.send([
            "@type": "getChatHistory",
            "chat_id": chatId,
            "limit": 60
        ]) { [weak self] resp in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.applyHistoryResponse(resp)
                if self.messages.isEmpty && !retryDone {
                    retryDone = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self = self, self.messages.isEmpty else { return }
                        TDClient.shared.send([
                            "@type": "getChatHistory",
                            "chat_id": self.chatId,
                            "from_message_id": 0,
                            "offset": 0,
                            "limit": 60,
                            "only_local": false
                        ]) { resp2 in
                            DispatchQueue.main.async { self.applyHistoryResponse(resp2) }
                        }
                    }
                }
            }
        }
    }

    private func applyHistoryResponse(_ resp: [String: Any]) {
        if tdString(resp["@type"]) == "error" {
            emptyLabel.text = "Error: " + tdString(resp["message"])
            return
        }
        let msgs = tdArray(resp["messages"])
        var entries: [MessageEntry] = []
        for m in msgs {
            if let e = Self.parse(m) { entries.append(e) }
        }
        entries.reverse()
        for e in entries where !knownIds.contains(e.id) {
            knownIds.insert(e.id)
            messages.append(e)
        }
        emptyLabel.text = messages.isEmpty ? "No messages yet" : ""
        tableView.reloadData()
        scrollToBottom()
    }

    static func parse(_ m: [String: Any]) -> MessageEntry? {
        let id = tdInt(m["id"])
        guard id != 0 else { return nil }
        let isOut = (m["is_outgoing"] as? Bool) ?? false
        let sender = tdInt(tdDict(m["sender_id"])?["user_id"])
        let date = Int(tdInt(m["date"]))
        guard let content = tdDict(m["content"]) else { return nil }
        switch tdString(content["@type"]) {
        case "messageText":
            // content.text is a formattedText OBJECT
            let formatted = tdDict(content["text"])
            let body = tdString(formatted?["text"])
            return MessageEntry(id: id, senderId: sender, isOut: isOut,
                                text: body.isEmpty ? "\u{1F516}" : body, kind: .text, date: date)
        case "messagePhoto":
            let photo = tdDict(content["photo"])
            var best: [String: Any]? = nil
            var bestArea: Int64 = 0
            for size in tdArray(photo?["sizes"]) {
                if tdString(size["@type"]) == "photoSize" {
                    let area = tdInt(size["width"]) * tdInt(size["height"])
                    if area > bestArea { bestArea = area; best = size }
                }
            }
            return MessageEntry(id: id, senderId: sender, isOut: isOut, text: "",
                                kind: .photo(fileId: tdInt(best?["photo"]),
                                             width: Int(tdInt(best?["width"])),
                                             height: Int(tdInt(best?["height"]))),
                                date: date)
        case "messageDocument":
            let doc = tdDict(content["document"])
            let file = tdDict(doc?["file"])
            let name = doc?["file_name"] as? String ?? "file"
            return MessageEntry(id: id, senderId: sender, isOut: isOut, text: "",
                                kind: .document(fileId: tdInt(file?["id"]),
                                                name: name,
                                                size: Int(tdInt(file?["size"]))),
                                date: date)
        default:
            return MessageEntry(id: id, senderId: sender, isOut: isOut,
                                text: "\u{1F516} Unsupported", kind: .text, date: date)
        }
    }

    private func scrollToBottom() {
        guard !messages.isEmpty else { return }
        let idx = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: idx, at: .bottom, animated: false)
    }

    // MARK: - UI

    private func setupTable() {
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsSelection = false
        tableView.keyboardDismissMode = .interactive
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .subText
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func setupInputBar() {
        inputBar.backgroundColor = .card
        inputBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputBar)

        attachButton.setTitle("\u{1F4CE}", for: .normal)
        attachButton.titleLabel?.font = .systemFont(ofSize: 22)
        attachButton.tintColor = .accent
        attachButton.addTarget(self, action: #selector(attachTapped), for: .touchUpInside)
        attachButton.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(attachButton)

        inputField.borderStyle = .none
        inputField.placeholder = "Message"
        inputField.font = .systemFont(ofSize: 16)
        inputField.delegate = self
        inputField.backgroundColor = .fieldBackground
        inputField.textColor = .text
        inputField.layer.cornerRadius = 18
        let pad = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        inputField.leftView = pad
        inputField.leftViewMode = .always
        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(inputField)

        sendButton.setTitle("Send", for: .normal)
        sendButton.setTitleColor(.white, for: .normal)
        sendButton.backgroundColor = .accent
        sendButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        sendButton.layer.cornerRadius = 18
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        inputBar.addSubview(sendButton)

        let safe = view.safeAreaLayoutGuide
        bottomConstraint = inputBar.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        NSLayoutConstraint.activate([
            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,
            inputBar.heightAnchor.constraint(equalToConstant: 62),

            attachButton.leadingAnchor.constraint(equalTo: inputBar.leadingAnchor, constant: 12),
            attachButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),

            inputField.leadingAnchor.constraint(equalTo: attachButton.trailingAnchor, constant: 8),
            inputField.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            inputField.heightAnchor.constraint(equalToConstant: 40),

            sendButton.leadingAnchor.constraint(equalTo: inputField.trailingAnchor, constant: 10),
            sendButton.trailingAnchor.constraint(equalTo: inputBar.trailingAnchor, constant: -12),
            sendButton.centerYAnchor.constraint(equalTo: inputBar.centerYAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 36)
        ])

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor)
        ])
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(self, selector: #selector(kbShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(kbHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func kbShow(_ n: Notification) {
        guard let frame = n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let safeBottom = view.safeAreaInsets.bottom
        bottomConstraint.constant = -(frame.height - safeBottom)
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    @objc private func kbHide(_ n: Notification) {
        bottomConstraint.constant = 0
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    // MARK: - Sending

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        sendTapped()
        return true
    }

    @objc private func sendTapped() {
        guard let text = inputField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        inputField.text = ""
        sendWithAlert([
            "@type": "sendMessage",
            "chat_id": chatId,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": ["@type": "formattedText", "text": text]
            ]
        ])
    }

    /// Sends request; surfaces TDLib errors as an alert.
    private func sendWithAlert(_ request: [String: Any], restoreText: String? = nil) {
        TDClient.shared.send(request) { [weak self] resp in
            guard let self = self else { return }
            if tdString(resp["@type"]) == "error" {
                DispatchQueue.main.async {
                    let msg = tdString(resp["message"])
                    let alert = UIAlertController(title: "Not sent",
                                                  message: msg.isEmpty ? "Unknown error" : msg,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                    if let restoreText = restoreText {
                        self.inputField.text = restoreText
                    }
                }
            }
        }
    }

    // MARK: - Attach

    @objc private func attachTapped() {
        view.endEditing(true)
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "\u{1F4F7} Photo or Video", style: .default) { [weak self] _ in
            self?.pickFromGallery()
        })
        sheet.addAction(UIAlertAction(title: "\u{1F4C4} File", style: .default) { [weak self] _ in
            self?.pickFile()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // iPad popover anchor
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = attachButton
            pop.sourceRect = attachButton.bounds
        }
        present(sheet, animated: true)
    }

    private func pickFromGallery() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.mediaTypes = ["public.image", "public.movie"]
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }

    private func pickFile() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        dismiss(animated: true)
        if let image = info[.originalImage] as? UIImage,
           let data = image.jpegData(compressionQuality: 0.85) {
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("photo_\(Int(Date().timeIntervalSince1970)).jpg")
            try? data.write(to: path)
            sendWithAlert([
                "@type": "sendMessage",
                "chat_id": chatId,
                "input_message_content": [
                    "@type": "inputMessagePhoto",
                    "photo": ["@type": "inputFileLocal", "path": path.path],
                    "width": Int(image.size.width),
                    "height": Int(image.size.height)
                ]
            ])
        } else if let url = info[.mediaURL] as? URL {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tmp)
            try? FileManager.default.copyItem(at: url, to: tmp)
            sendWithAlert([
                "@type": "sendMessage",
                "chat_id": chatId,
                "input_message_content": [
                    "@type": "inputMessageVideo",
                    "video": ["@type": "inputFileLocal", "path": tmp.path]
                ]
            ])
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.copyItem(at: url, to: tmp)

        sendWithAlert([
            "@type": "sendMessage",
            "chat_id": chatId,
            "input_message_content": [
                "@type": "inputMessageDocument",
                "document": ["@type": "inputFileLocal", "path": tmp.path]
            ]
        ])
    }

    // MARK: - Updates

    @objc private func handleUpdate(_ note: Notification) {
        guard let update = note.object as? [String: Any] else { return }
        switch tdString(update["@type"]) {
        case "updateNewMessage":
            guard let msg = tdDict(update["message"]),
                  tdInt(msg["chat_id"]) == chatId,
                  let entry = Self.parse(msg), !knownIds.contains(entry.id) else { return }
            knownIds.insert(entry.id)
            messages.append(entry)
            emptyLabel.text = ""
            tableView.reloadData()
            scrollToBottom()
        case "updateDeleteMessages":
            let ids = tdArray(update["message_ids"]).map { tdInt($0) }
            messages.removeAll { knownIds.contains($0.id) && ids.contains($0.id) }
            tableView.reloadData()
        default:
            break
        }
    }

    // MARK: - File download (via FileLoader)

    func localPath(for fileId: Int64) -> String? {
        return FileLoader.shared.cachedPath(fileId)
    }

    // MARK: - Table

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let entry = messages[indexPath.row]
        let cell: MessageCell
        if let reused = tableView.dequeueReusableCell(withIdentifier: cellId) as? MessageCell {
            cell = reused
        } else {
            cell = MessageCell(style: .default, reuseIdentifier: cellId)
        }
        cell.configure(entry: entry,
                       localPath: { [weak self] fileId in
                           guard let self = self else { return nil }
                           if let p = self.localPath(for: fileId) { return p }
                           // kick off chunked download once; FileLoader caches + completes
                           FileLoader.shared.requestPath(fileId: fileId) { [weak self] _ in
                               DispatchQueue.main.async { self?.tableView.reloadData() }
                           }
                           return nil
                       },
                       senderTitle: { senderId in
                           guard !entry.isOut, senderId != 0 else { return nil }
                           if let u = UserCache.shared.user(id: senderId) {
                               return ChatListViewController.userTitle(u)
                           }
                           UserCache.shared.fetchUser(id: senderId) { user in
                               DispatchQueue.main.async { self.tableView.reloadData() }
                           }
                           return nil
                       })
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return MessageCell.estimatedHeight(for: messages[indexPath.row], width: tableView.bounds.width)
    }
}
