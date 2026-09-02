import Foundation

/// A small recursive-descent evaluator for the calculator tool. Written by hand rather than using
/// `NSExpression`, which raises Objective-C exceptions on malformed input that Swift cannot catch.
enum Arithmetic {
    enum EvaluationError: LocalizedError, Equatable {
        case empty
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case unbalancedParenthesis
        case divisionByZero
        case notFinite

        var errorDescription: String? {
            switch self {
            case .empty: return "the expression is empty"
            case .unexpectedCharacter(let character): return "unexpected “\(character)”"
            case .unexpectedEnd: return "the expression ends too early"
            case .unbalancedParenthesis: return "unbalanced parentheses"
            case .divisionByZero: return "division by zero"
            case .notFinite: return "the result is not a finite number"
            }
        }
    }

    /// Supports + - * / % ^, unary minus, parentheses and decimal numbers.
    static func evaluate(_ expression: String) throws -> Double {
        var parser = Parser(expression)
        let value = try parser.parseExpression()
        try parser.expectEnd()
        guard value.isFinite else { throw EvaluationError.notFinite }
        return value
    }

    private struct Parser {
        private let characters: [Character]
        private var index = 0

        init(_ text: String) {
            characters = Array(text.replacingOccurrences(of: "×", with: "*")
                .replacingOccurrences(of: "÷", with: "/")
                .replacingOccurrences(of: ",", with: ""))
        }

        mutating func parseExpression() throws -> Double {
            var value = try parseTerm()
            while let character = peek(), character == "+" || character == "-" {
                advance()
                let right = try parseTerm()
                value = character == "+" ? value + right : value - right
            }
            return value
        }

        mutating func expectEnd() throws {
            skipSpaces()
            if let character = peek() {
                throw character == ")" ? EvaluationError.unbalancedParenthesis : EvaluationError.unexpectedCharacter(character)
            }
        }

        private mutating func parseTerm() throws -> Double {
            var value = try parseFactor()
            while let character = peek(), character == "*" || character == "/" || character == "%" {
                advance()
                let right = try parseFactor()
                switch character {
                case "*":
                    value *= right
                case "/":
                    guard right != 0 else { throw EvaluationError.divisionByZero }
                    value /= right
                default:
                    guard right != 0 else { throw EvaluationError.divisionByZero }
                    value = value.truncatingRemainder(dividingBy: right)
                }
            }
            return value
        }

        private mutating func parseFactor() throws -> Double {
            let base = try parseUnary()
            guard peek() == "^" else { return base }
            advance()
            let exponent = try parseFactor()
            return pow(base, exponent)
        }

        private mutating func parseUnary() throws -> Double {
            skipSpaces()
            guard let character = peek() else { throw EvaluationError.unexpectedEnd }
            if character == "-" {
                advance()
                return try -parseUnary()
            }
            if character == "+" {
                advance()
                return try parseUnary()
            }
            return try parsePrimary()
        }

        private mutating func parsePrimary() throws -> Double {
            skipSpaces()
            guard let character = peek() else { throw EvaluationError.unexpectedEnd }
            if character == "(" {
                advance()
                let value = try parseExpression()
                skipSpaces()
                guard peek() == ")" else { throw EvaluationError.unbalancedParenthesis }
                advance()
                return value
            }
            guard character.isNumber || character == "." else {
                throw EvaluationError.unexpectedCharacter(character)
            }
            var digits = ""
            var seenSeparator = false
            while let next = peek(), next.isNumber || (next == "." && !seenSeparator) {
                if next == "." { seenSeparator = true }
                digits.append(next)
                advance()
            }
            guard let value = Double(digits) else { throw EvaluationError.unexpectedCharacter(character) }
            return value
        }

        private func peek() -> Character? {
            var cursor = index
            while cursor < characters.count, characters[cursor] == " " {
                cursor += 1
            }
            return cursor < characters.count ? characters[cursor] : nil
        }

        private mutating func advance() {
            skipSpaces()
            if index < characters.count { index += 1 }
        }

        private mutating func skipSpaces() {
            while index < characters.count, characters[index] == " " {
                index += 1
            }
        }
    }
}
