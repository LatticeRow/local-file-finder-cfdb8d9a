import Foundation
import PDFKit
import UniformTypeIdentifiers
import Vision
import UIKit

struct ExtractedTextPayload {
    let normalizedText: String
    let preview: String
    let tokenCount: Int
    let usedOCR: Bool
    let chunkIndex: Int
    let pageNumber: Int?
}

final class ContentExtractionService {
    private let logger: AppLogger
    private let minimumUsefulEmbeddedTextLength = 48

    init(logger: AppLogger) {
        self.logger = logger
    }

    func extractionPipelineDescription() -> String {
        logger.info("Reporting extraction pipeline")
        return "Recursive local indexing is active. Plain text, PDF text, and scanned PDF OCR are searchable today."
    }

    func extractSearchableContent(from file: EnumeratedFile) -> [ExtractedTextPayload] {
        if let contentType = UTType(file.uti), contentType.conforms(to: .pdf) {
            return extractPDFContent(from: file.fileURL)
        }

        guard isTextLikeFile(file), let extractedText = readTextFile(at: file.fileURL) else {
            return []
        }

        return makePayload(
            from: extractedText,
            usedOCR: false,
            chunkIndex: 0,
            pageNumber: nil
        ).map { [$0] } ?? []
    }

    private func isTextLikeFile(_ file: EnumeratedFile) -> Bool {
        if let contentType = UTType(file.uti), contentType.conforms(to: .text) {
            return true
        }

        let extensionSet = Set(["txt", "md", "markdown", "json", "csv", "tsv", "log", "swift", "plist", "yaml", "yml", "xml"])
        return extensionSet.contains(file.fileURL.pathExtension.lowercased())
    }

    private func readTextFile(at url: URL) -> String? {
        coordinatedRead(at: url) { coordinatedURL in
            let encodings: [String.Encoding] = [
                .utf8,
                .utf16,
                .utf16LittleEndian,
                .utf16BigEndian,
                .unicode,
                .ascii,
                .isoLatin1,
                .macOSRoman,
                .windowsCP1252,
            ]

            for encoding in encodings {
                if let text = try? String(contentsOf: coordinatedURL, encoding: encoding) {
                    return text
                }
            }

            return nil
        } ?? nil
    }

    private func extractPDFContent(from url: URL) -> [ExtractedTextPayload] {
        guard let document = coordinatedRead(at: url, body: { PDFDocument(url: $0) }) ?? nil else {
            return []
        }

        var payloads: [ExtractedTextPayload] = []

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            let embeddedPayload = makePayload(
                from: page.string,
                usedOCR: false,
                chunkIndex: payloads.count,
                pageNumber: pageIndex + 1
            )

            if let preferredEmbeddedPayload = preferredEmbeddedPayload(embeddedPayload) {
                payloads.append(preferredEmbeddedPayload)
                continue
            }

            let ocrPayload = recognizeText(in: page, pageNumber: pageIndex + 1, chunkIndex: payloads.count)
            if let preferredPayload = preferredPayload(embeddedPayload: embeddedPayload, ocrPayload: ocrPayload) {
                payloads.append(preferredPayload)
            }
        }

        return payloads
    }

    private func recognizeText(in page: PDFPage, pageNumber: Int, chunkIndex: Int) -> ExtractedTextPayload? {
        guard let cgImage = renderPDFPage(page) else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.info("Vision OCR failed for PDF page \(pageNumber)")
            return nil
        }

        let recognizedText = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        return makePayload(
            from: recognizedText,
            usedOCR: true,
            chunkIndex: chunkIndex,
            pageNumber: pageNumber
        )
    }

    private func renderPDFPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else {
            return nil
        }

        let maxDimension: CGFloat = 2200
        let scale = min(maxDimension / max(bounds.width, bounds.height), 2.5)
        let targetSize = CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            context.cgContext.translateBy(x: 0, y: targetSize.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            context.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }

        return image.cgImage
    }

    private func makePayload(
        from text: String?,
        usedOCR: Bool,
        chunkIndex: Int,
        pageNumber: Int?
    ) -> ExtractedTextPayload? {
        guard let text else {
            return nil
        }

        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return nil
        }

        return ExtractedTextPayload(
            normalizedText: normalized,
            preview: String(normalized.prefix(220)),
            tokenCount: normalized.split(whereSeparator: \.isWhitespace).count,
            usedOCR: usedOCR,
            chunkIndex: chunkIndex,
            pageNumber: pageNumber
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func preferredEmbeddedPayload(_ payload: ExtractedTextPayload?) -> ExtractedTextPayload? {
        guard let payload else {
            return nil
        }

        return payload.normalizedText.count >= minimumUsefulEmbeddedTextLength ? payload : nil
    }

    private func preferredPayload(
        embeddedPayload: ExtractedTextPayload?,
        ocrPayload: ExtractedTextPayload?
    ) -> ExtractedTextPayload? {
        switch (embeddedPayload, ocrPayload) {
        case let (.some(embedded), .some(ocr)):
            return ocr.normalizedText.count > embedded.normalizedText.count ? ocr : embedded
        case let (.some(embedded), .none):
            return embedded
        case let (.none, .some(ocr)):
            return ocr
        case (.none, .none):
            return nil
        }
    }

    private func coordinatedRead<T>(at url: URL, body: (URL) -> T?) -> T? {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: T?

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = body(coordinatedURL)
        }

        if coordinationError != nil {
            logger.info("File coordination failed for \(url.lastPathComponent)")
        }

        return result
    }
}
