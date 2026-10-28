import Darwin
import Foundation

enum UPnPClient {
    static let host = "192.168.0.1"
    static let port: UInt16 = 1900
    static let path = "/ifc"
    static let ns = "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1"

    struct Totals {
        var sent: UInt64
        var received: UInt64
    }

    static func fetchTotals() throws -> Totals {
        let sent = try fetchUInt64(action: "GetTotalBytesSent", tag: "NewTotalBytesSent")
        let received = try fetchUInt64(action: "GetTotalBytesReceived", tag: "NewTotalBytesReceived")
        return Totals(sent: sent, received: received)
    }

    private static func fetchUInt64(action: String, tag: String) throws -> UInt64 {
        let xml = try soap(action: action)
        guard let value = xmlTag(xml, tag: tag).flatMap(UInt64.init) else {
            throw UPnPError.missingTag(tag)
        }
        return value
    }

    private static func soap(action: String) throws -> String {
        let body =
            "<?xml version=\"1.0\"?>" +
            "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" " +
            "s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">" +
            "<s:Body><u:\(action) xmlns:u=\"\(ns)\"></u:\(action)></s:Body></s:Envelope>"

        var request = ""
        request += "POST \(path) HTTP/1.1\r\n"
        request += "Host: \(host):\(port)\r\n"
        request += "Content-Type: text/xml; charset=\"utf-8\"\r\n"
        request += "SOAPAction: \"\(ns)#\(action)\"\r\n"
        request += "Content-Length: \(body.utf8.count)\r\n"
        request += "Connection: close\r\n\r\n"
        request += body
        return try httpPost(request)
    }

    private static func httpPost(_ request: String) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UPnPError.socket }

        var tv = timeval(tv_sec: 4, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            close(fd)
            throw UPnPError.connect
        }

        let connected: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connect(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            throw UPnPError.connect
        }

        let payload = Array(request.utf8)
        let sent = payload.withUnsafeBufferPointer { buf in
            Darwin.send(fd, buf.baseAddress, buf.count, 0)
        }
        guard sent == payload.count else {
            close(fd)
            throw UPnPError.send
        }

        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 2048)
        while true {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n < 0 {
                close(fd)
                throw UPnPError.recv
            }
            if n == 0 { break }
            data.append(contentsOf: chunk.prefix(n))
        }
        close(fd)

        guard let text = String(data: data, encoding: .utf8),
              let sep = text.range(of: "\r\n\r\n") else {
            throw UPnPError.badStatus
        }
        let head = text[..<sep.lowerBound]
        guard head.contains(" 200 ") || head.hasPrefix("HTTP/1.1 200") || head.hasPrefix("HTTP/1.0 200") else {
            throw UPnPError.badStatus
        }
        return String(text[sep.upperBound...])
    }

    private static func xmlTag(_ xml: String, tag: String) -> String? {
        let open = "<\(tag)>"
        guard let start = xml.range(of: open)?.upperBound,
              let end = xml[start...].range(of: "<")?.lowerBound else {
            return nil
        }
        return String(xml[start..<end])
    }
}

enum UPnPError: LocalizedError {
    case missingTag(String)
    case badStatus
    case socket
    case connect
    case send
    case recv

    var errorDescription: String? {
        switch self {
        case .missingTag(let tag): return "XML missing \(tag)"
        case .badStatus: return "HTTP status is not 200"
        case .socket: return "Could not create socket"
        case .connect: return "Cannot connect to \(UPnPClient.host):\(UPnPClient.port)"
        case .send: return "Send failed"
        case .recv: return "Receive failed"
        }
    }
}

enum ByteFormat {
    static func total(_ n: UInt64) -> String {
        format(Double(n), units: ["B", "KB", "MB", "GB", "TB"])
    }

    static func rate(_ bytesPerSec: Double) -> String {
        format(max(0, bytesPerSec), units: ["B/s", "KB/s", "MB/s", "GB/s"])
    }

    static func compactRate(_ bytesPerSec: Double) -> String {
        let v = max(0, bytesPerSec)
        let raw: String
        if v < 1024 {
            raw = String(format: "%dB/s", Int(v))
        } else if v < 100 * 1024 {
            raw = String(format: "%.1fKB/s", v / 1024)
        } else if v < 1024 * 1024 {
            raw = String(format: "%.0fKB/s", v / 1024)
        } else if v < 100 * 1024 * 1024 {
            raw = String(format: "%.1fMB/s", v / 1024 / 1024)
        } else if v < 1024 * 1024 * 1024 {
            raw = String(format: "%.0fMB/s", v / 1024 / 1024)
        } else {
            raw = String(format: "%.1fGB/s", v / 1024 / 1024 / 1024)
        }
        return raw.padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    static func delta(prev: UInt64, cur: UInt64) -> UInt64 {
        if cur >= prev { return cur - prev }
        if prev < (UInt64(1) << 32) { return cur &+ ((UInt64(1) << 32) &- prev) }
        return cur
    }

    private static func format(_ value: Double, units: [String]) -> String {
        var value = value
        var i = 0
        while i + 1 < units.count && value >= 1024 {
            value /= 1024
            i += 1
        }
        if i == 0 { return "\(Int(value)) \(units[i])" }
        return String(format: "%.2f %@", value, units[i])
    }
}
