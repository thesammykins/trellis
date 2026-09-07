import Foundation

@main enum MarkdownFenceParserCheck {
    static func expect(_ source: String, _ expected: [MarkdownMessageBlock], _ name: String) {
        let actual = MarkdownFenceParser.parse(source)
        guard actual == expected else { fatalError("\(name) failed: \(actual)") }
    }

    static func main() {
        expect("Use ``` inline.", [.prose("Use ``` inline.")], "inline prose")
        expect("````swift\nlet fence = \"```\"\n```\n````\nafter", [.code(language: "swift", body: "let fence = \"```\"\n```\n"), .prose("after")], "nested fence")
        expect("```text\n> ``` quoted\n```\n", [.code(language: "text", body: "> ``` quoted\n")], "quoted triple")
        expect("before\n```sh\nprintf 'exact\\n'\n", [.prose("before\n"), .code(language: "sh", body: "printf 'exact\\n'\n")], "unfinished fence")
        expect("~~~text\r\nkeeps CRLF\r\n~~~\r\n", [.code(language: "text", body: "keeps CRLF\r\n")], "tilde fence and CRLF")
        print("Markdown fence parser checks passed")
    }
}
