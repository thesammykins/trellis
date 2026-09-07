import Foundation

enum MarkdownMessageBlock: Equatable { case prose(String); case code(language: String, body: String) }

enum MarkdownFenceParser {
    static func parse(_ source: String) -> [MarkdownMessageBlock] {
        var result: [MarkdownMessageBlock] = [], prose = "", code = "", language = ""
        var activeFence: (marker: Character, length: Int)?
        for line in source.preservedLines {
            let content = line.withoutTerminator
            if let fence = activeFence {
                if isClosing(content, marker: fence.marker, minimum: fence.length) {
                    result.append(.code(language: language, body: code)); code = ""; language = ""; activeFence = nil
                } else { code += line }
            } else if let opening = opening(content) {
                if !prose.isEmpty { result.append(.prose(prose)); prose = "" }
                activeFence = (opening.marker, opening.length); language = opening.language
            } else { prose += line }
        }
        if activeFence != nil { result.append(.code(language: language, body: code)) }
        if !prose.isEmpty { result.append(.prose(prose)) }
        return result.isEmpty ? [.prose("")] : result
    }

    private static func opening(_ line: String) -> (marker: Character, length: Int, language: String)? {
        let indent = line.prefix(while: { $0 == " " }).count
        guard indent <= 3 else { return nil }
        let trimmed = line.dropFirst(indent)
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        guard length >= 3 else { return nil }
        let info = trimmed.dropFirst(length)
        guard marker != "`" || !info.contains("`") else { return nil }
        return (marker, length, info.trimmingCharacters(in: .whitespaces))
    }

    private static func isClosing(_ line: String, marker: Character, minimum: Int) -> Bool {
        let indent = line.prefix(while: { $0 == " " }).count
        guard indent <= 3 else { return false }
        let trimmed = line.dropFirst(indent), length = trimmed.prefix(while: { $0 == marker }).count
        return length >= minimum && trimmed.dropFirst(length).allSatisfy(\.isWhitespace)
    }
}

private extension String {
    var preservedLines: [String] {
        guard !isEmpty else { return [] }
        var lines: [String] = [], line = ""
        for character in self {
            line.append(character)
            if character.isNewline { lines.append(line); line = "" }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
    var withoutTerminator: String {
        var value = self
        if value.last?.isNewline == true { value.removeLast() }
        return value
    }
}
