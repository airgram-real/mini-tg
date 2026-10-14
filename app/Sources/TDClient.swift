import Foundation

/// Bridge to TDLib JSON interface. Single client, background receive loop.
final class TDClient {
    static let shared = TDClient()

    private var client: UnsafeMutableRawPointer?
    private var started = false
    private var nextRequestId: Int64 = 1
    private var responseHandlers: [Int64: ([String: Any]) -> Void] = [:]
    private let lock = NSLock()

    /// Called on main thread for every TDLib update (no @extra).
    var onUpdate: (([String: Any]) -> Void)?
    /// Called on main thread when database is ready enough to check auth state.
    var onReady: (() -> Void)?

    private init() {}

    func start(databasePath: String, filesPath: String) {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        client = td_json_client_create()

        // Kick off TDLib: parameters must be set before anything else.
        send([
            "@type": "setLogVerbosityLevel",
            "new_verbosity_level": 1
        ])
        send([
            "@type": "setTdlibParameters",
            "parameters": [
                "@type": "tdparameters",
                "use_test_dc": false,
                "database_directory": databasePath,
                "files_directory": filesPath,
                "database_encryption_key": "",
                "use_file_database": true,
                "use_chat_info_database": true,
                "use_message_database": true,
                "use_secret_chats": false,
                "api_id": API_ID,
                "api_hash": API_HASH,
                "system_language_code": "en",
                "device_model": DEVICE_MODEL,
                "system_version": UIDevice.current.systemVersion,
                "application_version": APP_VERSION,
                "enable_storage_optimizer": true,
                "ignore_file_names": false
            ]
        ])
        send([
            "@type": "setAuthenticationEncryptionKey",
            "key": ""
        ])

        // Background receive loop
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.receiveLoop()
        }
        DispatchQueue.main.async { [weak self] in
            self?.onReady?()
        }
    }

    private func receiveLoop() {
        while true {
            guard let c = client else { break }
            var result: [String: Any]? = nil
            if let raw = td_json_client_receive(c, 10.0) {
                let data = Data(bytes: raw, count: strlen(raw))
                result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            guard let json = result else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.handle(json: json)
            }
        }
    }

    private func handle(json: [String: Any]) {
        let type = tdString(json["@type"])
        if let extraRaw = json["@extra"] {
            let extra = tdInt(extraRaw)
            lock.lock()
            let handler = responseHandlers.removeValue(forKey: extra)
            lock.unlock()
            handler?(json)
            return
        }
        if type.hasPrefix("update") || type == "ok" {
            onUpdate?(json)
        }
    }

    /// Fire-and-forget or with completion. Returns request id.
    @discardableResult
    func send(_ request: [String: Any], completion: (([String: Any]) -> Void)? = nil) -> Int64 {
        var req = request
        var id: Int64 = 0
        lock.lock()
        id = nextRequestId
        nextRequestId += 1
        if let completion = completion {
            responseHandlers[id] = completion
        }
        lock.unlock()
        req["@extra"] = String(id)
        guard let c = client else { return id }
        if let data = try? JSONSerialization.data(withJSONObject: req) {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                if let base = raw.baseAddress {
                    td_json_client_send(c, base.assumingMemoryBound(to: CChar.self))
                }
            }
        }
        return id
    }

    /// Synchronous TDLib execute (for helpers like getTextEntities).
    func execute(_ request: [String: Any]) -> [String: Any]? {
        guard let c = client,
              let data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        var out: [String: Any]? = nil
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            if let base = raw.baseAddress {
                let resp = td_json_client_execute(c, base.assumingMemoryBound(to: CChar.self))
                if let resp = resp {
                    let rdata = Data(bytes: resp, count: strlen(resp))
                    out = (try? JSONSerialization.jsonObject(with: rdata)) as? [String: Any]
                }
            }
        }
        return out
    }
}
