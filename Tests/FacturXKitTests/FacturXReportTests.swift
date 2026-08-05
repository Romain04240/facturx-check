import XCTest
@testable import FacturXKit

/// Le rapport est ce que voient à la fois l'application et la commande. Ces
/// tests portent donc sur ce que l'utilisateur lit, pas sur la lecture du XML
/// — qui est couverte ailleurs.
final class FacturXReportTests: XCTestCase {

    private func invoice(_ xml: String) throws -> FacturXParsedInvoice {
        try XCTUnwrap(FacturXParser.parse(Data(xml.utf8)))
    }

    private func makeXML(profile: String = "urn:factur-x.eu:1p0:basicwl",
                         number: String? = "F26-001",
                         seller: String? = "Blanc-Conseil",
                         buyer: String? = "Atelier Bréal",
                         base: String = "1000.00",
                         tax: String = "200.00",
                         grand: String = "1200.00",
                         breakdownBase: String = "1000.00",
                         currency: String? = "EUR",
                         grandCurrencyID: String? = nil,
                         taxCurrency: String? = nil,
                         taxInTaxCurrency: String? = nil) -> String {
        func element(_ tag: String, _ value: String?) -> String {
            value.map { "<ram:\(tag)>\($0)</ram:\(tag)>" } ?? ""
        }
        func attribute(_ name: String, _ value: String?) -> String {
            value.map { " \(name)=\"\($0)\"" } ?? ""
        }
        // BT-111 : le même total de TVA, exprimé dans la devise de déclaration
        // fiscale. Second élément du même nom, au même endroit.
        let secondTaxTotal = taxInTaxCurrency.map {
            "<ram:TaxTotalAmount\(attribute("currencyID", taxCurrency))>\($0)</ram:TaxTotalAmount>"
        } ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rsm:CrossIndustryInvoice xmlns:rsm="urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
                                  xmlns:ram="urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
                                  xmlns:udt="urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100">
          <rsm:ExchangedDocumentContext>
            <ram:GuidelineSpecifiedDocumentContextParameter><ram:ID>\(profile)</ram:ID></ram:GuidelineSpecifiedDocumentContextParameter>
          </rsm:ExchangedDocumentContext>
          <rsm:ExchangedDocument>
            \(element("ID", number))
            <ram:TypeCode>380</ram:TypeCode>
            <ram:IssueDateTime><udt:DateTimeString format="102">20260312</udt:DateTimeString></ram:IssueDateTime>
          </rsm:ExchangedDocument>
          <rsm:SupplyChainTradeTransaction>
            <ram:ApplicableHeaderTradeAgreement>
              <ram:SellerTradeParty>\(element("Name", seller))</ram:SellerTradeParty>
              <ram:BuyerTradeParty>\(element("Name", buyer))</ram:BuyerTradeParty>
            </ram:ApplicableHeaderTradeAgreement>
            <ram:ApplicableHeaderTradeSettlement>
              \(element("TaxCurrencyCode", taxCurrency))
              \(element("InvoiceCurrencyCode", currency))
              <ram:ApplicableTradeTax>
                <ram:CalculatedAmount>\(tax)</ram:CalculatedAmount>
                <ram:BasisAmount>\(breakdownBase)</ram:BasisAmount>
                <ram:RateApplicablePercent>20.00</ram:RateApplicablePercent>
              </ram:ApplicableTradeTax>
              <ram:SpecifiedTradeSettlementHeaderMonetarySummation>
                <ram:LineTotalAmount>\(base)</ram:LineTotalAmount>
                <ram:TaxBasisTotalAmount>\(base)</ram:TaxBasisTotalAmount>
                <ram:TaxTotalAmount\(attribute("currencyID", currency))>\(tax)</ram:TaxTotalAmount>
                \(secondTaxTotal)
                <ram:GrandTotalAmount\(attribute("currencyID", grandCurrencyID))>\(grand)</ram:GrandTotalAmount>
                <ram:DuePayableAmount>\(grand)</ram:DuePayableAmount>
              </ram:SpecifiedTradeSettlementHeaderMonetarySummation>
            </ram:ApplicableHeaderTradeSettlement>
          </rsm:SupplyChainTradeTransaction>
        </rsm:CrossIndustryInvoice>
        """
    }

    private func failures(_ checks: [FacturXReport.Check]) -> [String] {
        checks.filter { $0.level == .failed }.map(\.message)
    }

    // MARK: - Le cas nominal

    func testASoundInvoiceFailsNothing() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML()))
        XCTAssertTrue(failures(checks).isEmpty, "aucun contrôle ne devrait échouer : \(failures(checks))")
    }

    // MARK: - Le contrôle qui compte

    /// L'erreur de génération la plus fréquente. Elle doit être signalée comme
    /// un échec, pas comme un avertissement : le destinataire, lui, rejette.
    func testTotalsThatDoNotAddUpAreAFailure() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(grand: "1250.00")))
        XCTAssertEqual(failures(checks).count, 1)
        XCTAssertTrue(failures(checks)[0].contains("1\u{202F}200,00\u{A0}€"),
                      "le rapport doit donner le total attendu : \(failures(checks)[0])")
    }

    /// Les sommes citées dans un échec sont lues par quelqu'un qui n'a pas
    /// écrit le générateur. Un « 0.02 » brut au milieu d'une phrase se relit
    /// deux fois ; le montant doit se présenter comme partout ailleurs.
    func testAFailureNamesItsAmountsInFrenchWithTheCurrency() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(grand: "1250.00")))
        let failed = try XCTUnwrap(checks.first { $0.level == .failed })
        XCTAssertTrue(failed.message.contains("1\u{202F}250,00\u{A0}€"),
                      "le TTC déclaré doit être mis en forme : \(failed.message)")
        let consequence = try XCTUnwrap(failed.consequence)
        XCTAssertTrue(consequence.contains("50,00\u{A0}€"),
                      "l'écart doit être mis en forme : \(consequence)")
    }

    /// Un centime d'écart vient de l'arrondi décimal du générateur, pas d'une
    /// erreur de calcul : le signaler ferait crier au loup sur des factures
    /// parfaitement valides.
    func testACentOfRoundingIsTolerated() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(grand: "1200.01")))
        XCTAssertTrue(failures(checks).isEmpty)
    }

    func testAVATBreakdownThatContradictsTheFooterIsAFailure() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(breakdownBase: "900.00")))
        XCTAssertEqual(failures(checks).count, 1)
    }

    // MARK: - Les devises

    /// Une facture peut porter deux fois son total de TVA : dans sa devise, et
    /// dans celle de la déclaration fiscale (BT-110 et BT-111). Retenir le
    /// second ferait échouer « HT + TVA = TTC » sur une facture valide — le
    /// contrôle même sur lequel l'outil est jugé.
    func testASecondVATTotalInTheTaxCurrencyIsNotMistakenForTheRealOne() throws {
        let parsed = try invoice(makeXML(taxCurrency: "CHF", taxInTaxCurrency: "188.00"))
        XCTAssertEqual(parsed.totalVAT, 200, "le total retenu doit être celui de la devise de la facture")
        XCTAssertTrue(failures(FacturXReport.evaluate(parsed)).isEmpty,
                      "\(failures(FacturXReport.evaluate(parsed)))")
    }

    /// Même document, sans devise déclarée : on ne peut plus s'appuyer sur
    /// elle, mais on sait au moins quel montant n'est pas le bon.
    func testTheTaxCurrencyAmountIsSetAsideEvenWithoutADeclaredCurrency() throws {
        let parsed = try invoice(makeXML(currency: nil, taxCurrency: "CHF", taxInTaxCurrency: "188.00"))
        XCTAssertEqual(parsed.totalVAT, 200)
    }

    func testADeclaredCurrencyPasses() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML()))
        XCTAssertTrue(checks.contains { $0.level == .passed && $0.message.contains("EUR") })
    }

    /// La devise se lit sur les montants, mais la mention obligatoire manque :
    /// l'afficher sans le dire laisserait croire la facture en règle.
    func testACurrencyFoundOnlyOnTheAmountsIsAWarning() throws {
        let parsed = try invoice(makeXML(currency: nil, grandCurrencyID: "EUR"))
        XCTAssertNil(parsed.declaredCurrencyCode)
        XCTAssertEqual(parsed.currencyCode, "EUR", "les montants restent affichables")
        let checks = FacturXReport.evaluate(parsed)
        XCTAssertTrue(failures(checks).isEmpty)
        XCTAssertTrue(checks.contains { $0.level == .warning && $0.message.contains("Devise") })
    }

    func testNoCurrencyAnywhereIsAFailure() throws {
        let parsed = try invoice(makeXML(currency: nil))
        XCTAssertNil(parsed.currencyCode)
        XCTAssertTrue(failures(FacturXReport.evaluate(parsed)).contains { $0.contains("devise") })
    }

    /// Sans devise, les montants s'écrivent sans symbole plutôt qu'en euros
    /// supposés — y compris dans les messages d'échec.
    func testAmountsWithoutACurrencyAreWrittenWithoutASymbol() throws {
        let parsed = try invoice(makeXML(grand: "1250.00", currency: nil))
        let failed = try XCTUnwrap(FacturXReport.evaluate(parsed).first {
            $0.level == .failed && $0.message.contains("HT + TVA")
        })
        XCTAssertTrue(failed.message.contains("1\u{202F}250,00"), failed.message)
        XCTAssertFalse(failed.message.contains("€"), failed.message)
    }

    // MARK: - Mentions obligatoires

    func testAMissingNumberIsAFailure() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(number: nil)))
        XCTAssertTrue(failures(checks).contains { $0.contains("Numéro") })
    }

    func testAMissingSellerIsAFailure() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(seller: nil)))
        XCTAssertTrue(failures(checks).contains { $0.contains("Émetteur") })
    }

    /// Le destinataire manque dans les profils les plus légers : c'est un
    /// avertissement, pas un échec — sinon l'outil condamnerait des factures
    /// que leur destinataire accepte.
    func testAMissingBuyerIsOnlyAWarning() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(buyer: nil)))
        XCTAssertTrue(failures(checks).isEmpty)
        XCTAssertTrue(checks.contains { $0.level == .warning && $0.message.contains("Destinataire") })
    }

    func testAnUnknownProfileIsOnlyAWarning() throws {
        let checks = FacturXReport.evaluate(try invoice(makeXML(profile: "urn:inventé:9p9:zzz")))
        XCTAssertTrue(failures(checks).isEmpty)
        XCTAssertTrue(checks.contains { $0.level == .warning && $0.message.contains("Profil") })
    }

    // MARK: - Ce qu'on reçoit vraiment

    /// Un PDF ordinaire est le cas le plus courant. Le verdict doit être
    /// explicite plutôt qu'un rapport vide qu'on prendrait pour un succès.
    func testAPlainPDFIsReportedAsNotFacturX() {
        let report = FacturXReport.analyse(pdf: Data("%PDF-1.4\n%%EOF\n".utf8), fileName: "devis.pdf")
        guard case .notFacturX(let reason) = report.outcome else {
            return XCTFail("verdict inattendu : \(report.outcome)")
        }
        XCTAssertFalse(report.outcome.isSound)
        XCTAssertFalse(reason.isEmpty, "le verdict doit expliquer, pas seulement constater")
    }

    func testSomethingThatIsNotAPDFIsReportedAsUnreadable() {
        let report = FacturXReport.analyse(pdf: Data("bonjour".utf8), fileName: "note.txt")
        guard case .unreadable = report.outcome else {
            return XCTFail("verdict inattendu : \(report.outcome)")
        }
    }

    func testAMissingFileDoesNotCrash() {
        let report = FacturXReport.analyse(fileURL: URL(fileURLWithPath: "/introuvable/nulle-part.pdf"))
        XCTAssertFalse(report.outcome.isSound)
        XCTAssertEqual(report.fileName, "nulle-part.pdf")
    }
}
