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
    var photoFileId: Int64
}

final class ChatListViewController: UITableViewController, UISearchBarDelegate {
    private var chats: [Int64: ChatEntry] = [:]
    private var orderedIds: [Int64] = []
    private let cellId = "ChatCell"

    // folder: -1 = main, otherwise TDLib folder id
    private var currentFolder: Int64 = -1
    private var folders: [(id: Int64, title: String)] = []
    private var loadingMore = false
    private var searchText = ""

    private let folderScroll = UIScrollView()
    private var searchController: UISearchBar!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Chats"
        view.backgroundColor = .background
        tableView.register(ChatCell.self, forCellReuseIdentifier: cellId)
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 70, bottom: 0, right: 0)
        tableView.backgroundColor = .background
        navigationController?.navigationBar.barTintColor = .navTint

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Me",
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(openProfile))

        setupFoldersBar()
        setupSearch()

        loadFolders()
        loadChatsRepeatedly()

        NotificationCenter.default.addObserver(self, selector: #selector(handleUpdate(_:)),
                                               name: .tdUpdate, object: nil)
        NotificationCenter.default.addObserver(forName: .themeChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.view.backgroundColor = .background
            self.tableView.backgroundColor = .background
            self.navigationController?.navigationBar.barTintColor = .navTint
            self.tableView.reloadData()
        }
    }

    // MARK: - Folder bar

    private func setupFoldersBar() {
        if navigationController?.viewControllers.first === self {
            folderScroll.backgroundColor = .clear
            folderScroll.showsHorizontalScrollIndicator = false
            folderScroll.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(folderScroll)
            NSLayoutConstraint.activate([
                folderScroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                folderScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                folderScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                folderScroll.heightAnchor.constraint(equalToConstant: 44)
            ])
            tableView.tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 0))
            // push table below folder bar via contentInset
            tableView.contentInset.top = 44
            tableView.scrollIndicatorInsets.top = 44
        }
    }

    private func rebuildFolderButtons() {
        folderScroll.subviews.forEach { $0.removeFromSuperview() }
        var x: CGFloat = 12
        let items: [(Int64, String)] = [(-1, "All")] + folders
        for (idx, item) in items.enumerated() {
            let (fid, ftitle) = item
            let btn = UIButton(type: .system)
            btn.setTitle(ftitle, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 14, weight: fid == currentFolder ? .bold : .regular)
            btn.setTitleColor(fid == currentFolder ? .accent : .subText, for: .normal)
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
            let w = btn.intrinsicContentSize.width + 24
            btn.frame = CGRect(x: x, y: 4, width: w, height: 36)
            btn.layer.cornerRadius = 18
            btn.backgroundColor = fid == currentFolder ? .accent.withAlphaComponent(0.15) : .clear
            btn.tag = idx
            btn.addTarget(self, action: #selector(folderTapped(_:)), for: .touchUpInside)
            folderScroll.addSubview(btn)
            x += w + 8
        }
        folderScroll.contentSize = CGSize(width: x, height: 44)
    }

    @objc private func folderTapped(_ sender: UIButton) {
        let items: [(Int64, String)] = [(-1, "All")] + folders
        guard sender.tag < items.count else { return }
        let fid = items[sender.tag].0
        guard fid != currentFolder else { return }
        currentFolder = fid
        chats.removeAll()
        orderedIds.removeAll()
        tableView.reloadData()
        rebuildFolderButtons()
        loadChatsRepeatedly()
    }

    // MARK: - Search

    private func setupSearch() {
        searchController = UISearchBar()
        searchController.delegate = self
        searchController.placeholder = "Search"
        searchController.searchBarStyle = .minimal
        searchController.translatesAutoresizingMaskIntoConstraints = false
        searchController.frame = CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 44)
        searchController.autoresizingMask = [.flexibleWidth]
        tableView.tableHeaderView = searchController
        // keep search above folder bar inset
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        resort()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    // MARK: - Folders

    private func loadFolders() {
        TDClient.shared.send(["@type": "getChatFolders"]) { [weak self] resp in
            guard let self = self, tdString(resp["@type"]) == "chatFolders" else { return }
            var list: [(Int64, String)] = []
            for f in tdArray(resp["chat_folders"]) {
                let id = tdInt(f["id"])
                var t = tdString(f["title"])
                if t.isEmpty { t = "Folder" }
                list.append((id, t))
            }
            DispatchQueue.main.async {
                self.folders = list
                self.rebuildFolderButtons()
            }
        }
    }

    // MARK: - Chats

    private var chatListReq: [String: Any] {
        currentFolder == -1
            ? ["@type": "chatListMain"]
            : ["@type": "chatListFolder", "chat_folder_id": currentFolder]
    }

    private func loadChatsRepeatedly() {
        loadingMore = true
        var rounds = 0
        let knownBefore = { [weak self] in self?.chats.count ?? 0 }

        func round() {
            guard rounds < 15 else { loadingMore = false; return }
            rounds += 1
            TDClient.shared.send(["@type": "loadChats", "chat_list": chatListReq, "limit": 100]) { resp in
                DispatchQueue.main.async {
                    self.refreshVisibleChats {
                        // stop when a round added nothing new and returned ok
                        if tdString(resp["@type"]) == "ok" && self.chats.count == knownBefore() && rounds > 1 {
                            self.loadingMore = false
                        } else if tdString(resp["@type"]) == "error" {
                            self.loadingMore = false
                        } else {
                            round()
                        }
                    }
                }
            }
        }
        round()
    }

    private func refreshVisibleChats(_ done: @escaping () -> Void) {
        // completion runs on main thread already
        TDClient.shared.send(["@type": "getChats", "chat_list": chatListReq, "limit": 200]) { [weak self] resp in
            guard let self = self else { return }
            let ids = tdArray(resp["chat_ids"]).map { tdInt($0) }
            let missing = ids.filter { self.chats[$0] == nil }
            if missing.isEmpty {
                self.resort()
                done()
                return
            }
            let group = DispatchGroup()
            for id in missing {
                group.enter()
                TDClient.shared.send(["@type": "getChat", "chat_id": id]) { chatResp in
                    DispatchQueue.main.async {
                        self.applyChat(chatResp)
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) { done() }
        }
    }

    private func applyChat(_ chat: [String: Any]) {
        let id = tdInt(chat["id"])
        guard id != 0 else { return }
        var entry = chats[id] ?? ChatEntry(id: id, order: 0, title: "", lastMessagePreview: "",
                                           lastMessageIsOut: false, unreadCount: 0, isPinned: false,
                                           lastTimestamp: 0, photoFileId: 0)
        if entry.title.isEmpty {
            entry.title = displayTitle(chat: chat)
        }
        for pos in tdArray(chat["positions"]) {
            let listDict = tdDict(pos["list"])
            let posType = tdString(listDict?["@type"])
            let isCurrentList: Bool
            if currentFolder == -1 {
                isCurrentList = posType == "chatListMain"
            } else {
                isCurrentList = posType == "chatListFolder" && tdInt(listDict?["chat_folder_id"]) == currentFolder
            }
            if isCurrentList {
                entry.order = tdInt(pos["order"])
                entry.isPinned = (pos["is_pinned"] as? Bool) ?? false
            }
        }
        if let unreadNum = chat["unread_count"] as? NSNumber { entry.unreadCount = unreadNum.intValue }
        if let photo = tdDict(chat["photo"]) {
            let small = tdDict(photo["small"])
            entry.photoFileId = tdInt(small?["id"])
        }
        if let lastMsg = tdDict(chat["last_message"]) {
            let (preview, isOut) = Self.preview(for: lastMsg)
            entry.lastMessagePreview = preview
            entry.lastMessageIsOut = isOut
            entry.lastTimestamp = Int(tdInt(lastMsg["date"]))
        }
        chats[id] = entry
    }

    static func preview(for message: [String: Any]) -> (String, Bool) {
        let isOut = (message["is_outgoing"] as? Bool) ?? false
        guard let content = tdDict(message["content"]) else { return ("", isOut) }
        var text = ""
        switch tdString(content["@type"]) {
        case "messageText":
            // content.text is formattedText object
            text = tdString(tdDict(content["text"])?["text"])
        case "messagePhoto":
            text = "\u{1F5BC} Photo"
        case "messageDocument":
            text = "\u{1F4CE} File"
        case "messageVideo":
            text = "\u{1F3AC} Video"
        case "messageVoiceNote":
            text = "\u{1F3A4} Voice"
        case "messageSticker":
            text = "\u{1F3A8} Sticker"
        case "messageAnimation":
            text = "\u{1F3AC} GIF"
        default:
            text = "\u{1F516} Message"
        }
        text = text.replacingOccurrences(of: "\n", with: " ")
        if text.count > 80 { text = String(text.prefix(80)) }
        return (text, isOut)
    }

    func displayTitle(chat: [String: Any]) -> String {
        let type = tdString(tdDict(chat["type"])?["@type"])
        if type == "chatTypePrivate" || type == "chatTypeSecret" {
            let userId = tdInt(chat["user_id"])
            if let user = UserCache.shared.user(id: userId) {
                return Self.userTitle(user)
            }
            UserCache.shared.fetchUser(id: userId) { [weak self] user in
                DispatchQueue.main.async {
                    guard let self = self, var entry = self.chats[tdInt(chat["id"])] else { return }
                    entry.title = Self.userTitle(user)
                    self.chats[tdInt(chat["id"])] = entry
                    self.resort()
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
        var list = chats.values.filter { entry in
            if searchText.isEmpty { return true }
            return entry.title.lowercased().contains(searchText.lowercased())
        }
        list.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            if a.order != b.order { return a.order > b.order }
            return a.lastTimestamp > b.lastTimestamp
        }
        orderedIds = list.map { $0.id }
        tableView.reloadData()
    }

    // MARK: - Updates

    @objc private func handleUpdate(_ note: Notification) {
        guard let update = note.object as? [String: Any] else { return }
        switch tdString(update["@type"]) {
        case "updateNewChat":
            if let chat = tdDict(update["chat"]) { applyChat(chat); resort() }
        case "updateChatPosition":
            let id = tdInt(update["chat_id"])
            if var entry = chats[id] {
                let pos = tdDict(update["position"])
                let posType = tdString(tdDict(pos?["list"])?["@type"])
                let isCurrent: Bool
                if currentFolder == -1 {
                    isCurrent = posType == "chatListMain"
                } else {
                    isCurrent = posType == "chatListFolder" && tdInt(tdDict(pos?["list"])?["chat_folder_id"]) == currentFolder
                }
                if isCurrent {
                    entry.order = tdInt(pos?["order"])
                    entry.isPinned = (pos?["is_pinned"] as? Bool) ?? false
                    chats[id] = entry
                    resort()
                }
            }
        case "updateChatLastMessage":
            let id = tdInt(update["chat_id"])
            if var entry = chats[id], let lastMsg = tdDict(update["last_message"]) {
                let (preview, isOut) = Self.preview(for: lastMsg)
                entry.lastMessagePreview = preview
                entry.lastMessageIsOut = isOut
                entry.lastTimestamp = Int(tdInt(lastMsg["date"]))
                chats[id] = entry
                resort()
            } else if chats[id] == nil {
                TDClient.shared.send(["@type": "getChat", "chat_id": id]) { [weak self] chatResp in
                    DispatchQueue.main.async {
                        self?.applyChat(chatResp)
                        self?.resort()
                    }
                }
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

    @objc private func openProfile() {
        let profile = ProfileViewController()
        navigationController?.pushViewController(profile, animated: true)
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
    private let photoView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let timeLabel = UILabel()
    private let badgeLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(avatarView)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        photoView.layer.cornerRadius = 24
        photoView.isHidden = true
        photoView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(photoView)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.numberOfLines = 1
        timeLabel.font = .systemFont(ofSize: 12)
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

            photoView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            photoView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            photoView.widthAnchor.constraint(equalToConstant: 48),
            photoView.heightAnchor.constraint(equalToConstant: 48),

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
        timeLabel.textColor = .subText
        titleLabel.text = entry.title

        var preview = entry.lastMessagePreview
        if entry.lastMessageIsOut && !preview.isEmpty {
            preview = "\u{2713} " + preview
        }
        messageLabel.text = preview

        if entry.photoFileId != 0 {
            photoView.isHidden = false
            avatarView.isHidden = true
            photoView.image = nil
            photoView.backgroundColor = .fieldBackground
            FileLoader.shared.loadImage(fileId: entry.photoFileId) { [weak photoView] img in
                photoView?.image = img
                photoView?.isHidden = img == nil
                if img == nil { photoView?.superview?.isHidden = false }
            }
            avatarView.set(name: entry.title) // fallback underneath
        } else {
            photoView.isHidden = true
            avatarView.isHidden = false
            avatarView.set(name: entry.title)
        }

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
        var hash: UInt32 = 2166136261
        for b in trimmed.utf8 {
            hash ^= UInt32(b)
            hash = hash &* 16777619
        }
        let palette: [UInt32] = [0xE17076, 0x7BC862, 0xE5CA77, 0x65AADD, 0xA695E7, 0xEE7AAE]
        backgroundColor = UIColor(hex: palette[Int(hash % 6)])
    }
}
