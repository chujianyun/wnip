import Foundation

/// Turns the user's naming rule into a concrete filename and resolves
/// collision-free destinations without ever overwriting an existing file.
struct FilenameResolver: Sendable {
    /// Only these tokens are treated as date fields; every other character in a
    /// rule is a literal, so rules such as `Shot-yyyy` keep their prose intact.
    private struct Token {
        let pattern: String
        let component: KeyPath<DateComponents, Int?>
        let digits: Int
        let isTwoDigitYear: Bool

        init(pattern: String, component: KeyPath<DateComponents, Int?>, digits: Int, isTwoDigitYear: Bool = false) {
            self.pattern = pattern
            self.component = component
            self.digits = digits
            self.isTwoDigitYear = isTwoDigitYear
        }
    }

    private static let tokens: [Token] = [
        Token(pattern: "yyyy", component: \.year, digits: 4),
        Token(pattern: "yy", component: \.year, digits: 2, isTwoDigitYear: true),
        Token(pattern: "MM", component: \.month, digits: 2),
        Token(pattern: "dd", component: \.day, digits: 2),
        Token(pattern: "HH", component: \.hour, digits: 2),
        Token(pattern: "mm", component: \.minute, digits: 2),
        Token(pattern: "ss", component: \.second, digits: 2)
    ]

    private static let unsafeScalars = CharacterSet(charactersIn: "/\\:?*\"<>|")

    let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func filename(rule: String, date: Date, extension fileExtension: String) -> String {
        let stem = sanitized(expanded(rule: rule, for: date))
        let resolvedExtension = sanitized(fileExtension)
        return resolvedExtension.isEmpty ? stem : "\(stem).\(resolvedExtension)"
    }

    func availableURL(in directory: URL, filename: String) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let stem = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension
        var suffix = 2
        while true {
            let name = pathExtension.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(pathExtension)"
            let url = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                return url
            }
            suffix += 1
        }
    }

    private func expanded(rule: String, for date: Date) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        var result = ""
        var index = rule.startIndex
        while index < rule.endIndex {
            let remaining = rule[index...]
            if let token = Self.tokens.first(where: { remaining.hasPrefix($0.pattern) }) {
                let value = components[keyPath: token.component] ?? 0
                let normalized = token.isTwoDigitYear ? value % 100 : value
                result += String(format: "%0\(token.digits)d", normalized)
                index = rule.index(index, offsetBy: token.pattern.count)
            } else {
                result.append(rule[index])
                index = rule.index(after: index)
            }
        }
        return result
    }

    private func sanitized(_ value: String) -> String {
        String(
            value.unicodeScalars.map { scalar in
                Self.unsafeScalars.contains(scalar) ? "-" : Character(scalar)
            }
        )
    }
}
