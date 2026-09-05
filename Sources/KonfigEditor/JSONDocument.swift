import Foundation

/// Normalizes JSONC tokens without changing string contents or joining tokens.
enum JSONDocument {
    struct Source {
        let text: String
        let hasComments: Bool
    }

    enum ParseError: LocalizedError {
        case unterminatedComment, commentsNotAllowed, trailingComma, missingValue
        var errorDescription: String? {
            switch self {
            case .unterminatedComment: return L10n.text("Unterminated block comment")
            case .commentsNotAllowed: return L10n.text("Comments are not allowed in strict JSON")
            case .trailingComma: return L10n.text("Trailing commas are not allowed in strict JSON")
            case .missingValue: return L10n.text("Expected a value before the comma")
            }
        }
    }

    static func prepare(_ text: String, allowsComments: Bool) throws -> Source {
        let chars = Array(text.unicodeScalars)
        var result = String.UnicodeScalarView()
        var i = 0
        var inString = false
        var escaped = false
        var hasComments = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                result.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
                i += 1
            } else if c == "\"" {
                inString = true
                result.append(c)
                i += 1
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                guard allowsComments else { throw ParseError.commentsNotAllowed }
                hasComments = true
                result.append(" ")
                i += 2
                while i < chars.count && chars[i] != "\r" && chars[i] != "\n" { i += 1 }
            } else if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                guard allowsComments else { throw ParseError.commentsNotAllowed }
                hasComments = true
                result.append(" ")
                i += 2
                var closed = false
                while i < chars.count {
                    if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                        i += 2
                        closed = true
                        break
                    }
                    if chars[i] == "\r" || chars[i] == "\n" { result.append(chars[i]) }
                    i += 1
                }
                guard closed else { throw ParseError.unterminatedComment }
            } else {
                result.append(c)
                i += 1
            }
        }
        // A second lexical pass allows comments between a trailing comma and its bracket.
        let stripped = Array(result)
        result = String.UnicodeScalarView()
        inString = false
        escaped = false
        for index in stripped.indices {
            let c = stripped[index]
            if inString {
                result.append(c)
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else if c == "\"" {
                inString = true
                result.append(c)
            } else if c == "," {
                var next = index + 1
                while next < stripped.count && [" ", "\t", "\r", "\n"].contains(stripped[next]) { next += 1 }
                if next < stripped.count && (stripped[next] == "}" || stripped[next] == "]") {
                    guard allowsComments else { throw ParseError.trailingComma }
                    var previous = index - 1
                    while previous >= 0 && [" ", "\t", "\r", "\n"].contains(stripped[previous]) { previous -= 1 }
                    guard previous >= 0, !["[", "{", ",", ":"].contains(stripped[previous]) else {
                        throw ParseError.missingValue
                    }
                } else { result.append(c) }
            } else {
                result.append(c)
            }
        }
        return Source(text: String(result), hasComments: hasComments)
    }

    static func parse(_ text: String, allowsComments: Bool) throws -> (object: Any, hasComments: Bool) {
        let source = try prepare(text, allowsComments: allowsComments)
        return (try JSONSerialization.jsonObject(with: Data(source.text.utf8), options: [.fragmentsAllowed]), source.hasComments)
    }

    static func formatted(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object,
            options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
