import UIKit

struct ChatEntry {
    var id: Int64
    var order: Int64
    var title: String
    var lastMessagePreview: String
    var lastMessageIsOut: Bool
    var unreadCount: Int
    var isPinned: Bool
    var lastTimestamp: Int
}

final class ChatListViewController: UITableViewController {
    private var chats: [Int64: ChatEntry] = [:]
    private var orderedIds: [Int64] = []
    private let cellId = "ChatCell"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chats"
        tableView.register(ChatCell.self, forCellReuseIdentifier: cellId)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 70, bottom: 0, right: 0)
        view.backgroundColor = .background
        tableView.backgroundColor = .background
        navigationController?.navigationBar.barTintColor = .navTint

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Me",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(openProfile))

        loadChats()

        NotificationCenter.default.addObserver(self, selector: #selector(handleUpdate(_:)),
                                               name: .tdUpdate, object: nil)
    }

    @objc private func openProfile() {
        let profile = ProfileViewController()
        navigationController?.pushViewController(profile, animated: true)
    }

    private func loadChats() {
        TDClient.shared.send([
            "@type": "getChats",
            "chat_list": ["@type": "chatListMain"],
            "limit": 100
        ]) { [weak self] resp in
            guard let self = self else { return }
            let ids = tdArray(resp["chat_ids"])
            DispatchQueue.main.async {
                for raw in ids {
                    let id = tdInt(raw)
                    if self.chats[id] == nil {
                        self.fetchChat(id: id)
                    }
                }
            }
        }
    }

    private func fetchChat(id: Int64) {
        TDClient.shared.send(["@type": "getChat", "chat_id": id]) { [weak self] resp in
            DispatchQueue.main.async { self?.applyChat(resp) }
        }
    }

    private func applyChat(_ chat: [String: Any]) {
        let id = tdInt(chat["id"])
        guard id != 0 else { return }
        var entry = chats[id] ?? ChatEntry(id: id, order: 0, title: "", lastMessagePreview: "",
                                           lastMessageIsOut: false, unreadCount: 0, isPinned: false, lastTimestamp: 0)
        if entry.title.isEmpty {
            entry.title = displayTitle(chat: chat)
        }
        // positions -> order
        for pos in tdArray(chat["positions"]) where tdString(pos["list"]) == "chatListMain" {
            entry.order = tdInt(pos["order"])
            entry.isPinned = (pos["is_pinned"] as? Bool) ?? false
        }
        if let unreadNum = chat["unread_count"] as? NSNumber { entry.unreadCount = unreadNum.intValue }
        if let lastMsg = tdDict(chat["last_message"]) {
            let (preview, isOut) = Self.preview(for: lastMsg)
            entry.lastMessagePreview = preview
            entry.lastMessageIsOut = isOut
            entry.lastTimestamp = Int(tdInt(lastMsg["date"]))
        }
        chats[id] = entry
        resort()
    }

    static func preview(for message: [String: Any]) -> (String, Bool) {
        let isOut = (message["is_outgoing"] as? Bool) ?? false
        var text = ""
        switch tdString(message["@type"]) {
        case "messageText":
            text = tdString(tdDict(message["content"])?["text"])
        case "messagePhoto":
            text = "\u{1F5BC} Photo"
        case "messageDocument":
            text = "\u{1F4CE} File"
        case "messageVideo":
            text = "\u{1F3AC} Video"
        case "messageVoiceNote":
            text = "\u{1F3A4} Voice"
        case "messageSticker":
            text = "\u{1F3AC} Sticker"
        default:
            text = "\u{1F516} Message"
        }
        if text.count > 80 { text = String(text.prefix(80)) }
        return (text, isOut)
    }

    func displayTitle(chat: [String: Any]) -> String {
        let type = tdString(tdDict(chat["type"])?["@type"])
        if type == "chatTypePrivate" || type == "chatTypeSecret" {
            // fetch user
            let userId = tdInt(chat["user_id"])
            if let user = UserCache.shared.user(id: userId) {
                return Self.userTitle(user)
            }
            UserCache.shared.fetchUser(id: userId) { [weak self] user in
                DispatchQueue.main.async {
                    guard var entry = self?.chats[tdInt(chat["id"])] else { return }
                    entry.title = Self.userTitle(user)
                    self?.chats[tdInt(chat["id"])] = entry
                    self?.resort()
                }
            }
            return "..."
        }
        return tdString(chat["title"])
    }

    static func userTitle(_ user: [String: Any]) -> String {
        var t = tdString(user["first_name"])
        let last = tdString(user["last_name"])
        if !last.isEmpty { t += (t.isEmpty ? "" : " ") + last }
        if t.isEmpty { t = tdString(user["username"]) }
        return t
    }

    private func resort() {
        orderedIds = chats.values.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.order != b.order { return a.order > b.order }
            return a.lastTimestamp > b.lastTimestamp
        }.map { $0.id }
        tableView.reloadData()
    }

    // MARK: - Updates

    @objc private func handleUpdate(_ note: Notification) {
        guard let update = note.object as? [String: Any] else { return }
        switch tdString(update["@type"]) {
        case "updateNewChat":
            if let chat = tdDict(update["chat"]) { applyChat(chat) }
        case "updateChatOrder", "updateChatIsPinned", "updateChatTitle", "updateChatPhoto":
            if let chat = tdDict(update["chat"]) { applyChat(chat) }
        case "updateChatLastMessage":
            let id = tdInt(update["chat_id"])
            if var entry = chats[id] {
                if let lastMsg = tdDict(update["last_message"]) {
                    let (preview, isOut) = Self.preview(for: lastMsg)
                    entry.lastMessagePreview = preview
                    entry.lastMessageIsOut = isOut
                    entry.lastTimestamp = Int(tdInt(lastMsg["date"]))
                    chats[id] = entry
                    resort()
                }
            } else {
                fetchChat(id: id)
            }
        case "updateChatReadInbox":
            let id = tdInt(update["chat_id"])
            if var entry = chats[id] {
                entry.unreadCount = (update["unread_count"] as? Int) ?? entry.unreadCount
                chats[id] = entry
                resort()
            }
        default:
            break
        }
    }

    // MARK: - Table

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return orderedIds.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath) as! ChatCell
        if let entry = chats[orderedIds[indexPath.row]] {
            cell.configure(entry)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let entry = chats[orderedIds[indexPath.row]] else { return }
        (splitViewController as? MainSplitViewController)?.openChat(id: entry.id, title: entry.title)
    }
}

