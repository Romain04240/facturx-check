import Foundation
import CoreGraphics
import Vision

/// Ce qu'un OCR lit dans le PDF.
///
/// C'est la contrepartie de tout l'outil : quand un PDF ne porte pas de facture
/// structurée, le destinataire n'a plus que l'image, et il en passe par là. Le
/// montrer vaut mieux que l'affirmer — on voit tout de suite ce qui se perd,
/// et à quel point la lecture est incertaine.
struct OCRResult: Sendable {
    struct Line: Identifiable, Sendable {
        let id = UUID()
        let page: Int
        let text: String
        let confidence: Float
    }

    let lines: [Line]
    let pageCount: Int
    let pagesRead: Int

    var text: String { lines.map(\.text).joined(separator: "\n") }

    /// En dessous de 80 %, Vision annonce lui-même qu'il n'est pas sûr. Sur une
    /// facture, ce sont presque toujours les chiffres.
    var uncertainCount: Int { lines.filter { $0.confidence < 0.8 }.count }
}

enum OCRReader {
    enum Failure: LocalizedError {
        case notAPDF
        case nothingRendered

        var errorDescription: String? {
            switch self {
            case .notAPDF:         return "Ce fichier n'est pas un PDF lisible."
            case .nothingRendered: return "Aucune page n'a pu être rendue."
            }
        }
    }

    /// On s'arrête à quatre pages : une facture en fait une ou deux, et rendre
    /// puis analyser un catalogue de trente pages ferait patienter pour rien.
    static let pageLimit = 4

    static func read(pdf: Data) async throws -> OCRResult {
        try await Task.detached(priority: .userInitiated) {
            guard let provider = CGDataProvider(data: pdf as CFData),
                  let document = CGPDFDocument(provider), document.numberOfPages > 0
            else { throw Failure.notAPDF }

            let pagesToRead = min(document.numberOfPages, pageLimit)
            var lines: [OCRResult.Line] = []
            var rendered = 0

            for index in 1...pagesToRead {
                guard let page = document.page(at: index),
                      let image = render(page) else { continue }
                rendered += 1

                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["fr-FR", "en-US"]
                // La correction linguistique remplacerait « F20260803-001 » par
                // un mot plausible. Or c'est exactement ce qu'on veut voir tel
                // quel : une référence de facture n'est pas du français.
                request.usesLanguageCorrection = false

                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

                for observation in request.results ?? [] {
                    guard let best = observation.topCandidates(1).first else { continue }
                    lines.append(.init(page: index, text: best.string, confidence: best.confidence))
                }
            }

            guard rendered > 0 else { throw Failure.nothingRendered }
            return OCRResult(lines: lines,
                             pageCount: document.numberOfPages,
                             pagesRead: rendered)
        }.value
    }

    /// Rendu à 2× le format du document, soit environ 144 points par pouce.
    /// En dessous, Vision perd les mentions en petits corps — celles des
    /// pénalités de retard, justement.
    private static func render(_ page: CGPDFPage) -> CGImage? {
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 2
        let width = Int(box.width * scale), height = Int(box.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }

        // Un PDF n'a pas de fond : sans ce blanc, le texte noir serait rendu
        // sur du transparent, que Vision reçoit comme du noir sur noir.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.origin.x, y: -box.origin.y)
        context.drawPDFPage(page)

        return context.makeImage()
    }
}
