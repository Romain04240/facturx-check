import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Pulls the embedded invoice XML back out of a received Factur-X PDF.
///
/// This is the counterpart to `PDFAttachmentWriter`, and the reason it matters
/// is regulatory: from 1 September 2026 every French company must be able to
/// *receive* electronic invoices. Until now the app guessed at a supplier's
/// PDF with OCR, which misreads amounts and numbers. When the sender used
/// Factur-X the exact figures are already inside the file — reading them is
/// not an improvement on OCR, it removes the guessing entirely.
public enum FacturXExtractor {
    /// Walks the PDF catalog's embedded-files name tree and returns the first
    /// attachment whose name looks like a Factur-X payload.
    ///
    /// Uses Core Graphics rather than hand-parsing: unlike writing, *reading*
    /// an attachment is something Apple's parser does well, including
    /// inflating the compressed streams most other generators produce (ours
    /// are stored uncompressed, but a file from another vendor rarely is).
    public static func embeddedXML(in pdf: Data) -> Data? {
        #if canImport(CoreGraphics)
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider),
              let catalog = document.catalog else { return nil }

        var names: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "Names", &names), let names else { return nil }
        var embeddedFiles: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(names, "EmbeddedFiles", &embeddedFiles), let embeddedFiles else { return nil }

        return searchNameTree(embeddedFiles)
        #else
        return nil
        #endif
    }

    /// Convenience: extract and parse in one step. Nil when the PDF carries no
    /// Factur-X attachment, which is the common case for a scanned invoice.
    public static func read(from pdf: Data) -> FacturXReadResult? {
        guard let xml = embeddedXML(in: pdf) else { return nil }
        guard let parsed = FacturXParser.parse(xml) else { return nil }
        return FacturXReadResult(xml: xml, invoice: parsed)
    }

    #if canImport(CoreGraphics)

    /// A PDF name tree is either a flat `/Names [key value …]` array or a
    /// `/Kids` list of sub-nodes. Large producers split into kids, so both
    /// shapes have to be handled or attachments go silently missing.
    private static func searchNameTree(_ node: CGPDFDictionaryRef) -> Data? {
        var pairs: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Names", &pairs), let pairs {
            let count = CGPDFArrayGetCount(pairs)
            var index = 0
            while index + 1 < count {
                var nameRef: CGPDFStringRef?
                var fileSpec: CGPDFDictionaryRef?
                if CGPDFArrayGetString(pairs, index, &nameRef),
                   CGPDFArrayGetDictionary(pairs, index + 1, &fileSpec),
                   let nameRef, let fileSpec {
                    let name = (CGPDFStringCopyTextString(nameRef) as String?) ?? ""
                    if isFacturXFilename(name), let data = streamData(fromFileSpec: fileSpec) {
                        return data
                    }
                }
                index += 2
            }
        }

        var kids: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(node, "Kids", &kids), let kids {
            for index in 0..<CGPDFArrayGetCount(kids) {
                var kid: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(kids, index, &kid), let kid,
                   let found = searchNameTree(kid) {
                    return found
                }
            }
        }
        return nil
    }

    private static func streamData(fromFileSpec fileSpec: CGPDFDictionaryRef) -> Data? {
        var embedded: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(fileSpec, "EF", &embedded), let embedded else { return nil }
        // "/F" is the classic key, "/UF" the Unicode one; either may be the
        // only one present depending on the producer.
        for key in ["F", "UF"] {
            var stream: CGPDFStreamRef?
            if CGPDFDictionaryGetStream(embedded, key, &stream), let stream {
                var format = CGPDFDataFormat.raw
                if let data = CGPDFStreamCopyData(stream, &format) {
                    return data as Data
                }
            }
        }
        return nil
    }

    #endif

    /// `factur-x.xml` is the name the standard mandates, but ZUGFeRD (the
    /// German original) and Order-X use their own, and plenty of real files
    /// still carry the older `ZUGFeRD-invoice.xml`. Accepting all of them
    /// costs nothing and avoids rejecting a perfectly readable invoice.
    static func isFacturXFilename(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return ["factur-x.xml", "zugferd-invoice.xml", "xrechnung.xml", "order-x.xml", "factur-x.xml"]
            .contains(lowered) || (lowered.hasSuffix(".xml") && lowered.contains("factur"))
    }
}

/// What a received Factur-X file yielded: the raw XML (kept so the app can
/// show it verbatim and archive it) and the values parsed out of it.
public struct FacturXReadResult: Sendable {
    public let xml: Data
    public let invoice: FacturXParsedInvoice

    public var xmlString: String { String(decoding: xml, as: UTF8.self) }
}
