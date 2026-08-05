import XCTest
@testable import FacturXKit

/// Le rapprochement page/XML est jugé sur deux risques opposés : laisser
/// passer une divergence réelle, et crier au loup sur une facture saine parce
/// que l'OCR a mal lu. Le second est le plus coûteux — c'est celui qui ferait
/// écrire à un prestataire pour rien.
final class PrintedComparisonTests: XCTestCase {

    private func invoice(number: String? = "FX-2026-0042",
                         seller: String? = "Blanc-Conseil",
                         ttc: String? = "1693.20",
                         ht: String? = "1440.00") -> FacturXParsedInvoice {
        var invoice = FacturXParsedInvoice()
        invoice.number = number
        invoice.sellerName = seller
        invoice.declaredCurrencyCode = "EUR"
        invoice.totalTTC = ttc.flatMap { Decimal(string: $0) }
        invoice.totalHT = ht.flatMap { Decimal(string: $0) }
        return invoice
    }

    private let printedPage = """
    Blanc-Conseil
    FACTURE
    N° FX-2026-0042
    Total HT 1 440,00 €
    TVA 253,20 €
    Total TTC 1 693,20 €
    """

    private func warnings(_ checks: [FacturXReport.Check]) -> [String] {
        checks.filter { $0.level == .warning }.map(\.message)
    }

    // MARK: - Une facture dont la page et le XML concordent

    func testAPageThatMatchesTheXMLRaisesNothing() {
        let checks = FacturXReport.comparePrinted(printedPage, with: invoice())
        XCTAssertTrue(warnings(checks).isEmpty, "\(warnings(checks))")
        XCTAssertFalse(checks.isEmpty)
    }

    /// Ce que l'OCR rend vraiment : majuscules perdues, accents mangés,
    /// espaces en trop. Rien de tout cela n'est une divergence.
    func testOCRQuirksDoNotRaiseAWarning() {
        let mangled = """
        BLANC-CONSEIL
        N°   FX-2026-0042
        Total HT       1440,00 EUR
        Total TTC      1 693,20 EUR
        """
        XCTAssertTrue(warnings(FacturXReport.comparePrinted(mangled, with: invoice())).isEmpty)
    }

    /// Un générateur anglo-saxon imprime « 1,693.20 » là où le XML écrit
    /// « 1693.20 ». C'est la même somme.
    func testAnAngloSaxonPrintedAmountIsRecognised() {
        let page = "Blanc-Conseil FX-2026-0042 Total HT 1,440.00 Total TTC 1,693.20"
        XCTAssertTrue(warnings(FacturXReport.comparePrinted(page, with: invoice())).isEmpty)
    }

    // MARK: - Les divergences qu'on cherche

    /// Le cas qui justifie tout le rapprochement : la page annonce une somme,
    /// le XML en déclare une autre. Le client paie l'une, son logiciel
    /// comptabilise l'autre.
    func testAPrintedTotalThatDiffersFromTheXMLIsReported() {
        let page = printedPage.replacingOccurrences(of: "1 693,20", with: "1 793,20")
        let checks = FacturXReport.comparePrinted(page, with: invoice())
        XCTAssertTrue(warnings(checks).contains { $0.contains("total TTC") }, "\(warnings(checks))")
        let warning = checks.first { $0.level == .warning && $0.message.contains("total TTC") }
        XCTAssertNotNil(warning?.consequence, "un avertissement doit dire ce qu'il coûte")
    }

    func testANumberAbsentFromThePageIsReported() {
        let page = printedPage.replacingOccurrences(of: "FX-2026-0042", with: "FX-2026-0043")
        XCTAssertTrue(warnings(FacturXReport.comparePrinted(page, with: invoice())).contains { $0.contains("numéro") })
    }

    /// Rien n'échoue jamais ici : l'OCR n'a pas autorité pour condamner une
    /// facture. Si cette règle change un jour, ce test doit tomber.
    func testNothingIsEverReportedAsAFailure() {
        let checks = FacturXReport.comparePrinted("page sans rapport", with: invoice())
        XCTAssertTrue(checks.allSatisfy { $0.level != .failed })
    }

    // MARK: - La lecture des nombres

    func testAmountsAreReadWhateverTheirWriting() {
        let found = FacturXReport.amounts(in: "1 693,20 puis 1,693.20 puis 1693.20 puis 1'693,20")
        XCTAssertTrue(found.contains(Decimal(string: "1693.20")!), "\(found.sorted(by: <))")
    }

    /// « 1.693 » peut se lire de deux façons ; les deux sont retenues, de
    /// sorte qu'une page écrite à l'anglaise ne déclenche pas d'alerte.
    func testAnAmbiguousSeparatorKeepsBothReadings() {
        let found = FacturXReport.amounts(in: "1.693")
        XCTAssertTrue(found.contains(Decimal(string: "1693")!))
        XCTAssertTrue(found.contains(Decimal(string: "1.693")!))
    }

    func testTextWithoutNumbersYieldsNothing() {
        XCTAssertTrue(FacturXReport.amounts(in: "aucune somme ici").isEmpty)
    }
}
