import Foundation

enum WildcardMatcher {
    static func matches(pattern: String, value: String) -> Bool {
        if pattern == "*" { return true }
        if !pattern.contains("*") {
            return pattern == value
        }

        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        guard let regex = try? NSRegularExpression(pattern: regexPattern) else {
            return false
        }
        let range = NSRange(location: 0, length: value.utf16.count)
        return regex.firstMatch(in: value, options: [], range: range) != nil
    }
}
