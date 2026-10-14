import Foundation
import UIKit

// App-level constants baked in at build time.
let API_ID = 35535818
let API_HASH = "3af4b687421b4a81355575d321e4efa1"
let APP_VERSION = "1.0"
let DEVICE_MODEL = "iPad Mini 2"

// UIColor helpers
extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255.0,
                  green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                  blue: CGFloat(hex & 0xFF) / 255.0,
                  alpha: 1.0)
    }
    static let tgBlue = UIColor(hex: 0x2AABEE)
    static let tgOutgoing = UIColor(hex: 0xEEFFDE)
    static let tgIncoming = UIColor.white
    static let tgBackground = UIColor(hex: 0xF0F0F0)

    // Theme-forwarding shortcuts so `.text` etc. resolve on UIColor
    static var background: UIColor { Theme.background }
    static var card: UIColor { Theme.card }
    static var text: UIColor { Theme.text }
    static var subText: UIColor { Theme.subText }
    static var accent: UIColor { Theme.accent }
    static var fieldBackground: UIColor { Theme.fieldBackground }
    static var bubbleOut: UIColor { Theme.bubbleOut }
    static var bubbleIn: UIColor { Theme.bubbleIn }
    static var navTint: UIColor { Theme.navTint }
}

func tdInt(_ v: Any?) -> Int64 {
    if let n = v as? Int64 { return n }
    if let n = v as? Int { return Int64(n) }
    if let n = v as? NSNumber { return n.int64Value }
    if let s = v as? String { return Int64(s) ?? 0 }
    return 0
}

func tdDouble(_ v: Any?) -> Double {
    if let n = v as? Double { return n }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? 0 }
    return 0
}

func tdString(_ v: Any?) -> String {
    return v as? String ?? ""
}

func tdDict(_ v: Any?) -> [String: Any]? {
    return v as? [String: Any]
}

func tdArray(_ v: Any?) -> [[String: Any]] {
    if let a = v as? [[String: Any]] { return a }
    if let a = v as? [Any] {
        return a.compactMap { $0 as? [String: Any] }
    }
    return []
}

// MARK: - Theme

extension Notification.Name {
    static let themeChanged = Notification.Name("themeChanged")
}

enum Theme {
    static var dark: Bool {
        UserDefaults.standard.bool(forKey: "darkMode")
    }
    static func setDark(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "darkMode")
        NotificationCenter.default.post(name: .themeChanged, object: nil)
    }

    static var background: UIColor { dark ? UIColor(hex: 0x17212B) : UIColor(hex: 0xF4F4F5) }
    static var card: UIColor { dark ? UIColor(hex: 0x232E3C) : .white }
    static var text: UIColor { dark ? .white : .black }
    static var subText: UIColor { dark ? UIColor(hex: 0x8A9AA9) : .darkGray }
    static var accent: UIColor { .tgBlue }
    static var fieldBackground: UIColor { dark ? UIColor(hex: 0x2B3A4C) : UIColor(hex: 0xF1F1F3) }
    static var bubbleOut: UIColor { dark ? UIColor(hex: 0x2B5278) : .tgOutgoing }
    static var bubbleIn: UIColor { dark ? UIColor(hex: 0x232E3C) : .tgIncoming }
    static var navTint: UIColor { dark ? UIColor(hex: 0x17212B) : .tgBlue }
}

// MARK: - File loader (chunked download, images + paths)

final class FileLoader {
    static let shared = FileLoader()

    private var requested = Set<Int64>()
    private var pathCache: [Int64: String] = [:]
    private var imgCache: [Int64: UIImage] = [:]
    private var imgCompletions: [Int64: [(UIImage?) -> Void]] = [:]
    private var pathCompletions: [Int64: [(String?) -> Void]] = [:]
    private var listening = false
    private let chunkSize = 1 << 20 // 1 MB

    func cachedPath(_ fileId: Int64) -> String? {
        return pathCache[fileId]
    }

    /// Loads file as UIImage (with in-memory cache).
    func loadImage(fileId: Int64, completion: @escaping (UIImage?) -> Void) {
        if fileId == 0 { completion(nil); return }
        if let img = imgCache[fileId] {
            completion(img)
            return
        }
        requestPath(fileId: fileId) { [weak self] path in
            guard let self = self, let path = path, let img = UIImage(contentsOfFile: path) else {
                completion(nil)
                return
            }
            self.imgCache[fileId] = img
            completion(img)
        }
    }

    /// Requests file download; completion receives local path (or nil on failure).
    func requestPath(fileId: Int64, completion: @escaping (String?) -> Void) {
        if fileId == 0 { completion(nil); return }
        if let p = pathCache[fileId] {
            completion(p)
            return
        }
        listen()
        pathCompletions[fileId, default: []].append(completion)
        guard !requested.contains(fileId) else { return }
        requested.insert(fileId)
        // start chunked download
        sendChunk(fileId: fileId, offset: 0)
    }

    private func sendChunk(fileId: Int64, offset: Int64) {
        TDClient.shared.send([
            "@type": "downloadFile",
            "file_id": fileId,
            "priority": 16,
            "offset": offset,
            "limit": chunkSize,
            "synchronous": false
        ])
    }

    private func listen() {
        guard !listening else { return }
        listening = true
        NotificationCenter.default.addObserver(forName: .tdUpdate, object: nil, queue: .main) { [weak self] note in
            guard let self = self,
                  let update = note.object as? [String: Any],
                  tdString(update["@type"]) == "updateFile",
                  let file = tdDict(update["file"]) else { return }
            let fileId = tdInt(file["id"])
            guard self.requested.contains(fileId), self.pathCache[fileId] == nil else { return }

            let local = tdDict(file["local"])
            let completed = (local?["is_downloading_completed"] as? Bool) == true
            if completed, let path = local?["path"] as? String {
                self.pathCache[fileId] = path
                let pbs = self.pathCompletions[fileId] ?? []
                self.pathCompletions[fileId] = []
                for cb in pbs { cb(path) }
                let ibs = self.imgCompletions[fileId] ?? []
                self.imgCompletions[fileId] = []
                if let img = UIImage(contentsOfFile: path) {
                    self.imgCache[fileId] = img
                    for cb in ibs { cb(img) }
                } else {
                    for cb in ibs { cb(nil) }
                }
                return
            }
            // not completed yet: request next chunk
            let downloaded = tdInt(local?["download_offset"])
            let expected = tdInt(file["expected_size"])
            if expected == 0 || downloaded < expected {
                self.sendChunk(fileId: fileId, offset: downloaded)
            }
        }
    }
}
