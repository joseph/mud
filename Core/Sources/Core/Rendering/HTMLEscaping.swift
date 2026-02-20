import Foundation

/// Shared HTML escaping utilities.
enum HTMLEscaping {
    /// Escapes `&`, `<`, `>`, and `"` for safe embedding in HTML.
    static func escape(_ string: String) -> String {
        var result = ""
        result.reserveCapacity(string.count)
        for c in string {
            switch c {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default:  result.append(c)
            }
        }
        return result
    }

    // Pre-computed byte arrays for hot-path emission.
    static let amp: [UInt8]  = Array("&amp;".utf8)
    static let lt: [UInt8]   = Array("&lt;".utf8)
    static let gt: [UInt8]   = Array("&gt;".utf8)
    static let quot: [UInt8] = Array("&quot;".utf8)
}