final class UserCache {
    static let shared = UserCache()
    private var users: [Int64: [String: Any]] = [:]
    private var fetching = Set<Int64>()

    func user(id: Int64) -> [String: Any]? { return users[id] }

    func fetchUser(id: Int64, done: @escaping ([String: Any]) -> Void) {
        guard id != 0, users[id] == nil, !fetching.contains(id) else { return }
        fetching.insert(id)
        TDClient.shared.send(["@type": "getUser", "user_id": id]) { [weak self] resp in
            guard let self = self else { return }
            if tdString(resp["@type"]) == "user" {
                self.users[id] = resp
                done(resp)
            }
            self.fetching.remove(id)
        }
    }
}

final class ChatCell: UITableViewCell {
    private let avatarView = AvatarView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let timeLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = .darkGray
        messageLabel.numberOfLines = 1
        timeLabel.font = .systemFont(ofSize: 12)
        timeLabel.textColor = .lightGray
        timeLabel.textAlignment = .right

        badgeLabel.font = .boldSystemFont(ofSize: 12)
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = .tgBlue
        badgeLabel.layer.cornerRadius = 11
        badgeLabel.layer.masksToBounds = true
        badgeLabel.textAlignment = .center

        for v in [titleLabel, messageLabel, timeLabel, badgeLabel] {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(v)
        }

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            avatarView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 48),
            avatarView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            messageLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            badgeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            badgeLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            badgeLabel.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ entry: ChatEntry) {
        contentView.backgroundColor = .background
        backgroundColor = .background
        titleLabel.textColor = .text
        messageLabel.textColor = .subText
        titleLabel.text = entry.title
        var preview = entry.lastMessagePreview
        if entry.lastMessageIsOut && !preview.isEmpty {
            preview = "\u{2713} " + preview
        }
        messageLabel.text = preview
        avatarView.set(name: entry.title)

        if entry.lastTimestamp > 0 {
            let date = Date(timeIntervalSince1970: TimeInterval(entry.lastTimestamp))
            let fmt = DateFormatter()
            fmt.dateFormat = (Calendar.current.isDateInToday(date)) ? "HH:mm" : "dd.MM"
            timeLabel.text = fmt.string(from: date)
        } else {
            timeLabel.text = ""
        }

        if entry.unreadCount > 0 {
            badgeLabel.isHidden = false
            badgeLabel.text = entry.unreadCount > 999 ? "1K+" : String(entry.unreadCount)
        } else {
            badgeLabel.isHidden = true
        }
    }
}

final class AvatarView: UIView {
    private let label = UILabel()
    private var initials: String = ""

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 24
        layer.masksToBounds = true
        label.font = .boldSystemFont(ofSize: 18)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != initials else { return }
        initials = trimmed
        var letters = ""
        let parts = trimmed.split(separator: " ")
        for p in parts.prefix(2) {
            if let f = p.first { letters.append(f) }
        }
        label.text = letters.uppercased()
        // deterministic color
        var hash: UInt32 = 2166136261
        for b in trimmed.utf8 {
            hash ^= UInt32(b)
            hash = hash &* 16777619
        }
        let palette: [UInt32] = [0xE17076, 0x7BC862, 0xE5CA77, 0x65AADD, 0xA695E7, 0xEE7AAE]
        backgroundColor = UIColor(hex: palette[Int(hash % 6)])
    }
}
