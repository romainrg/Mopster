import Foundation

/// A version string compared component by component: `1.10 > 1.9`, `2 == 2.0.0`, `1.0b3 < 1.0`.
/// A trailing build in parentheses (`1.2.3 (456)`) counts as one more component.
public struct AppVersion: Comparable, Hashable, Sendable {
    private struct Component {
        var number: Int
        var tail: String

        var isZero: Bool { number == 0 && tail.isEmpty }
    }

    private let components: [Component]

    public init(_ string: String) {
        var parsed: [Component] = []
        let separators = CharacterSet(charactersIn: ". ()-")
        for var token in string.components(separatedBy: separators) where !token.isEmpty {
            if parsed.isEmpty {
                let letters = token.prefix(while: { $0.isASCII && $0.isLetter })
                if token.dropFirst(letters.count).first?.isNumber == true { token = String(token.dropFirst(letters.count)) }
            }
            let digits = token.prefix(while: { $0.isASCII && $0.isNumber })
            if let number = Int(digits) {
                parsed.append(Component(number: number, tail: String(token.dropFirst(digits.count)).lowercased()))
            } else if parsed.indices.last.map({ parsed[$0].tail.isEmpty }) == true {
                parsed[parsed.count - 1].tail = token.lowercased()
            }
        }
        components = parsed
    }

    private var normalized: [Component] {
        var trimmed = components
        while trimmed.last?.isZero == true { trimmed.removeLast() }
        return trimmed
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool { compare(lhs, rhs) < 0 }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { compare(lhs, rhs) == 0 }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(components.isEmpty)
        for component in normalized {
            hasher.combine(component.number)
            let (letters, number) = Self.split(component.tail)
            hasher.combine(letters)
            hasher.combine(number)
        }
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        switch (lhs.components.isEmpty, rhs.components.isEmpty) {
        case (true, true): return 0
        case (true, false): return -1
        case (false, true): return 1
        case (false, false): break
        }
        let zero = Component(number: 0, tail: "")
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : zero
            let right = index < rhs.components.count ? rhs.components[index] : zero
            if left.number != right.number { return left.number < right.number ? -1 : 1 }
            let tails = compareTails(left.tail, right.tail)
            if tails != 0 { return tails }
        }
        return 0
    }

    /// No tail ranks above any tail (`1.0` is newer than `1.0b3`); tails compare by letters, then numerically.
    private static func compareTails(_ lhs: String, _ rhs: String) -> Int {
        if lhs == rhs { return 0 }
        if lhs.isEmpty { return 1 }
        if rhs.isEmpty { return -1 }
        let (leftLetters, leftNumber) = split(lhs)
        let (rightLetters, rightNumber) = split(rhs)
        if leftLetters != rightLetters { return leftLetters < rightLetters ? -1 : 1 }
        return leftNumber == rightNumber ? 0 : (leftNumber < rightNumber ? -1 : 1)
    }

    private static func split(_ tail: String) -> (letters: String, number: Int) {
        let letters = tail.prefix(while: { !$0.isNumber })
        return (String(letters), Int(tail.dropFirst(letters.count).prefix(while: \.isNumber)) ?? 0)
    }
}
