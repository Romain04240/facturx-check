import XCTest
@testable import FacturXKit

/// Le seul endroit où l'outil est éprouvé sur un vrai PDF.
///
/// Tous les autres tests partent d'un XML nu : ils vérifient les contrôles,
/// jamais le chemin qui va des octets du fichier jusqu'à eux — extraction de
/// la pièce jointe, arbre des noms, flux compressé ou non. C'est pourtant ce
/// chemin qui échoue en premier sur le fichier de quelqu'un d'autre.
///
/// Les fichiers viennent de `Scripts/make-samples.swift`. Ils sont trouvés
/// par rapport à ce fichier source plutôt que copiés dans les ressources du
/// paquet : deux PDF versionnés en double finiraient par diverger, et c'est
/// le fichier qu'on distribue qu'on veut éprouver, pas sa copie.
final class SamplePDFTests: XCTestCase {

    private func sample(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FacturXKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // racine du dépôt
        let url = root.appendingPathComponent("Samples/\(name)")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path),
                          "échantillon absent — lancer : swift Scripts/make-samples.swift")
        return try Data(contentsOf: url)
    }

    func testTheFacturXSampleIsReadEndToEnd() throws {
        let report = FacturXReport.analyse(pdf: try sample("facture-demo-facturx.pdf"),
                                           fileName: "facture-demo-facturx.pdf")

        XCTAssertEqual(report.outcome, .sound, "contrôles en échec : \(report.checks.filter { $0.level == .failed }.map(\.message))")
        let invoice = try XCTUnwrap(report.invoice)
        XCTAssertEqual(invoice.number, "FX-2026-0042")
        XCTAssertEqual(invoice.sellerName, "Blanc-Conseil")
        XCTAssertEqual(invoice.declaredCurrencyCode, "EUR")
        XCTAssertEqual(invoice.totalHT, Decimal(string: "1440.00"))
        XCTAssertEqual(invoice.totalVAT, Decimal(string: "253.20"))
        XCTAssertEqual(invoice.totalTTC, Decimal(string: "1693.20"))
        XCTAssertEqual(invoice.profile, .basicWL)
    }

    /// Deux taux : c'est ce qui donne à la ventilation quelque chose à
    /// contredire, et au contrôle correspondant une chance de servir.
    func testTheSampleCarriesBothVATRates() throws {
        let report = FacturXReport.analyse(pdf: try sample("facture-demo-facturx.pdf"),
                                           fileName: "facture-demo-facturx.pdf")
        let rates = try XCTUnwrap(report.invoice).vatBreakdown.map(\.rate)
        XCTAssertEqual(Set(rates), [Decimal(string: "20.00")!, Decimal(string: "5.50")!])
    }

    /// Le fichier jumeau : même page à l'œil, rien dedans pour une machine.
    /// C'est la démonstration entière de l'outil, tenue par deux fichiers.
    func testTheTwinWithoutXMLIsReportedAsNotFacturX() throws {
        let report = FacturXReport.analyse(pdf: try sample("facture-demo-simple.pdf"),
                                           fileName: "facture-demo-simple.pdf")
        guard case .notFacturX = report.outcome else {
            return XCTFail("verdict inattendu : \(report.outcome)")
        }
        XCTAssertNil(report.xml)
    }
}
