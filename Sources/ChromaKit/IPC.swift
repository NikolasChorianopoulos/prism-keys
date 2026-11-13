import Foundation

/// Tiny line-based JSON protocol over a Unix domain socket between the CLI and the service.
public enum IPC {
    public static func send(_ message: [String: String], timeout: TimeInterval = 3) -> [String: String]? {
        let path = Store.shared.socketPath
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        guard connectUnix(fd, path) else { return nil }
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return nil }
        data.append(0x0A)
        let ok = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) == data.count }
        guard ok else { return nil }
        var buf = [UInt8](repeating: 0, count: 65536)
        var resp = Data()
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            resp.append(buf, count: n)
            if buf[n - 1] == 0x0A { break }
        }
        return (try? JSONSerialization.jsonObject(with: resp)) as? [String: String]
    }

    static func withAddr<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8.prefix(103)) + [0]
        withUnsafeMutableBytes(of: &addr.sun_path) { p in for (i, b) in bytes.enumerated() { p[i] = b } }
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    static func connectUnix(_ fd: Int32, _ path: String) -> Bool {
        withAddr(path) { connect(fd, $0, $1) == 0 }
    }

    /// Starts a server on a background thread. Handler runs on that thread.
    public static func serve(_ handler: @escaping ([String: String]) -> [String: String]) throws {
        let path = Store.shared.socketPath
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ChromaError.io("socket() failed") }
        guard withAddr(path, { bind(fd, $0, $1) }) == 0 else { throw ChromaError.io("can't bind \(path)") }
        chmod(path, 0o600)
        listen(fd, 8)
        Thread.detachNewThread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { continue }
                var buf = [UInt8](repeating: 0, count: 65536)
                var data = Data()
                while true {
                    let n = read(c, &buf, buf.count)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                    if buf[n - 1] == 0x0A { break }
                }
                let req = ((try? JSONSerialization.jsonObject(with: data)) as? [String: String]) ?? [:]
                let resp = handler(req)
                if var out = try? JSONSerialization.data(withJSONObject: resp) {
                    out.append(0x0A)
                    _ = out.withUnsafeBytes { write(c, $0.baseAddress, out.count) }
                }
                close(c)
            }
        }
    }
}
