import Foundation
import PDFKit

enum PDFTextExtractor {
    static func extractText(from url: URL, maxCharacters: Int = 8_000) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var text = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let pageText = page.string else { continue }
            text += pageText
            text += "\n"
            if text.count >= maxCharacters { break }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > maxCharacters else { return trimmed }
        return String(trimmed.prefix(maxCharacters)) + "…"
    }
}
