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
