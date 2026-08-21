import Foundation

/// Line-delimited JSON-RPC over a child process's stdio, which is how the Codex
/// `app-server` speaks. Port of the reader thread plus `rpc_read`.
final class RPCChannel {
    private let condition = NSCondition()
    private var messages: [[String: Any]] = []
    private var buffer = Data()

    /// Feeds raw stdout bytes; complete lines that parse as JSON become
    /// messages. Partial lines are held until the rest arrives.
    func feed(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let message = object as? [String: Any] else { continue }
            condition.lock()
            messages.append(message)
            condition.signal()
            condition.unlock()
        }
    }

    struct Timeout: Error, LocalizedError {
        var errorDescription: String? { "Codex did not respond in time" }
    }
    struct RPCError: Error, LocalizedError {
        let payload: Any
        /// Python raises `str(message["error"])` — a dict repr. JSON is the
        /// closest honest equivalent; the parity script normalizes this text
        /// because it is inherently implementation-specific.
        var errorDescription: String? {
            guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                         options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8) else { return "\(payload)" }
            return text
        }
    }

    /// The result for `id`, or throws. Messages for other ids are discarded,
    /// exactly as the reference does.
    func waitFor(id: Int, timeout: TimeInterval) throws -> Any {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while true {
            while !messages.isEmpty {
                let message = messages.removeFirst()
                guard (message["id"] as? NSNumber)?.intValue == id else { continue }
                if let error = message["error"] { throw RPCError(payload: error) }
                return message["result"] ?? NSNull()
            }
            if Date() >= deadline { throw Timeout() }
            if !condition.wait(until: deadline) { throw Timeout() }
        }
    }
}
