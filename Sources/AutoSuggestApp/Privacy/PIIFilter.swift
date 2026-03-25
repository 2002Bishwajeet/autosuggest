import Foundation

struct PIIFilter {
    func sanitize(_ text: String) -> String {
        var output = text
        output = replacing(output, pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, replacement: "<email>")
        output = replacing(output, pattern: #"\b(?:\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b"#, replacement: "<phone>")
        output = replacing(output, pattern: #"\b(?:\d[ -]*?){13,16}\b"#, replacement: "<card>")
        return output
    }

    private func replacing(_ text: String, pattern: String, replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}
